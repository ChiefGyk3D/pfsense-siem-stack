# Quick Start

Get Suricata dashboards running in Grafana. Budget 30–60 minutes for a from-scratch
deployment (10 minutes if your SIEM server is already running).

## Prerequisites

**Hardware/hosts you need** (see [Hardware Requirements](docs/install/HARDWARE_REQUIREMENTS.md)):

- **pfSense 2.7.2+/2.8.x** with Suricata installed and enabled on at least one
  interface, and SSH enabled (System → Advanced → Secure Shell)
- **A Linux server** (Ubuntu 24.04 LTS recommended) for the SIEM stack — 8 GB RAM
  minimum, 16 GB+ recommended, 100 GB+ disk for logs
- **A workstation** (can be the SIEM server itself) with `bash`, `ssh`, `curl`, `jq`,
  and `python3` to run the scripts from

**Honest expectations:**

- SSH key-based auth to pfSense is required (`ssh-copy-id`) — the scripts never prompt
  for passwords
- GeoIP enrichment (the attack map) needs a MaxMind GeoLite2 database on pfSense —
  optional, see [GeoIP Setup](docs/install/GEOIP_SETUP.md)
- pfBlockerNG panels need Telegraf configured separately — see
  [Telegraf pfBlockerNG Pipeline](docs/pfsense/TELEGRAF_PFBLOCKER_SETUP.md)

## Steps

### 1. Clone, configure, and run the preflight check

```bash
git clone https://github.com/ChiefGyk3D/pfsense-siem-stack.git
cd pfsense-siem-stack
cp config.env.example config.env
nano config.env
```

Set at least:

```bash
SIEM_HOST=192.168.1.10    # Your SIEM server (OpenSearch/Logstash/Grafana)
PFSENSE_HOST=192.168.1.1  # Your pfSense firewall
PFSENSE_USER=admin        # SSH user for pfSense (default admin account)
```

Set up SSH keys, then verify everything with the preflight check:

```bash
ssh-copy-id admin@192.168.1.1   # pfSense
./scripts/preflight.sh
```

Preflight validates config.env, SSH access to pfSense and the SIEM server, Python on
pfSense, OpenSearch reachability, and GeoIP presence — fix any ✗ before continuing.
(`setup.sh` also runs it automatically; skip with `--skip-preflight` if you must.)

### 2. Install the SIEM stack (skip if already running)

On the SIEM server:

```bash
sudo ./install.sh
```

Installs OpenSearch 2.x, Logstash 8.x, and Grafana with the
`grafana-opensearch-datasource` plugin. Details:
[SIEM Stack Installation](docs/install/INSTALL_SIEM_STACK.md).

### 3. Deploy everything with setup.sh

```bash
./setup.sh
```

The installer will:
1. **Run preflight + prerequisite checks** — OpenSearch, Grafana, SSH, Suricata EVE logs
2. **Configure OpenSearch** — index templates (keyword, ip, geo_point) and auto-create
3. **Deploy Logstash config** — flat JSON parsing pipeline (via SSH to SIEM server)
4. **Deploy forwarder to pfSense** — plus rc.d service and watchdog cron
5. **Import dashboards** — IDS/IPS and Per-Interface dashboards via the Grafana API
6. **Verify data flow** — confirm events are appearing in OpenSearch

### 4. Open Grafana and check the dashboards

Navigate to `http://<your-siem>:3000/d/suricata_ids_ips` — you should see events within
a minute or two.

If `setup.sh` could not reach Grafana, import manually (Grafana → Dashboards → Import):

- `dashboards/Suricata_IDS_IPS.json` — OpenSearch datasource
- `dashboards/Suricata_Per_Interface.json` — OpenSearch datasource
- `dashboards/pfsense_pfblockerng_system.json` — InfluxDB + OpenSearch-pfBlockerNG
  datasources (needs Telegraf)

Details: [Dashboard Installation](docs/install/INSTALL_DASHBOARD.md).

## After Installation

```bash
./scripts/status.sh                        # Check all component status
./scripts/diagnose-and-repair.sh           # Auto-diagnose problems
./scripts/configure-retention-policy.sh    # Set index retention (default 30 days)
./pfsense-siem                             # Interactive management console
```

Verify the forwarder on pfSense:

```bash
ssh admin@<pfsense> 'service suricata_forwarder status'
```

## Where to next

- **Full documentation hub**: [docs/DOCUMENTATION_INDEX.md](docs/DOCUMENTATION_INDEX.md)
- **Tune Suricata rules** (do this — the defaults are noisy):
  [Suricata Optimization Guide](docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md)
- **Something broken?** [Troubleshooting Guide](docs/troubleshooting/TROUBLESHOOTING.md)
- **Step-by-step validation**: [New User Checklist](docs/install/NEW_USER_CHECKLIST.md)

## Manual Installation

If you prefer to install each component separately instead of using `setup.sh`:

1. **OpenSearch config:** `./scripts/install-opensearch-config.sh`
2. **Logstash config:** Copy `config/logstash-suricata.conf` to `/etc/logstash/conf.d/suricata.conf`
3. **Forwarder:** Copy `scripts/forward-suricata-eve.py` to pfSense at `/usr/local/bin/`
   — see [pfSense Forwarder Installation](docs/install/INSTALL_PFSENSE_FORWARDER.md)
4. **Dashboards:** Import `dashboards/Suricata_IDS_IPS.json` in Grafana UI → Dashboards → Import
