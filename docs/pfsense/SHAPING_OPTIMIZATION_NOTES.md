# Optimizing pfSense traffic shaping on a gigabit cable line

> **Audience**: anyone running pfSense limiters (dummynet) on a fast cable or fibre line who wants low latency under load
> without giving up throughput.
>
> **Scope**: generic pfSense material from a measured migration, October 2026. The box was pfSense CE 2.8.1 on a 4-core
> Xeon D, a 2.5G WAN port, a 2x1G LACP LAN trunk, many VLANs and inline Suricata on the WAN, moving from a 35 Mbit/s uplink
> to a **1000 Mbit/s down, 500 Mbit/s up** line. Addresses, hostnames and interface numbers are left out on purpose.
> It extends the [Traffic Shaping Guide](TRAFFIC_SHAPING_GUIDE.md), which it corrects in three places.

## What changed, in numbers

| | Before | After |
|---|---|---|
| Download pipe | 920 Mbit/s, delivered about 800 to 840 | 980 Mbit/s, delivered about 880 to 900 on a single server |
| Upload pipe | 33 Mbit/s (sized for the old uplink) | 475 Mbit/s (the line does about 510) |
| Line speed with the WAN limiter rules disabled | n/a | 945 to 1020 Mbit/s down from one favourable server, about 910 combined across two servers, about 510 up |
| Worst-case latency under heavy parallel download | 105 ms unshaped | 47 ms shaped |
| 5 Mbit/s UDP stream while a bulk host saturated the uplink at about 480 Mbit/s | not measured | 0% loss, 1.0 ms jitter (3.2 ms idle) |

## Lessons, in order of impact

1. **An upload limiter caps your download.** Every fast download needs ACKs going back out. A 33 Mbit/s upload limiter
   squeezed them, and shaped download stalled around 800 to 840 Mbit/s while the line did more. Resize both pipes when the
   line changes, and treat the upload pipe as part of the download path.
2. **Size child queues explicitly.** A dummynet child queue defaults to 50 slots: about 18 ms at 33 Mbit/s, but under 1 ms at
   475 Mbit/s, so every burst is tail-dropped and throughput falls. The pipe-level queue size does not reach its children.
   Set a size on each child; sizes of 300 to 900 slots were used here.
3. **Keep queue sizes below `net.inet.ip.dummynet.pipe_slot_limit` (1000).** A child queue set to exactly 1000 silently
   lost CoDel on one reload. The `AQM CoDel` label that `dnctl queue show` prints was also not a reliable indicator on this
   system: a freshly created queue sometimes showed none. Do not treat the label as proof; bound the worst case with the
   queue size instead.
4. **pfSense loads the limiter file incrementally.** Queues you delete from the configuration stay in the kernel until a
   reboot, and re-sending a queue's configuration does not always change it. Check `dnctl queue show` after a change and
   do not assume a removed queue is gone.
5. **`filter_configure()` is asynchronous.** In a script it only queues a reload. Call `filter_configure_sync()` and load
   `shaper.inc`, or your check runs before the new rules exist.
6. **The mask direction was backwards.** On a rule on a LAN-side interface, per-device limiters need the upload pipe masked
   on **source** address and the download pipe on **destination** address. The reverse keys the buckets on the remote
   server, so a device talking to fifty servers gets fifty caps. Verified live for downloads: `dnctl sched <n> show` listed
   buckets keyed on LAN hosts.
7. **A limiter on a LAN rule only sees connections the LAN starts.** Inbound port-forward traffic belongs to a state created
   by the WAN-side rule. To cap a node that accepts inbound peers, put the limiter on that forward's associated WAN rule
   (the download pipe first, then the upload pipe).
8. **Do not test shaping from the firewall itself.** Connections that terminate on the firewall interact with dummynet
   differently: shaped upload read 130 to 160 Mbit/s there, against 457 Mbit/s from a wired LAN client through the same
   firewall. Test from a wired host.
9. **Shape the failover link too.** A cellular failover with no limiter added 120 to 220 ms of latency under download (485
   ms worst). It measured about 200 Mbit/s down and 13 Mbit/s up and varied over the day; a limiter at roughly 85 to 90
   percent of the slowest reading (120 and 10) cut the worst case to under 200 ms. To test a link that is not the default
   route, add a temporary host route for the test server through that gateway, bind the test to the interface address, and
   delete the route afterwards.
10. **Remove dead shaper wizard output.** The wizard had left 13 ALTQ trees and 58 floating match rules with no tag, queue,
    pipe or gateway. Both carried zero packets. Removing them cut the active ruleset by 228 lines. Check that nothing else
    references an ALTQ queue name before deleting.
11. **Look at the resolver.** Forwarding over TLS with DNSSEC made cold lookups average 179 ms where the same upstreams answered
    directly in 23 to 36 ms. Prefetch, a larger cache (message cache 4 to 32 MB) and serve-expired make repeat lookups
    instant (0 ms) without changing the first-lookup path.
12. **Check Ethernet flow control.** All four NICs ran full pause frames (`dev.<driver>.<n>.fc` of 3) although a loader
    tunable said off. Pause frames can hide queues from CoDel. Set it with a runtime tunable and re-measure.

## The design that worked

Download is one flat `fq_codel` pipe. Its per-flow queues already serve small, sparse packets (game and voice traffic)
quickly, so classes there add complexity for little gain. Upload is a `wf2q+` pipe with four child queues, each with its own
size; the weights only matter when the uplink is saturated.

| Class | Weight | Queue size | Matched by |
|---|---|---|---|
| Real-time | 8 | 300 | UDP, any host, except port 443 |
| RTMP | 6 | 300 | TCP 1935 |
| Default | 3 | 600 | everything else, including QUIC (UDP 443) |
| Bulk | 1 | 900 | traffic from VLANs tagged bulk (guest, IoT, cameras, storage, crypto nodes, lab) |

Rule order at WAN egress, all quick: RTMP, then tagged bulk, then QUIC (UDP 443) back to default, then other UDP to
real-time, then the default catch-all. Port 443 over UDP is QUIC, which carries bulk web and cloud uploads, so it must not
qualify as real-time; pfSense has no "not port" match for a port, so a rule that sends port 443 to the default queue sits
ahead of the real-time rule.

The bulk class uses a pf tag. A floating `match` rule on the bulk VLANs (direction in) sets the tag, and the WAN egress rule
matches it. Put that tag rule **first** among the floating rules, so a `quick` rule from a package (pfBlockerNG) cannot
end evaluation before the tag is set. Bulk traffic was confirmed tagged end to end by the packet counter on the WAN rule.

Per-VLAN caps on top: a shared pool for guests with one fair queue per guest, per-device caps for IoT and cameras, and a
per-node cap for crypto nodes that also covers their inbound peers (lesson 7).

## How to measure

- Use **two test servers** in different regions you control, not public ones. Single-server results moved by about 15
  percent from path and host variance alone. [speedtest-droplet](https://github.com/ChiefGyk3D/speedtest-droplet) builds
  throwaway iperf3 servers with the firewall rules (TCP and UDP) already filled in.
- Compare **shaped and unshaped** by disabling only the WAN limiter rules (by tracker ID) for a few minutes, with a
  dead-man timer that restores the configuration if your session drops.
- Measure **latency under load**, not only throughput: run `ping` to a nearby host while iperf3 runs and compare with idle.
- For the real-time class, run `iperf3 -u -b 5M` for jitter and loss while a wired LAN host saturates the uplink.
- Read `pfctl -vsr` to see the packet counter on each class rule; it proves traffic landed in the class you meant.
- UDP tests need UDP allowed in the cloud firewall as well as the host firewall, or `iperf3 -u` hangs at its handshake.

## Making changes safely

Back up the configuration, arm a dead-man timer that restores it after ten to fifteen minutes, apply, then verify with
gates: rule counts changed by the expected amount, the limiter attachments you did not touch are still there, WAN answers
ping, every gateway is online. If any gate fails, restore automatically. Two of the changes here rolled themselves back
on a check that was too strict; that is the system working, and the fix was to correct the check.

## What is still unverified

- Whether CoDel is active on the upload child queues. The `dnctl` label changed between states for the same
  configuration, so it was treated as unreliable and the queue sizes bound the delay.
- The upload side of the mask check (only the download side was observed with live buckets).
- Cellular speed varies with time of day; re-measure before trusting a single reading.
