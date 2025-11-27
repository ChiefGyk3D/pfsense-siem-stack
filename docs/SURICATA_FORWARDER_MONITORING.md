# Suricata EVE JSON Forwarder Monitoring

This document explains how to ensure the Suricata log forwarder (`forward-suricata-eve.py`) continues running reliably and automatically recovers from failures.

## Table of Contents
- [Problem Statement](#problem-statement)
- [Monitoring Options](#monitoring-options)
- [Option Comparison](#option-comparison)
- [Installation Instructions](#installation-instructions)
- [Verification](#verification)
- [Troubleshooting](#troubleshooting)

---

## Problem Statement

The Suricata EVE JSON forwarder reads log files from `/var/log/suricata/*/eve.json` and forwards them to OpenSearch/Logstash. Under certain conditions, the forwarder may:

1. **Crash unexpectedly** - Process dies, logs stop flowing
2. **Get stuck on old files** - After Suricata restart, forwarder continues reading old eve.json files
3. **Stop processing** - Process runs but doesn't forward new events

Without monitoring, these issues cause **gaps in your security logs** that can last hours or days.

---

## Monitoring Options

We provide **three monitoring strategies** that can be used individually or combined. Choose based on your environment:

### Option 1: Simple Keepalive (Crash Recovery)

**Best for:** Most users, simple setups, low-maintenance environments

**What it does:** Checks every 5 minutes if forwarder is running. If not, starts it.

**Cron entry:**
```bash
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

**Pros:**
- ✅ Simplest solution (one line)
- ✅ Low overhead (just process check)
- ✅ Handles process crashes
- ✅ Safe (won't restart if already running)
- ✅ Works 24/7

**Cons:**
- ❌ Doesn't detect stuck/frozen processes
- ❌ Doesn't handle Suricata restart scenario
- ❌ Up to 5-minute recovery delay

**Resource usage:** Negligible (runs 288 times/day, ~0.1s each)

---

### Option 2: Event-Driven Hook (Suricata Restart Handler)

**Best for:** Frequent Suricata restarts, advanced users, testing/development environments

**What it does:** Automatically restarts forwarder whenever Suricata restarts (rule updates, config changes)

**Requirements:**
- pfSense `shellcmd` package installed

**Installation:**

1. Install shellcmd package:
   ```bash
   pkg install pfSense-pkg-shellcmd
   ```

2. Add restart command via WebGUI:
   - Navigate to **Services > Shellcmd**
   - Click **Add**
   - **Command:** `/usr/bin/killall python3.11; sleep 2; /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &`
   - **Shellcmd Type:** `afterfilterchangeshellcmd`
   - **Description:** `Restart Suricata log forwarder after filter changes`
   - Click **Save**

**Pros:**
- ✅ Event-driven (restarts when needed)
- ✅ No delay (immediate restart)
- ✅ Solves Suricata restart scenario
- ✅ Low overhead (only runs during Suricata events)
- ✅ Logical integration with Suricata lifecycle

**Cons:**
- ❌ Requires additional package (shellcmd)
- ❌ Doesn't handle standalone crashes
- ❌ May not survive pfSense updates
- ❌ Harder to troubleshoot
- ❌ More complex setup

**Resource usage:** Only runs during Suricata restarts (typically 1-5 times/day)

---

### Option 3: Smart Activity Monitor (Stuck Process Detection)

**Best for:** Active 24/7 networks, business environments, comprehensive monitoring

**What it does:** Checks if eve.json files are being actively written. If no activity for X minutes, restarts forwarder.

**Cron entry (basic):**
```bash
*/10 * * * * [ $(find /var/log/suricata/*/eve.json -mmin -10 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

**Variants:**

**Conservative (20-minute window):**
```bash
*/20 * * * * [ $(find /var/log/suricata/*/eve.json -mmin -20 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

**Business hours only (9 AM - 11 PM):**
```bash
*/15 9-23 * * * [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

**Pros:**
- ✅ Detects stuck/frozen processes
- ✅ Handles Suricata restart scenario
- ✅ Catches file-related issues
- ✅ Self-healing
- ✅ No additional packages required

**Cons:**
- ❌ Assumes constant network activity
- ❌ Can false-trigger on quiet networks
- ❌ May restart unnecessarily during idle periods
- ❌ More aggressive than Option 1
- ❌ 10-20 minute detection window

**Resource usage:** Runs file system scan 144 times/day (10-min interval), ~0.5s each

---

## Option Comparison

| Feature | Option 1<br/>Keepalive | Option 2<br/>Hook | Option 3<br/>Activity Monitor |
|---------|----------------------|------------------|----------------------------|
| **Handles crashes** | ✅ Yes | ❌ No | ✅ Yes |
| **Handles Suricata restart** | ❌ No | ✅ Yes | ✅ Yes |
| **Detects stuck process** | ❌ No | ❌ No | ✅ Yes |
| **False positives** | None | None | Possible (quiet networks) |
| **Setup complexity** | Easy | Medium | Easy |
| **Dependencies** | None | shellcmd pkg | None |
| **Resource usage** | Very Low | Very Low | Low |
| **Recovery time** | 0-5 min | Immediate | 0-20 min |
| **24/7 safe** | ✅ Yes | ✅ Yes | ⚠️ Maybe |

---

## Installation Instructions

### Recommended: Hybrid Approach (Option 1 + Option 3)

For most environments, we recommend combining Option 1 (crash recovery) with Option 3 (activity monitoring during active hours).

**Step 1: SSH into pfSense**
```bash
ssh root@192.168.1.1
```

**Step 2: Edit crontab**
```bash
crontab -e
```

**Step 3: Add both monitoring entries**
```bash
# Suricata Log Forwarder Monitoring
# Option 1: Simple keepalive - handles crashes
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &

# Option 3: Activity monitor - handles stuck processes during active hours (9 AM - 11 PM)
*/15 9-23 * * * [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

**Step 4: Save and exit**
- In vi: Press `ESC`, type `:wq`, press `ENTER`
- In nano: Press `CTRL+X`, then `Y`, then `ENTER`

**Step 5: Verify cron installation**
```bash
crontab -l | grep forward-suricata
```

You should see both lines.

---

### Alternative: Single Option Installation

Choose one option if you prefer a simpler approach:

#### Install Option 1 Only (Crash Recovery)
```bash
ssh root@192.168.1.1
crontab -e
# Add this line:
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

#### Install Option 2 Only (Event Hook)
```bash
# Install shellcmd package
ssh root@192.168.1.1
pkg install pfSense-pkg-shellcmd

# Then via WebGUI:
# Services > Shellcmd > Add
# Command: /usr/bin/killall python3.11; sleep 2; /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
# Type: afterfilterchangeshellcmd
```

#### Install Option 3 Only (Activity Monitor)
```bash
ssh root@192.168.1.1
crontab -e
# Add this line (choose your preferred variant):
*/15 9-23 * * * [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

---

## Environment-Specific Recommendations

### Home Lab / Family Network
**Recommended:** Option 1 + Option 3 (Hybrid, active hours only)

**Why:**
- Network activity varies (busy evenings, quiet nights)
- Occasional Suricata restarts (rule updates)
- Want automatic recovery without false alarms

**Configuration:**
```bash
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
*/15 9-23 * * * [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

---

### Small Business (9-5 operation)
**Recommended:** Option 1 + Option 3 (Business hours only)

**Why:**
- Active during business hours
- Minimal weekend traffic
- Need reliability during work hours

**Configuration:**
```bash
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
*/15 8-18 * * 1-5 [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

---

### 24/7 Active Network (Data Center, Always-On Services)
**Recommended:** Option 1 + Option 3 (24/7 monitoring)

**Why:**
- Constant traffic
- Need immediate detection
- False positives unlikely

**Configuration:**
```bash
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
*/10 * * * * [ $(find /var/log/suricata/*/eve.json -mmin -10 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

---

### Testing/Development (Frequent Config Changes)
**Recommended:** Option 1 + Option 2

**Why:**
- Frequent Suricata restarts
- Need immediate recovery
- Want event-driven automation

**Configuration:**
```bash
# Cron:
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &

# Plus shellcmd hook (via WebGUI)
```

---

### Minimal Maintenance (Set and Forget)
**Recommended:** Option 1 only

**Why:**
- Simplest approach
- Handles most issues
- Manual intervention acceptable for edge cases

**Configuration:**
```bash
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

---

## Verification

### Test Forwarder Restart
After installing monitoring, verify it works:

**Method 1: Kill forwarder and wait**
```bash
ssh root@192.168.1.1
killall python3.11
# Wait 5 minutes, then check:
ps aux | grep forward-suricata-eve.py | grep -v grep
```

**Method 2: Check cron is running**
```bash
ssh root@192.168.1.1
# Wait for cron to run (check at 5-minute mark)
tail -f /var/log/cron
# Look for: forward-suricata-eve.py entries
```

**Method 3: Verify logs are flowing**
```bash
# Check OpenSearch has recent events
curl -s "http://192.168.210.10:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | \
  python3 -c "import sys,json; print('Last event:', json.load(sys.stdin)['hits']['hits'][0]['_source']['suricata']['eve']['timestamp'])"
```

Expected: Timestamp within last few minutes

---

## Troubleshooting

### Logs Not Flowing After 15+ Minutes

**Check forwarder status:**
```bash
ssh root@192.168.1.1
ps aux | grep forward-suricata-eve.py | grep -v grep
```

**Check cron is configured:**
```bash
crontab -l | grep forward-suricata
```

**Manually restart forwarder:**
```bash
killall python3.11
/usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

**Check for errors:**
```bash
tail -50 /var/log/suricata_forwarder_debug.log
```

---

### False Restarts (Option 3)

If you see forwarder restarting during legitimate quiet periods:

**Solution 1: Increase time threshold**
```bash
# Change from -10 to -20 minutes
*/20 * * * * [ $(find /var/log/suricata/*/eve.json -mmin -20 | wc -l) -eq 0 ] && ...
```

**Solution 2: Limit to active hours**
```bash
# Only check during 8 AM - 11 PM
*/15 8-23 * * * [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && ...
```

**Solution 3: Disable Option 3, keep Option 1 only**
```bash
crontab -e
# Comment out or delete the Option 3 line
```

---

### Cron Not Running

**Check cron service:**
```bash
service cron status
# If not running:
service cron start
service cron enable
```

**Check cron log:**
```bash
tail -f /var/log/cron
```

---

### Forwarder Starts But Immediately Dies

**Check Python version:**
```bash
which python3.11
# Should return: /usr/local/bin/python3.11
```

**Check script exists:**
```bash
ls -la /usr/local/bin/forward-suricata-eve.py
```

**Check dependencies:**
```bash
python3.11 -c "import geoip2, socket, syslog, json"
```

**Run forwarder manually to see errors:**
```bash
/usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py
# Leave running and check for errors
```

---

## Monitoring Effectiveness

### Check Last Restart Time
```bash
ps aux | grep forward-suricata-eve.py | grep -v grep | awk '{print $2}'
# Get PID, then:
ps -p <PID> -o lstart=
```

### Count Restarts Per Day
```bash
grep "forward-suricata-eve.py" /var/log/cron | grep "$(date +%Y-%m-%d)" | wc -l
```

### Verify No Log Gaps
```bash
# Check OpenSearch for continuous timestamps
curl -s "http://192.168.210.10:9200/suricata-*/_search?size=100&sort=@timestamp:desc" | \
  python3 -c "
import sys, json
data = json.load(sys.stdin)
for hit in data['hits']['hits']:
    print(hit['_source']['suricata']['eve']['timestamp'])
" | head -20
```

Look for any gaps > 10 minutes in timestamps.

---

## Related Documentation

- [Suricata Log Forwarding Setup](./SURICATA_LOG_FORWARDING.md) - Initial forwarder setup
- [OpenSearch Configuration](./OPENSEARCH_SETUP.md) - Backend log storage
- [Grafana Dashboard Setup](./GRAFANA_SETUP.md) - Visualization
- [Troubleshooting Guide](./TROUBLESHOOTING_CHECKLIST.md) - Common issues

---

## Contributing

Found a better approach? Have environment-specific recommendations? Please contribute!

1. Fork the repository
2. Create a branch: `git checkout -b feature/monitoring-improvement`
3. Update this document
4. Submit a pull request

---

## Changelog

- **2025-11-26**: Initial documentation with three monitoring options
- **2025-11-26**: Added hybrid approach and environment-specific recommendations
