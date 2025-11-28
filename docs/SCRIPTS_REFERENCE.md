# Scripts Reference Guide

> **Complete reference for all helper scripts** in the pfSense SIEM Stack

This document provides detailed information about every script in the `scripts/` directory, including purpose, usage, parameters, and examples.

---

## Quick Reference

| Script | Purpose | Usage | When to Use |
|--------|---------|-------|-------------|
| **status.sh** | System health check | `./status.sh` | Daily monitoring |
| **restart-services.sh** | Restart SIEM services | `sudo ./restart-services.sh` | Services down |
| **configure-retention-policy.sh** | Set data retention | `./configure-retention-policy.sh 90` | Disk management |
| **install-opensearch-config.sh** | Configure OpenSearch | `./install-opensearch-config.sh` | Initial setup |
| **suricata-forwarder-watchdog.sh** | Monitor forwarder | Runs via cron | Auto-deployed |
| **suricata-restart-hook.sh** | Restart after Suricata | Runs automatically | Auto-deployed |
| **check_custom_sids.sh** | Verify SID configuration | `./check_custom_sids.sh` | Rule management |

---

## Core Scripts

### status.sh

**Purpose:** Comprehensive health check of entire SIEM stack

**What it checks:**
- ✓ OpenSearch connectivity and cluster health
- ✓ Auto-create index setting
- ✓ Logstash UDP port listening
- ✓ Index list and document counts
- ✓ Latest event timestamp
- ✓ Forwarder running on pfSense
- ✓ Watchdog cron job installed
- ✓ Monitored interfaces
- ✓ Data flow rates

**Usage:**
```bash
./scripts/status.sh
```

**Output example:**
```
========================================
SIEM Server Status (192.168.210.10)
========================================

Checking OpenSearch... ✓ OpenSearch is running
  Cluster status: green
  ✓ Auto-create enabled for suricata-*

Checking Logstash port... ✓ Logstash UDP port 5140 is listening

Indices:
index                docs.count store.size
suricata-2024.11.27  123456     450.2mb

Total events: 123456
Latest event: 2024-11-27T10:15:30Z

========================================
pfSense Status (192.168.1.1)
========================================

Forwarder: ✓ Running (PID: 12345)
Watchdog: ✓ Installed

Monitored interfaces:
  • /var/log/suricata/suricata_ix055721/eve.json
  • /var/log/suricata/suricata_lagg1.1020460/eve.json

Status: ✅ All systems operational
```

**Exit codes:**
- `0` - All checks passed
- `>0` - Number of failed checks

**Configuration:**
Reads from `../config.env` if available, otherwise uses defaults.

**Variables:**
- `SIEM_HOST` - SIEM server IP
- `PFSENSE_HOST` - pfSense IP  
- `OPENSEARCH_PORT` - OpenSearch port (default: 9200)
- `LOGSTASH_UDP_PORT` - Logstash port (default: 5140)
- `INDEX_PREFIX` - Index prefix (default: suricata)

---

### restart-services.sh

**Purpose:** Gracefully restart all SIEM services in proper order

**What it does:**
1. Restarts OpenSearch (waits for cluster)
2. Restarts Logstash (waits for pipeline)
3. Restarts Grafana (waits for web UI)
4. Verifies each service started successfully

**Usage:**
```bash
sudo ./scripts/restart-services.sh
```

**Requirements:**
- Root/sudo privileges
- Systemd-based system

**Output example:**
```
=== Restarting SIEM Services ===

Restarting opensearch... ✓
Restarting logstash... ✓
Restarting grafana-server... ✓

✓ All services restarted successfully

Verify status:
  systemctl status opensearch logstash grafana-server
```

**When to use:**
- After configuration changes
- Services become unresponsive
- High CPU/memory usage
- After system updates

**Troubleshooting:**
If a service fails to restart:
```bash
# Check logs
sudo journalctl -u opensearch -n 50
sudo journalctl -u logstash -n 50
sudo journalctl -u grafana-server -n 50

# Check service status
systemctl status opensearch
systemctl status logstash
systemctl status grafana-server
```

---

### configure-retention-policy.sh

**Purpose:** Configure OpenSearch Index Lifecycle Management (ILM) for automatic data deletion

**Usage:**
```bash
./scripts/configure-retention-policy.sh [DAYS]
```

**Parameters:**
- `DAYS` - Number of days to retain data (default: 30)

**Examples:**
```bash
# Set 30-day retention
./configure-retention-policy.sh 30

# Set 90-day retention
./configure-retention-policy.sh 90

# Set 1-year retention
./configure-retention-policy.sh 365
```

**What it does:**
1. Connects to OpenSearch
2. Creates/updates ISM (Index State Management) policy
3. Sets delete_after to specified days
4. Applies policy to index pattern
5. Verifies policy is active

**Output example:**
```
Configuring retention policy for suricata-* indices
Setting retention to 90 days

✓ ISM policy created
✓ Policy applied to suricata-* indices
✓ Configuration verified

Retention policy active:
  Index pattern: suricata-*
  Retention: 90 days
  Next cleanup: Check daily at midnight
```

**How it works:**

The script creates an ISM policy like this:
```json
{
  "policy": {
    "description": "Auto-delete old Suricata indices",
    "default_state": "active",
    "states": [
      {
        "name": "active",
        "transitions": [{
          "state_name": "delete",
          "conditions": {
            "min_index_age": "90d"
          }
        }]
      },
      {
        "name": "delete",
        "actions": [{"delete": {}}]
      }
    ]
  }
}
```

**Disk space calculation:**

Estimate disk usage:
```
Storage = Events/day × Event_size × Retention_days

Low traffic:
  1,000 events/day × 2KB × 30 days = 60MB

Medium traffic:
  10,000 events/day × 2KB × 30 days = 600MB

High traffic:
  100,000 events/day × 2KB × 30 days = 6GB

Very high traffic:
  1,000,000 events/day × 2KB × 30 days = 60GB
```

**Recommendations:**
- **Home lab:** 30-90 days (plenty for learning/testing)
- **Small business:** 90-180 days (good for incident investigation)
- **Enterprise:** 365+ days (compliance requirements)

**Verification:**
```bash
# Check active policies
curl http://localhost:9200/_plugins/_ism/policies

# Check policy applied to indices
curl http://localhost:9200/_cat/indices/suricata-*?v

# Check index ages
curl http://localhost:9200/_cat/indices/suricata-*?v&h=index,creation.date,creation.date.string
```

---

### install-opensearch-config.sh

**Purpose:** Configure OpenSearch for Suricata data with proper mappings

**Usage:**
```bash
OPENSEARCH_HOST=localhost OPENSEARCH_PORT=9200 ./scripts/install-opensearch-config.sh
```

**Environment variables:**
- `OPENSEARCH_HOST` - OpenSearch hostname (default: localhost)
- `OPENSEARCH_PORT` - OpenSearch port (default: 9200)

**What it configures:**

1. **Index Template** (`suricata-template`)
   - Maps `geoip_src.location` and `geoip_dest.location` as `geo_point`
   - Sets proper field types for Suricata data
   - Applies to all `suricata-*` indices

2. **Auto-Create Index**
   - Enables automatic index creation for `suricata-*`
   - Prevents midnight UTC data loss
   - Allows Logstash to create indices automatically

3. **Cluster Settings**
   - Disables destructive wildcard deletes (safety)
   - Configures shard/replica settings

**Index template:**
```json
{
  "index_patterns": ["suricata-*"],
  "template": {
    "mappings": {
      "properties": {
        "suricata": {
          "properties": {
            "eve": {
              "properties": {
                "geoip_src": {
                  "properties": {
                    "location": {"type": "geo_point"}
                  }
                },
                "geoip_dest": {
                  "properties": {
                    "location": {"type": "geo_point"}
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
```

**Why geo_point matters:**

Without proper `geo_point` mapping:
- ❌ Geomaps won't display
- ❌ Coordinates stored as strings
- ❌ Can't use geo queries
- ❌ Must reindex to fix

With `geo_point` mapping:
- ✅ Geomaps work perfectly
- ✅ Attack sources visualized
- ✅ Geographic queries enabled
- ✅ Distance calculations available

**When to run:**
- **BEFORE** any Suricata data flows
- During initial setup
- After OpenSearch reinstall
- If geomaps not working

**Verification:**
```bash
# Check template exists
curl http://localhost:9200/_index_template/suricata-template

# Verify geo_point mapping
curl http://localhost:9200/suricata-*/_mapping | jq '.[] | .mappings.properties.suricata.properties.eve.properties.geoip_src.properties.location'

# Should return: {"type": "geo_point"}

# Check auto-create setting
curl http://localhost:9200/_cluster/settings?filter_path=persistent.action.auto_create_index

# Should return: {"persistent":{"action":{"auto_create_index":"suricata-*,-.ds-*"}}}
```

**Troubleshooting:**

**Problem:** Geomaps not displaying

**Solution:**
```bash
# 1. Check if template applied to existing indices
curl http://localhost:9200/suricata-*/_mapping | grep geo_point

# 2. If not found, you must reindex
# WARNING: This is complex, backup first!

# 3. Or delete existing indices (data loss!)
curl -X DELETE http://localhost:9200/suricata-*

# 4. Re-run config script
./install-opensearch-config.sh

# 5. Wait for new data to flow
```

---

## pfSense Scripts

### forward-suricata-eve-python.py

**Purpose:** Multi-interface Suricata log forwarder with GeoIP enrichment

**Features:**
- ✅ Auto-discovers all Suricata instances
- ✅ Monitors multiple eve.json files simultaneously
- ✅ Handles log rotation gracefully (inode tracking)
- ✅ GeoIP enrichment (city-level accuracy)
- ✅ Sends via UDP to Logstash
- ✅ Debug logging available

**Deployed to:** `/usr/local/bin/forward-suricata-eve.py` on pfSense

**Usage:**
```bash
# Started automatically by watchdog
nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &
```

**Configuration:**
Hardcoded in script (set during deployment):
```python
GRAYLOG_SERVER = "192.168.210.10"  # Your SIEM server IP
GRAYLOG_PORT = 5140                # Logstash UDP port
DEBUG_ENABLED = False              # Set True for debug logs
```

**Monitored interfaces:**
Auto-discovers all Suricata instances:
```
/var/log/suricata/suricata_ix055721/eve.json      (WAN1)
/var/log/suricata/suricata_ix144397/eve.json      (WAN2)
/var/log/suricata/suricata_lagg1.1020460/eve.json (VLAN 10)
/var/log/suricata/suricata_lagg1.2249359/eve.json (VLAN 22)
... etc for all Suricata instances
```

**Log rotation handling:**

**Problem:** Suricata rotates logs, old script would get stuck on old file

**Solution:** Inode tracking
```python
# Track file by inode, not name
current_inode = os.stat(eve_json_path).st_ino

# Check if file rotated
new_inode = os.stat(eve_json_path).st_ino
if new_inode != current_inode:
    # File rotated, reopen
    f.close()
    f = open(eve_json_path, 'r')
    f.seek(0, 2)  # Seek to end
    current_inode = new_inode
```

**GeoIP enrichment:**

Uses MaxMind GeoLite2-City database:
```python
import geoip2.database

# Enrich source IP
if 'src_ip' in event:
    try:
        response = reader.city(event['src_ip'])
        event['geoip_src'] = {
            'country': response.country.iso_code,
            'city': response.city.name,
            'location': {
                'lat': response.location.latitude,
                'lon': response.location.longitude
            }
        }
    except:
        pass  # Private IP or lookup failure
```

**Debug logging:**

Enable debug mode:
```bash
ssh root@pfsense

# Edit script
vi /usr/local/bin/forward-suricata-eve.py

# Change DEBUG_ENABLED to True
DEBUG_ENABLED = True

# Restart forwarder
pkill -f forward-suricata-eve
nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &

# View debug logs
tail -f /var/log/system.log | grep suricata-forwarder
```

**Debug output:**
```
suricata-forwarder: Started monitoring 15 interfaces
suricata-forwarder: Discovered: /var/log/suricata/suricata_ix055721/eve.json
suricata-forwarder: GeoIP: 203.0.113.1 -> US, New York (40.7128, -74.0060)
suricata-forwarder: Sent event: alert signature_id=2024897
suricata-forwarder: Sent 150 events in batch
```

**Performance:**

Tested on Intel Atom C3758 (8-core):
- 15 Suricata instances monitored
- ~185,000 events/hour peak
- CPU usage: 2-5% average
- Memory: ~50MB RSS

---

### suricata-forwarder-watchdog.sh

**Purpose:** Monitor forwarder health and auto-restart if needed

**Deployed to:** `/usr/local/bin/suricata-forwarder-watchdog.sh` on pfSense

**Runs via cron:** Every 1 minute

**Crontab entry:**
```cron
* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh
```

**What it does:**

```bash
#!/bin/sh
FORWARDER_SCRIPT="/usr/local/bin/forward-suricata-eve.py"
LOG_TAG="suricata-forwarder-watchdog"

# Check if forwarder is running
PYTHON_PID=$(ps aux | grep "[f]orward-suricata-eve.py" | awk '{print $2}' | head -1)

if [ -z "$PYTHON_PID" ]; then
    # Not running, start it
    logger -t "$LOG_TAG" "Forwarder not running, starting..."
    nohup /usr/local/bin/python3.11 "$FORWARDER_SCRIPT" > /dev/null 2>&1 &
    
    # Verify started
    sleep 2
    PYTHON_PID=$(ps aux | grep "[f]orward-suricata-eve.py" | awk '{print $2}' | head -1)
    if [ -n "$PYTHON_PID" ]; then
        logger -t "$LOG_TAG" "Forwarder started (PID: $PYTHON_PID)"
    else
        logger -t "$LOG_TAG" "ERROR: Failed to start forwarder"
    fi
else
    # Running, log status every 5 minutes
    MINUTE=$(date +%M)
    if [ "$((MINUTE % 5))" -eq 0 ]; then
        CPU=$(ps aux | grep "[f]orward-suricata-eve.py" | awk '{print $3}' | head -1)
        logger -t "$LOG_TAG" "Forwarder running (PID: $PYTHON_PID, CPU: ${CPU}%)"
    fi
fi
```

**Monitoring:**

View watchdog activity:
```bash
ssh root@pfsense 'tail -100 /var/log/system.log | grep watchdog'
```

**Output:**
```
Nov 27 10:00:01 pfsense suricata-forwarder-watchdog: Forwarder running (PID: 12345, CPU: 2.5%)
Nov 27 10:05:01 pfsense suricata-forwarder-watchdog: Forwarder running (PID: 12345, CPU: 3.1%)
```

**Test watchdog:**

```bash
# Kill forwarder
ssh root@pfsense 'pkill -f forward-suricata-eve'

# Wait 1 minute for watchdog to detect and restart

# Check if restarted
ssh root@pfsense 'ps aux | grep forward-suricata-eve'
```

---

### suricata-restart-hook.sh

**Purpose:** Restart forwarder when Suricata restarts or reloads rules

**Deployed to:** `/usr/local/bin/suricata-restart-hook.sh` on pfSense

**Triggered by:** Suricata package hooks

**What it does:**

```bash
#!/bin/sh
LOG_TAG="suricata-restart-hook"

logger -t "$LOG_TAG" "Suricata restarted, restarting forwarder..."

# Stop forwarder
pkill -f forward-suricata-eve.py

# Wait for Suricata to fully start
sleep 5

# Start forwarder
nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &

logger -t "$LOG_TAG" "Forwarder restarted"
```

**When triggered:**
- Suricata service restart
- Suricata rule reload
- Interface enable/disable
- Suricata package update

**Monitoring:**
```bash
ssh root@pfsense 'tail -f /var/log/system.log | grep suricata-restart-hook'
```

---

## Advanced Scripts

### check_custom_sids.sh

**Purpose:** Verify Suricata SID (signature ID) configuration

**Usage:**
```bash
./scripts/check_custom_sids.sh
```

**What it checks:**
- Installed SID management files
- Disabled SIDs count
- Suppressed rules count
- Compares with repository defaults
- Verifies Suricata configuration

**Output example:**
```
=== Suricata SID Configuration Check ===

Checking local configuration:
  ✓ disablesid.conf found (219 rules)
  ✓ suppress.conf found (2 rules)

Checking repository defaults:
  ✓ config/sid/disable/disablesid.conf (219 rules)
  ✓ config/sid/suppress/suppress.conf (2 rules)

Status: ✅ Local config matches repository

Applied rules:
  • 219 disabled SIDs (performance optimization)
  • 2 suppressed rules (conditional suppression)

To apply changes:
  1. Copy updated files to pfSense
  2. Services → Suricata → Interface → Rules → Update
  3. Services → Suricata → Interface → Restart
```

**See also:**
- [SID Management Documentation](../config/sid/README.md)
- [Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md)

---

### check-telegram-alerts.sh

**Purpose:** Setup and test Telegram alert notifications

**Usage:**
```bash
./scripts/check-telegram-alerts.sh
```

**What it does:**
1. Tests Telegram bot connectivity
2. Validates bot token
3. Verifies chat ID
4. Sends test message
5. Configures alert rules

**Requirements:**
- Telegram bot token (from @BotFather)
- Chat ID (from @userinfobot or @IDBot)

**Configuration:**
Set in `config.env`:
```bash
TELEGRAM_BOT_TOKEN="1234567890:ABCdef..."
TELEGRAM_CHAT_ID="-1001234567890"
```

**Test:**
```bash
# Send test message
curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d "chat_id=${TELEGRAM_CHAT_ID}" \
  -d "text=Test message from pfSense SIEM Stack"
```

---

## Script Maintenance

### Updating Scripts

**Update forwarder on pfSense:**
```bash
# Make changes to local copy
nano scripts/forward-suricata-eve-python.py

# Redeploy
./setup.sh
```

**Update watchdog:**
```bash
# Edit locally
nano scripts/suricata-forwarder-watchdog.sh

# Redeploy
scp scripts/suricata-forwarder-watchdog.sh root@pfsense:/usr/local/bin/
ssh root@pfsense 'chmod +x /usr/local/bin/suricata-forwarder-watchdog.sh'
```

### Debugging Scripts

**Enable debug logging:**
```bash
# Add to top of script
set -x  # Print each command before execution

# Or run with debugging
bash -x script.sh
```

**Check script syntax:**
```bash
# Bash scripts
bash -n script.sh

# Python scripts
python3 -m py_compile script.py
```

**Common issues:**

**Permission denied:**
```bash
chmod +x script.sh
```

**Command not found:**
```bash
# Check PATH
echo $PATH

# Use full path
/usr/local/bin/python3.11 script.py
```

**Syntax error:**
```bash
# Check for:
- Missing quotes
- Unclosed brackets
- Wrong line endings (CRLF vs LF)

# Convert line endings
dos2unix script.sh
```

---

## Best Practices

1. **Always test scripts in development first**
   - Don't test on production pfSense
   - Use virtual machine or test firewall

2. **Check exit codes**
   ```bash
   if ./script.sh; then
       echo "Success"
   else
       echo "Failed with code $?"
   fi
   ```

3. **Log script execution**
   ```bash
   ./script.sh 2>&1 | tee script.log
   ```

4. **Use absolute paths**
   ```bash
   # Good
   /usr/local/bin/python3.11 /usr/local/bin/script.py
   
   # Bad (may fail in cron)
   python3.11 script.py
   ```

5. **Handle errors gracefully**
   ```bash
   set -e  # Exit on error
   set -u  # Exit on undefined variable
   set -o pipefail  # Exit on pipe failure
   ```

---

## Support

**Issues with scripts:**
- Check logs first
- Test connectivity
- Verify permissions
- Check documentation

**Get help:**
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [GitHub Issues](https://github.com/ChiefGyk3D/pfsense_grafana/issues)
- [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense_grafana/discussions)

---

**Built with ❤️ for the pfSense and open-source security community**
