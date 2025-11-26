# pfSense Filterlog Rotation Issue - Fix and Prevention

## Problem Summary

When pfSense's `filter.log` is rotated by `newsyslog` (at 500KB by default), the `filterlog` daemon does not properly reopen the log file. This causes:
- **All firewall logging stops** (filter.log receives no new entries)
- **pfBlockerNG IP blocking logs stop** (ip_block.log dependent on filter.log)
- **Grafana pfBlocker dashboard panels show no data**
- Issue persists until filterlog daemon is restarted

**Symptoms:**
- filter.log shows only newsyslog rotation message and nothing else
- pfBlocker panels in Grafana show "No data"
- `lsof -p <filterlog_pid>` shows no file descriptor for filter.log
- pfBlocker rules still blocking, but events not logged

---

## Immediate Fix (When It Happens)

### Option 1: Via SSH (Fastest)
```bash
# SSH to pfSense
ssh root@<pfsense-ip>

# Restart filterlog and pfBlockerNG logging
php -r 'require_once("/etc/inc/filter.inc"); filter_configure(); system_syslogd_start();'
php -r 'require_once("/usr/local/pkg/pfblockerng/pfblockerng.inc"); pfblockerng_sync_on_changes();'

# Verify it's working
tail -f /var/log/filter.log
tail -f /var/log/pfblockerng/ip_block.log
```

### Option 2: Via pfSense Web GUI
1. Go to **Diagnostics → Command Prompt**
2. **Execute Shell Command:**
   ```php
   php -r 'require_once("/etc/inc/filter.inc"); filter_configure(); system_syslogd_start();'
   ```
3. Click **Execute**
4. Then run second command:
   ```php
   php -r 'require_once("/usr/local/pkg/pfblockerng/pfblockerng.inc"); pfblockerng_sync_on_changes();'
   ```
5. Click **Execute**

### Option 3: Reboot pfSense
- Go to **Diagnostics → Reboot**
- Click **Submit**
- All services restart cleanly, filterlog reopens log files

---

## GUI Configuration Options

### 1. Increase Log Rotation Size (Reduce Rotation Frequency)

**Location:** Status → System Logs → Settings

**Current Setting:** 500KB (default)
**Recommendation:** Increase to 2000KB or 5000KB

**Steps:**
1. Navigate to **Status → System Logs → Settings**
2. Find **Log Rotation Size (KB)** field
3. Change from `500` to `2000` (or higher)
4. Click **Save**

**Effect:**
- Logs rotate less frequently
- Reduces chance of hitting rotation bug
- Does NOT fix the underlying issue, just reduces frequency

**Note:** This setting affects ALL logs (system.log, filter.log, vpn.log, etc.)

### 2. Adjust Log Rotation Count

**Location:** Status → System Logs → Settings

**Current Setting:** 7 archives (1 week of logs)
**Options:** Any number 1-99

**Steps:**
1. Navigate to **Status → System Logs → Settings**
2. Find **Log Rotation Count** field
3. Set desired number of archives to keep
4. Click **Save**

**Effect:**
- Controls how many old log files are kept
- Does not affect rotation frequency
- Higher = more disk space used, more history

---

## Permanent Fix Options

### Option 1: Automated Monitoring Script (RECOMMENDED)

Create a script on your SIEM/monitoring server that:
1. Checks filter.log modification time every 5 minutes
2. If filter.log hasn't been updated in 10 minutes, alert and auto-restart
3. Integrates with your existing monitoring

**Create monitoring script:**

```bash
#!/bin/bash
# File: /usr/local/bin/check-pfsense-filterlog.sh

PFSENSE_HOST="${PFSENSE_HOST:-192.168.1.1}"
PFSENSE_USER="${PFSENSE_USER:-root}"
MAX_AGE_SECONDS=600  # 10 minutes

# Get last modification time of filter.log
LAST_MOD=$(ssh ${PFSENSE_USER}@${PFSENSE_HOST} "stat -f %m /var/log/filter.log" 2>/dev/null)

if [ -z "$LAST_MOD" ]; then
    echo "ERROR: Could not check filter.log on pfSense"
    exit 1
fi

NOW=$(date +%s)
AGE=$((NOW - LAST_MOD))

if [ $AGE -gt $MAX_AGE_SECONDS ]; then
    echo "WARNING: filter.log is $AGE seconds old (threshold: $MAX_AGE_SECONDS)"
    echo "Restarting filterlog daemon..."
    
    ssh ${PFSENSE_USER}@${PFSENSE_HOST} "php -r 'require_once(\"/etc/inc/filter.inc\"); filter_configure(); system_syslogd_start();'"
    ssh ${PFSENSE_USER}@${PFSENSE_HOST} "php -r 'require_once(\"/usr/local/pkg/pfblockerng/pfblockerng.inc\"); pfblockerng_sync_on_changes();'"
    
    echo "Filterlog restarted successfully"
    exit 2
else
    echo "OK: filter.log is current ($AGE seconds old)"
    exit 0
fi
```

**Make executable:**
```bash
chmod +x /usr/local/bin/check-pfsense-filterlog.sh
```

**Add to crontab:**
```bash
# Check every 5 minutes
*/5 * * * * /usr/local/bin/check-pfsense-filterlog.sh >> /var/log/pfsense-filterlog-check.log 2>&1
```

**Integrate with status.sh:**

Add this to `scripts/status.sh` in the pfSense checks section:

```bash
# Check filter.log freshness
echo -n "Checking filter.log age... "
FILTER_LOG_MOD=$(ssh -o BatchMode=yes ${PFSENSE_USER}@${PFSENSE_HOST} "stat -f %m /var/log/filter.log" 2>/dev/null)
if [ -n "$FILTER_LOG_MOD" ]; then
    NOW=$(date +%s)
    AGE=$((NOW - FILTER_LOG_MOD))
    if [ $AGE -gt 600 ]; then
        echo -e "${RED}✗${NC} filter.log is ${AGE}s old (stale)"
        ((ERRORS++))
    else
        echo -e "${GREEN}✓${NC} ${AGE}s old"
    fi
else
    echo -e "${RED}✗${NC} Could not check"
    ((ERRORS++))
fi
```

### Option 2: pfSense Cron Job (Direct on Firewall)

Add a cron job directly on pfSense to restart filterlog after newsyslog runs.

**Steps:**
1. Go to **Services → Cron** in pfSense GUI
2. Click **Add** (+ icon)
3. Configure:
   - **Minute:** `5,15,25,35,45,55` (every 10 minutes, offset from hourly)
   - **Hour:** `*`
   - **Day of Month:** `*`
   - **Month:** `*`
   - **Day of Week:** `*`
   - **User:** `root`
   - **Command:** 
     ```bash
     /usr/bin/find /var/log/filter.log -mmin +10 -exec php -r 'require_once("/etc/inc/filter.inc"); filter_configure(); system_syslogd_start();' \;
     ```
   - **Description:** `Auto-restart filterlog if stale`
4. Click **Save**

**What this does:**
- Every 10 minutes, checks if filter.log hasn't been modified in 10+ minutes
- If stale, restarts filterlog
- Minimal overhead, runs quickly

### Option 3: Modify newsyslog Rotation Behavior

**⚠️ Advanced - Requires manual file editing on pfSense**

This changes how newsyslog handles filter.log rotation.

**Steps:**

1. SSH to pfSense
2. Edit newsyslog config:
   ```bash
   vi /var/etc/newsyslog.conf.d/pfSense.conf
   ```

3. Find the filter.log line:
   ```
   /var/log/filter.log             root:wheel      600     7       500     *       C
   ```

4. Change the `C` flag to `B`:
   ```
   /var/log/filter.log             root:wheel      600     7       500     *       B
   ```

5. Save and exit

**Flag meanings:**
- `C` = Send SIGHUP signal to process (filterlog doesn't handle this properly)
- `B` = Binary log, no signal sent (filterlog keeps writing to old file handle)

**⚠️ WARNING:** This change will be **overwritten** on every pfSense config change or reboot. You'd need to script it to persist.

**Better approach:** Create a custom config file that won't be overwritten:

```bash
# Create custom newsyslog config
cat > /var/etc/newsyslog.conf.d/custom-filterlog.conf << 'EOF'
# Custom filter.log rotation without signal
/var/log/filter.log             root:wheel      600     7       2000    *       B
EOF
```

This file survives reboots but may conflict with pfSense's auto-generated config.

---

## Detection and Diagnostics

### Check if Filter.log is Stale

**From SIEM server:**
```bash
ssh root@192.168.1.1 "ls -lh /var/log/filter.log && stat /var/log/filter.log"
```

**Check age:**
```bash
ssh root@192.168.1.1 "echo 'Last modified:' && date -r \$(stat -f %m /var/log/filter.log) && echo 'Current time:' && date"
```

### Check Filterlog Process

**See if filterlog has file open:**
```bash
ssh root@192.168.1.1 "FILTERLOG_PID=\$(pgrep filterlog) && lsof -p \$FILTERLOG_PID | grep filter.log"
```

**If no output:** filterlog has no file handle (PROBLEM!)

### Check pfBlocker Data in InfluxDB

**From SIEM server:**
```bash
influx -host 192.168.210.10 -database pfsense -execute "SELECT COUNT(*) FROM tail_ip_block_log WHERE time > now() - 1h"
```

**Expected:** Should show count > 0 if pfBlocker is blocking traffic  
**Problem:** Returns empty if no data in last hour

---

## Integration with Project Status Script

Add to `scripts/status.sh` after pfSense forwarder checks:

```bash
echo ""
echo "=== pfSense Filterlog Health ==="

# Check filter.log age
echo -n "Filter.log freshness... "
FILTER_LOG_STAT=$(ssh -o BatchMode=yes ${PFSENSE_USER}@${PFSENSE_HOST} "stat -f %m /var/log/filter.log" 2>/dev/null)
if [ $? -eq 0 ]; then
    NOW=$(date +%s)
    AGE=$((NOW - FILTER_LOG_STAT))
    if [ $AGE -gt 600 ]; then
        echo -e "${RED}✗${NC} Stale (${AGE}s old, threshold 600s)"
        echo "  → Run: ssh root@${PFSENSE_HOST} 'php -r \"require_once(\\\"/etc/inc/filter.inc\\\"); filter_configure(); system_syslogd_start();\"'"
        ((ERRORS++))
    else
        echo -e "${GREEN}✓${NC} Current (${AGE}s old)"
    fi
else
    echo -e "${RED}✗${NC} Could not check"
    ((ERRORS++))
fi

# Check filterlog has file open
echo -n "Filterlog file handle... "
HAS_HANDLE=$(ssh -o BatchMode=yes ${PFSENSE_USER}@${PFSENSE_HOST} "lsof -p \$(pgrep filterlog) 2>/dev/null | grep -c filter.log" 2>/dev/null)
if [ "$HAS_HANDLE" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} Open"
else
    echo -e "${RED}✗${NC} No file handle"
    echo "  → Filterlog daemon needs restart"
    ((ERRORS++))
fi

# Check recent pfBlocker data
echo -n "pfBlocker data (last hour)... "
PFBLOCKER_COUNT=$(curl -s "http://${SIEM_HOST}:8086/query?db=pfsense&q=SELECT+COUNT(*)+FROM+tail_ip_block_log+WHERE+time+%3E+now()-1h" | jq -r '.results[0].series[0].values[0][1] // 0' 2>/dev/null)
if [ "$PFBLOCKER_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓${NC} ${PFBLOCKER_COUNT} events"
else
    echo -e "${YELLOW}⚠${NC} No events (might be no blocked traffic)"
fi
```

---

## Recommended Implementation

**For Production Use:**

1. **GUI Change (Now):**
   - Increase log rotation size to 2000KB in Status → System Logs → Settings
   - Reduces rotation frequency from ~every 2 hours to ~every 8 hours

2. **Monitoring (This Week):**
   - Add filter.log age check to `scripts/status.sh`
   - Run status.sh via cron every 5 minutes
   - Alert if filter.log is stale

3. **Auto-Remediation (Optional):**
   - Extend status.sh to auto-restart filterlog if stale
   - OR add pfSense cron job to check and restart

4. **Documentation:**
   - Add troubleshooting section to README
   - Reference this document for future occurrences

---

## Testing the Fix

After implementing monitoring/auto-restart:

1. **Manually trigger rotation:**
   ```bash
   ssh root@192.168.1.1 "newsyslog -f /var/log/filter.log"
   ```

2. **Wait 5-10 minutes** (for monitoring to detect)

3. **Verify auto-restart occurred:**
   ```bash
   ssh root@192.168.1.1 "tail -20 /var/log/filter.log"
   ```

4. **Should see:** Recent firewall events

5. **Check monitoring logs:**
   ```bash
   tail /var/log/pfsense-filterlog-check.log
   ```

---

## Related Issues

- [pfSense Bug #8555](https://redmine.pfsense.org/issues/8555) - filterlog doesn't handle log rotation
- Known issue since pfSense 2.4.x
- No official fix as of pfSense 2.8.1
- Workaround: Manual restart or automated monitoring

---

## Quick Reference

**Check if broken:**
```bash
ssh root@192.168.1.1 "wc -l /var/log/filter.log"
# If only 1 line (newsyslog message), it's broken
```

**Quick fix:**
```bash
ssh root@192.168.1.1 "php -r 'require_once(\"/etc/inc/filter.inc\"); filter_configure(); system_syslogd_start();'"
```

**Verify fixed:**
```bash
ssh root@192.168.1.1 "tail -f /var/log/filter.log"
# Should see live firewall events
```
