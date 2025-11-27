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

---

## Important: pfBlocker Log Permissions Issue

### The Problem

When the filterlog monitoring cron restarts pfBlockerNG (via `pfblockerng_sync_on_changes()`), it recreates the pfBlocker log files with restrictive permissions (`600` - owner only). This prevents Telegraf (running as user `telegraf`) from reading them, breaking the pfBlocker dashboard panels.

**Symptoms:**
- pfBlocker panels in Grafana show "No data"
- InfluxDB query returns empty: `SELECT * FROM tail_ip_block_log WHERE time > now() - 1h`
- Telegraf has no open file handles for pfBlocker logs: `lsof -p <telegraf_pid> | grep pfblockerng` returns nothing

**This will happen:**
- Every time the filterlog monitoring cron runs and restarts pfBlocker
- When pfBlockerNG package is updated
- When pfBlocker feeds are updated
- After system reboot
- When pfBlocker logs are rotated

### Solution Options

You need to implement ONE of these permanent fixes:

---

#### Option 1: Add Telegraf User to Necessary Groups

**How it works:** Add the `telegraf` user to the `proxy`, `wheel`, and `unbound` groups so it can read pfBlocker logs AND access `/dev/pf` for PF firewall statistics.

**Setup:**
```bash
# SSH to pfSense
ssh root@pfsense

# Add telegraf to groups
pw groupmod proxy -m telegraf    # For /dev/pf access (PF Information panel)
pw groupmod wheel -m telegraf    # For /var/log/pfblockerng/ip_block.log
pw groupmod unbound -m telegraf  # For /var/log/pfblockerng/dnsbl.log

# Verify group membership
id telegraf
# Should show: uid=884(telegraf) gid=884(telegraf) groups=884(telegraf),62(proxy),0(wheel),59(unbound)
```

**⚠️ CRITICAL: FreeBSD daemon doesn't inherit supplementary groups**

The standard `service telegraf restart` uses FreeBSD's `daemon` command which **does NOT** pick up supplementary groups by default. You have two options:

**Option A: Modify rc.d script (RECOMMENDED - survives restarts):**
```bash
# Backup original
cp /usr/local/etc/rc.d/telegraf /usr/local/etc/rc.d/telegraf.backup

# Edit the rc.d script
vi /usr/local/etc/rc.d/telegraf

# Find the line with daemon command (around line 50):
#     /usr/sbin/daemon -fcr -P ${pidfile} -u ${telegraf_user} -o ${logfile} \
# 
# Change it to include -g option with all groups:
#     /usr/sbin/daemon -fcr -P ${pidfile} -u ${telegraf_user} -g "telegraf,proxy,wheel,unbound" -o ${logfile} \

# Restart Telegraf
service telegraf onestop && service telegraf onestart

# Verify it's working - check for proxy group and pf data
ps -axo user,group,command | grep telegraf
sleep 30
# From SIEM: influx -host <ip> -database pfsense -execute "SELECT COUNT(*) FROM pf WHERE time > now() - 1m"
```

**Option B: Use su command instead (temporary - testing only):**
```bash
# Stop service
service telegraf onestop

# Start manually with su to inherit groups
su -m telegraf -c '/usr/local/bin/telegraf --config /usr/local/etc/telegraf.conf &'

# This won't survive reboot - use Option A for permanent fix
```

**Pros:**
- ✅ Clean security model (follows Unix group permissions)
- ✅ Works for ALL panels: pfBlocker logs AND PF Information
- ✅ No cron job overhead
- ✅ Works for all current and future pfBlocker logs
- ✅ Enables PF firewall statistics panel

**Cons:**
- ❌ Gives Telegraf access to ALL files readable by wheel/unbound/proxy groups
- ❌ Requires modifying rc.d script (may be overwritten by package updates)
- ❌ Requires manual SSH setup (can't configure via GUI)
- ❌ Standard `service` restart doesn't pick up groups without rc.d modification

**Best for:** Users who want proper permission model and are comfortable editing system files

**Note:** Without the proxy group, the "PF Information" dashboard panel will show "No data" because Telegraf can't access `/dev/pf` to run `pfctl` commands.

---

#### Option 2: Cron Job to Fix Permissions (RECOMMENDED)

**How it works:** A cron job runs every 5 minutes to ensure pfBlocker log files are world-readable AND `/dev/pf` is accessible by Telegraf.

**Setup via pfSense GUI:**

1. Go to **Services → Cron**
2. Click **Add** (+)
3. Configure:
   - **Minute:** `*/5`
   - **Hour:** `*`
   - **Day/Month/Week:** `*` (all)
   - **User:** `root`
   - **Command:**
     ```bash
     /bin/chmod 644 /var/log/pfblockerng/ip_block.log /var/log/pfblockerng/dnsbl.log 2>/dev/null; /bin/chmod 660 /dev/pf && /usr/sbin/chown root:proxy /dev/pf 2>/dev/null
     ```
4. Click **Save**

**What this fixes:**
- ✅ pfBlocker IP blocking logs (`ip_block.log`) - for pfBlocker panels
- ✅ pfBlocker DNS blocking logs (`dnsbl.log`) - for DNS panels
- ✅ PF device access (`/dev/pf`) - for **PF Information panel** (firewall statistics)

**Why /dev/pf permissions matter:**
- The PF Information panel uses Telegraf's `pf` plugin
- This plugin runs `pfctl -s info` to get firewall statistics
- `pfctl` needs read/write access to `/dev/pf` (normally `root:proxy` mode 660)
- Without this access, you'll see errors: `pfctl: /dev/pf: Permission denied`
- Telegraf user needs to be in `proxy` group (set once: `pw groupmod proxy -m telegraf`)

**Pros:**
- ✅ Simple to set up via GUI (no SSH required after initial group setup)
- ✅ Survives reboots (GUI-managed cron persists)
- ✅ Easy to verify and troubleshoot
- ✅ Minimal security impact (only affects specific files/devices)
- ✅ Works even if permissions are reset
- ✅ Fixes **ALL** Telegraf permission issues (pfBlocker + PF Information)
- ✅ No rc.d modifications needed

**Cons:**
- ❌ 5-minute delay between permission reset and fix
- ❌ Cron overhead (runs every 5 minutes, but command is very lightweight)
- ❌ Reactive rather than proactive
- ❌ Requires one-time SSH setup to add telegraf to proxy group

**Best for:** Most users - easy, GUI-configurable, reliable, complete solution

**One-time setup via SSH:**
```bash
# SSH to pfSense (only needed once)
ssh root@pfsense

# Add telegraf to proxy group for /dev/pf access
pw groupmod proxy -m telegraf

# Verify
id telegraf
# Should show groups including "proxy"
```

After adding this cron AND the one-time group membership, all Telegraf panels will work.

---

#### Option 3: Run Telegraf as Root

**How it works:** Change Telegraf to run as the `root` user instead of `telegraf` user.

**Setup:**
```bash
# SSH to pfSense
ssh root@pfsense

# Edit Telegraf rc file
vi /usr/local/etc/rc.d/telegraf

# Find line:
telegraf_user=${telegraf_user:-"telegraf"}

# Change to:
telegraf_user=${telegraf_user:-"root"}

# Restart Telegraf
service telegraf onestop && service telegraf onestart
```

**Pros:**
- ✅ Telegraf can read everything (no permission issues ever)
- ✅ No cron overhead
- ✅ Works immediately and permanently

**Cons:**
- ❌❌❌ **MAJOR SECURITY RISK** - Telegraf runs with full root privileges
- ❌❌❌ If Telegraf is compromised, attacker has root access
- ❌❌ Changes may be overwritten by pfSense/Telegraf package updates
- ❌ Against security best practices
- ❌ Telegraf doesn't need root for anything else

**Best for:** **NOT RECOMMENDED** - Security risk outweighs benefits

---

#### Option 4: Filesystem ACLs (Advanced)

**How it works:** Use FreeBSD Access Control Lists to grant the `telegraf` user specific read access to pfBlocker logs.

**Setup:**
```bash
# SSH to pfSense
ssh root@pfsense

# Set ACLs for telegraf user
setfacl -m u:telegraf:r /var/log/pfblockerng/ip_block.log
setfacl -m u:telegraf:r /var/log/pfblockerng/dnsbl.log

# Verify ACLs
getfacl /var/log/pfblockerng/ip_block.log
```

**Pros:**
- ✅ Granular security (telegraf only gets read access to these specific files)
- ✅ Best security model (principle of least privilege)
- ✅ No cron overhead
- ✅ Immediate effect

**Cons:**
- ❌❌ **ACLs are lost when files are recreated** (pfBlocker recreates logs, not truncates)
- ❌ Requires SSH access (not GUI-configurable)
- ❌ More complex to troubleshoot
- ❌ Need to reapply ACLs after every pfBlocker reload
- ❌ Would still need a cron job to reapply ACLs periodically

**Best for:** Advanced users, but still needs supplemental automation

---

### Recommended Solution: Option 2 (Cron Job) + /dev/pf Fix

For most users, **Option 2 (Cron Job) with /dev/pf permission fix** is the best choice because:

1. **Easy Setup:** Configure via GUI, no SSH needed
2. **Persistent:** Survives reboots and updates  
3. **Reliable:** Fixes permissions even if they're reset multiple times
4. **Low Risk:** Only affects specific log files and device
5. **Debuggable:** Easy to verify with `ls -l`
6. **Complete:** Fixes both pfBlocker logs AND PF Information panel

The 5-minute delay is acceptable because:
- pfBlocker data is historical analysis, not real-time alerting
- PF statistics are cumulative counters, not real-time events
- The filterlog monitoring cron runs every 10 minutes, so worst case is 5-minute gap
- Alternative solutions have worse trade-offs (rc.d doesn't support supplementary groups)

---

### Combined Setup: Filterlog + Permission Fix

When setting up both cron jobs, you'll have:

**Cron Job 1: Filterlog Monitoring** (every 10 minutes)
```bash
*/10 * * * * /usr/bin/find /var/log/filter.log -mmin +10 -exec sh -c 'php -r "require_once(\"/etc/inc/filter.inc\"); filter_configure(); system_syslogd_start();" && php -r "require_once(\"/usr/local/pkg/pfblockerng/pfblockerng.inc\"); pfblockerng_sync_on_changes();"' \; 2>&1 | logger -t filterlog-monitor
```

**Cron Job 2: pfBlocker Permission Fix** (every 5 minutes)
```bash
*/5 * * * * /bin/chmod 644 /var/log/pfblockerng/ip_block.log /var/log/pfblockerng/dnsbl.log 2>/dev/null
```

**Result:**
- Filterlog automatically restarts if stale
- pfBlocker logs automatically become readable
- Maximum 5-minute data gap if permissions reset
- All manageable via pfSense GUI

---

### Testing the Fix

After implementing your chosen solution:

**1. Trigger the problem:**
```bash
# SSH to pfSense
ssh root@pfsense

# Force pfBlocker to recreate logs with wrong permissions
php -r 'require_once("/usr/local/pkg/pfblockerng/pfblockerng.inc"); pfblockerng_sync_on_changes();'

# Check permissions (should be 600 - unreadable by telegraf)
ls -l /var/log/pfblockerng/ip_block.log
```

**2. Wait for fix:**
- **Option 1 (Groups):** Immediate - check `lsof -p $(pgrep telegraf) | grep pfblockerng`
- **Option 2 (Cron):** Wait 5 minutes, then check permissions with `ls -l`

**3. Verify Telegraf can read:**
```bash
# Check Telegraf has files open
lsof -p $(pgrep telegraf) | grep pfblockerng

# Should show:
# telegraf <PID> telegraf 6r VREG ... /var/log/pfblockerng/dnsbl.log
# telegraf <PID> telegraf 9r VREG ... /var/log/pfblockerng/ip_block.log
```

**4. Verify data in InfluxDB:**
```bash
# From SIEM server
influx -host 192.168.210.10 -database pfsense -execute "SELECT COUNT(*) FROM tail_ip_block_log WHERE time > now() - 1h"

# Should return count > 0
```

**5. Check Grafana:**
- Refresh the Telegraf dashboard
- pfBlocker panels should populate with data

---

### Troubleshooting

**Permissions keep resetting:**
- Option 1: Verify groups with `id telegraf` (should show wheel and unbound)
- Option 2: Check cron is running: `grep chmod /var/log/system.log`

**Telegraf still can't read logs:**
```bash
# Check what user Telegraf runs as
ps aux | grep telegraf

# If running as root, no permission issues
# If running as telegraf, verify permissions or group membership

# Test read access
su -m telegraf -c 'cat /var/log/pfblockerng/ip_block.log | head -1'
# Should output a log line, not "Permission denied"
```

**No data after fix:**
```bash
# Restart Telegraf to force re-read
service telegraf onestop && service telegraf onestart

# Wait 30 seconds and check
lsof -p $(pgrep telegraf) | grep pfblockerng
```

That's it! The filterlog rotation bug will now automatically fix itself within 10 minutes of occurring.
