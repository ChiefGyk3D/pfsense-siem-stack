# Quick Start

Get Suricata dashboards running in Grafana in under 10 minutes.

## What You Need

**Already running:**
- pfSense with Suricata enabled on at least one interface
- A Linux server with OpenSearch, Logstash, and Grafana installed
- The `grafana-opensearch-datasource` plugin in Grafana

**Not yet installed?** See [SIEM Stack Installation Guide](docs/INSTALL_SIEM_STACK.md).

## Steps

### 1. Clone and configure

```bash
git clone https://github.com/ChiefGyk3D/pfsense-siem-stack.git
cd pfsense-siem-stack
cp config.env.example config.env
```

Edit `config.env` with your IPs:
```bash
SIEM_HOST=192.168.1.10    # Your SIEM server (OpenSearch/Logstash/Grafana)
PFSENSE_HOST=192.168.1.1  # Your pfSense firewall
PFSENSE_USER=admin        # SSH user for pfSense
```

### 2. Set up SSH access to pfSense

```bash
ssh-copy-id admin@192.168.1.1
```

Make sure you can SSH without a password prompt before continuing.

### 3. Run the installer

```bash
./setup.sh
```

The installer will:
1. **Check prerequisites** — OpenSearch, Grafana reachable, SSH works, Suricata has EVE logs
2. **Configure OpenSearch** — apply index template with proper field types (keyword, ip, geo_point)
3. **Deploy Logstash config** — flat JSON parsing pipeline (via SSH to SIEM server)
4. **Deploy forwarder** — copy to pfSense, install watchdog cron, start it
5. **Import dashboards** — both IDS/IPS and Per-Interface dashboards via Grafana API
6. **Verify data flow** — confirm events are appearing in OpenSearch

### 4. Open Grafana

Navigate to `http://<your-siem>:3000/d/suricata_ids_ips` and you should see data.

## After Installation

### Check status
```bash
./scripts/status.sh
```

### Diagnose problems
```bash
./scripts/diagnose-and-repair.sh
```

### View forwarder on pfSense
```bash
ssh admin@<pfsense> 'ps aux | grep forward-suricata'
ssh admin@<pfsense> 'tail -20 /var/log/messages | grep suricata'
```

**Access Grafana:**
1. Open browser: `http://SIEM_IP:3000`
2. Login: `admin` / (your password)
3. Import dashboards (import all three):
   - Click **+** → Import
   - **Dashboard 1**: Upload `dashboards/pfsense_pfblockerng_system.json`
     - Select InfluxDB datasource (for system metrics panels)
     - Select OpenSearch-pfBlockerNG datasource (for pfBlockerNG panels)
   - **Dashboard 2**: Upload `dashboards/Suricata_IDS_IPS.json`
     - Select OpenSearch datasource
   - **Dashboard 3**: Upload `dashboards/Suricata_Per_Interface.json`
     - Select OpenSearch datasource

### Set up index retention
```bash
./scripts/configure-retention-policy.sh
```

## Manual Installation

If you prefer to install each component separately instead of using `setup.sh`:

1. **OpenSearch config:** `./scripts/install-opensearch-config.sh`
2. **Logstash config:** Copy `config/logstash-suricata.conf` to `/etc/logstash/conf.d/suricata.conf`
3. **Forwarder:** Copy `scripts/forward-suricata-eve.py` to pfSense at `/usr/local/bin/`
4. **Dashboards:** Import `dashboards/Suricata_IDS_IPS.json` in Grafana UI → Dashboards → Import

See the detailed docs in `docs/` for each step.
