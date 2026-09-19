# Repository Layout

> Where things live and which entry point to use. For *what to read*, use the
> [Documentation Index](docs/DOCUMENTATION_INDEX.md).

## Entry points

| Command | Runs on | What it does |
|---------|---------|--------------|
| `./pfsense-siem` | workstation | Interactive menu wrapping everything below ([docs](docs/operations/MANAGEMENT_CONSOLE.md)) |
| `./scripts/preflight.sh` | workstation | Validates `config.env`, SSH to both hosts, Python on pfSense, OpenSearch reachability |
| `sudo ./install.sh` | SIEM server (Ubuntu) | Installs OpenSearch 2.x, Logstash 8.x, Grafana 12.x and the OpenSearch datasource plugin |
| `./setup.sh` | workstation | Applies index templates, deploys the Logstash pipeline, deploys the forwarder + rc.d service + watchdog to pfSense, creates Grafana datasources, imports the Suricata dashboards, verifies data flow. **Idempotent — re-run after a pfSense upgrade.** |
| `./install_plugins.sh` | workstation | Copies the Telegraf exec plugins in `plugins/` to pfSense |
| `./scripts/status.sh` / `diagnose-and-repair.sh` | workstation | Health check and guided repair |

## Tree

```
pfsense-siem-stack/
├── README.md                  ← Project overview and status
├── QUICK_START.md             ← Deployment walkthrough
├── ORGANIZATION.md            ← This file
├── ROADMAP.md · CHANGELOG.md · CONTRIBUTING.md · LICENSE (MPL 2.0)
├── config.env.example         ← Copy to config.env; consumed by setup.sh and every script
├── pfsense-siem · install.sh · setup.sh · install_plugins.sh
│
├── docs/
│   ├── DOCUMENTATION_INDEX.md ← Hub, organised by task
│   ├── ARCHIVE.md             ← Superseded material → git history
│   ├── pfsense/               ← Generic pfSense knowledge (works without the SIEM)
│   │   ├── SURICATA_OPTIMIZATION_GUIDE.md · SURICATA_CONFIGURATION.md
│   │   ├── PFBLOCKERNG_OPTIMIZATION.md · PFBLOCKERNG_FEED_REFERENCE.md
│   │   ├── TELEGRAF_ON_PFSENSE.md · TELEGRAF_PFBLOCKER_SETUP.md · MAC_VENDOR_LOOKUP_SETUP.md
│   │   ├── LAN_MONITORING.md · TRAFFIC_SHAPING_GUIDE.md
│   │   ├── PFSENSE_UPGRADE_GUIDE.md   ← 2.8.1 → 2.9.0 and what survives
│   │   └── crowdsec-phase1.md
│   ├── install/               ← HARDWARE_REQUIREMENTS · NEW_USER_CHECKLIST · INSTALL_SIEM_STACK
│   │                            INSTALL_PFSENSE_FORWARDER · GEOIP_SETUP · INSTALL_DASHBOARD
│   ├── operations/            ← MANAGEMENT_CONSOLE · SURICATA_FORWARDER_MONITORING · MULTI_INTERFACE_RETENTION
│   ├── troubleshooting/       ← TROUBLESHOOTING · DASHBOARD_NO_DATA_FIX · OPENSEARCH_AUTO_CREATE
│   │                            LOG_ROTATION_FIX · PFSENSE_FILTERLOG_ROTATION_FIX
│   ├── reference/             ← CONFIGURATION · FIELD_REFERENCE · architecture.mmd/.png
│   └── siem/                  ← COMPARISON · wazuh/README · graylog/README
│
├── config/
│   ├── README.md              ← The shipped config files explained
│   ├── logstash-suricata.conf ← Logstash pipeline (flat EVE fields → suricata-YYYY.MM.DD)
│   ├── opensearch-index-template.json        ← suricata-* mappings (geo_point, keyword, ip)
│   ├── opensearch-pfblockerng-template.json  ← pfblockerng-* mappings (keyword)
│   ├── dnsbl_whitelist.txt    ← pfBlockerNG DNSBL whitelist
│   └── sid/                   ← Suricata SID lists: disable/ drop/ suppress/ + README
│
├── dashboards/                ← Grafana JSON; README.md is the inventory
│   ├── Suricata_IDS_IPS.json · Suricata_Per_Interface.json · pfsense_pfblockerng_system.json
│   ├── windows_exporter.json · prometheus_stats.json · docker_container_monitoring.json
│   ├── suricata_ids_ips_active.json (raw export, same UID — do not import both)
│   ├── datasources_reference.json
│   └── wazuh/                 ← 3 Wazuh dashboards + README
│
├── scripts/                   ← README.md documents every script and marks legacy ones
│   ├── forward-suricata-eve.py            ★ the forwarder (deployed by setup.sh)
│   ├── preflight.sh · status.sh · diagnose-and-repair.sh · restart-services.sh
│   ├── install-opensearch-config.sh · configure-retention-policy.sh
│   ├── deploy-wazuh-dashboards.py · check-doc-links.py (CI)
│   ├── check_custom_sids.sh · check-telegram-alerts.sh · apply-suricata-drop-rules.sh · enable-selective-blocking.sh
│   └── legacy: setup_forwarder_monitoring.sh · suricata-forwarder-watchdog.sh · suricata-eve-forwarder.sh
│               suricata-restart-hook.sh · suricata-restart-with-forwarder.sh · unified-monitoring-watchdog.sh
│
├── plugins/                   ← Telegraf exec plugins for pfSense (+ README)
├── tests/                     ← pytest forwarder tests (CI) + live integration scripts
├── media/                     ← Screenshots
└── .github/workflows/lint.yml ← CI: bash -n, shellcheck, JSON, py_compile, link check, pytest
```

## What `setup.sh` puts on pfSense

| Path on pfSense | Purpose | Survives pfSense upgrade? |
|-----------------|---------|---------------------------|
| `/usr/local/bin/forward-suricata-eve.py` | Forwarder (shebang set to the detected Python) | Usually; re-run `setup.sh` if the Python version changed |
| `/usr/local/etc/rc.d/suricata_forwarder.sh` | rc.d service, started at boot by pfSense (`*.sh` only) | Usually |
| `/usr/local/bin/suricata-forwarder-watchdog.sh` + root crontab line (every minute) | Restarts the service if the process dies | Usually (not in config.xml backups) |

Details and the full persistence table:
[Upgrading pfSense](docs/pfsense/PFSENSE_UPGRADE_GUIDE.md).

## Archive policy

Superseded material is deleted from the working tree and preserved in git history. See
[docs/ARCHIVE.md](docs/ARCHIVE.md) for the last commit containing the old
`docs/archive/`, `scripts/archive/`, `dashboards/archive/` and `plugins/Old/` trees.
