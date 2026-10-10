# October 2026 Tuning Results: What Changed and What It Measured

> **Audience**: anyone deciding which pfSense tuning steps are worth doing, and what to expect from them.
>
> **Scope**: one real firewall (pfSense CE 2.8.1, 4-core Xeon D at 2.2 GHz with no turbo, a 2.5G WAN port, a 2x1G LACP LAN
> trunk, 14 VLANs, inline Suricata on the WAN, pfBlockerNG with DNSBL) moved from a 35 Mbit/s uplink to a **1 Gbit/s down,
> 500 Mbit/s up** cable line. Every number below was measured on that box. Most are single boxes and a few runs each, so read
> them as orders of magnitude. Addresses, hostnames and interface names are left out on purpose.

Each section links to the guide with the method and commands.

## Summary

| Area | Before | After | Where |
|---|---|---|---|
| Download pipe, delivered | 920 Mbit/s pipe, about 800 to 840 delivered | 980 Mbit/s pipe, about 880 to 900 delivered (one server) | [Shaping notes](SHAPING_OPTIMIZATION_NOTES.md) |
| Upload pipe | 33 Mbit/s (sized for the old uplink) | 475 Mbit/s | [Shaping notes](SHAPING_OPTIMIZATION_NOTES.md) |
| Worst latency under heavy parallel download | 105 ms unshaped | 47 ms shaped | [Shaping notes](SHAPING_OPTIMIZATION_NOTES.md) |
| 5 Mbit/s UDP stream while a bulk host saturated the uplink (about 480 Mbit/s) | not measured | 0% loss; jitter 3.2 ms idle, 1.0 ms loaded | [Shaping notes](SHAPING_OPTIMIZATION_NOTES.md) |
| Cellular failover latency under download | +120 to +220 ms (485 ms worst), unshaped | under 200 ms worst, with a limiter at 85 to 90% of the slowest reading | [Shaping notes](SHAPING_OPTIMIZATION_NOTES.md) |
| Active pf ruleset | 1,049 lines (dead ALTQ and wizard rules) | 821 lines, then 790 after disabling 17 duplicate pass rules (840 once pfBlockerNG re-added its own DNSBL rules) | [Shaping notes](SHAPING_OPTIMIZATION_NOTES.md) |
| Suricata CPU for the LAN parent instance (same 237 Mbit/s download) | +64% of a core | +3% of a core | [Suricata guide](SURICATA_OPTIMIZATION_GUIDE.md#do-not-inspect-the-same-packets-twice) |
| Suricata CPU, all instances together (same download) | +136% | about +73% | same |
| Rules loaded on the inline WAN instance | 70,600 | 59,233 (-16%) | [Suricata guide](SURICATA_OPTIMIZATION_GUIDE.md#inline-ips-cost-what-it-takes-what-cuts-it-what-does-not) |
| WAN IPS drops that were IP-reputation duplicates of pfBlockerNG | 113 of 116 in one hour | 0 (rules removed) | same |
| Suricata capture drops after the changes | not measured (stats were off) | 0 kernel drops on WAN, cell and LAN instances | same |
| DNSBL (blocklist DNS) | not enforcing for about 5 months: feed files about 3,570 hours old, a listed ad domain resolved normally | enforcing, listed domains answer `0.0.0.0`, feeds refreshed daily | [pfBlockerNG guide](PFBLOCKERNG_OPTIMIZATION.md#4-is-dnsbl-actually-enforcing) |
| pfBlockerNG feeds known dead or broken | unknown | 6 found dead or broken, 2 fixed, 1 removed; see below | [pfBlockerNG guide](PFBLOCKERNG_OPTIMIZATION.md#6-are-the-feeds-themselves-alive) |
| EVE forwarder to the SIEM | dead since 2026-07-30 (72 days, nobody noticed) | running, 16 interfaces; watchdog restart verified within one minute | [Forwarder monitoring](../operations/SURICATA_FORWARDER_MONITORING.md) |
| DNS repeat lookups | cold lookup about 179 ms (DoT + DNSSEC) | repeat lookups 0 ms with prefetch and a 32 MB cache; cold path unchanged | [Shaping notes](SHAPING_OPTIMIZATION_NOTES.md) |

## What was measured and found, in the order it mattered

1. **The old upload limiter was throttling the new download.** ACKs for a fast download have to go out; a 33 Mbit/s upload
   pipe held downloads near 800 to 840 Mbit/s while the line could do about 1 Gbit/s. With the limiter rules off the line
   measured 945 to 1,020 Mbit/s down from one favourable server (about 910 combined across two) and about 510 Mbit/s up.
2. **Suricata inspected the same LAN packets three times** (the WAN inline instance, a legacy instance on the VLAN trunk's
   parent interface, and the VLAN's own instance). A BPF filter on the parent removed the duplicate for about a 45%
   cut in total Suricata CPU, with no inspection lost.
3. **DNSBL had been silently off since a package reinstall.** pfBlockerNG 3.2.14 stores the DNSBL virtual IP as a VIP ID;
   the migration dropped it, and the GUI still showed lists as configured. Verified fixed by resolving a listed domain.
4. **The SIEM pipeline was dead for 72 days** because of a mis-named boot script, a missing forwarder file and an empty root
   crontab. A freshness check now exits non-zero when the newest event is stale.
5. **pfBlockerNG feeds had quietly died**; see the table below.
6. **Things that were tested and did not pay off at 1 Gbit/s:** bypassing Suricata inspection of encrypted flows (no change
   for bulk transfers, about a third less CPU for many short connections) and moving Suricata signature files into
   pfBlockerNG (nothing worth moving: the overlap was only the IP-reputation set, already removed).

## pfBlockerNG feed health (audit, 2026-10-10)

About 25 IP feeds and 40 DNSBL feeds were checked for entry count, file age and download failures.

| Finding | Count / detail |
|---|---|
| IP tables that are only the `127.1.7.7` placeholder or have 1 to 3 entries from a large feed | `Abuse_SSLBL` (feed retired upstream 2025-01-02), `ISC_Shadowserver` and `ISC_Shodan` (wrong URL form for the parser), `Darklist` (header only that day) |
| Feeds that fail to download repeatedly | `Maltrail_Scanners_All` (15 in 3 days), `H3X_1M`, `osint_malicious`, `1Hosts_Pro` (5 each) |
| Orphan list files 150 days old | 3 (from feeds that were renamed or removed) |
| DNSBL feeds showing 0 entries | about 10, most likely cross-feed de-duplication, not proven broken |
| Fixes applied | `Abuse_SSLBL` removed; the two ISC URLs switched to their `?text` form. With the new URL the downloads parse 988 (Shadowserver) and 55 (Shodan) addresses instead of 3 and 2; after de-duplication against the other scanner lists 24 and 2 are new. The next scheduled fetch (00:01) is what confirms the URL change end to end. |

See the guide's section for the commands to reproduce this on your own box.

## What was applied but not isolated

These were changed in the same window as others, so no separate effect is claimed:

- Ethernet flow control turned off on the WAN, cell and LAN NICs. The change is persistent through four tunables but
  has not yet been verified across a reboot.
- DHCP "deny unknown clients" on four sensitive VLANs (Kea `KNOWN` class), with static reservations added first.
- UPnP restricted to the three VLANs that need it with one allowed host, and stale hosts removed.

## What was not measured

- Throughput or latency effect of flow control on its own.
- Behaviour across the pfSense 2.8.1 to 2.9.0 upgrade. Pre- and post-upgrade checks are in the
  [Upgrading pfSense](PFSENSE_UPGRADE_GUIDE.md) guide.
- Anything above 1 Gbit/s on the WAN. The capacity table in the Suricata guide is a projection from a UDP sweep up to
  950 Mbit/s, not a measurement at 2 or 2.5 Gbit/s.
