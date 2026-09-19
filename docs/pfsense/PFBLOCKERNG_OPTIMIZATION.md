# pfBlockerNG Optimization Guide

## Overview

pfBlockerNG is the pfSense package for DNS-based (DNSBL) and IP-based blocklisting. Used well, it removes known-bad traffic **before Suricata ever inspects it**, which cuts IDS/IPS load and makes the alerts that remain more meaningful.

This is the **strategy** guide: why to run pfBlockerNG alongside Suricata, which handful of feeds matter most, how to set actions and update cadence, how to order rules, and how to check it is working. The exhaustive feed catalog — every pre-configured IP and DNSBL feed worth enabling, grouped by priority, plus the whitelisting guide and privacy notes — is in **[PFBLOCKERNG_FEED_REFERENCE.md](PFBLOCKERNG_FEED_REFERENCE.md)**. Read this one first, then use the reference to build out your groups.

It applies to any pfSense box. Only the [Dashboard Panels](#3-dashboard-panels) section depends on this repository's SIEM stack.

---

## Why Use pfBlockerNG with Suricata?

1. **Upstream filtering**: block known bad actors before they generate Suricata alerts
2. **Reduced noise**: fewer alerts from addresses everyone already knows are hostile
3. **Performance**: less traffic to inspect means less Suricata CPU
4. **Layered defence**: reputation (pfBlockerNG) + signatures (Suricata) catch different things

**Division of labour:**

| pfBlockerNG handles | Suricata handles |
|---------------------|------------------|
| IP reputation (scanners, botnet C2, spam sources) | Exploit attempts and protocol attacks |
| DNS blocking (ads, trackers, malware domains) | Signature-based malware detection |
| GeoIP country blocking | Anything reputation lists cannot see |

Disable Suricata's own IP-reputation categories (`emerging-drop`, `emerging-dshield`, `emerging-ciarmy` if you like) once pfBlockerNG carries those feeds; keeping both just doubles the work.

---

## Recommended Blocklists

A short list of high-value feeds. The full catalog with URLs and pre-configured feed names is in the [feed reference](PFBLOCKERNG_FEED_REFERENCE.md#ip-block-lists). **Verify a feed's URL before adding it**; several once-popular sources have gone offline or moved.

### IP Blocklists (high priority)

**Abuse.ch Feodo Tracker** (pre-configured)
- Purpose: banking-trojan and botnet C2 servers
- Action: **Deny Both**
- Update: **every hour**

**Abuse.ch SSL Blacklist** (pre-configured / `sslbl.abuse.ch`)
- Purpose: IPs serving known-malicious TLS certificates
- Action: **Deny Both**
- Update: **every hour**

**Abuse.ch URLhaus**
- Purpose: malware distribution servers
- Action: **Deny Both**
- Update: **every hour**

**Spamhaus DROP** (pre-configured)
- Purpose: hijacked netblocks, bulletproof hosting
- Action: **Deny Inbound**
- Update: **every 4 hours**

**Emerging Threats Compromised / ET Block** (pre-configured)
- Purpose: compromised hosts and known attackers
- Action: **Deny Inbound**
- Update: **every 4 hours**

**Scanner lists** (Maltrail scanners, ISC Shodan/Shadowserver — pre-configured)
- Purpose: internet-wide scanners; blocking them mostly reduces log noise
- Action: **Deny Inbound**
- Update: **daily**

### DNS Blocklists (optional but recommended)

**OISD** (pre-configured, "Compilation" category) — ads, trackers and malware domains with a low false-positive rate. Pick this **one** all-in-one list first; add others only after it has run cleanly for a week.

**Abuse.ch URLhaus / OpenPhish / PhishTank** (pre-configured) — malware and phishing domains.

Update: **daily** for all DNSBL groups.

---

## Configuration Best Practices

### 1. Update cadence

One rule, used consistently here and in the [feed reference](PFBLOCKERNG_FEED_REFERENCE.md#performance-tuning):

| Feed type | Frequency | Why |
|-----------|-----------|-----|
| C2 / malware infrastructure (Feodo, SSLBL, URLhaus) | **Every hour** | Short-lived infrastructure |
| General inbound reputation (Spamhaus, ET, BlockList.de, FireHOL) | **Every 4 hours** | Changes daily, not hourly |
| Scanner lists | **Daily** | Scanner IPs are stable |
| DNSBL | **Daily** | Domain lists are stable and large |

On low-end hardware (2 cores / 2 GB) drop the hourly tier to every 4 hours; the update process is PHP-heavy.

### 2. pfBlockerNG IP settings

**Firewall → pfBlockerNG → IP**

- **Enable suppression** and whitelist:
  - the RFC 1918 ranges you use internally
  - your upstream DNS servers
  - your SIEM/monitoring server (an accidental block here silences your dashboards)
- **Logging**: enable on Deny rules; the logs are what feed the [dashboard panels](#3-dashboard-panels)
- **De-duplication**: on (drops entries already covered by another enabled list)

### 3. List actions

| Feed type | Action | Reason |
|-----------|--------|--------|
| C2 servers | Deny Both | Stop inbound attacks **and** outbound beaconing from infected hosts |
| Scanners / brute-force | Deny Inbound | Block reconnaissance; your outbound traffic is unaffected |
| Spam sources | Deny Inbound | Block spam; let your mail server talk out |
| Malware distribution | Deny Both | Stop downloads and stop callbacks |

### 4. Rule order relative to Suricata

pfBlockerNG creates its own firewall rules (aliases prefixed `pfB_`) and, by default, places them **at the top** of each interface's rule set. Suricata in inline mode sits in the packet path *before* pf, so strictly speaking it sees everything — but connections pfBlockerNG rejects never complete, so Suricata's stateful inspection has nothing to alert on. The net effect is the one you want: reputation blocks first, signatures on what is left.

Check the rules exist:

```bash
ssh admin@<PFSENSE_IP> "pfctl -sr | grep -c pfB_"
```

Anything greater than zero means the lists are loaded into pf.

---

## Monitoring & Validation

### 1. Blocklist status

**Firewall → pfBlockerNG → Reports → Alerts** — recent blocks, per feed. Review weekly for false positives and add them to the suppression/whitelist rather than disabling the feed.

**Firewall → pfBlockerNG → Update → View Update Status** — download failures show up here as `Download FAIL`; fix or remove the feed.

### 2. Suricata load reduction

Compare the alert rate on the WAN instance before and after enabling the IP groups:

```bash
ssh admin@<PFSENSE_IP> "grep -c '\"event_type\":\"alert\"' /var/log/suricata/suricata_<iface><id>/eve.json"
```

A 20-40% drop in raw WAN alerts is typical once the C2 and scanner feeds are active, mostly from `ET SCAN` and `ET DROP` signatures that no longer fire.

### 3. Dashboard Panels

*(SIEM stack only)*

pfBlockerNG's `ip_block.log` and `dnsbl.log` are tailed by Telegraf on the firewall and written straight to OpenSearch (`pfblockerng-*` indices), where the `pfsense_pfblockerng_system.json` dashboard reads them through the OpenSearch-pfBlockerNG datasource: blocks over time, top blocked sources and destinations, ports, protocols, countries, feeds, and DNSBL domains and clients.

- Pipeline setup: [TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md)
- Panel list and import: [dashboards/README.md](../../dashboards/README.md)

---

## Troubleshooting

### A legitimate site is blocked

1. Find the list: **Firewall → pfBlockerNG → Reports → Alerts** (IP) or **DNSBL → Reports** (DNS)
2. Whitelist: for IP, add the address to the group's **Custom List** with *Permit*, or to the IP **Suppression** list; for DNSBL, add the domain to a **Whitelist** group (the `+` icon next to the alert does this for you)
3. **Firewall → pfBlockerNG → Update → Reload**

The [whitelisting guide](PFBLOCKERNG_FEED_REFERENCE.md#whitelisting-guide) lists the CDNs, identity providers and conferencing domains that break most often.

### pfBlockerNG is not blocking

1. **Firewall → pfBlockerNG → General → Enable** is checked
2. Feeds downloaded: **Update → View Update Status**
3. Rules present: `pfctl -sr | grep pfB_ | head`
4. For DNSBL: the DNS Resolver (Unbound) is enabled and clients actually use the firewall for DNS (devices with hard-coded 8.8.8.8 or DoH bypass DNSBL entirely)

### Updates are slow or CPU-heavy

- Move feeds down a tier in the [update cadence](#1-update-cadence) table
- Consolidate: one aggregated feed (FireHOL level1, OISD) instead of five overlapping ones
- Remove low-value lists; quality beats quantity

### Firewall table limit exceeded

`pfctl` reports `table-entries limit ... exceeded`: raise **System → Advanced → Firewall & NAT → Firewall Maximum Table Entries** (2,000,000 is plenty for 30+ lists on a box with 8 GB), or drop lists.

---

## Performance Tips

1. **Aliases, not rules** — pfBlockerNG already packs each list into one pf table; check **Firewall → Aliases → IP** for the `pfB_*` aliases
2. **Fewer, better lists** — Feodo, SSLBL, Spamhaus and OISD carry most of the value
3. **Stagger update times** — **Firewall → pfBlockerNG → General → CRON Settings**; run the daily tier at 03:00-05:00 so it does not coincide with Suricata rule updates
4. **Watch memory** — **Diagnostics → System Activity**; each loaded list lives in kernel memory, and DNSBL with several large lists adds a few hundred MB to Unbound

---

## Quick Setup

1. Install pfBlockerNG-devel, enable it, enable CRON
2. Create IP suppression/whitelist entries for your subnets, DNS servers and SIEM
3. Add one IP group **"Critical"**: Feodo, SSLBL, URLhaus — *Deny Both*, hourly
4. Add one IP group **"Inbound"**: Spamhaus DROP, ET Compromised — *Deny Inbound*, every 4 hours
5. Add one DNSBL group with OISD — daily
6. **Update → Reload → All**, then watch **Reports → Alerts** for 48 hours
7. Expand using the [feed reference](PFBLOCKERNG_FEED_REFERENCE.md#implementation-checklist)

Validation:

```bash
ssh admin@<PFSENSE_IP> "pfctl -sr | grep -c pfB_"      # > 0: rules loaded
ssh admin@<PFSENSE_IP> "pfctl -t pfB_Critical_v4 -T show | wc -l"   # entries in a table
```

---

## Further Reading

- **[PFBLOCKERNG_FEED_REFERENCE.md](PFBLOCKERNG_FEED_REFERENCE.md)** — full feed catalog, whitelisting, privacy notes
- **[SURICATA_OPTIMIZATION_GUIDE.md](SURICATA_OPTIMIZATION_GUIDE.md)** — the other half of the detection stack
- **[TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md)** — getting pfBlockerNG logs into OpenSearch
- pfBlockerNG official docs: https://docs.netgate.com/pfsense/en/latest/packages/pfblocker.html
- Abuse.ch feeds: https://abuse.ch/
- Spamhaus DROP: https://www.spamhaus.org/drop/
