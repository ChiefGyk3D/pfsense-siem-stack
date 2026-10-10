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

### 3. Do both layers block the same thing?

Suricata inline sees a packet **before** `pf`, so an IP that is on a pfBlockerNG list is still inspected, and often
dropped, by Suricata first. If you run the IP-reputation rule categories (for example ET CINS and compromised-host
rules) in Suricata *and* similar IP feeds in pfBlockerNG, measure how much they overlap before keeping both:

```bash
# source IPs the WAN instance blocked, tested against the pfBlockerNG tables
grep '"event_type":"alert"' /var/log/suricata/suricata_<iface><id>/eve.json \
  | sed -E 's/.*"src_ip":"([0-9.]+)".*/\1/' | sort -u > /tmp/blocked.txt
for ip in $(cat /tmp/blocked.txt); do
  for t in $(pfctl -sT | grep '^pfB_' | grep -v _v6); do
    pfctl -t $t -T test $ip >/dev/null 2>&1 && { echo $ip; break; }
  done
done | wc -l        # how many of the blocked IPs are already in a pfBlockerNG table
```

On the reference firewall 102 of 105 unique blocked IPs (97 percent) were already on a pfBlockerNG list. That makes the
Suricata IP-reputation rules mostly redundant noise on the WAN instance. They are a small share of the rule count, so
the saving is memory and alert volume more than CPU; decide with your own numbers.

### 4. Is DNSBL actually enforcing?

DNSBL failing leaves the IP lists working, so **nothing looks broken**. Check it explicitly, and after every pfBlockerNG
install, reinstall or upgrade:

```bash
# 1. a domain that is on your lists should NOT resolve normally
#    (Python mode answers 0.0.0.0; Unbound mode answers the DNSBL virtual IP)
drill <a-known-ad-domain> @127.0.0.1

# 2. the log should not say the VIP is missing
grep -c 'DNSBL disabled' /var/log/pfblockerng/pfblockerng.log

# 3. DNSBL data should be fresh (age in hours of the newest file)
ls -lt /var/db/pfblockerng/dnsbl | head -3
```

### 5. Dashboard Panels

*(SIEM stack only)*

pfBlockerNG's `ip_block.log` and `dnsbl.log` are tailed by Telegraf on the firewall and written straight to OpenSearch (`pfblockerng-*` indices), where the `pfsense_pfblockerng_system.json` dashboard reads them through the OpenSearch-pfBlockerNG datasource: blocks over time, top blocked sources and destinations, ports, protocols, countries, feeds, and DNSBL domains and clients.

- Pipeline setup: [TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md)
- Panel list and import: [dashboards/README.md](../../dashboards/README.md)

---

### 6. Are the feeds themselves alive?

A feed can fail for months while the list keeps "working": pfBlockerNG keeps the last good copy, or, when a download
returns an error page or nothing, fills the table with the placeholder address `127.1.7.7`. Nothing alerts. In October
2026 an audit of a running box found, among about 25 IP feeds:

| Symptom | Example found | Cause |
|---|---|---|
| Table is just `127.1.7.7` | `Abuse_SSLBL` (last updated 2025-01-02) | abuse.ch retired the SSL IP blacklist; the URL answers with a stub |
| Table has 1 to 3 entries from a feed that should have hundreds | `ISC_Shadowserver`, `ISC_Shodan` | The URL returned an HTML page (Shadowserver) or XML on a single line (Shodan), and the parser keeps what it can find per line. The `isc.sans.edu/api/threatlist/<name>?text` form returns one entry per line and parses. |
| Header only, no IPs | `Darklist` (one run) | Upstream returned a header with an empty list; recheck later before removing |
| Same feed fails every day | `Maltrail_Scanners_All` (15 failures in 3 days), `H3X_1M`, `osint_malicious`, `1Hosts_Pro` (5 each) | Intermittent or persistent download failure; the log line is `Download FAIL` |
| DNSBL source cache is months old | `dnsblorig/*.orig` dated months ago for about 45 feeds while the log says "Update found" every night | The TOP1M whitelist (Services > pfBlockerNG > DNSBL > TOP1M) is a zip. pfBlockerNG validates downloads with `/usr/bin/file --mime-type`, which on this FreeBSD 15 base reports zip files as `application/octet-stream`; the download is rejected ("Failed or invalid Mime Type"), `pfbalexawhitelist.txt` is never built, and every run then sets "reuse the cache" for the whole DNSBL, so **nothing downloads**. Check: `ls /var/db/pfblockerng/pfbalexawhitelist.txt` and `grep 'Failed or invalid Mime Type' /var/log/pfblockerng/pfblockerng.log`. Fix: place the unzipped `top-1m.csv` in `/var/db/pfblockerng/` yourself (any zip of rank,domain lines, for example Cisco's or Tranco's), or turn the TOP1M whitelist off. |
| A CDN-hosted list returns 403 | Hagezi Pro/TIF via `cdn.jsdelivr.net` ("Package size exceeded the configured limit") | Use the project's own mirrors (GitLab or Codeberg) instead |
| Per-feed DNSBL file shows 0 lines | about 10 feeds | Usually normal: pfBlockerNG removes domains already listed by an earlier feed, so a feed that is a subset of another shows 0. Not proof of a dead feed. |

Check your own box (read-only, on pfSense):

```sh
# 1. Placeholder or near-empty IP tables, and files that stopped changing
now=$(date +%s)
for f in /var/db/pfblockerng/deny/*_v4.txt; do
  n=$(grep -cE '^[0-9]' "$f"); a=$(( (now - $(stat -f %m "$f")) / 86400 ))
  [ "$n" -le 2 ] || [ "$a" -gt 3 ] && echo "$(basename "$f" .txt): $n entries, ${a}d old"
done

# 2. What the feed really returned (the raw download), not what the parser kept
head -c 300 /var/db/pfblockerng/original/<ListName>_v4.orig

# 3. Which feeds failed to download, and how often (the log only goes back a few days)
grep 'Download FAIL' /var/log/pfblockerng/pfblockerng.log | sed -E 's/ \[ [0-9\/]+ [0-9:]+ \]//' | sort | uniq -c | sort -rn
```

A cheap monthly habit: run the first loop, open the `.orig` of anything it prints, and replace or drop the feed.

**Making a URL change take effect.** Editing a feed's URL does not redownload it. Each list is fetched only when the cron
job reaches its own schedule (a list set to `EveryDay` at hour 0 is fetched once a day at 00:01), and both
`pfblockerng.php update` and `updateip` only *reload* from the cached download. A full forced update takes about 10 to
12 minutes, restarts the DNSBL resolver for a moment, and still left the old HTML page in the cache. To test a URL
change now, fetch the file yourself into `/var/db/pfblockerng/original/<ListName>_v4.orig` with the same User-Agent
pfBlockerNG uses (`pfSense/pfBlockerNG cURL download agent-...`), then run `updateip`; otherwise wait for the schedule.
Confirm afterwards that the raw entry count in the `.orig` and the final count make sense: pfBlockerNG removes
addresses already present in other lists, so a feed that overlaps heavily shows few entries (the ISC Shadowserver list
parsed 988 addresses but only 24 were new, and ISC Shodan 55 but only 2, after de-duplication against the mass-scanner lists).

**Overlap with Suricata, measured.** Before moving Suricata rule files "into" pfBlockerNG, count the real overlap:
the abuse.ch `feodotracker.rules` is 5 rules, `emerging-threatview_CS_c2.rules` has 752 Cobalt Strike C2 addresses of
which only 1 is in any pfBlockerNG list (so it is unique coverage), and `sslblacklist_tls_cert.rules` is 10,879
certificate-fingerprint rules that an IP list cannot replace. The only large, safe overlap was the ET IP-reputation set
(97% of the WAN IPS's blocked sources were already in pfBlockerNG tables); see the
[Suricata guide](SURICATA_OPTIMIZATION_GUIDE.md#inline-ips-cost-what-it-takes-what-cuts-it-what-does-not).

### 7. Which blocks hurt real use? (false-positive review)

Method used on a busy home network: take `dnsbl.log` (client address and domain per block) and `ip_block.log`, de-duplicate,
and read them by VLAN and by feed. The client's third octet gives the VLAN. Eight days of history (the log was lost
and rebuilt, so the dates are not contiguous) was about 2,400 distinct domain-and-client pairs.

**IP lists were clean.** In 8 days there were about 40,400 blocks, every one inbound (scanners and botnets hitting the
WAN), and none caused by a LAN device reaching a listed address. A few log rows say `out`, but they are inbound SYNs whose
destination is the WAN address, logged around Suricata restarts; do not read them as your devices being blocked.

**DNSBL false positives were concentrated in two feeds, for a structural reason.** Feeds that list individual phishing
or malware *URLs* (PhishTank, OpenPhish) and "ad-fritzbox" style lists get reduced to hostnames by pfBlockerNG, so one bad
page on a big site blocks the whole site:

| Blocked domain | Feed | Effect |
|---|---|---|
| `apis.google.com`, `firebasestorage.googleapis.com` | PhishTank | breaks Google sign-in widgets and apps that store data in Firebase |
| `www.bing.com`, `th.bing.com` | PhishTank | search and image thumbnails fail |
| `gravatar.com`, `0.gravatar.com`, `framer.com`, `issuu.com`, `embeds.beehiiv.com`, `us5.campaign-archive.com` | PhishTank | avatars, embeds and newsletter archive pages fail |
| `paypalobjects.com`, `disqus.com`, `onesignal.com`, `ucarecdn.com` | Kowabit | PayPal's static assets (checkout pages), comment widgets, push notifications and a CDN fail |

A domain on its own in this table was blocked at least once; `apis.google.com` and `www.bing.com` were still returning
`0.0.0.0` when checked. Pure tracker and telemetry blocks (Microsoft `events.data` endpoints, Firebase logging, ad
networks) outnumber everything else and are harmless to function.

**Your choices, in order of effect:**

1. Drop or demote the URL-based phishing feeds from DNSBL (PhishTank first), and keep domain-based ones
   (`phishing_army`, Hagezi TIF). This removes the largest source of whole-site blocks at the cost of some coverage.
2. Allowlist the specific domains you rely on in the **GUI** (**DNSBL > DNSBL Whitelist**). Writing the same entries into
   `config.xml` from a script saved them but never reached the generated whitelist the resolver reads, so use the GUI
   and then re-run the DNSBL reload. Do this after every "it only breaks at home" complaint; the list on the box had 2,449 entries after a few
   months of that.
3. Keep telemetry blocking away from a managed work machine if your employer's device-management tooling expects its
   telemetry endpoints. The DNSBL cannot exempt a *network*, but its Python mode has a **Group Policy bypass list**
   (DNSBL settings; off by default) that exempts individual *client IPs*, exact match, no CIDR. Give those machines
   DHCP reservations first so the addresses do not change. Unbound's `access-control-view` is the alternative if you
   need whole-network exemptions.

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

### DNSBL silently stopped after a package reinstall or upgrade

**Symptoms**: the IP lists still update and block, but a domain on your DNSBL feeds resolves normally,
`pfblockerng.log` repeats `DNSBL disabled: no VIP configured`, and the DNSBL feed files stop updating.

**Cause** (seen on pfBlockerNG-devel 3.2.14_1): the package upgrade rewrote the DNSBL settings. In the new schema the
DNSBL virtual IP is stored as a VIP **ID** (`_vip<uniqid>`) under `pfb_dnsvip4`, the VIP must sit on the same interface as
`dnsbl_interface`, and the Unbound python hook is managed by the package. The migration dropped the VIP selection and the
VIP itself, so the package disabled DNSBL and removed its Unbound integration, without any error in the GUI.

**Fix**: create the virtual IP again (type *IP Alias*, a single `/32` from a private range you do not use elsewhere, on
the DNSBL interface), select it on **Firewall → pfBlockerNG → DNSBL**, save, then force a DNSBL reload. From the shell:

```bash
php /usr/local/www/pfblockerng/pfblockerng.php updatednsbl
```

With about 85 feeds this takes roughly ten minutes. Then run the three checks in
[Is DNSBL actually enforcing?](#4-is-dnsbl-actually-enforcing). Setting only the old key names (`pfb_dnsvip`) from a
backup does **not** work on the new schema.

**Detect it early**: config backups record the change (`pfBlockerNG: saving DNSBL changes` right after a
`Creating restore point before package installation` entry), and the DNSBL feed files go stale. A weekly check of the
three commands above catches it in days instead of months.

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
