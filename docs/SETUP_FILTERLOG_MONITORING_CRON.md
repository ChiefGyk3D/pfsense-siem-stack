# Setup pfSense Filterlog Monitoring Cron Job

This guide shows how to add automated monitoring for the filterlog rotation bug directly in pfSense using the built-in Cron package.

## Prerequisites

The **Cron** package must be installed on pfSense.

### Install Cron Package (if not already installed)

1. Go to **System → Package Manager → Available Packages**
2. Search for **"cron"**
3. Click **Install** next to "Cron"
4. Wait for installation to complete

## Setup Monitoring Cron Job

### Option 1: Auto-Restart if Filter.log is Stale (Recommended)

This cron job checks if filter.log hasn't been updated in 10+ minutes and automatically restarts filterlog.

**Steps:**

1. Go to **Services → Cron** in pfSense web interface

2. Click **Add** button (+ icon in bottom right)

3. Configure the following settings:

   | Field | Value | Notes |
   |-------|-------|-------|
   | **Minute** | `*/10` | Every 10 minutes |
   | **Hour** | `*` | Every hour |
   | **Day of Month** | `*` | Every day |
   | **Month** | `*` | Every month |
   | **Day of Week** | `*` | Every day of week |
   | **User** | `root` | Must be root |
   | **Command** | See below | Full command |

4. **Command to use:**

   ```bash
   /usr/bin/find /var/log/filter.log -mmin +10 -exec sh -c 'php -r "require_once(\"/etc/inc/filter.inc\"); filter_configure(); system_syslogd_start();" && php -r "require_once(\"/usr/local/pkg/pfblockerng/pfblockerng.inc\"); pfblockerng_sync_on_changes();"' \; 2>&1 | logger -t filterlog-monitor
   ```

5. Click **Save**

6. The cron job is now active

**What This Does:**
- Runs every 10 minutes
- Checks if `/var/log/filter.log` hasn't been modified in 10+ minutes (`-mmin +10`)
- If stale, restarts filterlog and pfBlockerNG logging
- Logs output to syslog with tag `filterlog-monitor`

**Verify It's Working:**

After adding, check the cron list:
```bash
# SSH to pfSense
ssh root@192.168.1.1
crontab -l | grep filterlog
```

Check syslog for activity:
```bash
grep filterlog-monitor /var/log/system.log
```

---

### Option 2: Simple Periodic Restart (Nuclear Option)

If you want to just restart filterlog periodically regardless of state (less elegant but bulletproof):

**Cron Settings:**

| Field | Value |
|-------|-------|
| **Minute** | `5` |
| **Hour** | `*/4` |
| **Day of Month** | `*` |
| **Month** | `*` |
| **Day of Week** | `*` |
| **User** | `root` |
| **Command** | `php -r 'require_once("/etc/inc/filter.inc"); filter_configure(); system_syslogd_start();' 2>&1 \| logger -t filterlog-restart` |

**What This Does:**
- Restarts filterlog every 4 hours at 5 minutes past the hour (00:05, 04:05, 08:05, etc.)
- Ensures filterlog never gets stale for more than 4 hours
- Simple and reliable

---

## Testing the Cron Job

### Manual Test

After setting up the cron, you can manually test by killing the filterlog daemon:

```bash
# SSH to pfSense
ssh root@192.168.1.1

# Kill filterlog daemon to simulate the bug
pkill -9 filterlog

# Check filter.log - no new entries will appear
tail -f /var/log/filter.log &
TAIL_PID=$!

# Wait 10 minutes for cron to detect and fix

# Kill the tail
kill $TAIL_PID

# Should now see new firewall events
tail -10 /var/log/filter.log
```

**Alternative Quick Test - Manually Run the Cron Command:**

```bash
# SSH to pfSense
ssh root@192.168.1.1

# Run the cron command manually to test it works
/usr/bin/find /var/log/filter.log -mmin +10 -exec sh -c 'php -r "require_once(\"/etc/inc/filter.inc\"); filter_configure(); system_syslogd_start();" && php -r "require_once(\"/usr/local/pkg/pfblockerng/pfblockerng.inc\"); pfblockerng_sync_on_changes();"' \;

# If filter.log is NOT stale (less than 10 min old), nothing happens
# To force execution for testing, change +10 to +0:
/usr/bin/find /var/log/filter.log -mmin +0 -exec sh -c 'php -r "require_once(\"/etc/inc/filter.inc\"); filter_configure(); system_syslogd_start();" && php -r "require_once(\"/usr/local/pkg/pfblockerng/pfblockerng.inc\"); pfblockerng_sync_on_changes();"' \;

# Verify filter.log is now receiving events
tail -5 /var/log/filter.log
```

### Monitor Cron Execution

```bash
# Watch for cron execution in syslog
tail -f /var/log/system.log | grep -E 'filterlog-monitor|CRON'
```

### Verify Filter.log Health

```bash
# Check last modification time
ls -lh /var/log/filter.log
stat /var/log/filter.log

# Should be less than 10 minutes old
```

---

## Troubleshooting

### Cron Job Not Running

**Check if cron service is running:**
```bash
service cron status
ps aux | grep cron
```

**Verify crontab entry exists:**
```bash
crontab -l | grep filterlog
```

**Check for errors in syslog:**
```bash
grep -i cron /var/log/system.log | tail -20
```

### Cron Runs But Doesn't Fix Issue

**Check command syntax:**
```bash
# Test the command manually
/usr/bin/find /var/log/filter.log -mmin +10 -exec sh -c 'php -r "require_once(\"/etc/inc/filter.inc\"); filter_configure(); system_syslogd_start();" && php -r "require_once(\"/usr/local/pkg/pfblockerng/pfblockerng.inc\"); pfblockerng_sync_on_changes();"' \;
```

**Check command output:**
```bash
# Look for errors in syslog
grep filterlog-monitor /var/log/system.log | tail -10
```

### Filter.log Still Gets Stale

**Increase check frequency:**
- Change cron from `*/10` (every 10 min) to `*/5` (every 5 min)

**Decrease staleness threshold:**
- Change `-mmin +10` to `-mmin +5` (restart if 5+ minutes old)

---

## Alternative: SIEM-Side Monitoring

If you prefer to monitor from your SIEM server instead of on pfSense:

### Create Monitoring Script on SIEM Server

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

**Setup:**
```bash
# Make executable
chmod +x /usr/local/bin/check-pfsense-filterlog.sh

# Test it
/usr/local/bin/check-pfsense-filterlog.sh

# Add to SIEM server crontab
crontab -e

# Add this line:
*/5 * * * * /usr/local/bin/check-pfsense-filterlog.sh >> /var/log/pfsense-filterlog-check.log 2>&1
```

**Advantage:**
- Centralized monitoring on SIEM
- Can monitor multiple pfSense firewalls
- Logs kept with other monitoring data

**Disadvantage:**
- Requires SSH key authentication from SIEM to pfSense
- Slightly more complex setup

---

## Monitoring the Monitoring

### Check if Cron is Working

**View recent cron executions:**
```bash
# On pfSense
grep filterlog-monitor /var/log/system.log | tail -5
```

**Check for successful restarts:**
```bash
# Should see entries like:
# Nov 25 21:50:01 chiefgyk3d filterlog-monitor: filterlog restarted
```

### Integrate with Grafana (Optional)

You can create a Grafana dashboard panel to show filterlog health:

1. Add InfluxDB query to check filter.log age
2. Set alert if age > 10 minutes
3. Display on monitoring dashboard

**Example query (if you log metrics to InfluxDB):**
```sql
SELECT last("age_seconds") FROM "filterlog_age" WHERE time > now() - 1h
```

---

## Recommended Setup

For best results, use **both**:

1. **pfSense Cron** (Option 1): Auto-restart if stale every 10 min
2. **SIEM Monitoring**: Check via `status.sh` every 5 min

This provides:
- ✅ Automatic remediation (pfSense cron)
- ✅ Centralized visibility (SIEM monitoring)
- ✅ Alerting capability (via status.sh checks)
- ✅ Historical logging (SIEM logs)

---

## Summary

**Quick Setup (5 minutes):**

1. Install Cron package on pfSense (if not installed)
2. Go to Services → Cron
3. Add new cron job:
   - Every 10 minutes: `*/10`
   - User: `root`
   - Command: (copy from Option 1 above)
4. Save
5. Test by manually running the command (see Testing section above)

**Verify Working:**
```bash
# After 10 minutes, check filter.log
ssh root@192.168.1.1 "tail -10 /var/log/filter.log"
# Should show live firewall events, not just rotation message
```

**Monitor:**
```bash
# Check cron execution
ssh root@192.168.1.1 "grep filterlog-monitor /var/log/system.log"
```

That's it! The filterlog rotation bug will now automatically fix itself within 10 minutes of occurring.
