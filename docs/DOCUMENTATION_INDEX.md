# Documentation Index

> This repo doubles as a **pfSense knowledge base** and the documentation for a
> **production pfSense → SIEM deployment**. Everything here is written from a real,
> running stack — pfSense with Suricata, pfBlockerNG and Telegraf feeding OpenSearch,
> Logstash and Grafana — so others can run the same thing, understand why it is built
> this way, and keep it healthy.

Pick the path that matches what you are trying to do:

| I want to... | Start at |
|--------------|----------|
| Run Suricata / pfBlockerNG / Telegraf well on pfSense (no SIEM needed) | [pfSense knowledge base](#-pfsense-knowledge-base-no-siem-required) |
| **Upgrade pfSense** (2.8.1 → 2.9.0) without breaking things | [Upgrading pfSense](pfsense/PFSENSE_UPGRADE_GUIDE.md) |
| Deploy the SIEM stack from scratch | [Deploy it](#-deploy-it) |
| Understand the architecture and data model | [Understand it](#-understand-it) |
| Keep a running deployment healthy | [Operate it](#-operate-it) |
| Fix something that broke | [Fix it](#-fix-it) |
| Add capability or another SIEM backend | [Extend it](#-extend-it) |

Directory layout:

```
docs/
├── DOCUMENTATION_INDEX.md   ← You are here
├── ARCHIVE.md               ← Where superseded material went (git history)
├── pfsense/                 ← Generic pfSense knowledge: Suricata, pfBlockerNG, Telegraf, QoS, upgrades
├── install/                 ← SIEM server, forwarder, GeoIP, dashboards, hardware, checklist
├── operations/              ← Management console, forwarder monitoring, retention
├── troubleshooting/         ← Symptom → root cause → fix
├── reference/               ← Configuration, field reference, architecture
└── siem/                    ← Other backends: comparison, Wazuh, Graylog
```

Conventions used throughout: `admin@<PFSENSE_IP>` is your pfSense SSH login,
`<SIEM_IP>` your SIEM server, interface names like `igc0` / `igc1.20` are examples —
substitute your own. Example public addresses use RFC 5737 space (`203.0.113.x`).

---

## 🔥 pfSense knowledge base (no SIEM required)

These guides apply to any pfSense CE 2.7+/2.8/2.9 box. Only the sections that mention
Grafana panels depend on the rest of this repo.

### Suricata

- **[Suricata Optimization Guide](pfsense/SURICATA_OPTIMIZATION_GUIDE.md)** ⭐ — the
  complete path: install, choose rulesets (ET Open + Snort registered), inline IPS on WAN
  vs IDS on VLANs, performance tuning (stream memcap, detect profile), testing and
  validation
- **[Suricata Configuration & Design Decisions](pfsense/SURICATA_CONFIGURATION.md)** —
  why Suricata over Snort, interface strategy, and the **SID tuning philosophy**: start
  broad, measure noise, then disable/suppress with tracked lists instead of ad-hoc GUI
  clicks
- **[SID lists](../config/sid/README.md)** — the maintainer's `disablesid` / `dropsid` /
  `suppress` lists, how they were derived, how to build your own from your alert
  volume, and how to apply them through SID Mgmt (survives upgrades)
- **[LAN / East-West Monitoring](pfsense/LAN_MONITORING.md)** — IDS on internal VLANs
  to catch lateral movement, with per-VLAN policy examples

### pfBlockerNG

- **[pfBlockerNG Optimization](pfsense/PFBLOCKERNG_OPTIMIZATION.md)** — strategy:
  which feed tiers, how pfBlockerNG and Suricata divide the work, update cadence, CPU
  and memory impact
- **[pfBlockerNG Feed Reference](pfsense/PFBLOCKERNG_FEED_REFERENCE.md)** — the long
  catalog: IP and DNSBL feeds by category, whitelisting strategy
  ([`config/dnsbl_whitelist.txt`](../config/dnsbl_whitelist.txt)), privacy notes,
  troubleshooting

### Telegraf and metrics

- **[Telegraf on pfSense](pfsense/TELEGRAF_ON_PFSENSE.md)** — install, where the config
  really lives (config.xml → regenerated `telegraf.conf`), the *Additional
  Configuration* box, why it runs as root, how to restart it correctly, the
  **pfSense 2.9.0 Telegraf breakage** and workaround
- **[Telegraf plugins](../plugins/README.md)** — gateway status, ARP MAC vendor,
  temperature and Unbound collectors shipped in this repo
- **[MAC Vendor Lookup](pfsense/MAC_VENDOR_LOOKUP_SETUP.md)** — device manufacturer
  identification from the ARP table
- **[Telegraf pfBlockerNG Pipeline](pfsense/TELEGRAF_PFBLOCKER_SETUP.md)** — shipping
  pfBlockerNG block/DNSBL logs to OpenSearch via Telegraf's tail input

### Platform

- **[Upgrading pfSense](pfsense/PFSENSE_UPGRADE_GUIDE.md)** ⭐ — general checklist plus
  the 2.9.0 specifics (FreeBSD 16-CURRENT, PHP 8.5, sshd algorithm changes, Telegraf
  package breakage, certificate enforcement), what this repo drops on pfSense and what
  survives, post-upgrade verification
- **[pfSense Filterlog Rotation Bug](troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md)** —
  firewall and pfBlockerNG logging silently stopping after newsyslog rotation, and the
  Cron-package job that fixes it
- **[Traffic Shaping Guide](pfsense/TRAFFIC_SHAPING_GUIDE.md)** — limiters, CoDel and
  weighted queues for streaming/gaming/VoIP alongside bulk traffic
- **[Hardware Requirements](install/HARDWARE_REQUIREMENTS.md)** — sizing pfSense for
  IDS/IPS (and the SIEM server), and why SD cards will ruin your day
- **[CrowdSec (exploratory)](pfsense/crowdsec-phase1.md)** — notes toward a CrowdSec
  integration; not part of the stack yet

---

## 🚀 Deploy it

Ordered steps for a from-scratch SIEM deployment. The short version is
[QUICK_START.md](../QUICK_START.md); these are the detailed guides behind each step.

1. **[Hardware Requirements](install/HARDWARE_REQUIREMENTS.md)** — size both hosts first
2. **[New User Checklist](install/NEW_USER_CHECKLIST.md)** — tick-box path from bare
   metal to working dashboards
3. **Server side** — point `config.env` at an existing OpenSearch + Grafana
   ([siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack) is the
   recommended backend). No server yet? **[SIEM Stack Installation](install/INSTALL_SIEM_STACK.md)**
   covers the bare-metal single-box path (`install.sh` and the manual steps behind it)
4. **[pfSense Forwarder Installation](install/INSTALL_PFSENSE_FORWARDER.md)** — the EVE
   forwarder, rc.d service and watchdog on pfSense (what `setup.sh` automates)
5. **[GeoIP Setup](install/GEOIP_SETUP.md)** — reusing the GeoLite2 database already on
   pfSense for the attack map
6. **[Dashboard Installation](install/INSTALL_DASHBOARD.md)** — datasources, the
   OpenSearch plugin, importing and adapting the dashboards
   ([inventory](../dashboards/README.md))

> `scripts/preflight.sh` validates config.env, SSH to both hosts, Python on pfSense and
> OpenSearch reachability before anything is changed. `setup.sh` runs it automatically.

---

## 🧠 Understand it

- **[Architecture diagram](reference/architecture.png)** (source
  [architecture.mmd](reference/architecture.mmd)) — pfBlockerNG → Suricata → EVE →
  forwarder (UDP) → Logstash → OpenSearch → Grafana, plus Telegraf → InfluxDB/OpenSearch
- **[Field Reference](reference/FIELD_REFERENCE.md)** — the authoritative list of what
  is stored in `suricata-*` and `pfblockerng-*`, and **why fields are flat, not nested**
- **[Configuration Reference](reference/CONFIGURATION.md)** — every `config.env`
  variable, forwarder behaviour, Logstash pipeline, index templates, Grafana
  datasources, tuning and Logstash maintenance
- **[Config files](../config/README.md)** — the shipped Logstash pipeline and index
  templates themselves
- **[SIEM backend comparison](siem/COMPARISON.md)** — OpenSearch vs Wazuh vs Graylog for
  this use case, and what was decided

---

## ⚙️ Operate it

- **[Management Console](operations/MANAGEMENT_CONSOLE.md)** — the `pfsense-siem` menu:
  install, deploy, status, logs, backups, preflight
- **[Forwarder Monitoring](operations/SURICATA_FORWARDER_MONITORING.md)** — how the
  forwarder runs (rc.d + `daemon`), the watchdog, day-2 commands, what survives
  reboot/upgrade, uninstall
- **[Multi-Interface & Retention](operations/MULTI_INTERFACE_RETENTION.md)** — many
  Suricata instances at once, and ISM retention to control disk
- **[Scripts Reference](../scripts/README.md)** — every helper script, where it runs,
  and which are legacy
- **[Upgrading pfSense](pfsense/PFSENSE_UPGRADE_GUIDE.md)** — the post-upgrade
  procedure for the SIEM pieces (`preflight.sh` → `setup.sh` → `status.sh`)

---

## 🔧 Fix it

- **[Troubleshooting Guide](troubleshooting/TROUBLESHOOTING.md)** — master runbook;
  start with `./scripts/status.sh` and `./scripts/diagnose-and-repair.sh`
- **[Dashboard shows "No Data"](troubleshooting/DASHBOARD_NO_DATA_FIX.md)** 🔥 — the most
  common issue: datasource, index pattern, field mapping
- **[Data stops at midnight UTC](troubleshooting/OPENSEARCH_AUTO_CREATE.md)** —
  `action.auto_create_index` blocking the new daily index
- **[Forwarder and rotated logs](troubleshooting/LOG_ROTATION_FIX.md)** — how the
  forwarder follows Suricata's rotation (and how that differs from the filterlog bug)
- **[pfSense filterlog rotation bug](troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md)**
  — pfBlockerNG/firewall logs stop after newsyslog rotation
- **[Telegraf on pfSense → Troubleshooting](pfsense/TELEGRAF_ON_PFSENSE.md)** — PF
  Information panel empty, exec plugin timeouts, 2.9.0 config rejection

---

## 🧩 Extend it

- **[Wazuh](siem/wazuh/README.md)** — what ships here (three dashboards +
  `deploy-wazuh-dashboards.py`), how pfSense feeds Wazuh (RFC 5424 syslog), and where
  the Wazuh server lives ([siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack))
- **[Graylog](siem/graylog/README.md)** — explored and shelved; what a revival would need
- **[Roadmap](../ROADMAP.md)** — alerting as code, TLS/queued transport, OpenSearch
  security, LAN dashboard, multi-firewall
- **[Contributing](../CONTRIBUTING.md)** — how to submit dashboards, docs and fixes;
  what CI checks

---

## 🗄️ Archived material

Superseded docs, scripts, dashboards and plugins were removed from the working tree and
live in git history. **[ARCHIVE.md](ARCHIVE.md)** has the commit hash and recovery
commands.
