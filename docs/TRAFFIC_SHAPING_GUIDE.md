# pfSense Traffic Shaping for Homelab — Complete Guide

> **Audience**: Homelabbers running pfSense who need QoS for streaming, gaming, VoIP, or other latency-sensitive workloads alongside bulk traffic (NAS sync, P2P, backups).

> **Prerequisites**: pfSense 2.7+ or pfSense CE 2.7+, SSH access to firewall, basic familiarity with firewall rules.

---

## Table of Contents

1. [The Problem](#the-problem)
2. [Traffic Shaping Approaches in pfSense](#traffic-shaping-approaches-in-pfsense)
3. [Approach 1: ALTQ (Legacy Queues)](#approach-1-altq-legacy-queues)
4. [Approach 2: Dummynet Limiters](#approach-2-dummynet-limiters)
5. [Approach 3: Limiters with Weighted Queues (Recommended)](#approach-3-limiters-with-weighted-queues-recommended)
6. [Real-World Example: Streaming Priority](#real-world-example-streaming-priority)
7. [Real-World Example: Gaming + VoIP Priority](#real-world-example-gaming--voip-priority)
8. [Real-World Example: VLAN-Based Bandwidth Caps](#real-world-example-vlan-based-bandwidth-caps)
9. [CoDel and fq_codel — Fighting Bufferbloat](#codel-and-fq_codel--fighting-bufferbloat)
10. [Tag-Based QoS — The Flexible Pattern](#tag-based-qos--the-flexible-pattern)
11. [Monitoring and Verification](#monitoring-and-verification)
12. [Common Mistakes](#common-mistakes)
13. [Decision Tree](#decision-tree)

---

## The Problem

Most homelabs share a single ISP uplink across many devices and VLANs. Without traffic shaping, all traffic is treated equally by the firewall. When your WAN upload or download approaches capacity, **every connection suffers** — including latency-sensitive ones like live streams, video calls, and online games.

### Symptoms of Missing QoS

- Live stream frame drops during uploads from other devices
- VoIP/Zoom calls breaking up when NAS syncs to cloud
- Gaming lag spikes when someone starts a large download
- General "internet feels slow" even though speedtests look fine

### Why Speedtests Lie

A speedtest measures **maximum throughput** with nothing else competing. Real-world traffic has dozens of flows competing simultaneously. Without QoS, a NAS uploading 50GB to OneDrive will happily saturate your entire upload pipe, starving your 6 Mbps live stream of the bandwidth it needs.

---

## Traffic Shaping Approaches in pfSense

pfSense offers three distinct traffic shaping mechanisms. They can be **combined** but understanding when to use each is critical.

| Approach | Mechanism | Best For | Limitations |
|---|---|---|---|
| **ALTQ** | Priority queuing on interfaces | Simple priority (gaming > browsing > P2P) | Per-interface only, no per-host limits, deprecated in newer FreeBSD |
| **Limiters (dummynet pipes)** | Bandwidth caps with AQM | VLAN/host bandwidth caps, CoDel bufferbloat prevention | No priority between flows within a pipe (without child queues) |
| **Limiters + Weighted Queues** | dummynet pipes with WF2Q+ child queues | Priority + bandwidth control combined | Slightly more complex config |

**Recommendation**: Use **Limiters + Weighted Queues** (Approach 3) for most homelab scenarios. It gives you both bandwidth caps AND priority in one system.

---

## Approach 1: ALTQ (Legacy Queues)

ALTQ (Alternate Queuing) is pfSense's built-in traffic shaper wizard. It creates priority queues on each interface using PRIQ (priority queuing).

### How It Works

```
WAN Interface (igc0)
├── qACK      priority 6  ← TCP ACKs (highest, keeps connections responsive)
├── qGames    priority 5  ← Gaming traffic
├── qOthersHigh priority 4 ← VoIP, streaming
├── qDefault  priority 3  ← Normal browsing (default queue)
├── qOthersLow priority 2 ← Low-priority bulk
└── qP2P      priority 1  ← Torrents, P2P (lowest)
```

### Configuration via GUI

1. **Firewall → Traffic Shaper → By Interface**
2. Set WAN interface bandwidth (slightly below actual — e.g., 33 Mbps for a 35 Mbps connection)
3. Create queues with priorities 1-7
4. **Firewall → Traffic Shaper → Floating Rules** → Create match rules that assign traffic to queues

### Example: ALTQ Match Rule for RTMP

```
Type: match
Interface: WAN
Direction: any
Protocol: TCP
Destination Port: 1935
Queue: qOthersHigh
Description: Match RTMP Streaming
```

### Pros
- Simple wizard-driven setup
- Good for basic "gaming > browsing > torrents" priority
- Built into pfSense GUI natively

### Cons
- **Cannot set per-host or per-VLAN bandwidth limits**
- **Only works on traffic already on the interface** — cannot prioritize by source VLAN
- Port-based matching misses RTMPS (port 443) and many modern protocols
- Priority is strict — lower queues get **nothing** if higher queues are full
- Cannot use CoDel or fq_codel AQM (limited to RED/ECN)
- **Deprecated** in newer FreeBSD — may be removed in future pfSense versions

### When to Use ALTQ
- You just need basic priority classes
- Your traffic is easily classified by port number
- You don't need per-device bandwidth limits

---

## Approach 2: Dummynet Limiters

Dummynet limiters (pipes) are pfSense's bandwidth control system. They cap throughput for matched traffic.

### How It Works

```
Pipe 14 (Crypto_Node_Up): 3 Mbps
  └── All traffic from VLAN 18 → capped at 3 Mbps upload total

Pipe 6 (Security_Up): 20 Mbps
  └── All traffic from VLAN 15 → capped at 20 Mbps upload total
```

### Configuration via GUI

1. **Firewall → Traffic Shaper → Limiters**
2. Create a **pipe** (parent) with bandwidth limit
3. Create **child queues** (optional) under the pipe
4. **Firewall → Rules → [Interface]** → Edit a pass rule → Advanced → set "In/Out" pipe

### Per-Host vs Per-Subnet Masks

Limiters support **masks** that create separate bandwidth buckets per host:

```xml
<!-- Per-host: each device on VLAN gets its own 3 Mbps limit -->
<mask>dstaddress</mask>
<maskbits>32</maskbits>

<!-- Per-subnet: entire VLAN shares one 3 Mbps limit -->
<mask>none</mask>
```

### Applying Limiters to Firewall Rules

In the GUI, edit a firewall rule → Advanced Options → In/Out pipe:

| Field | Value | Meaning |
|---|---|---|
| In (pipe) | `VLAN_Upload_Limiter` | Caps upload (traffic entering the firewall from this interface) |
| Out (pipe) | `VLAN_Download_Limiter` | Caps download (traffic leaving the firewall to this interface) |

**Critical**: "In" and "Out" are from the **firewall's perspective on the interface where the rule matches**. For a rule on VLAN 100:
- **In** = traffic from VLAN 100 hosts → firewall → WAN (upload)
- **Out** = traffic from WAN → firewall → VLAN 100 hosts (download)

### Example: Cap a VLAN to 3 Mbps Upload

```
Pipe: Crypto_Node_Up
  Bandwidth: 3 Mbps
  Mask: dstaddress/32 (per-host on destination = per-source-host for upload)
  AQM: droptail
  Scheduler: FIFO

Firewall Rule on VLAN 18:
  pass in from VLAN18_NET to any → In pipe: Crypto_Node_Up, Out pipe: Crypto_Node_Down
```

### Pros
- Per-VLAN, per-host, or per-subnet bandwidth caps
- CoDel AQM available (bufferbloat prevention)
- Masks allow dynamic per-host fairness without individual rules
- Works alongside ALTQ

### Cons
- **No priority within a pipe** (without child queues) — all flows treated equally
- Cannot say "streaming is more important than backups" within the same pipe
- Configuration via GUI can be unintuitive (In/Out direction confusion)

### When to Use Plain Limiters
- You need hard bandwidth caps per VLAN or per host
- You want CoDel bufferbloat prevention on WAN
- You don't need intra-pipe priority (e.g., all traffic in a VLAN is equal)

---

## Approach 3: Limiters with Weighted Queues (Recommended)

This combines dummynet pipes with **WF2Q+ weighted child queues** — giving you both bandwidth caps AND priority differentiation.

### How It Works

```
Pipe 16 (WANUp): 33 Mbps, WF2Q+ scheduler
├── WANUpStream:  weight 9  (90% priority) → Streaming PC traffic
└── WANUpQ:       weight 1  (10% priority) → Everything else

When both queues have traffic:
  WANUpStream gets 29.7 Mbps (9/10 of 33)
  WANUpQ gets 3.3 Mbps (1/10 of 33)

When only one queue has traffic:
  That queue gets the full 33 Mbps (WF2Q+ is work-conserving)
```

### Key Concept: Work-Conserving Scheduling

WF2Q+ (Weighted Fair Queuing) is **work-conserving** — unused bandwidth from one queue is immediately available to others. Weights only matter during **contention** (when the pipe is full).

This means:
- When you're NOT streaming, everything gets full speed
- When you ARE streaming, your stream gets priority, and everything else still works (just slower)
- No bandwidth is "wasted" by reserving it for traffic that isn't happening

### Configuration via GUI

1. **Firewall → Traffic Shaper → Limiters**
2. Create parent pipe: `WANUp`, 33 Mbps, Scheduler: `wf2q+`, AQM: `codel`
3. Create child queue: `WANUpStream`, Weight: 9, AQM: `codel`, ECN: on
4. Create child queue: `WANUpQ`, Weight: 1, AQM: `codel`, ECN: on
5. Create firewall rules that route priority traffic to `WANUpStream` and everything else to `WANUpQ`

### Configuration via config.xml

```xml
<dnshaper>
    <queue>
        <name>WANUp</name>
        <number>16</number>
        <bandwidth>
            <item>
                <bw>33</bw>
                <bwscale>Mb</bwscale>
            </item>
        </bandwidth>
        <enabled>on</enabled>
        <mask>none</mask>
        <sched>wf2q+</sched>
        <aqm>codel</aqm>
        <ecn>on</ecn>
        <!-- High-priority child queue -->
        <queue>
            <name>WANUpStream</name>
            <number>3</number>
            <weight>9</weight>
            <enabled>on</enabled>
            <aqm>codel</aqm>
            <ecn>on</ecn>
        </queue>
        <!-- Default/bulk child queue -->
        <queue>
            <name>WANUpQ</name>
            <number>2</number>
            <weight>1</weight>
            <enabled>on</enabled>
            <aqm>codel</aqm>
            <ecn>on</ecn>
        </queue>
    </queue>
</dnshaper>
```

### Weight Math

| Weight Ratio | High Queue Share | Low Queue Share | Use Case |
|---|---|---|---|
| 9:1 | 90% | 10% | Streaming — needs most of the pipe |
| 7:3 | 70% | 30% | Gaming — needs priority but not as much bandwidth |
| 5:5 | 50% | 50% | Fair share between two equal classes |
| 3:1 | 75% | 25% | VoIP — low bandwidth but strict priority |

### Pros
- **Best of both worlds**: bandwidth caps + priority
- **Work-conserving**: no wasted bandwidth
- CoDel AQM on each queue independently
- Flexible weight ratios
- Tag-based classification (see below) works perfectly with this

### Cons
- Slightly more complex than plain limiters
- Must understand child queue numbering for `dnqueue()` rules
- GUI support for child queue weights can be inconsistent — may need config.xml editing

### When to Use Weighted Queues
- You need both bandwidth control AND priority
- Multiple traffic classes compete for the same pipe (streaming + bulk + IoT)
- You want CoDel per-class (not just per-pipe)

---

## Real-World Example: Streaming Priority

**Scenario**: Live streaming PC simulcasting to 4 platforms (Twitch, Kick, YouTube, TikTok) on a 35 Mbps WAN upload.

### The Problem

| Stream | Bitrate | Protocol | Port |
|---|---|---|---|
| Twitch | 6,000 Kbps + audio | RTMP or RTMPS | 1935 or 443 |
| Kick | 6,000 Kbps + audio | RTMPS | 443 |
| YouTube | 6,000 Kbps + audio | RTMPS | 443 |
| TikTok | 2,500 Kbps + audio | RTMPS | 443 |
| **Total** | **~22 Mbps** | | |

A port-based ALTQ rule only catches port 1935. Most platforms now use RTMPS on port 443, which is indistinguishable from HTTPS browsing traffic by port alone.

### The Solution: Tag + Weighted Queue

**Step 1**: Create weighted pipe (as in Approach 3 above)

**Step 2**: Tag all traffic from the streaming PC

```
Floating Match Rule:
  Direction: in
  Interface: VLAN where streaming PC lives
  Source: 192.168.x.x (streaming PC IP)
  Tag: STREAM_PC
```

**Step 3**: Route tagged traffic to priority queue before the catch-all

```
Floating Pass Rule (BEFORE catch-all):
  Direction: out
  Interface: WAN
  Tagged: STREAM_PC
  Quick: yes
  In pipe: WANUpStream
  Out pipe: WANDownQ

Floating Pass Rule (catch-all, existing):
  Direction: out
  Interface: WAN
  Source: WAN address
  In pipe: WANUpQ
  Out pipe: WANDownQ
```

**Rule order matters**: The tagged rule must come BEFORE the catch-all in floating rules. pfSense processes floating rules top-to-bottom, and `quick` stops processing at the first match.

### Result

| Condition | Stream Gets | Everything Else Gets |
|---|---|---|
| Not streaming | — | Full 33 Mbps |
| Streaming, no contention | ~22 Mbps | Remaining ~11 Mbps |
| Streaming + NAS sync + Monero | ~29.7 Mbps (90%) | ~3.3 Mbps (10%) |

### Important: State Table Flushing

New rules only apply to **new connections**. Existing TCP sessions (including active streams) follow the rule they were created with. After adding priority rules, you must either:

1. Restart OBS (creates new connections through new rules), or
2. Flush the streaming PC's states: `pfctl -k 192.168.x.x` (causes ~3-5 second reconnect)

---

## Real-World Example: Gaming + VoIP Priority

**Scenario**: Gaming PC and VoIP phone need low latency. NAS/servers do bulk uploads.

### Configuration

```
Pipe: WANUp (33 Mbps, WF2Q+, CoDel)
├── WANUpRealtime:  weight 5  → Gaming + VoIP
├── WANUpNormal:    weight 3  → Normal browsing, email
└── WANUpBulk:      weight 2  → NAS sync, backups, P2P
```

### Tagging Rules

```
match in on GAMING_VLAN from GAMING_PC → tag REALTIME
match in on VOIP_VLAN from any → tag REALTIME
match in on NAS_VLAN from NAS_IP → tag BULK

pass out quick on WAN tagged REALTIME → WANUpRealtime
pass out quick on WAN tagged BULK → WANUpBulk
pass out quick on WAN from wanip → WANUpNormal  (catch-all)
```

### Under Contention (33 Mbps pipe full)

| Queue | Weight | Share | Typical Traffic |
|---|---|---|---|
| Realtime | 5 | 16.5 Mbps | Gaming (1-3 Mbps) + VoIP (100 Kbps) — huge headroom |
| Normal | 3 | 9.9 Mbps | Web browsing, email, API calls |
| Bulk | 2 | 6.6 Mbps | OneDrive sync, Backblaze, torrents |

Gaming typically only needs 1-3 Mbps but is extremely latency-sensitive. The weight-5 allocation ensures gaming packets are **always dequeued first** during contention, preventing lag spikes.

---

## Real-World Example: VLAN-Based Bandwidth Caps

**Scenario**: Multiple VLANs with different trust levels and bandwidth needs.

### Plain Limiters (No Priority Within VLAN)

| VLAN | Pipe | Download | Upload | Mask | Purpose |
|---|---|---|---|---|---|
| 10 — Users | No limiter | Full | Full | — | Trusted users, full speed |
| 13 — Guest | Guest_Down/Up | 100 Mbps | 2 Mbps | Per-host /32 | Each guest capped individually |
| 14 — IoT | IoT_Down/Up | 10 Mbps | 2 Mbps | Per-host /32 | IoT devices capped individually |
| 15 — Security | Security_Down/Up | 200 Mbps | 20 Mbps | Per-host /32 | Cameras need download for firmware |
| 18 — Crypto | Crypto_Down/Up | 30 Mbps | 3 Mbps | Per-host /32 | Node bandwidth capped |

### Applying in GUI

For each VLAN's "pass all" rule:
1. Edit the rule → Advanced Options
2. **In / Out pipe**: Select upload limiter / download limiter
3. Save → Apply

### Per-Host vs Shared

- **Per-host mask** (`dstaddress/32` for upload, `srcaddress/32` for download): Each device gets its own bandwidth bucket. 10 IoT devices each get 2 Mbps upload independently.
- **No mask** (`none`): All devices on the VLAN share the limit. 10 IoT devices share 2 Mbps upload total.

Choose per-host for guest/IoT (fairness), shared for VLANs where total aggregate matters (crypto nodes, NAS).

---

## CoDel and fq_codel — Fighting Bufferbloat

### What Is Bufferbloat?

When a link is saturated, packets queue up in buffers. Large buffers cause **hundreds of milliseconds of latency** for ALL traffic — even small packets like game inputs or VoIP audio. This is bufferbloat.

### CoDel (Controlled Delay)

CoDel is an **Active Queue Management** (AQM) algorithm that:
1. Monitors the **sojourn time** (how long packets sit in the queue)
2. If sojourn time exceeds `target` (default 5ms) for longer than `interval` (default 100ms), starts dropping packets
3. Dropped packets signal TCP senders to slow down
4. Result: queue stays short, latency stays low

### fq_codel (Fair Queuing + CoDel)

fq_codel adds per-flow fairness on top of CoDel:
- Creates separate sub-queues per flow (identified by 5-tuple)
- Each flow gets CoDel independently
- A bulk download can't abuse a gaming flow's queue

### When to Use Which

| AQM | Use When |
|---|---|
| **droptail** | Low-bandwidth VLANs where CoDel overhead isn't worth it (IoT, crypto nodes) |
| **codel** | WAN pipes, any pipe where latency matters |
| **fq_codel** | Single flat pipe (no child queues) where you want per-flow fairness built-in |
| **codel on each child queue** | WF2Q+ weighted queues — recommended, gives CoDel per traffic class |

### CoDel Parameters

| Parameter | Default | What It Does |
|---|---|---|
| `target` | 5 ms | Maximum acceptable queuing delay |
| `interval` | 100 ms | How long to wait before starting drops |

**Do not change these** unless you have specific latency measurements showing they're wrong. The defaults are well-tuned for most connections.

### Enable ECN

**ECN (Explicit Congestion Notification)** allows CoDel to signal congestion without dropping packets. Enable it on all CoDel queues:

```xml
<aqm>codel</aqm>
<ecn>on</ecn>
```

This reduces unnecessary retransmissions and improves throughput by ~5-10% under congestion.

---

## Tag-Based QoS — The Flexible Pattern

Tags are **the most powerful QoS mechanism** in pfSense because they decouple classification from action.

### How Tags Work

1. A **match** or **pass** rule on an internal interface **tags** packets (e.g., `tag STREAM_PC`)
2. The tag follows the packet through all subsequent rule processing
3. A rule on the WAN interface matches **tagged** packets and applies QoS

### Why Tags Beat Port-Based Rules

| Method | Catches | Misses |
|---|---|---|
| Port 1935 match | Raw RTMP | RTMPS (443), YouTube (443), Kick (443), TikTok (443) |
| Source IP tag | **Everything from that host** | Nothing — catches RTMP, RTMPS, API calls, chat, analytics |

Modern streaming platforms use HTTPS/TLS on port 443. Port-based classification is useless for prioritizing streams unless you tag by source.

### Tag Rule Template

```xml
<!-- Floating match rule — tags traffic, doesn't pass/block -->
<rule>
    <type>match</type>
    <interface>opt1</interface>          <!-- VLAN interface name -->
    <ipprotocol>inet</ipprotocol>
    <tag>MY_TAG</tag>                    <!-- Tag name - arbitrary string -->
    <direction>in</direction>
    <floating>yes</floating>
    <source>
        <address>192.168.x.x</address>  <!-- Device to tag -->
    </source>
    <destination>
        <any></any>
    </destination>
    <descr>Tag My Device</descr>
</rule>

<!-- Floating pass rule — matches tagged traffic, applies QoS -->
<rule>
    <type>pass</type>
    <interface>wan</interface>
    <ipprotocol>inet</ipprotocol>
    <tagged>MY_TAG</tagged>              <!-- Match the tag -->
    <direction>out</direction>
    <quick>yes</quick>                   <!-- Stop processing here -->
    <floating>yes</floating>
    <source>
        <network>wanip</network>
    </source>
    <destination>
        <any></any>
    </destination>
    <descr>Priority for My Device</descr>
    <gateway>WAN_DHCP</gateway>
    <dnpipe>HighPriorityQueue</dnpipe>   <!-- Upload queue -->
    <pdnpipe>DownloadQueue</pdnpipe>     <!-- Download queue -->
</rule>
```

### Multiple Tags

You can tag different devices/VLANs and route them to different queues:

```
match in on VLAN10 from STREAM_PC → tag STREAM
match in on VLAN15 from GAMING_PC → tag GAMING  
match in on VLAN21 from NAS → tag BULK

pass out quick on WAN tagged STREAM → WANUpStream (weight 9)
pass out quick on WAN tagged GAMING → WANUpGaming (weight 7)
pass out quick on WAN tagged BULK → WANUpBulk (weight 1)
pass out quick on WAN from wanip → WANUpDefault (weight 3)
```

---

## Monitoring and Verification

### Check Active Pipes and Queues

```bash
# SSH to pfSense
ssh admin@your-pfsense-ip

# Show all pipes with bandwidth and scheduler
dnctl pipe show

# Show all queues with weights, AQM, and traffic stats
dnctl queue show

# Show a specific pipe
dnctl pipe 16 show
```

### Check Active Firewall Rules

```bash
# Show all active rules (look for dnqueue/dnpipe assignments)
pfctl -sr | grep -E 'dnpipe|dnqueue|tag '

# Show ALTQ queue stats
pfctl -s queue

# Show state table entries for a specific host
pfctl -s states | grep '192.168.x.x'
```

### Real-Time Bandwidth Monitoring

```bash
# WAN throughput — 1-second samples, 5 samples
netstat -I igc0 -b -w 1 -q 5

# Output columns: input packets/bytes, output packets/bytes
# Multiply bytes by 8 and divide by 1,000,000 for Mbps
```

### Verify Traffic Hitting Correct Queue

```bash
# Watch queue stats — look for increasing packet counts
watch -n 1 'dnctl queue show'

# If a queue shows 0 flows, traffic isn't matching the rule
# Common cause: existing states pre-date the rule
# Fix: pfctl -k <source-ip>  (flushes states, causes brief reconnect)
```

### Per-Host Upload Analysis (Advanced)

```bash
# Dump verbose state table and analyze with Python
pfctl -vvs states > /tmp/states.txt

# Parse for per-host upload bytes:
# Look for igc0 (WAN) lines with (inner_ip:port) -> dest
# The first number in "X:Y bytes" is outbound
```

---

## Common Mistakes

### 1. Setting WAN Pipe to Exactly ISP Speed

**Wrong**: Setting WANUp to 35 Mbps when ISP provides 35 Mbps.

**Right**: Set to **90-95% of actual speed** (e.g., 33 Mbps). This ensures YOUR firewall is the bottleneck — not the ISP's equipment. If the ISP router's buffer fills up first, your CoDel/queuing is useless because the queue is in someone else's hardware.

### 2. Forgetting to Flush States

New rules only apply to **new connections**. If you add priority rules while traffic is flowing, existing TCP sessions continue through the old rule path. Either restart the application or flush states:

```bash
pfctl -k 192.168.x.x  # Flush specific host
pfctl -F states        # CAUTION: Flush ALL states (disrupts everything)
```

### 3. ALTQ + Limiters Conflict

ALTQ queue assignments (`queue qOthersHigh`) and limiter queue assignments (`dnqueue(3, 1)`) are **separate systems**. A packet can be assigned to both, but they don't interact. If you set ALTQ priority on a match rule AND a limiter on a pass rule, the limiter controls bandwidth while ALTQ controls the scheduling within the ALTQ tree.

**Recommendation**: Pick one system and use it consistently. Limiters with WF2Q+ child queues can do everything ALTQ does plus bandwidth caps.

### 4. Wrong Mask Direction

For **upload** limiters (traffic leaving the LAN toward the firewall):
- In-pipe mask should be `dstaddress` (destination = the internet, one bucket per internet destination) or `none` (shared)
- Most commonly use `dstaddress/32` to create per-host buckets **from pfSense's perspective**

For **download** limiters:
- Out-pipe mask should be `srcaddress` (source = the internet, one bucket per source)

**When in doubt**: Use `none` for shared limits, test, then add masks if you need per-host fairness.

### 5. Not Setting Pipe Bandwidth Below ISP Rate

The pipe bandwidth must be **below** your ISP's actual capacity for CoDel to work. If the pipe is set at or above ISP speed, packets queue at the ISP's equipment (where you have no control), not at your firewall (where CoDel manages the queue).

### 6. Using fq_codel with Child Queues

If you're using WF2Q+ child queues, set the pipe scheduler to `wf2q+` and use `codel` AQM on each child queue individually. Don't set the pipe itself to `fq_codel` — the per-flow fairness of fq_codel conflicts with the weighted scheduling of WF2Q+.

---

## Decision Tree

```
Do you need bandwidth caps per VLAN/host?
├── YES → Use Limiters (Approach 2 or 3)
│   │
│   └── Do you need priority WITHIN a pipe?
│       ├── YES → Use Limiters + WF2Q+ Weighted Queues (Approach 3)
│       │   │
│       │   └── Is traffic identifiable by port?
│       │       ├── YES → Port-based match rules assign queues
│       │       └── NO → Tag-based classification (recommended)
│       │
│       └── NO → Plain Limiters with CoDel (Approach 2)
│
└── NO → Just need priority classes?
    ├── Simple / few classes → ALTQ (Approach 1)
    └── Complex / future-proof → Limiters + Weighted Queues (Approach 3)

Always enable CoDel on WAN-facing pipes.
Always set pipe bandwidth to 90-95% of actual ISP speed.
Always use Tags for host-based classification over port-based.
```

---

## Further Reading

- [pfSense Traffic Shaping Documentation](https://docs.netgate.com/pfsense/en/latest/trafficshaper/index.html)
- [Bufferbloat.net — Understanding Bufferbloat](https://www.bufferbloat.net/)
- [CoDel Algorithm (RFC 8289)](https://www.rfc-editor.org/rfc/rfc8289)
- [dummynet(4) — FreeBSD Manual](https://man.freebsd.org/cgi/man.cgi?query=dummynet)
- [WF2Q+ Paper — Fair Queuing](https://ieeexplore.ieee.org/document/642480)
