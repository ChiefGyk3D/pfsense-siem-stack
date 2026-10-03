# Glossary

One-line definitions of the terms used across this wiki, with a link to the page that
explains each in depth. Grouped by where you meet them.

## pfSense

| Term | Meaning |
|------|---------|
| **pfSense CE / Plus** | The free Community Edition and Netgate's commercial Plus edition of the pfSense firewall. These guides are written for CE 2.7.2 and later (2.8.1 tested, 2.9.0 with caveats). |
| **config.xml** | The single file that holds every setting made through the pfSense GUI. It is what **Diagnostics → Backup & Restore** saves and the only thing pfSense guarantees to carry through an upgrade or reinstall. See [Upgrading pfSense](../docs/pfsense/PFSENSE_UPGRADE_GUIDE.md). |
| **Package** | Software added through **System → Package Manager**: Suricata, pfBlockerNG-devel, Telegraf, ntopng, Cron, Filer, Service_Watchdog, nut. Packages installed from the GUI are recorded in `config.xml` and reinstalled after an upgrade; `pkg install` from the shell is not. |
| **Cron package** | The pfSense package that stores cron jobs in `config.xml`. Use it instead of editing `/etc/crontab`, which pfSense regenerates. Used for the [filterlog fix](../docs/troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md). |
| **Filer package** | Stores the *contents* of arbitrary files inside `config.xml` and rewrites them to disk at boot. The durable way to keep scripts such as the [Telegraf plugins](../plugins/README.md) on the box. |
| **rc.d script** | A FreeBSD service script in `/usr/local/etc/rc.d/`. pfSense only auto-starts the ones whose name ends in `.sh` at boot, which is why this project's forwarder service is `suricata_forwarder.sh`. |
| **daemon(8)** | The FreeBSD supervisor used by the forwarder's rc.d script: detaches the process, writes a pidfile, captures output and restarts the child if it exits. |
| **filterlog / newsyslog** | `filterlog` turns pf log records into `/var/log/filter.log`; `newsyslog` rotates logs. A pfSense bug makes filterlog lose its handle after rotation, so logging stops. [Fix](../docs/troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md). |
| **pf / pfctl** | The FreeBSD packet filter and its control tool. `pfctl -sr` lists loaded rules; `pfctl -s info` reports statistics only to root, which is why Telegraf runs as root. |
| **Unbound** | The DNS Resolver built into pfSense. pfBlockerNG's DNSBL works by feeding it block entries; the Telegraf Unbound plugin reads its statistics. |
| **VLAN** | A tagged virtual network on a physical interface (`igc1.20` is VLAN 20 on `igc1`). Segmenting Trusted, IoT and Guest networks onto VLANs is what makes [east-west monitoring](../docs/pfsense/LAN_MONITORING.md) useful. |
| **East-west traffic** | Traffic between internal networks or hosts, as opposed to north-south traffic to and from the internet. WAN-only IDS never sees it. |
| **ZFS boot environment** | A snapshot of the pfSense system you can boot back into. Create one before an upgrade. |
| **Limiter / ALTQ / CoDel** | pfSense traffic-shaping mechanisms. See the [Traffic Shaping Guide](../docs/pfsense/TRAFFIC_SHAPING_GUIDE.md). |

## Suricata

| Term | Meaning |
|------|---------|
| **IDS / IPS** | Intrusion *Detection* System (alerts only) versus Intrusion *Prevention* System (can block). Start in IDS mode; promote WAN to IPS after tuning. [IDS vs IPS Mode](../docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md#ids-vs-ips-mode). |
| **Inline mode / netmap** | Capture method where Suricata sits in the packet path using FreeBSD netmap. Required for blocking and the best-performing choice on Intel NICs. Enabling it does **not** block anything by itself. |
| **Legacy mode** | pcap-based capture. Fall back to it only if inline misbehaves on your NIC or VLAN/LAGG parent. |
| **Promiscuous mode** | Makes Suricata see frames not addressed to the firewall's own MAC. Needed only for mirror ports and some bridge setups. |
| **Instance** | One Suricata process per enabled interface, each with its own copy of the rule set, its own log directory (`/var/log/suricata/suricata_<iface><id>/`) and its own CPU and memory cost. |
| **Rule / signature** | A pattern Suricata matches against traffic, with an action (`alert`, `drop`), a message and a **SID**. |
| **SID / GID** | Signature ID and generator ID. `1:2029322` is signature 2029322 from the main engine; preprocessor events use other GIDs (`119:31`). |
| **Classtype** | A rule's category label (`trojan-activity`, `attempted-recon`, `misc-activity`). The most reliable signal of how confident a rule is, and what the shipped drop lists match on. |
| **Rule sources** | Where rules come from: **Emerging Threats Open** (free), **Snort registered** (free with an account) and **Snort subscriber** (paid), plus abuse.ch's Feodo Tracker and SSL Blacklist. |
| **Oinkcode** | The personal key from snort.org that lets the Suricata package download Snort rules. |
| **ET / GPL / SURICATA prefixes** | Where an alert's message comes from: Emerging Threats, the old GPL community rules, or Suricata's own engine and protocol-anomaly events. The last group is almost always noise. |
| **disablesid.conf** | SID Mgmt file listing rules that are not loaded at all. Zero cost. For rules that are always noise on your network. [SID Management](../config/sid/README.md). |
| **dropsid.conf** | SID Mgmt file that rewrites listed rules from `alert` to `drop`. Only has an effect on inline-IPS interfaces. |
| **Suppress list** | Hides alerts from a rule when the source or destination matches an IP or subnet. The rule still runs and still costs CPU. For false positives limited to specific hosts. |
| **SID Mgmt** | **Services → Suricata → SID Mgmt**, the GUI tab that applies the files above and stores them in `config.xml`. |
| **Pass list** | Addresses Suricata should never block (your own networks, DNS servers, the SIEM). |
| **HOME_NET / EXTERNAL_NET** | Variables that define "inside" and "outside" for the rules. Set HOME_NET to your internal ranges on VLAN instances. |
| **Stream memcap / reassembly memcap** | Per-instance memory ceilings for TCP stream tracking and reassembly. pfSense defaults 256 MB / 128 MB; raise toward 1 GB when the memcap counters climb or an instance crashes on a busy link. [Stream Memory](../docs/pfsense/SURICATA_CONFIGURATION.md#-stream-memory). |
| **Detect engine profile** | Low / medium / high setting trading memory for detection speed. High on WAN, medium on VLANs. |
| **capture.kernel_drops** | The stats counter for packets Suricata could not keep up with. Should be at or near zero. |
| **EVE JSON / eve.json** | Suricata's structured event log: one JSON object per line for alerts, DNS, HTTP, TLS, flows and stats. This is what the forwarder ships. |
| **Live Rule Swap** | Global Setting that reloads rules without restarting the instance. Enable it. |

## pfBlockerNG

| Term | Meaning |
|------|---------|
| **pfBlockerNG-devel** | The package branch to install; it gets features first and is what these guides describe. |
| **IP blocklist / feed** | A downloaded list of hostile addresses turned into a pf table and firewall rules (aliases prefixed `pfB_`). |
| **DNSBL** | DNS-based blocklist: domains the firewall's resolver answers with a sinkhole address. Only works for clients that use the firewall for DNS. |
| **Deny Inbound / Deny Both** | List actions. *Deny Both* for command-and-control and malware infrastructure (stops outbound beaconing too); *Deny Inbound* for scanners and spam sources. |
| **Suppression / whitelist** | Addresses or domains exempted from blocking. Always whitelist your own subnets, DNS servers and the SIEM. [Whitelisting Guide](../docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md#whitelisting-guide). |
| **Feodo Tracker, SSLBL, URLhaus, Spamhaus DROP, OISD** | The handful of feeds that carry most of the value. [pfBlockerNG Optimization](../docs/pfsense/PFBLOCKERNG_OPTIMIZATION.md). |
| **MaxMind / GeoLite2** | The free GeoIP database (needs a free account and license key). pfBlockerNG or ntopng downloads it; this project's forwarder only reads it. [GeoIP Setup](../docs/install/GEOIP_SETUP.md). |

## Telegraf and metrics

| Term | Meaning |
|------|---------|
| **Telegraf** | InfluxData's metrics agent, available as a pfSense package. Collects system metrics and, here, tails pfBlockerNG logs. [Telegraf on pfSense](../docs/pfsense/TELEGRAF_ON_PFSENSE.md). |
| **Additional Configuration** | The free-text box on **Services → Telegraf** that is appended to the generated config. The only persistent place for your own inputs and outputs. |
| **telegraf.conf** | The file the package regenerates from `config.xml` on every save. Read it; never edit it. |
| **inputs.exec** | Telegraf input that runs a script and parses its output. How the [plugins](../plugins/README.md) are wired in. |
| **inputs.tail** | Telegraf input that follows a log file. Used with grok patterns for pfBlockerNG's `ip_block.log` and `dnsbl.log`. |
| **outputs.opensearch** | Telegraf output (1.28+) that writes measurements as OpenSearch documents. Used for pfBlockerNG data; not to be confused with `outputs.elasticsearch`, which fails against OpenSearch. |
| **Line protocol** | InfluxDB's text format (`measurement,tag=v field=v timestamp`). What the exec plugins print. |
| **InfluxDB** | Time-series database for system metrics. Better than OpenSearch for throughput and gateway graphs; worse for anything with IP addresses, which blow up its series cardinality. |
| **OUI** | The first three bytes of a MAC address, which identify the manufacturer. [MAC Vendor Lookup](../docs/pfsense/MAC_VENDOR_LOOKUP_SETUP.md). |

## SIEM stack

| Term | Meaning |
|------|---------|
| **SIEM** | Security Information and Event Management: central storage, search and visualisation of security events. Here, OpenSearch + Logstash + Grafana. |
| **Forwarder** | `forward-suricata-eve.py`, the Python process on pfSense that tails every `eve.json`, survives rotation, adds GeoIP and sends events over UDP 5140. [Forwarder Operations](../docs/operations/SURICATA_FORWARDER_MONITORING.md). |
| **Watchdog** | A one-line cron job in root's crontab that restarts the forwarder service if the process is gone. Runs every minute. |
| **Logstash** | Receives the UDP events, parses the JSON and indexes it into OpenSearch. [Configuration Files](../config/README.md). |
| **OpenSearch** | The Apache-2.0 search and analytics store (a fork of Elasticsearch) where events live. |
| **Index** | A daily collection of documents: `suricata-YYYY.MM.DD`, `pfblockerng-YYYY.MM.DD`. Dashboards query the pattern `suricata-*`. |
| **Index template** | The mapping OpenSearch applies when a new daily index is created (`geo_point` for locations, `keyword` for things you aggregate on). |
| **action.auto_create_index** | Cluster setting that must allow the daily index names, or ingestion stops at midnight UTC. [Data Stops at Midnight UTC](../docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md). |
| **ISM** | Index State Management, OpenSearch's retention mechanism: delete indices older than N days. [Multi-Interface and Retention](../docs/operations/MULTI_INTERFACE_RETENTION.md). |
| **Flat fields** | Events are stored exactly as Suricata wrote them, at the root of the document (`src_ip`, `alert.signature`), never nested under a `suricata.eve.*` prefix. [Field Reference](../docs/reference/FIELD_REFERENCE.md). |
| **geoip_src / geoip_dest** | The enrichment objects the forwarder adds: country, city and a `location` the map panel can plot. |
| **in_iface** | The EVE field naming the interface an event was seen on. What the per-interface dashboard filters on. |
| **Grafana** | The dashboard front end. Datasources `OpenSearch`, `OpenSearch-pfBlockerNG`, `InfluxDB-pfSense`. [Dashboards](../dashboards/README.md). |
| **config.env** | The one file on your workstation that tells every script where pfSense and the SIEM are. [Configuration Reference](../docs/reference/CONFIGURATION.md). |
| **setup.sh / install.sh / preflight.sh / status.sh** | Deploy everything to pfSense and the SIEM; build a bare-metal SIEM server; check prerequisites; check health. [Scripts Reference](../scripts/README.md). |
| **pfsense-siem** | The interactive menu wrapping the scripts. [Management Console](../docs/operations/MANAGEMENT_CONSOLE.md). |
| **siem-docker-stack** | The maintainer's Dockerised SIEM backend (OpenSearch, Logstash, Grafana, Wazuh), the recommended server side. [SIEM Backend Comparison](../docs/siem/COMPARISON.md). |
| **Wazuh** | Host-based security platform (agents, file integrity, vulnerabilities, compliance). Its indexer is OpenSearch, so the same Grafana shows both. [Wazuh Integration](../docs/siem/wazuh/README.md). |
| **RFC 5424** | The syslog format pfSense must use when sending logs to Wazuh, so the hostname is present. |
