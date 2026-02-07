# Quick Start Guide

Get your pfSense monitoring stack running in **under 15 minutes**.

## What You'll Get

- **OpenSearch** - Log storage and search
- **Logstash** - Log processing pipeline
- **Grafana** - Beautiful dashboards with three pre-built views:
  - **pfSense System Dashboard** - Hardware, network, pfBlockerNG stats
  - **Suricata WAN Dashboard** - External threat detection
  - **Suricata Per-Interface Dashboard** - Internal/LAN monitoring
- **Automated deployment** - One command for SIEM, one for pfSense
- **Your choice**: Suricata IDS/IPS logs, Telegraf metrics, or both

---

## Prerequisites

### SIEM Server (Where logs are stored and viewed)
- Ubuntu 22.04+ LTS
- 8GB+ RAM (16GB recommended for production)
- 100GB+ disk space
- Root/sudo access

### pfSense Firewall
- pfSense 2.8.1+
- Suricata installed (if monitoring IDS/IPS)
- SSH enabled: System → Advanced → Secure Shell
- SSH key configured OR password ready

---

## Installation Methods

### Method 1: Management Console (Recommended)

**Easiest option** - Interactive menu for everything:

```bash
# Clone repository
git clone https://github.com/ChiefGyk3D/pfsense_grafana.git
cd pfsense_grafana

# Run management console
./pfsense-siem

# Use menu options:
#  1) Install SIEM Stack
#  2) Deploy to pfSense
#  3) Configure OpenSearch
#  4) Import Dashboards
#  5) Check System Status
```

**Features:**
- Complete interactive interface
- All operations in one place
- Built-in health checks
- Service management
- Log viewing
- Troubleshooting tools

**[Full documentation →](docs/MANAGEMENT_CONSOLE.md)**

### Method 2: Manual Installation (3 Steps)

#### Step 1: Install SIEM Stack (5 minutes)

On your SIEM server:

```bash
# Clone repository
git clone https://github.com/ChiefGyk3D/pfsense_grafana.git
cd pfsense_grafana

# Run interactive installer
sudo bash install.sh
```

**The installer will ask:**
1. What to monitor? (Suricata / Telegraf / Both)
2. SIEM server IP? (auto-detected)
3. pfSense IP address?
4. Data retention days? (default: 90)
5. Grafana admin password? (default: admin)

**Then it automatically:**
- ✅ Installs OpenSearch, Logstash, Grafana
- ✅ Configures everything based on your answers
- ✅ Sets up retention policy
- ✅ Opens firewall ports
- ✅ Generates deployment script for pfSense

**Wait for:** "Installation Complete!" message (5-10 minutes)

---

### Step 2: Deploy to pfSense (2 minutes)

The installer created `/tmp/deploy-to-pfsense.sh` for you.

**On your workstation** (not the SIEM server):

```bash
# Copy the generated script
scp user@siem-server:/tmp/deploy-to-pfsense.sh .

# Make it executable
chmod +x deploy-to-pfsense.sh

# Run it
bash deploy-to-pfsense.sh
```

**This automatically:**
- ✅ Tests connectivity to pfSense
- ✅ Deploys Suricata forwarder (if selected)
- ✅ Starts monitoring
- ✅ Sets up watchdog

**Alternatively, use the repository script directly:**

```bash
cd pfsense_grafana
bash deploy-pfsense-forwarder.sh PFSENSE_IP SIEM_IP
```

---

### Step 3: Verify & Access (2 minutes)

**Check system health:**
```bash
cd pfsense_grafana/scripts
bash check-system-health.sh
```

Expected output:
```
✓ OpenSearch is running
✓ Port 9200/tcp is open
✓ Cluster health: green
✓ Events flowing: 1,234
✓ Latest event: 15 seconds ago
```

**Check pfSense forwarder:**
```bash
bash check-forwarder-status.sh PFSENSE_IP
```

**Access Grafana:**
1. Open browser: `http://SIEM_IP:3000`
2. Login: `admin` / (your password)
3. Import dashboards (import all three):
   - Click ➕ → Import
   - **Dashboard 1**: Upload `dashboards/pfsense_pfblockerng_system.json`
     - Select InfluxDB datasource (for system metrics panels)
     - Select OpenSearch-pfBlockerNG datasource (for pfBlockerNG panels)
     - Click Import
   - **Dashboard 2**: Upload `dashboards/Suricata IDS_IPS Dashboard.json`
     - Select OpenSearch datasource
     - Click Import
   - **Dashboard 3**: Upload `dashboards/Suricata_Per_Interface.json`
     - Select OpenSearch datasource
     - Click Import

**You should see:**
- **pfSense Dashboard**: System metrics, network stats, pfBlockerNG blocks
- **Suricata WAN Dashboard**: Security events, alerts, attack sources
- **Suricata Per-Interface Dashboard**: Per-VLAN/LAN monitoring with dynamic sections

---

## Monitoring Modes

### Option 1: Suricata Only (Security Monitoring)
- ✅ IDS/IPS alerts
- ✅ DNS queries
- ✅ TLS/HTTPS traffic
- ✅ HTTP activity
- ✅ File transfers
- ✅ Network flows

**Use case:** Security teams, threat hunting, compliance

### Option 2: Telegraf Only (Performance Monitoring)
- ✅ Interface throughput
- ✅ CPU/Memory usage
- ✅ Gateway status
- ✅ DHCP leases
- ✅ Temperature sensors
- ✅ System metrics

**Use case:** Network operations, capacity planning, SLA monitoring

### Option 3: Both (Complete Monitoring)
- ✅ All security events
- ✅ All performance metrics
- ✅ Correlated views
- ✅ Separate indices

**Use case:** Large deployments, SOC + NOC teams

---

## Quick Troubleshooting

### No data in Grafana?

```bash
# Check if events are reaching OpenSearch
curl -s http://SIEM_IP:9200/suricata-*/_count

# Check Logstash logs
ssh SIEM_IP "sudo journalctl -u logstash -n 50"

# Check forwarder on pfSense
ssh root@PFSENSE_IP "ps aux | grep forward-suricata"
ssh root@PFSENSE_IP "tail -20 /var/log/system.log | grep suricata-forwarder"
```

### Services not running?

```bash
cd pfsense_grafana/scripts
sudo bash restart-services.sh
```

### Forwarder not working?

```bash
# Re-deploy forwarder
bash deploy-pfsense-forwarder.sh PFSENSE_IP SIEM_IP

# Check pfSense logs
ssh root@PFSENSE_IP "tail -f /var/log/system.log | grep suricata"
```

### Firewall blocking?

```bash
# On SIEM server
sudo ufw status

# Should show:
# 9200/tcp   ALLOW  (OpenSearch)
# 5140/udp   ALLOW  (Logstash Suricata)
# 3000/tcp   ALLOW  (Grafana)
```

---

## What Gets Installed?

### On SIEM Server
```
/opt/opensearch/          - OpenSearch installation
/etc/logstash/            - Logstash configs
/etc/grafana/             - Grafana configs
/var/lib/opensearch/      - Data storage
```

### On pfSense
```
/usr/local/bin/forward-suricata-eve-python.py  - Forwarder script
/usr/local/bin/forward-suricata-eve.sh         - Wrapper
/usr/local/bin/suricata-forwarder-watchdog.sh  - Auto-restart
```

### Ports Used
- **9200/tcp** - OpenSearch API
- **5140/udp** - Logstash Suricata input
- **8086/tcp** - Logstash Telegraf input (if using Telegraf)
- **3000/tcp** - Grafana Web UI

---

## Next Steps

### 1. Customize Dashboard
- Add/remove panels
- Change time ranges
- Set up alerts
- Create variables for filtering

See: [docs/INSTALL_DASHBOARD.md](docs/INSTALL_DASHBOARD.md)

### 2. Multi-Interface Setup
- Automatically monitors all Suricata interfaces
- Filter by `suricata.interface` field
- Create per-interface panels

See: [docs/MULTI_INTERFACE_RETENTION.md](docs/MULTI_INTERFACE_RETENTION.md)

### 3. Adjust Retention
```bash
# Change retention to 30 days
cd pfsense_grafana/scripts
bash configure-retention-policy.sh 30
```

### 4. Set Up Monitoring
```bash
# Add to cron for daily health checks
0 8 * * * /path/to/scripts/check-system-health.sh | mail -s "SIEM Health" admin@example.com
```

### 5. Backup Configuration
```bash
# Export dashboard
bash scripts/export-dashboard.sh suricata-complete backup.json

# Backup OpenSearch config
sudo tar -czf opensearch-backup.tar.gz /opt/opensearch/config/
```

---

## Performance Tuning

### High Event Rate (1000+ events/sec)
```bash
# Increase OpenSearch heap
sudo vim /opt/opensearch/config/jvm.options
# Set: -Xms8g -Xmx8g

# Increase Logstash workers
sudo vim /etc/logstash/logstash.yml
# Set: pipeline.workers: 8
```

### Low Memory Environment
```bash
# Reduce OpenSearch heap
sudo vim /opt/opensearch/config/jvm.options
# Set: -Xms2g -Xmx2g

# Reduce retention
bash scripts/configure-retention-policy.sh 14
```

---

## Comparison: Manual vs Automated

### Before (Manual Installation)
1. ⏱️ Read 300+ line installation guide
2. ⏱️ Copy/paste 50+ commands
3. ⏱️ Edit 5+ config files manually
4. ⏱️ Troubleshoot typos and mistakes
5. ⏱️ Figure out which ports to open
6. ⏱️ Manually set retention policy
7. ⏱️ Deploy forwarder step-by-step
8. ⏱️ **Total time: 1-2 hours**

### Now (Automated Installation)
1. ✅ Run `sudo bash install.sh`
2. ✅ Answer 5 questions
3. ✅ Run `bash deploy-to-pfsense.sh`
4. ✅ **Total time: 10-15 minutes**

---

## Architecture Diagram

```
┌─────────────────┐              ┌─────────────────┐              ┌─────────────────┐
│   pfSense       │              │  SIEM Server    │              │  Your Browser   │
│                 │              │                 │              │                 │
│  ┌───────────┐  │              │  ┌───────────┐  │              │                 │
│  │ Suricata  │  │   UDP 5140   │  │ Logstash  │  │              │                 │
│  │ EVE JSON  ├──┼─────────────>│  │ Pipeline  │  │              │                 │
│  └─────┬─────┘  │              │  └─────┬─────┘  │              │                 │
│        │        │              │        │        │              │                 │
│  ┌─────▼─────┐  │              │  ┌─────▼─────┐  │   HTTP 3000  │  ┌───────────┐  │
│  │  Python   │  │              │  │OpenSearch │  │◄─────────────┼──┤  Grafana  │  │
│  │ Forwarder │  │              │  │  Indices  │  │              │  │ Dashboard │  │
│  └───────────┘  │              │  └───────────┘  │              │  └───────────┘  │
│        ▲        │              │        ▲        │              │                 │
│  ┌─────┴─────┐  │              │  ┌─────┴─────┐  │              │                 │
│  │ Watchdog  │  │              │  │ Retention │  │              │                 │
│  │Cron(1 min)│  │              │  │  Policy   │  │              │                 │
│  └───────────┘  │              │  │  (90 day) │  │              │                 │
└─────────────────┘              │  └───────────┘  │              └─────────────────┘
                                 └─────────────────┘
```

---

## Support & Documentation

- 📖 **Full Docs**: [README.md](README.md)
- 🔧 **Troubleshooting**: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
- 🎯 **Configuration**: [docs/CONFIGURATION.md](docs/CONFIGURATION.md)
- 🔄 **Multi-Interface**: [docs/MULTI_INTERFACE_RETENTION.md](docs/MULTI_INTERFACE_RETENTION.md)
- 💬 **Issues**: [GitHub Issues](https://github.com/ChiefGyk3D/pfsense_grafana/issues)
- 💡 **Discussions**: [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense_grafana/discussions)

---

## Common Commands Reference

```bash
# System Health
cd pfsense_grafana/scripts
bash check-system-health.sh

# Verify Data
bash verify-suricata-data.sh PFSENSE_IP

# Restart Services
sudo bash restart-services.sh

# Check Forwarder
bash check-forwarder-status.sh PFSENSE_IP

# Export Dashboard
bash export-dashboard.sh suricata-complete backup.json

# Change Retention
bash configure-retention-policy.sh 30

# View Logs
ssh SIEM_IP "sudo journalctl -u opensearch -f"
ssh SIEM_IP "sudo journalctl -u logstash -f"
ssh SIEM_IP "sudo journalctl -u grafana-server -f"
ssh PFSENSE_IP "tail -f /var/log/system.log | grep suricata"
```

---

**Ready? Let's get started!**

```bash
sudo bash install.sh
```
