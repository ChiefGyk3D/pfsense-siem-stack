# pfSense SIEM Stack - Management Console

> **Complete command-line interface** for managing your pfSense monitoring infrastructure

## Overview

The `pfsense-siem` management console provides a unified interface for installing, configuring, and managing your entire pfSense SIEM stack. No need to remember multiple scripts or commands - everything is accessible from one interactive menu.

## Quick Start

```bash
# Make executable
chmod +x pfsense-siem

# Run the management console
./pfsense-siem
```

---

## Features

### 🚀 Installation & Setup
- **One-command SIEM installation** - OpenSearch, Logstash, Grafana
- **Automated pfSense deployment** - Forwarder and watchdog setup
- **OpenSearch configuration** - Index templates and settings
- **Dashboard import guidance** - All three dashboards with instructions

### 🔧 System Management
- **Health checks** - Comprehensive status of all components
- **Service restart** - Graceful restart of SIEM services
- **Log viewing** - Real-time logs from any component
- **Retention management** - Adjust data retention policies

### 📡 pfSense Operations
- **Forwarder status** - Check if forwarder is running
- **Forwarder restart** - Stop and start forwarder
- **Forwarder logs** - Real-time forwarder activity
- **Connectivity testing** - Verify pfSense connection

### 🛠️ Advanced Features
- **End-to-end verification** - Test complete data flow
- **Custom SID management** - Configure Suricata signatures
- **Telegram alerts** - Setup notification integration
- **Backup/Restore** - Save and restore configurations

### 📚 Documentation Access
- **Quick Start Guide** - View setup documentation
- **Troubleshooting** - Access problem-solving guides
- **Configuration display** - Show current settings

---

## Menu Structure

```
═══ Main Menu ═══

Installation:
  1) Install SIEM Stack
  2) Deploy to pfSense
  3) Configure OpenSearch
  4) Import Dashboards

Management:
  5) Check System Status
  6) Restart Services
  7) View Logs
  8) Configure Retention Policy

pfSense Operations:
  9) Check Forwarder Status
 10) Restart Forwarder
 11) View Forwarder Logs
 12) Test pfSense Connectivity

Advanced:
 13) Verify Data Flow
 14) Configure Custom SIDs
 15) Setup Telegram Alerts
 16) Backup Configuration
 17) Restore Configuration

Documentation:
 18) View Quick Start Guide
 19) Open Troubleshooting Guide
 20) Show Configuration

  0) Exit
```

---

## Detailed Feature Guide

### Installation Functions

#### 1. Install SIEM Stack

**What it does:**
- Checks system requirements (RAM, disk, OS)
- Interactive configuration wizard
- Installs OpenSearch 2.x
- Installs Logstash 8.x
- Installs Grafana 12.x
- Configures firewall rules
- Sets up data retention

**Requirements:**
- Root/sudo access
- Ubuntu 22.04+ or Debian 11+
- 8GB+ RAM (16GB recommended)
- 100GB+ disk space

**Usage:**
```bash
# From menu: Option 1
# Or directly:
sudo ./install.sh
```

**Interactive prompts:**
1. Monitoring mode (Suricata / Telegraf / Both)
2. SIEM server IP (auto-detected)
3. pfSense IP address
4. Data retention (days)
5. Grafana admin password

**Output:**
- Generates `/tmp/deploy-to-pfsense.sh` for pfSense deployment
- Creates installation log at `/var/log/pfsense-monitoring-install.log`

#### 2. Deploy to pfSense

**What it does:**
- Tests SSH connectivity to pfSense
- Deploys Suricata forwarder Python script
- Installs watchdog for auto-restart
- Configures cron job for monitoring
- Starts forwarder and verifies

**Requirements:**
- `config.env` must be configured
- SSH access to pfSense (key or password)
- Python 3.11 on pfSense
- Suricata installed and running

**Usage:**
```bash
# From menu: Option 2
# Or directly:
./setup.sh
```

**Verification:**
- Shows forwarder PID
- Lists monitored interfaces (eve.json files)
- Checks initial event count in OpenSearch

#### 3. Configure OpenSearch

**What it does:**
- Creates index templates with geo_point mapping
- Enables auto-create for `suricata-*` indices
- Configures field mappings for proper geomap display
- Sets up cluster settings

**Requirements:**
- OpenSearch must be running
- Network access to OpenSearch (port 9200)

**Usage:**
```bash
# From menu: Option 3
# Or directly:
./scripts/install-opensearch-config.sh
```

**Important:**
This must be run **before** any Suricata data flows, otherwise you'll need to reindex.

#### 4. Import Dashboards

**What it does:**
- Shows available dashboards with descriptions
- Provides step-by-step import instructions
- Opens dashboard import documentation

**Dashboards:**
1. **pfsense_pfblockerng_system.json** (InfluxDB)
   - pfSense system metrics
   - Network performance
   - PfBlockerNG statistics

2. **Suricata IDS_IPS Dashboard.json** (OpenSearch)
   - WAN-side security
   - Attack visualization
   - Geographic mapping

3. **Suricata_Per_Interface.json** (OpenSearch)
   - Per-VLAN monitoring
   - Dynamic interface sections
   - Internal threat detection

**Manual steps:**
1. Open Grafana at `http://SIEM_IP:3000`
2. Login with admin credentials
3. Go to: Dashboards → Import
4. Upload JSON file
5. Select datasource
6. Click Import

---

### Management Functions

#### 5. Check System Status

**Comprehensive health check:**

**SIEM Server:**
- ✓ OpenSearch connectivity and cluster health
- ✓ Auto-create index setting verification
- ✓ Logstash UDP port listening
- ✓ Index list and document counts
- ✓ Latest event timestamp

**pfSense:**
- ✓ Forwarder process running
- ✓ Watchdog cron job installed
- ✓ Monitored interfaces list
- ✓ Recent forwarder activity

**Data Flow:**
- ✓ Event count by day
- ✓ Events per second rate
- ✓ Data freshness (last event age)

**Usage:**
```bash
# From menu: Option 5
# Or directly:
./scripts/status.sh
```

**Exit codes:**
- `0` - All checks passed
- `>0` - Number of failed checks

#### 6. Restart Services

**Restarts SIEM services in proper order:**

1. **OpenSearch** (wait for cluster to stabilize)
2. **Logstash** (wait for pipeline to load)
3. **Grafana** (wait for web UI)

**Requirements:**
- Root/sudo access

**Usage:**
```bash
# From menu: Option 6
# Or directly:
sudo ./scripts/restart-services.sh
```

**Verification:**
- Checks service status after each restart
- Reports failures with log viewing commands

#### 7. View Logs

**Real-time log viewing:**

**Options:**
1. **OpenSearch** - `journalctl -u opensearch -f`
2. **Logstash** - `journalctl -u logstash -f`
3. **Grafana** - `journalctl -u grafana-server -f`
4. **Forwarder** - SSH to pfSense, tail system log
5. **All SIEM** - Combined view of all services

**Usage:**
- Select log source from menu
- Press `Ctrl+C` to exit log view
- Automatically follows new entries

**Troubleshooting tips:**
- Look for `ERROR` or `WARN` messages
- Check timestamps for recent issues
- Watch for connection failures

#### 8. Configure Retention Policy

**Adjust data retention:**

**What it does:**
- Configures OpenSearch Index Lifecycle Management (ILM)
- Sets delete_after period for old indices
- Updates `config.env` with new retention

**Default:** 30 days

**Recommended:**
- **Home lab:** 30-90 days
- **Small business:** 90-180 days
- **Enterprise:** 365+ days (regulatory compliance)

**Disk calculation:**
```
Disk = Events/Day × Event_Size × Retention_Days

Example:
  10,000 events/day × 2KB × 90 days = 1.7GB
  100,000 events/day × 2KB × 90 days = 17GB
  1,000,000 events/day × 2KB × 90 days = 170GB
```

**Usage:**
```bash
# From menu: Option 8
# Or directly:
./scripts/configure-retention-policy.sh 90
```

---

### pfSense Operations

#### 9. Check Forwarder Status

**What it checks:**
- Forwarder process running (PID)
- Monitored interfaces (lsof eve.json files)
- Recent log activity (last 10 entries)
- Watchdog cron job status

**Output example:**
```
✓ Forwarder is running
  PID: 12345

Monitored interfaces:
  • /var/log/suricata/suricata_ix055721/eve.json
  • /var/log/suricata/suricata_lagg1.1020460/eve.json
  • /var/log/suricata/suricata_lagg1.2249359/eve.json

Recent activity:
  Nov 27 10:15:23 forwarder: Sent 150 events to 192.168.210.10:5140
```

#### 10. Restart Forwarder

**When to use:**
- Forwarder not running
- Forwarder stuck or high CPU
- After forwarder script update
- After Suricata restart

**Process:**
1. Kills existing forwarder process
2. Waits 2 seconds
3. Starts new forwarder instance
4. Verifies startup (PID check)

**Usage:**
```bash
# From menu: Option 10
```

**Troubleshooting:**
If forwarder fails to start, check:
1. Python 3.11 available: `which python3.11`
2. Script exists: `ls -la /usr/local/bin/forward-suricata-eve.py`
3. Script executable: `chmod +x /usr/local/bin/forward-suricata-eve.py`
4. Logs: `tail -50 /var/log/system.log | grep suricata`

#### 11. View Forwarder Logs

**Real-time forwarder activity:**

**Shows:**
- Event sending confirmations
- Connection errors to SIEM
- Interface monitoring status
- GeoIP enrichment results
- Rotation handling events

**Usage:**
```bash
# From menu: Option 11
```

**Press `Ctrl+C` to exit**

**Log examples:**
```
suricata-forwarder: Started monitoring 15 interfaces
suricata-forwarder: Sent 150 events to 192.168.210.10:5140
suricata-forwarder: GeoIP: 203.0.113.1 -> US, New York
suricata-forwarder-watchdog: Forwarder running (PID: 12345, CPU: 2.5%)
```

#### 12. Test pfSense Connectivity

**Comprehensive connectivity test:**

**Tests:**
1. **Ping** - Basic network reachability
2. **SSH** - SSH access with key or password
3. **Suricata** - Package installed check
4. **Python 3.11** - Python interpreter available

**Usage:**
```bash
# From menu: Option 12
```

**Output:**
```
Testing connection to 192.168.1.1...

  Ping test... ✓
  SSH test... ✓
  Suricata installed... ✓
  Python 3.11 available... ✓
```

**Troubleshooting:**
- **Ping fails:** Firewall rule or routing issue
- **SSH fails:** Enable SSH in pfSense: System → Advanced → Secure Shell
- **Suricata not installed:** Install from Package Manager
- **Python not found:** pfSense 2.7+ includes Python 3.11

---

### Advanced Functions

#### 13. Verify Data Flow

**End-to-end data flow test:**

**Checks:**
1. OpenSearch connectivity
2. Event count in indices
3. Latest event timestamp
4. Forwarder running status

**Usage:**
```bash
# From menu: Option 13
```

**Includes test alert generation:**
```
Run this from any machine behind pfSense:
  curl http://testmyids.com
```

This generates a test IDS alert that should appear in Grafana within 30 seconds.

**Output example:**
```
1. OpenSearch connectivity... ✓
2. Checking for events... ✓ 123,456 events
3. Latest event age... ✓ 2024-11-27T10:15:30Z
4. Forwarder status... ✓ Running (PID: 12345)
```

#### 14. Configure Custom SIDs

**Manage Suricata signature IDs:**

**Features:**
- Check enabled/disabled rules
- Verify custom disablesid.conf
- Compare with repository defaults
- Apply changes to pfSense

**Usage:**
```bash
# From menu: Option 14
# Or directly:
./scripts/check_custom_sids.sh
```

**See also:**
- [SID Management Documentation](../config/sid/README.md)
- [Suricata Optimization Guide](../docs/SURICATA_OPTIMIZATION_GUIDE.md)

#### 15. Setup Telegram Alerts

**Configure Telegram notifications:**

**Features:**
- Test Telegram bot connectivity
- Configure alert thresholds
- Setup alert messages
- Test notification delivery

**Requirements:**
- Telegram bot token (from @BotFather)
- Chat ID (from bot or IDBot)

**Usage:**
```bash
# From menu: Option 15
# Or directly:
./scripts/check-telegram-alerts.sh
```

#### 16. Backup Configuration

**Backup all configurations:**

**Includes:**
- `config.env` settings
- Dashboards (all JSON files)
- Config files (logstash, templates)
- Custom scripts

**Excludes:**
- OpenSearch data
- Log files
- Temporary files

**Backup location:**
```
~/pfsense-siem-backups/backup_YYYYMMDD_HHMMSS.tar.gz
```

**Usage:**
```bash
# From menu: Option 16
```

**Manual backup:**
```bash
tar -czf ~/backup.tar.gz config.env dashboards/ config/
```

#### 17. Restore Configuration

**Restore from backup:**

**What it does:**
- Lists available backups
- Extracts selected backup
- Overwrites current configuration

**⚠️ Warning:** This will overwrite:
- `config.env`
- All dashboards
- Configuration files

**Usage:**
```bash
# From menu: Option 17
```

**Recommendation:**
Create a backup before restoring in case you need to rollback.

---

### Documentation Functions

#### 18. View Quick Start Guide

Opens `QUICK_START.md` for reference.

**Includes:**
- 15-minute deployment walkthrough
- System requirements
- Installation steps
- Verification procedures

#### 19. Open Troubleshooting Guide

Opens `docs/TROUBLESHOOTING.md` for problem-solving.

**Covers:**
- Common issues and fixes
- Dashboard "No Data" problems
- Forwarder issues
- OpenSearch configuration
- Log rotation problems

#### 20. Show Configuration

Displays current `config.env` settings:

**Shows:**
- SIEM server details (IP, ports)
- pfSense connection info
- Index configuration
- Retention settings
- Debug mode status

---

## Configuration File

### config.env

**Required variables:**
```bash
# SIEM Server
SIEM_HOST=192.168.210.10           # Your SIEM server IP

# pfSense
PFSENSE_HOST=192.168.1.1           # Your pfSense IP
PFSENSE_USER=root                  # SSH user (default: root)

# Optional settings
OPENSEARCH_PORT=9200               # OpenSearch HTTP port
LOGSTASH_UDP_PORT=5140             # Logstash Suricata input
GRAFANA_PORT=3000                  # Grafana web UI
INDEX_PREFIX=suricata              # Index name prefix
RETENTION_DAYS=30                  # Data retention
DEBUG_ENABLED=False                # Debug logging
```

**Creating config.env:**

Option 1: Copy from example
```bash
cp config.env.example config.env
nano config.env
```

Option 2: Let management console create it
```bash
./pfsense-siem
# Select any option, it will prompt to create config.env
```

---

## Common Workflows

### First-Time Setup

```bash
# 1. Run management console
./pfsense-siem

# 2. Install SIEM stack (Option 1)
#    - Answer configuration questions
#    - Wait for installation (15-20 minutes)

# 3. Configure OpenSearch (Option 3)
#    - Sets up index templates
#    - Enables auto-create

# 4. Deploy to pfSense (Option 2)
#    - Deploys forwarder
#    - Starts monitoring

# 5. Import dashboards (Option 4)
#    - Follow Grafana import instructions

# 6. Verify (Option 13)
#    - Check data flow end-to-end
```

### Daily Operations

```bash
# Check system health
./pfsense-siem → Option 5

# View forwarder status
./pfsense-siem → Option 9

# Check forwarder logs
./pfsense-siem → Option 11
```

### Troubleshooting

```bash
# No data in Grafana?
./pfsense-siem → Option 13  # Verify data flow
./pfsense-siem → Option 9   # Check forwarder
./pfsense-siem → Option 7   # View Logstash logs

# Forwarder not running?
./pfsense-siem → Option 10  # Restart forwarder
./pfsense-siem → Option 11  # Check logs

# Services down?
./pfsense-siem → Option 6   # Restart services
./pfsense-siem → Option 5   # Check status
```

### Maintenance

```bash
# Weekly
./pfsense-siem → Option 5   # Health check

# Monthly
./pfsense-siem → Option 16  # Backup config

# As needed
./pfsense-siem → Option 8   # Adjust retention
./pfsense-siem → Option 14  # Update SIDs
```

---

## Exit Codes

The management console and underlying scripts use standard exit codes:

- **0** - Success, all checks passed
- **1** - General error
- **>1** - Number of failed checks (status.sh)

---

## Logging

### Installation Log
```
/var/log/pfsense-monitoring-install.log
```
Complete installation transcript for troubleshooting.

### Service Logs
```bash
# OpenSearch
sudo journalctl -u opensearch -n 100

# Logstash
sudo journalctl -u logstash -n 100

# Grafana
sudo journalctl -u grafana-server -n 100

# Forwarder (pfSense)
ssh root@pfsense 'tail -100 /var/log/system.log | grep suricata'
```

---

## Tips & Best Practices

### Performance

1. **Use the status check regularly**
   - Run `Option 5` daily or weekly
   - Watch for event count drops
   - Monitor latest event age

2. **Monitor disk space**
   ```bash
   df -h /
   curl -s http://localhost:9200/_cat/indices/suricata-*?v
   ```

3. **Adjust retention as needed**
   - Start with 30 days
   - Increase if you have disk space
   - Decrease if disk fills up

### Security

1. **Change Grafana password**
   - Don't use default `admin/admin`
   - Set during installation or after

2. **Use SSH keys for pfSense**
   - More secure than password
   - Required for automated scripts

3. **Restrict OpenSearch access**
   - Bind to localhost if SIEM is single-server
   - Use firewall rules for multi-server

### Reliability

1. **Backup regularly**
   - Use `Option 16` monthly
   - Store backups off-server

2. **Test forwarder watchdog**
   - Kill forwarder: `pkill -f forward-suricata`
   - Wait 1 minute
   - Check if it restarted automatically

3. **Monitor forwarder logs**
   - Check for connection errors
   - Watch for rotation issues
   - Verify all interfaces monitored

---

## Troubleshooting the Management Console

### Menu doesn't display properly

**Problem:** Colors/characters not rendering

**Solution:**
```bash
# Check TERM environment
echo $TERM

# Should be: xterm-256color or similar
# If not, set it:
export TERM=xterm-256color
```

### "Command not found"

**Problem:** Script not executable

**Solution:**
```bash
chmod +x pfsense-siem
```

### Config file issues

**Problem:** Management console can't find config.env

**Solution:**
```bash
# Create from example
cp config.env.example config.env

# Edit with your settings
nano config.env
```

### Permission denied errors

**Problem:** Some options require root/sudo

**Solution:**
```bash
# Run with sudo
sudo ./pfsense-siem

# Or specific option
sudo ./install.sh
sudo ./scripts/restart-services.sh
```

---

## Support & Documentation

**Complete documentation:**
- [Main README](../README.md)
- [Quick Start](../QUICK_START.md)
- [Troubleshooting](../docs/TROUBLESHOOTING.md)
- [Documentation Index](../docs/DOCUMENTATION_INDEX.md)

**Get help:**
- GitHub Issues: https://github.com/ChiefGyk3D/pfsense_grafana/issues
- GitHub Discussions: https://github.com/ChiefGyk3D/pfsense_grafana/discussions

**Community:**
- Share your deployment experiences
- Report bugs and request features
- Contribute improvements

---

**Built with ❤️ for the pfSense and open-source security community**
