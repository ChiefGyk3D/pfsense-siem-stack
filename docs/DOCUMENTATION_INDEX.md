# Documentation Index

> This repo doubles as a **documentation hub for a production pfSense → SIEM deployment**.
> Everything here is written from a real, running stack — pfSense with Suricata and
> pfBlockerNG feeding OpenSearch, Logstash, and Grafana — so others can deploy the same
> thing, understand why it is built this way, and keep it healthy.

The docs are organized by task. Pick the path that matches what you are trying to do:

| I want to... | Start at |
|--------------|----------|
| Deploy the stack from scratch | [Deploy it](#-deploy-it) |
| Understand the architecture and design decisions | [Understand it](#-understand-it) |
| Keep a running deployment healthy | [Operate it](#-operate-it) |
| Fix something that broke | [Fix it](#-fix-it) |
| Add capability or another SIEM backend | [Extend it](#-extend-it) |

Directory layout:

```
docs/
├── DOCUMENTATION_INDEX.md   ← You are here
├── ARCHIVE.md               ← Where superseded material went (git history)
├── install/                 ← SIEM server, forwarder, dashboards, GeoIP
├── pfsense/                 ← Suricata/pfBlockerNG tuning, Telegraf, traffic shaping
├── operations/              ← Monitoring, watchdogs, retention, management console
├── troubleshooting/         ← Symptom → root cause → fix guides
├── reference/               ← Configuration reference, scripts reference, architecture
└── siem/                    ← SIEM backend comparison (OpenSearch, Wazuh, Graylog)
```

---

## 🚀 Deploy it

Ordered steps for a from-scratch deployment. The short version lives in
[QUICK_START.md](../QUICK_START.md); these are the detailed guides behind each step.

1. **[Hardware Requirements](install/HARDWARE_REQUIREMENTS.md)** — sizing the SIEM
   server and pfSense box before you start (and why SD cards will ruin your day)
2. **[New User Checklist](install/NEW_USER_CHECKLIST.md)** — complete step-by-step
   checklist from bare metal to working dashboards
3. **[SIEM Stack Installation](install/INSTALL_SIEM_STACK.md)** — OpenSearch, Logstash,
   and Grafana on Ubuntu 24.04 (automated by `install.sh`)
4. **[pfSense Forwarder Installation](install/INSTALL_PFSENSE_FORWARDER.md)** — the
   Python EVE forwarder on pfSense (automated by `setup.sh`)
5. **[GeoIP Setup](install/GEOIP_SETUP.md)** — MaxMind GeoLite2 databases for the
   geographic attack map
6. **[Dashboard Installation](install/INSTALL_DASHBOARD.md)** — Grafana datasources,
   the OpenSearch plugin, and importing the prebuilt dashboards

> Before running anything, `scripts/preflight.sh` validates config.env, SSH access to
> both hosts, Python on pfSense, and OpenSearch reachability. `setup.sh` runs it
> automatically.

---

## 🧠 Understand it

The architecture and the design decisions behind it.

- **[Architecture Diagram](reference/architecture.png)** — full data-flow picture
  (source: [architecture.mmd](reference/architecture.mmd)); traffic → pfBlockerNG →
  Suricata → EVE JSON → forwarder (UDP) → Logstash → OpenSearch → Grafana
- **[Configuration Reference](reference/CONFIGURATION.md)** — every config file
  explained: OpenSearch index templates, the Logstash pipeline (including **why events
  are kept in flat EVE format** instead of nested ECS — Grafana's OpenSearch datasource
  aggregates far better on flat keyword fields), Grafana datasources, and forwarder
  settings
- **[Suricata Configuration Guide](pfsense/SURICATA_CONFIGURATION.md)** — why Suricata
  over Snort, interface strategy (inline IPS on WAN, IDS on VLANs), and the **SID tuning
  philosophy**: start broad, measure noise in the dashboard, then disable/suppress with
  tracked SID lists (`config/sid/`) instead of ad-hoc GUI clicks

---

## ⚙️ Operate it

Day-2 operations: monitoring the monitoring, retention, and routine maintenance.

- **[Management Console](operations/MANAGEMENT_CONSOLE.md)** — the `pfsense-siem`
  interactive menu: install, deploy, status, logs, backups, and preflight checks in one place
- **[Scripts Reference](reference/SCRIPTS_REFERENCE.md)** — every helper script in
  `scripts/`, with usage and when to reach for it
- **[Forwarder Monitoring](operations/SURICATA_FORWARDER_MONITORING.md)** — the
  reliability chain that keeps the forwarder alive: rc.d service (boot), watchdog cron
  (crash), restart hook (Suricata upgrades)
- **[Forwarder Monitoring Quick Reference](operations/FORWARDER_MONITORING_QUICK_REF.md)**
  — condensed commands for checking/restarting the forwarder
- **[Multi-Interface & Retention](operations/MULTI_INTERFACE_RETENTION.md)** — monitoring
  several Suricata interfaces at once and pruning old indices to control disk usage
- **[Filterlog Monitoring Cron](operations/SETUP_FILTERLOG_MONITORING_CRON.md)** —
  automated detection of the pfSense filterlog rotation bug
- **[Telegraf Restart Procedure](pfsense/TELEGRAF_RESTART_PROCEDURE.md)** — safely
  restarting Telegraf on pfSense (it runs as root there, on purpose)

---

## 🔧 Fix it

Symptom-driven guides. Start with the general guide, then the specific fix.

- **[Troubleshooting Guide](troubleshooting/TROUBLESHOOTING.md)** — the master guide:
  diagnostic commands and fixes for forwarder, Logstash, OpenSearch, and Grafana issues
- **[Dashboard Shows "No Data"](troubleshooting/DASHBOARD_NO_DATA_FIX.md)** — the most
  common issue: datasource, index pattern, and field-mapping causes
- **[Data Stops at Midnight UTC](troubleshooting/OPENSEARCH_AUTO_CREATE.md)** —
  OpenSearch `action.auto_create_index` blocking new daily indices
- **[Forwarder Stuck on Rotated Logs](troubleshooting/LOG_ROTATION_FIX.md)** — inode-aware
  rotation handling in the forwarder, and how it was fixed
- **[pfSense Filterlog Rotation Bug](troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md)**
  — firewall/pfBlockerNG logging silently stopping after newsyslog rotation
- **[PF Information Panel Empty](troubleshooting/PF_INFORMATION_PANEL_ISSUE.md)** —
  Telegraf's `pf` input needing root access to `/dev/pf`
- **[Telegraf Interface Detection Fixes](troubleshooting/TELEGRAF_INTERFACE_FIXES.md)** —
  making dashboards work with any NIC naming (igb/ix/em/re), not just hardcoded ones

---

## 🧩 Extend it

Optional capability on top of the base deployment, plus other SIEM backends.

### More pfSense visibility

- **[Suricata Optimization Guide](pfsense/SURICATA_OPTIMIZATION_GUIDE.md)** ⭐ — rule
  selection, performance tuning, IDS vs IPS per interface, testing and validation
- **[pfBlockerNG Optimization](pfsense/PFBLOCKERNG_OPTIMIZATION.md)** — blocklist
  strategy that cuts noise *before* it reaches Suricata
- **[LAN Monitoring & East-West Detection](pfsense/LAN_MONITORING.md)** — watching
  internal/VLAN traffic for lateral movement, not just the WAN edge
- **[Traffic Shaping Guide](pfsense/TRAFFIC_SHAPING_GUIDE.md)** — QoS for homelab
  streaming/gaming/VoIP alongside bulk traffic
- **[Telegraf pfBlockerNG Pipeline](pfsense/TELEGRAF_PFBLOCKER_SETUP.md)** — shipping
  pfBlockerNG block/DNSBL events straight to OpenSearch via Telegraf
- **[MAC Vendor Lookup](pfsense/MAC_VENDOR_LOOKUP_SETUP.md)** — device manufacturer
  identification from ARP data in Grafana
- **[CrowdSec Phase 1](pfsense/crowdsec-phase1.md)** — planned CrowdSec integration for
  aggregated ban decisions
- **[Telegraf plugins](../plugins/README.md)** — gateway, temperature, and Unbound DNS
  metrics collectors (installed by `install_plugins.sh`)

### Other SIEM backends

- **[SIEM Backend Comparison](siem/COMPARISON.md)** — OpenSearch vs Wazuh vs Graylog for
  this stack
- **[Wazuh Integration](siem/wazuh/README.md)** — XDR/compliance angle; Wazuh dashboards
  ship today in `dashboards/wazuh/`
- **[Graylog Integration](siem/graylog/README.md)** — explored and currently shelved;
  status and what a revival would need

### Contributing

- **[Contributing Guide](../CONTRIBUTING.md)** — how to submit dashboards, docs, and
  fixes back to the project

---

## 🗄️ Archived material

Superseded docs, scripts, dashboards, and plugins were removed from the working tree and
live in git history. See **[ARCHIVE.md](ARCHIVE.md)** for the exact commit hash and how
to recover anything.
