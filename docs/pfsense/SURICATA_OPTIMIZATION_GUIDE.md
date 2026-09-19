# Suricata IDS/IPS Optimization Guide for pfSense

The complete walk-through for Suricata on pfSense: install → interfaces → rule selection → IDS vs IPS → performance → log management → validation → maintenance. It is written for home labs and small businesses and applies to **any pfSense box**; the few places that mention forwarding logs to a SIEM are marked as optional.

Its companion, [SURICATA_CONFIGURATION.md](SURICATA_CONFIGURATION.md), covers the *why*: design decisions, interface strategy, SID-tuning philosophy, GeoIP, common failure modes and what survives a pfSense upgrade. Read this guide first, then that one.

## Table of Contents
- [Initial Setup](#initial-setup)
- [Interface Configuration](#interface-configuration)
- [Rule Selection Strategy](#rule-selection-strategy)
- [Performance Tuning](#performance-tuning)
- [Log Management](#log-management)
- [IDS vs IPS Mode](#ids-vs-ips-mode)
- [Testing and Validation](#testing-and-validation)
- [Maintenance](#maintenance)
- [Reference Deployment](#reference-deployment)
- [Quick Reference](#quick-reference)

---

## Initial Setup

### Installation

1. **Install the Suricata package**
   - **System > Package Manager > Available Packages**
   - Search for "Suricata", click **Install**

2. **Enable Suricata on interfaces**
   - **Services > Suricata > Interfaces**
   - Click **Add**
   - Start with the WAN interface

### Hardware

Sizing depends almost entirely on how many interfaces you inspect and whether any of them run inline IPS. See [HARDWARE_REQUIREMENTS.md](../install/HARDWARE_REQUIREMENTS.md) for the full tables. In short:

| Deployment | CPU | RAM |
|------------|-----|-----|
| WAN only, IDS mode | 2-4 cores | 8 GB |
| WAN inline IPS + a few VLANs | 4-8 cores | 8-16 GB |
| Many interfaces (10+), mixed IPS/IDS | 8 cores | 16 GB |

Intel NICs (igb/igc/ix/em) have the best netmap support, which matters for inline mode. The single [reference deployment](#reference-deployment) used throughout this repository's docs is an 8-core Intel Atom C3758 with 16 GB RAM running 15 Suricata instances.

---

## Interface Configuration

### Which Interfaces to Monitor?

**Home lab / family network:**
```
✅ WAN              - Monitor all inbound threats (essential)
⚠️ LAN              - Optional: internal visibility
⚠️ VLAN interfaces  - Optional: each one adds CPU cost; see LAN_MONITORING.md for when east-west visibility is worth it
```

**Small business:**
```
✅ WAN              - Essential
✅ DMZ              - If you have one
✅ Guest network    - If publicly accessible
⚠️ LAN / VLANs      - For insider threat and lateral movement detection
```

Every interface is a separate Suricata process with its own copy of the rule set. On the reference deployment 13 VLAN instances in IDS mode roughly double the steady-state CPU load compared with the two WAN instances alone, so add internal interfaces deliberately. [LAN_MONITORING.md](LAN_MONITORING.md) covers per-VLAN rule selection and the detection you gain.

**Example layout** (interface names are placeholders — substitute your own):

- **igc0 (WAN)** — primary internet connection, inline IPS
- **igc3 (WAN2)** — backup WAN, inline IPS
- **igc1.20 (IoT VLAN)** — untrusted devices, IDS

### Interface Settings

For each interface, configure:

1. **Enable Interface:** ✅ Checked
2. **Interface:** the pfSense interface (e.g. `igc0`)
3. **Description:** a clear name (e.g. "WAN IPS", "IoT VLAN IDS")

**IDS/IPS Mode:**
- **IDS (alert only)** — recommended for new installs and for all internal interfaces. Detects but never blocks. Learn your network first.
- **IPS (inline blocking)** — for WAN after tuning. Can block legitimate traffic if misconfigured. See [IDS vs IPS Mode](#ids-vs-ips-mode).

**Capture settings:**
- **IPS Mode: Inline** — uses netmap; the best-performing choice on NICs with native netmap support (Intel igb/igc/ix/em). Required for actual blocking.
- **Legacy Mode** — pcap-based; fall back to it only if inline causes problems with your NIC or with VLAN/LAGG parents.
- **Promiscuous Mode** — needed when Suricata should see traffic not addressed to the firewall's own MAC (some VLAN/bridge setups, or a mirror/span feed). Otherwise leave it off; it adds work for no benefit on a routed interface.

---

## Rule Selection Strategy

### Rule Sources

1. **Emerging Threats Open (ET Open)** — free, community-maintained, updated daily. Always enable.
2. **Snort Registered rules** — free with an account at [snort.org](https://www.snort.org/users/sign_up); paste the Oinkcode into Global Settings. Broader coverage than ET Open alone.
3. **Snort Subscriber rules** — paid ($30/year for personal use); the same rules 30 days earlier. Recommended if you run inline IPS on WAN.
4. **Feodo Tracker Botnet C2** and **Abuse.ch SSL Blacklist** — free, low false-positive IP/certificate feeds. Enable both.

Enable them under **Services > Suricata > Global Settings**, then **Services > Suricata > Updates > Update Rules**. The first download takes several minutes.

### Recommended Ruleset for a Home Lab

#### Phase 1: Starting Out (First Month)

**Emerging Threats (~42 categories):**

**Core security (must enable):**
```
✅ emerging-malware.rules           # Malware detection
✅ emerging-botcc.rules             # Botnet C2
✅ emerging-exploit.rules           # Exploit attempts
✅ emerging-exploit_kit.rules       # Exploit frameworks
✅ emerging-shellcode.rules         # Shellcode patterns
✅ emerging-worm.rules              # Worm propagation
✅ emerging-compromised.rules       # Known bad hosts
✅ emerging-attack_response.rules   # Successful attacks
✅ emerging-current_events.rules    # Zero-days
✅ emerging-phishing.rules          # Phishing attempts
```

**Web security:**
```
✅ emerging-web_server.rules        # Web server attacks
✅ emerging-web_client.rules        # Browser attacks
✅ emerging-web_specific_apps.rules # Vulnerable apps
✅ emerging-activex.rules           # ActiveX exploits
```

**Network protocols:**
```
✅ emerging-dns.rules               # DNS attacks/tunneling
✅ emerging-smtp.rules              # Email attacks
✅ emerging-sql.rules               # SQL injection
✅ emerging-netbios.rules           # SMB/NetBIOS exploits
✅ emerging-icmp.rules              # ICMP attacks
✅ emerging-ftp.rules               # FTP attacks
✅ emerging-telnet.rules            # Telnet (IoT devices)
```

**Additional threats:**
```
✅ emerging-dos.rules               # DoS attacks
✅ emerging-scan.rules              # Port scanning
✅ emerging-hunting.rules           # Threat hunting
✅ emerging-mobile_malware.rules    # Mobile threats
✅ emerging-user_agents.rules       # Malicious UAs
✅ emerging-adware_pup.rules        # Adware/PUPs
✅ emerging-chat.rules              # Chat-based threats
✅ emerging-p2p.rules               # P2P threats
✅ emerging-games.rules             # Game hacking tools
```

**Reputation lists:**
```
✅ emerging-ciarmy.rules            # IP reputation
✅ emerging-botcc.portgrouped.rules # Botnet C2 (optimized)
```

**Disable these (too noisy or not applicable):**
```
❌ emerging-coinminer.rules         # If you mine crypto
❌ emerging-drop.rules              # Redundant with pfBlockerNG
❌ emerging-dshield.rules           # Redundant with pfBlockerNG
❌ emerging-info.rules              # Too noisy
❌ emerging-ja3.rules               # Complex, needs tuning
❌ emerging-retired.rules           # Obsolete
❌ emerging-dyn_dns.rules           # If you use DynDNS
❌ emerging-remote_access.rules     # If you use TeamViewer/AnyDesk
❌ emerging-tor.rules               # If you use Tor
❌ emerging-file_sharing.rules      # Optional, try enabling
```

If you run pfBlockerNG, let it own IP-reputation blocking and keep Suricata for signatures; see [PFBLOCKERNG_OPTIMIZATION.md](PFBLOCKERNG_OPTIMIZATION.md).

#### Phase 2: Snort Rules (If You Have an Oinkcode)

**Essential (21 categories to add):**
```
✅ content-replace.rules            # MITM detection
✅ file-executable.rules            # Malicious executables
✅ file-java.rules                  # Java exploits
✅ file-office.rules                # Office malware
✅ file-pdf.rules                   # PDF exploits
✅ indicator-compromise.rules       # IOC detection
✅ indicator-shellcode.rules        # Shellcode patterns
✅ server-webapp.rules              # Web app attacks
✅ web-attacks.rules                # XSS, CSRF
✅ web-php.rules                    # PHP exploits
✅ web-client.rules                 # Browser attacks
✅ sql.rules                        # SQL injection
✅ exploit-kit.rules                # Exploit frameworks
✅ shellcode.rules                  # Generic shellcode
✅ dns.rules                        # DNS attacks
✅ smtp.rules                       # Email attacks
✅ mysql.rules                      # MySQL exploits
✅ specific-threats.rules           # APT detection
✅ netbios.rules                    # NetBIOS/SMB
✅ bad-traffic.rules                # Malformed packets
✅ other-ids.rules                  # IDS evasion
```

**Plus the usual 25 Snort categories:**
```
✅ browser-chrome/firefox/ie/other/plugins/webkit
✅ malware-backdoor/cnc/other/tools
✅ botnet-cnc, blacklist, ddos
✅ os-linux/mobile/windows/other
✅ pua-adware/other/toolbars
✅ dos, exploit, phishing-spam, spyware-put, virus
```

**Total: ~46 Snort categories.**

### Tuning Out Noise

After the first week you will have a handful of signatures producing most of your alerts. Disable or suppress them rather than living with them; a noisy rule set hides real alerts and wastes CPU. The procedure, the difference between disabling and suppressing, and a starting list of 218 known-noisy SIDs are in [config/sid/README.md](../../config/sid/README.md).

---

## Performance Tuning

### CPU

Roughly, per interface with the Phase 1 ET set: 15-30% of one core at idle-to-moderate traffic; add 10-15 points for the Snort categories. Rule reloads spike every instance to 100% for 3-5 minutes; that is normal.

**Optimization tips:**
1. **Disable unused categories** — every loaded rule costs CPU on every packet
2. **Use inline mode** — netmap is cheaper than the pcap path used by legacy mode
3. **Limit interfaces** — only monitor what you will actually look at
4. **Use SID management** — see [config/sid/README.md](../../config/sid/README.md)

### Memory

- Base Suricata: 200-400 MB per instance
- With the full rule set: 500-800 MB per instance
- Stream and reassembly memory on top, per instance (below)

**Stream settings** (**Services > Suricata > Interfaces > [Interface] > Flow/Stream**):

- **Stream Memcap:** pfSense GUI default **256 MB** (268435456 bytes; upstream Suricata defaults to 64 MB)
- **Reassembly Memcap:** pfSense GUI default **128 MB** (134217728 bytes)

Leave the defaults unless you see memcap trouble. The symptoms are `stream.memcap` / `tcp.reassembly_memcap` counters climbing in `stats.log` or the Interface Stats page, or an instance dying at startup with an out-of-memory message on a busy link. In that case raise the stream memcap in steps, up to **1 GB (`1073741824`)** per interface. The [reference deployment](#reference-deployment) runs 1 GB on every interface after memcap-related crashes on its 15-instance, 8-core box; with that many instances plan RAM accordingly (16 GB there). The value is a cap, not a reservation, but a busy interface will grow into it.

### Network

**Inline mode:**
1. **Services > Suricata > Interfaces > [Interface]**
2. **IPS Mode:** Inline
3. Save and restart the instance

**QUIC:**
If `suricata.log` shows "QUIC crypto fragments too long" warnings:
1. Open the interface's **App Parsers** tab
2. Set **QUIC crypto max length** to `65536`
3. Save and restart

---

## Log Management

### Automatic Log Management

**Always enable** automatic log management:

1. **Services > Suricata > Log Mgmt**
2. ✅ **Enable automatic unattended management of Suricata logs**
3. Set the per-log limits below

### Recommended Log Settings

```
Log Type          | Max Size | Retention | Reason
------------------|----------|-----------|------------------
eve-json          | 10 MB    | 1 DAY     | Forwarded to SIEM (raise retention if not forwarding)
alert             | 1 MB     | 7 DAYS    | Alert summary
block             | 1 MB     | 7 DAYS    | Blocked IPs
http              | 2 MB     | 7 DAYS    | HTTP sessions
tls               | 1 MB     | 7 DAYS    | TLS handshakes
sid_changes       | 250 KB   | 14 DAYS   | Rule changes (useful)
stats             | 1 MB     | 7 DAYS    | Performance stats
Captured Files    | 500 MB   | 1 DAY     | Large, rarely needed
TLS Certs         | -        | 7 DAYS    | Small, useful
PCAP Files        | -        | 1 DAY     | Huge, troubleshooting only
```

Multiply the size expectations by the number of interfaces: every instance writes its own set of logs under `/var/log/suricata/suricata_<iface><id>/`. Keep `/var` on real storage, never an SD card.

### Log Forwarding (optional)

For history beyond a few days, forward `eve.json` to a SIEM and keep the local copy as a short buffer. This repository's forwarder and OpenSearch/Grafana stack do exactly that; see [SURICATA_FORWARDER_MONITORING.md](../operations/SURICATA_FORWARDER_MONITORING.md). Nothing else in this guide depends on it.

---

## IDS vs IPS Mode

### IDS Mode (Alert Only) — recommended to start

**Configuration:**
- Inline capture for performance, but leave every rule at its default `alert` action
- Review alerts (GUI Alerts tab or your SIEM)
- No automatic blocking

**Pros:** safe, cannot break traffic; lets you baseline the network; easy troubleshooting
**Cons:** no automatic blocking; you act on alerts by hand (or via pfBlockerNG)

**Best for:** home labs, family networks, the first 1-3 months of any deployment, and all internal interfaces.

### IPS Mode (Inline Blocking) — after tuning

Suricata only blocks when the *rule action* is `drop`. Enabling inline mode by itself blocks nothing; you still have to decide which rules should drop.

**Method 1: Snort IPS policy (easy)**
- **Categories** tab → **Use IPS Policy** → choose *Connectivity*, *Balanced*, *Security* or *Max-Detect*
- Snort rules the policy marks as drop will block; ET rules are unaffected

**Method 2: `dropsid.conf` (works for every rule source)**
- **Services > Suricata > SID Mgmt** → create a `dropsid.conf` and assign it to the WAN interface(s) in the *Drop SID File* column
- Match by **classtype** rather than by rule-file name — the regex is applied to the rule text, and classtypes are the most reliable signal of confidence:

```
# High-confidence classtypes with near-zero false positives — start here
pcre:classtype:exploit-kit
pcre:classtype:trojan-activity
pcre:classtype:command-and-control
pcre:classtype:domain-c2
pcre:classtype:successful-admin
pcre:classtype:successful-user
```

Ready-made lists (`dropsid-minimal-safe.conf` above, and a tiered `dropsid-comprehensive.conf`), plus how to apply them so they persist, are in [config/sid/README.md](../../config/sid/README.md).

**Rolling out IPS:**
1. Enable on one interface first — WAN, or a guest VLAN if you want a low-risk trial
2. Run with the minimal drop list for a week
3. Watch the **Blocks** tab and your users for broken services
4. Suppress false positives by host rather than disabling rules globally
5. Widen the drop list one tier at a time

**Pros:** real-time blocking; automated defence
**Cons:** false positives cause outages; needs ongoing tuning; may block VPNs, remote access tools, cloud sync, gaming

**Best for:** WAN interfaces after 1-3 months in IDS mode, on networks whose applications you understand.

---

## Testing and Validation

### Verify Suricata is running

```bash
ssh admin@<PFSENSE_IP> "ps aux | grep '[s]uricata'"
```

One process per enabled interface.

### Check logs are being written

```bash
ssh admin@<PFSENSE_IP> "ls -lh /var/log/suricata/suricata_*/eve.json"
```

Files should be growing.

### Generate a test alert

`testmyids.com` now redirects to HTTPS, so Suricata cannot see the payload any more. Use one of these from a client behind the firewall:

```bash
# ET POLICY / GPL ATTACK_RESPONSE "id check returned root" test signature over plain HTTP
curl -A "BlackSun" http://testmynids.org/uid/index.html
```

or the test rule from the [Suricata quickstart](https://docs.suricata.io/en/latest/quickstart.html), which triggers on the same page. Then:

```bash
ssh admin@<PFSENSE_IP> "tail -f /var/log/suricata/suricata_*/eve.json | grep -F '\"event_type\":\"alert\"'"
```

If the WAN interface runs inline IPS with a drop list that covers `attempted-recon`/`bad-unknown`, the request may be **blocked** rather than merely alerted — a `block` event with the same signature is a pass.

### Monitor performance

1. **CPU:** `top -P` on the box, or **Diagnostics > System Activity**
2. **Memory:** `ps aux | grep '[s]uricata' | awk '{print $6/1024 " MB", $11}'`
3. **Drops:** **Services > Suricata > Interfaces** → *Interface Stats* per interface; `capture.kernel_drops` should stay at or near zero and the `memcap` counters should not climb

### Review stats

```bash
ssh admin@<PFSENSE_IP> "tail -100 /var/log/suricata/suricata_*/stats.log"
```

Look at `capture.kernel_drops` (near zero), `flow.memuse` and `tcp.memuse` (well under the memcaps), `tcp.reassembly_memcap` and `stream.memcap` (not increasing).

---

## Maintenance

### Rule Updates

**Automatic (recommended):**
1. **Services > Suricata > Global Settings**
2. **Update Interval:** daily (12 hours is fine too), **Update Start Time:** 03:00 or another quiet hour
3. ✅ **Live Rule Swap on Update** — reload without restarting the instances
4. ✅ **Keep Suricata Settings After Deinstall** — protects your configuration if you ever reinstall the package

**Manual:** **Services > Suricata > Updates > Update Rules**.

Expect every instance to sit at 100% CPU for 3-5 minutes during a rule reload. In inline mode that can mean brief packet loss on a heavily loaded box; schedule updates accordingly.

### Weekly

1. Review alerts (GUI or dashboard)
2. Add newly identified false positives to your disable/suppress lists
3. If forwarding to a SIEM, confirm the forwarder is running
4. Check `/var/log/suricata` disk usage

### Monthly

1. Review CPU/memory trends
2. Apply pfSense and Suricata package updates — then read [SURICATA_CONFIGURATION.md](SURICATA_CONFIGURATION.md#after-a-pfsense-or-suricata-package-upgrade) for what to re-check
3. Prune noisy categories
4. Confirm log rotation is still working

### Troubleshooting

**High CPU:** fewer categories, fewer interfaces, check for drops (a box that cannot keep up needs more hardware or less work).
**False positives:** confirm the traffic is legitimate, then disable (global noise) or suppress (specific hosts); see [config/sid/README.md](../../config/sid/README.md).
**Packet drops:** raise stream/reassembly memcaps if the memcap counters are climbing; otherwise reduce rules or interfaces.
**Logs not forwarding (SIEM stack):** [SURICATA_FORWARDER_MONITORING.md](../operations/SURICATA_FORWARDER_MONITORING.md).

---

## Reference Deployment

All numbers in this repository's docs come from one deployment, described fully in [HARDWARE_REQUIREMENTS.md](../install/HARDWARE_REQUIREMENTS.md):

- **CPU:** Intel Atom C3758, 8 cores @ 2.2 GHz; **RAM:** 16 GB; Intel NICs
- **Instances:** 15 — 2 WAN inline IPS + 13 VLAN IDS
- **Rules:** ~42 ET categories + ~46 Snort categories (subscriber)
- **Stream memcap:** 1 GB per interface (raised after memcap-related crashes)
- **CPU:** 25-35% average, 100% for 3-5 minutes during rule reloads
- **RAM:** 12-14 GB in use
- **Log volume:** roughly 50-100 MB/day of `eve.json` per busy interface, forwarded to OpenSearch

If your box has fewer cores, scale the interface count down before scaling the rule set down; each instance is a full copy of the engine.

---

## Quick Reference

**New users (first month):**
- Mode: IDS
- Interfaces: WAN only
- Rules: ~42 ET categories
- Capture: inline
- Local log retention: 7 days

**After tuning:**
- Mode: IDS everywhere, plus a minimal drop list on WAN
- Interfaces: WAN + the VLANs you actually want to watch ([LAN_MONITORING.md](LAN_MONITORING.md))
- Rules: ET + Snort (if you have an Oinkcode)
- Local log retention: 1-3 days, forwarding to a SIEM

**Small business / production:**
- Mode: inline IPS on all perimeter interfaces with a tiered drop list
- Rules: full ET + Snort subscriber + custom rules
- Local log retention: 1 day, long-term storage in a SIEM
- Redundancy: HA pair

---

## Additional Resources

- **[SURICATA_CONFIGURATION.md](SURICATA_CONFIGURATION.md)** — design decisions, interface strategy, upgrade notes
- **[config/sid/README.md](../../config/sid/README.md)** — disable / drop / suppress lists and how to build your own
- **[LAN_MONITORING.md](LAN_MONITORING.md)** — east-west detection on VLANs
- **[HARDWARE_REQUIREMENTS.md](../install/HARDWARE_REQUIREMENTS.md)** — sizing
- **[GEOIP_SETUP.md](../install/GEOIP_SETUP.md)** — IP geolocation for alerts
- **[SURICATA_FORWARDER_MONITORING.md](../operations/SURICATA_FORWARDER_MONITORING.md)** — keeping logs flowing to the SIEM
- **[TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md)** — common issues
- **Suricata documentation:** https://docs.suricata.io/
- **pfSense Suricata package:** https://docs.netgate.com/pfsense/en/latest/packages/suricata/
