# Suricata Configuration Guide

Design decisions behind running Suricata on pfSense: why Suricata, which rule sources, how to split interfaces between IPS and IDS, how to think about SID tuning, and the failure modes you will meet. It is the companion to [SURICATA_OPTIMIZATION_GUIDE.md](SURICATA_OPTIMIZATION_GUIDE.md), which is the step-by-step install → rules → IDS/IPS → performance → validation guide; if you are setting Suricata up for the first time, start there.

Everything here applies to any pfSense box. The [No Alerts in Dashboard](#issue-5-no-alerts-in-dashboard) item and the forwarder mentions are the only parts specific to this repository's SIEM stack.

---

## 📋 Table of Contents

- [Why Suricata Over Snort](#-why-suricata-over-snort)
- [Rule Sources](#-rule-sources)
- [Stream Memory](#-stream-memory)
- [Interface Strategy](#️-interface-strategy)
- [Performance Tuning](#-performance-tuning)
- [SID Tuning Philosophy](#-sid-tuning-philosophy)
- [GeoIP](#-geoip)
- [After a pfSense or Suricata Package Upgrade](#-after-a-pfsense-or-suricata-package-upgrade)
- [Common Issues](#-common-issues)
- [Monitoring Performance](#-monitoring-performance)
- [Configuration Checklist](#-configuration-checklist)

---

## 🔥 Why Suricata Over Snort?

### Multithreading

**Suricata** was designed for multicore processors:

✅ **True multithreading**: packet processing is spread across all cores in one process
✅ **Higher throughput** on the same hardware
✅ **Active development**: frequent releases, modern protocol support (TLS 1.3, QUIC, HTTP/2)
✅ **Native EVE JSON** output, which is what makes the SIEM side of this project simple

**Snort 2.x** is single-threaded per instance; getting parallelism means running several instances by hand. Snort 3 improves on this, but the pfSense Snort package and its ecosystem still lag Suricata on pfSense.

### Real-World Numbers

The reference deployment used throughout these docs (details in [HARDWARE_REQUIREMENTS.md](../install/HARDWARE_REQUIREMENTS.md)):

- Intel Atom C3758, 8 cores, 16 GB RAM
- 15 Suricata instances: 2 WAN inline IPS + 13 VLAN IDS
- 25-35% average CPU, well distributed across cores
- 100% CPU for 3-5 minutes during rule reloads (expected)
- Gigabit bursts without kernel drops

---

## 📚 Rule Sources

Enable these in **Services → Suricata → Global Settings**:

1. **Emerging Threats Open** — free, community-maintained, updated daily. Always enable.
2. **Snort Registered rules** — free with an account at [snort.org](https://www.snort.org/users/sign_up); paste your Oinkcode. Broader coverage than ET Open alone.
3. **Snort Subscriber rules** — paid ($30/year personal); the same rules 30 days before registered users get them. Worth it if you run inline IPS on WAN.
4. **Feodo Tracker Botnet C2 IP** (abuse.ch) — known C2 addresses, updated hourly, very low false-positive rate.
5. **Abuse.ch SSL Blacklist** — malicious TLS certificate fingerprints.

### Update Schedule

Also in Global Settings:

- **Update Interval:** daily (12 hours is fine too)
- **Update Start Time:** 03:00 or another quiet hour — every instance hits 100% CPU for a few minutes during a reload
- ☑ **Live Rule Swap on Update** — reload the rules without restarting the instance
- ☑ **Keep Suricata Settings After Deinstall**
- **Remove Blocked Hosts Interval:** 1 hour (inline IPS only)

Then **Services → Suricata → Updates → Update Rules** and watch `/var/log/suricata/suricata_<iface><id>/suricata.log` for load errors.

---

## 🔧 Stream Memory

### Defaults

Per interface, under **Services → Suricata → Interfaces → [Interface] → Flow/Stream**:

- **Stream Memcap:** **256 MB** (pfSense GUI default, 268435456 bytes; upstream Suricata defaults to 64 MB)
- **Reassembly Memcap:** **128 MB** (pfSense GUI default)

These are fine for a single WAN interface on a typical home connection.

### When to raise them

Raise the stream memcap — in steps, up to **1 GB (`1073741824`)** — if you see either of these:

- The `stream.memcap` or `tcp.reassembly_memcap` counters climbing in **Interface Stats** or `stats.log`. Once the cap is hit Suricata starts dropping segments from tracked flows, which shows up as missed detections and, in inline mode, as broken connections.
- An instance that refuses to start or dies under load with an out-of-memory style message in `suricata.log`.

The reference deployment runs **1 GB per interface** on all 15 instances after exactly those memcap-related crashes on its busy 8-core box. The memcap is a ceiling rather than a reservation, but a busy interface will grow into it, so with many instances plan RAM to match (16 GB there, 12-14 GB in use). Two WAN instances on a quad-core box with 8 GB can afford 1 GB each; fifteen instances on 8 GB cannot.

Steps: **Services → Suricata → [Interface] → Flow/Stream → Stream Memcap** → new value → **Save** → repeat per interface → restart the instances from **Services → Suricata → Interfaces**. The setting lives in `config.xml` and survives upgrades.

---

## ⚙️ Interface Strategy

### Two roles

**Inline IPS** on WAN interfaces:
- Mode: **Inline**, with a drop list so that high-confidence rules actually block
- Purpose: stop known-bad traffic at the edge
- Cost: higher CPU; false positives break real traffic
- Use on: WAN interfaces only

**IDS** on internal interfaces:
- Mode: IDS (alert only)
- Purpose: visibility — lateral movement, scanning, infected hosts
- Cost: lower; nothing is ever blocked
- Use on: LAN and VLAN interfaces

### Recommended split

| Interface | Mode | Purpose |
|-----------|------|---------|
| WAN (primary) | Inline IPS | Active blocking |
| WAN (secondary) | Inline IPS | Active blocking |
| LAN | IDS | Monitoring |
| VLAN (trusted) | IDS | Light monitoring |
| VLAN (IoT) | IDS | Heavy monitoring |
| VLAN (guest) | IDS | Heavy monitoring |

**Why IDS internally?** Inline blocking between internal segments breaks internal applications in ways users notice immediately and you cannot easily diagnose from the outside. IDS still catches lateral movement, scanning and malware beaconing, and you can always promote an interface to IPS later once the alerts on it are clean.

**VLAN interfaces are optional.** Each one is another full Suricata process with its own rule set, so each adds CPU and memory. [LAN_MONITORING.md](LAN_MONITORING.md) explains when east-west visibility is worth that cost and how to tune per-VLAN rule sets.

**Promiscuous mode** is needed when Suricata should see traffic not addressed to the firewall's own MAC — some VLAN/bridge arrangements, or a mirror-port feed. On a normally routed interface leave it off.

---

## 🎯 Performance Tuning

### Per-interface starting points

**WAN (inline IPS):**
```
Flow/Stream:
  Stream Memcap:            256 MB default; raise (up to 1 GB) on memcap drops or crashes
  Reassembly Memcap:        128 MB default; raise alongside stream memcap
  Reassembly Depth:         1 MB
App Parsers:
  HTTP request/response body limit: 100 KB
Detection:
  Detect Engine Profile:    high
  Max Pending Packets:      1024 (lower if you see drops)
```

**VLAN (IDS):**
```
Flow/Stream:
  Stream Memcap:            256 MB default; raise only if memcap counters climb
  Reassembly Memcap:        128 MB default
  Reassembly Depth:         512 KB
App Parsers:
  HTTP request/response body limit: 50 KB
Detection:
  Detect Engine Profile:    medium
  Max Pending Packets:      512
```

### Scaling with cores

- **4 cores:** 2-4 instances; medium/low detect profile on VLANs
- **6-8 cores:** 5-10 instances; high on WAN, medium on VLANs
- **8+ cores:** 15 or more instances (the reference deployment runs 15 on 8 cores at 25-35% average)

Watch **Diagnostics → System Activity** during a rule reload: 100% for 3-5 minutes is normal. Sustained load above ~80% outside reloads means fewer rules, fewer interfaces or a lower detect profile.

---

## 🎛️ SID Tuning Philosophy

A fresh Suricata install with the recommended rule sources produces hundreds of alerts a day, and most of them will be the same 20 signatures: stream/TCP anomaly events on WAN retransmissions, `ET INFO` notices about Java versions and user agents, chat and P2P policy rules, and preprocessor events inherited from Snort. Left alone they bury the alerts you care about.

The approach that works:

1. **Run in IDS mode for one to two weeks** and let the noise show itself.
2. **Aggregate by signature ID.** Whatever is in your top 20 by volume is either a real ongoing problem or a rule that should not be firing on your network — decide which for each.
3. **Disable globally noisy rules** (`disablesid.conf`): the rule is not even loaded, so it costs nothing.
4. **Suppress by IP** only when a rule is a false positive for one or two specific hosts and you still want it for everyone else. Suppressed rules still run; a long suppress list is a performance smell.
5. **Drop only high-confidence classtypes** (`dropsid.conf`) on inline interfaces, one tier at a time.
6. **Apply everything through the GUI** (Services → Suricata → SID Mgmt and Suppress) so it lands in `config.xml` and survives rule updates and upgrades.

The full procedure, including the OpenSearch aggregation to find your noisy signatures, plus the maintainer's 218-SID disable list and two drop lists to start from, is in [config/sid/README.md](../../config/sid/README.md).

---

## 🌍 GeoIP

GeoIP enrichment for alerts and the dashboards' maps comes from MaxMind GeoLite2 databases. On pfSense several packages can download them (Suricata's own Global Settings has a **GeoLite2 DB License Key** field; pfBlockerNG has another), and this repository's forwarder reads whichever City or Country database it finds on the box before shipping events. Which database to use, where each package puts it, the field names that end up in OpenSearch and how to verify the map panels are all in **[GEOIP_SETUP.md](../install/GEOIP_SETUP.md)**.

---

## 🔄 After a pfSense or Suricata Package Upgrade

The Suricata package stores nearly everything you configure through the GUI in `config.xml`: interface definitions and their modes, memcaps and detect profiles, rule-source selections and the Oinkcode, SID Mgmt lists, suppress lists, pass lists, log-management settings. All of that survives a pfSense upgrade, a package reinstall and a restore onto new hardware.

What does **not** survive:

- **Hand edits to generated files** — `suricata.yaml`, `threshold.config`, anything under `/usr/local/etc/suricata/suricata_<iface><id>/`. The package rewrites them on every save and rule update. If you changed something there, find the equivalent GUI setting or accept that you will redo it.
- **Custom rule files you copied to disk** rather than pasting into the interface's `custom.rules` box.
- **Scripts and cron entries added from the shell** (`/usr/local/bin`, `/etc/crontab`). Use the Cron and Filer packages instead.

Version notes:

- On pfSense 2.8.1 the Suricata package is in the **7.0.x** line. Suricata **8** changes the EVE DNS record format (v3: request/response merged into a single object with different field names). When the package moves to Suricata 8, re-check any DNS dashboard panels and Logstash filters that reference `dns.rrname`, `dns.rcode` or `dns.answers`.
- After any *major* Suricata bump, run one rule update, confirm every instance starts, and compare the alert rate with the previous week before trusting the dashboards again.

The full pre/post-upgrade checklist for this stack — forwarder, Telegraf, cron jobs, SID lists — is in [PFSENSE_UPGRADE_GUIDE.md](PFSENSE_UPGRADE_GUIDE.md).

---

## 🚨 Common Issues

### Issue 1: Suricata Won't Start After Install

**Symptom:** interface shows "stopped" and will not start.

**Diagnosis:** read `/var/log/suricata/suricata_<iface><id>/suricata.log`. The usual causes are a rule file that failed to load (bad rule source, half-downloaded update), a netmap error on a NIC that does not support it in inline mode, or — on a busy link — memcap/out-of-memory.

**Fix:** re-run the rule update; switch the interface to legacy capture if netmap is the problem; raise the stream memcap (see [Stream Memory](#-stream-memory)) if the log says so.

### Issue 2: High CPU During Rule Reloads

**Symptom:** 100% CPU for 3-5 minutes after a rule update.

**Cause:** normal — every instance recompiles its detection engine.

**Mitigation:** schedule updates off-peak; make sure cooling is adequate; enable Live Rule Swap. A faster CPU shortens the window; nothing removes it.

### Issue 3: Packet Drops in Inline IPS Mode

**Symptom:** packet loss or latency spikes under load; `capture.kernel_drops` climbing.

**Fix, in order:**
1. Lower **Max Pending Packets** (512, then 256)
2. Lower the detect profile to medium
3. Cut rule categories (see [SID Tuning Philosophy](#-sid-tuning-philosophy))
4. Raise memcaps if the memcap counters are the ones climbing
5. Fall back to IDS on that interface, or upgrade hardware

### Issue 4: False Positives Breaking Traffic

**Symptom:** a legitimate application fails; users report connectivity problems.

**Fix:**
1. **Services → Suricata → Alerts** (or **Blocks**) → identify the SID and the hosts involved
2. Suppress it for those hosts, or disable it globally if it is noise everywhere — [config/sid/README.md](../../config/sid/README.md)
3. **Update Rules** to apply, then clear the blocked host from the **Blocks** tab

**Prevention:** run IDS first, tune, then enable dropping one tier at a time.

### Issue 5: No Alerts in Dashboard

*(SIEM stack only)*

**Symptom:** Grafana shows "No data".

**Fix:**
1. Forwarder running? `ssh admin@<PFSENSE_IP> "ps aux | grep '[f]orward-suricata-eve'"`
2. Forwarder log: `tail -f /var/log/suricata_forwarder_debug.log`
3. OpenSearch receiving? `curl -s http://<SIEM_IP>:9200/suricata-*/_count`
4. [DASHBOARD_NO_DATA_FIX.md](../troubleshooting/DASHBOARD_NO_DATA_FIX.md)

### Issue 6: Rule Updates Fail

**Symptom:** "Failed to download rules".

**Fix:**
1. Check the Oinkcode at [snort.org](https://www.snort.org/)
2. `ping -c 3 rules.emergingthreats.net` and `host rules.emergingthreats.net` from the box
3. Retry from **Services → Suricata → Updates**
4. Read `/var/log/suricata/suricata_<iface><id>/suricata.log`

---

## 📊 Monitoring Performance

**CPU:**
```bash
ssh admin@<PFSENSE_IP> "top -P"
```
Suricata processes should average well under 50% outside rule reloads.

**Memory:**
```bash
ssh admin@<PFSENSE_IP> "vmstat -h; ps aux | grep '[s]uricata' | awk '{print \$6/1024 \" MB\", \$11}'"
```
Keep 2-4 GB free.

**Drops and memcaps:** **Services → Suricata → Interfaces → Interface Stats** per interface, or `tail -100 /var/log/suricata/suricata_*/stats.log`:

- `capture.kernel_drops` — zero or near zero
- `stream.memcap`, `tcp.reassembly_memcap` — should not increase
- `tcp.reassembly_gap` — should be low

---

## 🔗 Related Documentation

- **[SURICATA_OPTIMIZATION_GUIDE.md](SURICATA_OPTIMIZATION_GUIDE.md)** — step-by-step install, rules, IDS/IPS, validation
- **[config/sid/README.md](../../config/sid/README.md)** — disable / drop / suppress lists and how to build your own
- **[LAN_MONITORING.md](LAN_MONITORING.md)** — east-west detection on VLANs
- **[HARDWARE_REQUIREMENTS.md](../install/HARDWARE_REQUIREMENTS.md)** — sizing and the reference deployment
- **[GEOIP_SETUP.md](../install/GEOIP_SETUP.md)** — GeoIP databases and fields
- **[PFSENSE_UPGRADE_GUIDE.md](PFSENSE_UPGRADE_GUIDE.md)** — what survives an upgrade
- **[TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md)** — SIEM-side issues

---

## ✅ Configuration Checklist

Before calling Suricata "production ready":

- [ ] **Rule sources configured** (ET Open, Snort, Feodo, Abuse.ch SSL)
- [ ] **Update schedule set** (daily, off-peak, live rule swap on)
- [ ] **Interface modes chosen** (inline IPS on WAN, IDS internally)
- [ ] **Stream memcap reviewed** (default 256 MB; raised only where memcap counters or crashes said so)
- [ ] **Two weeks in IDS mode** and the top noisy SIDs disabled or suppressed via SID Mgmt
- [ ] **Drop list on WAN** starting with the minimal high-confidence classtypes
- [ ] **No sustained drops** (`capture.kernel_drops` ≈ 0, CPU < 80% outside reloads)
- [ ] **GeoIP database present** (if you want maps)
- [ ] **Log management enabled** with sane retention
- [ ] *(SIEM stack)* forwarder deployed, dashboards receiving data, watchdogs in place

**Pro tip:** start with IDS on everything, run for 1-2 weeks, tune out false positives, *then* enable dropping on WAN. It is far easier to add blocking to a quiet rule set than to debug an outage caused by a noisy one.
