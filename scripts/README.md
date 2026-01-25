# Scripts Directory

Automation scripts, forwarders, watchdogs, and helpers for pfSense SIEM monitoring. **Most users only need `../setup.sh`** for initial setup.

---

## 🚀 Main Scripts

### ../setup.sh (Project Root)
**ONE-COMMAND automated deployment** - Run from project root after configuring `config.env`

```bash
./setup.sh
```

**What it does:**
- ✅ Loads configuration from `config.env`
- ✅ Configures OpenSearch index templates and auto-create settings
- ✅ Deploys forwarder to pfSense with your SIEM IP
- ✅ Installs watchdog for automatic restart on failure
- ✅ Verifies data flow from pfSense → Logstash → OpenSearch

**Required before running:**
```bash
cp config.env.example config.env
nano config.env  # Set SIEM_HOST and PFSENSE_HOST
```

### status.sh
**Health check and diagnostics** - Run when troubleshooting

```bash
./scripts/status.sh
```

**Checks:**
- OpenSearch cluster health
- Logstash pipeline status
- Forwarder process on pfSense
- Data flow (recent events in OpenSearch)
- Suricata instances running

**Output:** Color-coded status report with actionable recommendations

---

## 🔄 Forwarder Scripts

### forward-suricata-eve-python.py
**Production Suricata EVE forwarder with GeoIP enrichment** (deployed to pfSense by `setup.sh`)

**Features:**
- Tails ALL Suricata `eve.json` files (auto-discovers all interfaces)
- **Multi-threaded**: One thread per interface for reliable monitoring
- **GeoIP enrichment**: Adds country, city, coordinates using `maxminddb` (pre-installed on pfSense 2.8.1+)
- **No pip install required**: Uses only standard pfSense libraries
- **Interface normalization**: Strips Netmap markers (`^`, `*`, etc.)
- **UDP transport**: Sends events to Logstash UDP 5140
- **Debug logging**: `/var/log/suricata_forwarder_debug.log` (when enabled)

**Deployment:**
```bash
# Automated (recommended)
./setup.sh

# Manual
scp scripts/forward-suricata-eve-python.py admin@<pfsense>:/usr/local/bin/
ssh admin@<pfsense> "chmod +x /usr/local/bin/forward-suricata-eve-python.py"
```

**Configuration:** Via environment variables (or edit header defaults)
```bash
# Environment variables (or edit script defaults)
SIEM_HOST="192.168.210.10"      # Your SIEM IP
LOGSTASH_UDP_PORT="5140"        # Logstash UDP port
DEBUG_ENABLED="true"            # Enable debug logging
```

**GeoIP Database Priority:**
1. `/usr/local/share/ntopng/GeoLite2-City.mmdb` (best for geomaps)
2. `/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb` (Suricata default)
3. `/usr/local/share/GeoIP/GeoLite2-Country.mmdb` (pfBlockerNG)

See [docs/GEOIP_SETUP.md](../docs/GEOIP_SETUP.md) for GeoIP details.

---

## 🛡️ Watchdog Scripts

### suricata-forwarder-watchdog.sh
**Automatic forwarder restart on failure** (deployed to pfSense by `setup.sh`)

**Purpose:** Monitors forwarder process health and restarts if:
- Process crashed
- Not forwarding data (stuck state)
- File descriptor leaks

**Deployment:**
```bash
# Automated via setup.sh, or manual:
scp scripts/suricata-forwarder-watchdog.sh root@<pfsense>:/usr/local/bin/
ssh root@<pfsense> "chmod +x /usr/local/bin/suricata-forwarder-watchdog.sh"

# Add to cron (every 5 minutes)
ssh root@<pfsense>
crontab -e
# Add line:
*/5 * * * * /usr/local/bin/suricata-forwarder-watchdog.sh > /dev/null 2>&1
```

**Check watchdog status:**
```bash
ssh root@<pfsense> "tail -20 /var/log/system.log | grep watchdog"
```

### unified-monitoring-watchdog.sh
**Combined watchdog** - Monitors forwarder + Suricata instances

**Features:**
- Checks forwarder process health
- Checks Suricata instance count (ensures all interfaces running)
- Restarts failed components
- Syslog alerting

**Use case:** Environments where Suricata instances occasionally crash

### suricata-restart-hook.sh
**Suricata restart integration** - Ensures forwarder starts after Suricata upgrades

**Deployment:**
```bash
scp scripts/suricata-restart-hook.sh root@<pfsense>:/usr/local/pkg/suricata/
ssh root@<pfsense> "chmod +x /usr/local/pkg/suricata/suricata-restart-hook.sh"
```

**Integration:** Called by pfSense Suricata package after restarts/upgrades

---

## ⚙️ Configuration Scripts

### install-opensearch-config.sh
**OpenSearch index template and settings configuration** (called by `setup.sh`)

**Purpose:**
- Creates index templates for `suricata-*` and `filterlog-*` patterns
- Configures field mappings (nested, geo_point, keyword)
- Sets `action.auto_create_index` to allow midnight UTC index creation
- Prevents "No Data" issues at midnight

**Manual run:**
```bash
./scripts/install-opensearch-config.sh
```

**Requires:** OpenSearch running and reachable

See [docs/OPENSEARCH_AUTO_CREATE.md](../docs/OPENSEARCH_AUTO_CREATE.md) for details.

### configure-retention-policy.sh
**Data retention policy configuration**

**Purpose:** Set index lifecycle management (ILM) for automatic old data deletion

**Usage:**
```bash
./scripts/configure-retention-policy.sh
# Prompts for retention days (default: 90)
```

**What it configures:**
- OpenSearch ILM policy for `suricata-*` indices
- Automatic deletion after N days
- Rollover on size/age thresholds

### setup_forwarder_monitoring.sh
**Interactive forwarder monitoring setup**

**Purpose:** Configure automated forwarder health checks with preset strategies

**Usage:**
```bash
./scripts/setup_forwarder_monitoring.sh
```

**Monitoring strategies:**
- **Hybrid** (recommended): Crash recovery + activity monitoring
- **Simple**: Crash-only recovery
- **24/7**: Full monitoring around the clock
- **Business Hours**: Weekday 8am-6pm monitoring
- **Custom**: Configure your own cron schedule

See [docs/FORWARDER_MONITORING_QUICK_REF.md](../docs/FORWARDER_MONITORING_QUICK_REF.md) for details.

---

## 🔧 Utility Scripts

### restart-services.sh
**Restart SIEM stack services** - Use when troubleshooting Logstash/OpenSearch

```bash
./scripts/restart-services.sh
```

**What it restarts:**
- Logstash
- OpenSearch
- Grafana (optional)

**When to use:**
- After configuration changes
- When Logstash is stuck
- After OpenSearch mapping updates

### apply-suricata-drop-rules.sh
**Apply drop rules to Suricata** - Convert IDS alerts to IPS blocks

**Purpose:** Dynamically block IPs generating high alert counts

**Usage:**
```bash
ssh root@<pfsense> "/usr/local/bin/apply-suricata-drop-rules.sh"
```

**Requires:** Custom Suricata configuration to honor drop rules

### enable-selective-blocking.sh
**Configure selective IPS blocking** - Block specific signatures, alert on others

**Purpose:** Fine-tune IPS mode to block critical threats while alerting on lower-priority

**Usage:**
```bash
./scripts/enable-selective-blocking.sh
```

---

## 📁 Archive

Old/deprecated scripts kept for reference:

- **suricata-eve-forwarder.sh** - Shell-based forwarder (superseded by Python version)
- **suricata-restart-with-forwarder.sh** - Manual restart (superseded by watchdog)

See [scripts/archive/](archive/) for historical scripts.

---

## 🛠️ Development & Testing

### Testing Forwarder Locally

```bash
# Simulate forwarder without deploying to pfSense
cd scripts
python3.11 forward-suricata-eve.py

# Check debug output
tail -f /var/log/suricata_forwarder_debug.log
```

### Testing Watchdog

```bash
# Kill forwarder to trigger watchdog
ssh root@<pfsense> "pkill -9 -f forward-suricata-eve.py"

# Wait 5 minutes (watchdog cron interval)
sleep 300

# Check if watchdog restarted it
ssh root@<pfsense> "ps aux | grep forward-suricata-eve.py | grep -v grep"
```

---

## 📚 Related Documentation

- **[Main README](../README.md)** - Project overview
- **[Installation Guide](../docs/INSTALL_PFSENSE_FORWARDER.md)** - Forwarder deployment
- **[Log Rotation Fix](../docs/LOG_ROTATION_FIX.md)** - Rotation handling details
- **[Troubleshooting](../docs/TROUBLESHOOTING.md)** - Common issues
- **[Forwarder Monitoring](../docs/FORWARDER_MONITORING_QUICK_REF.md)** - Monitoring setup

---

## 🚀 Quick Reference

**Initial Setup:**
```bash
sudo ./install.sh                 # Install SIEM stack (OpenSearch, Logstash, Grafana)
cp config.env.example config.env  # Create config
nano config.env                   # Edit SIEM_HOST and PFSENSE_HOST
./setup.sh                        # Automated deployment
```

**Health Check:**
```bash
./scripts/status.sh               # Full system status
```

**Troubleshooting:**
```bash
./scripts/restart-services.sh     # Restart SIEM services
ssh root@<pfsense> "tail -f /var/log/suricata_forwarder_debug.log"  # Forwarder logs
```

**Manual Forwarder Restart:**
```bash
ssh root@<pfsense> "pkill -f forward-suricata-eve.py && sleep 2 && nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &"
```

---

**For complete documentation, see [docs/](../docs/) or run `./setup.sh --help`**
