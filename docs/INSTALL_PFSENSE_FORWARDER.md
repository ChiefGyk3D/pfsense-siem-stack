# pfSense Forwarder Installation Guide

Complete guide for deploying the Python-based Suricata log forwarder on pfSense 2.8.1+.

## Prerequisites

- pfSense 2.8.1 or later (includes Python 3.11)
- Suricata installed and running on at least one interface
- SSH access to pfSense (enable in System > Advanced > Secure Shell)
- Network connectivity between pfSense and SIEM server

## Overview

The forwarder consists of two components:
1. **Python Forwarder** (`forward-suricata-eve-python.py`) - Reads Suricata EVE JSON and sends to Logstash via UDP
2. **Watchdog Script** (`suricata-forwarder-watchdog.sh`) - Monitors forwarder and restarts if stopped

## Installation Steps

### 1. Prepare pfSense Files

On your workstation, save these files:

**File: `forward-suricata-eve-python.py`**
```python
#!/usr/local/bin/python3.11
"""
Reliable Suricata EVE JSON forwarder for pfSense
Forwards Suricata EVE JSON events via UDP to Logstash
"""
import socket
import sys
import syslog
import time
import glob

GRAYLOG_SERVER = "192.168.210.10"  # CHANGE THIS to your SIEM server IP
GRAYLOG_PORT = 5140

def find_eve_log():
    """Find the Suricata EVE JSON log file"""
    matches = glob.glob("/var/log/suricata/*/eve.json")
    if matches:
        return matches[0]
    return None

def main():
    eve_log = find_eve_log()
    if not eve_log:
        syslog.syslog(syslog.LOG_ERR, "suricata-forwarder: No EVE JSON file found")
        sys.exit(1)
    
    syslog.syslog(syslog.LOG_INFO, f"suricata-forwarder: Starting Python forwarder from {eve_log} to {GRAYLOG_SERVER}:{GRAYLOG_PORT}")
    
    # Create UDP socket
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # Open and follow the log file
    with open(eve_log, 'r') as f:
        # Seek to end of file
        f.seek(0, 2)
        
        while True:
            line = f.readline()
            if line:
                # Send non-empty lines via UDP
                line = line.strip()
                if line:
                    try:
                        sock.sendto(line.encode('utf-8'), (GRAYLOG_SERVER, GRAYLOG_PORT))
                    except Exception as e:
                        syslog.syslog(syslog.LOG_WARNING, f"suricata-forwarder: Send error: {e}")
            else:
                # No new data, sleep briefly
                time.sleep(0.1)

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        syslog.syslog(syslog.LOG_INFO, "suricata-forwarder: Stopped")
        sys.exit(0)
    except Exception as e:
        syslog.syslog(syslog.LOG_ERR, f"suricata-forwarder: Fatal error: {e}")
        sys.exit(1)
```

**File: `forward-suricata-eve.sh`**
```bash
#!/bin/sh
# Simple wrapper to start the Python forwarder
exec /usr/local/bin/forward-suricata-eve-python.py
```

**File: `suricata-forwarder-watchdog.sh`**
```bash
#!/bin/sh
# Watchdog script to ensure the Suricata Python forwarder stays running
# Run from cron every minute: * * * * * /usr/local/bin/suricata-forwarder-watchdog.sh

FORWARDER_SCRIPT="/usr/local/bin/forward-suricata-eve.sh"
PYTHON_SCRIPT="/usr/local/bin/forward-suricata-eve-python.py"
LOG_TAG="suricata-forwarder-watchdog"

# Check if Python forwarder is running
PYTHON_PID=$(ps aux | grep "[f]orward-suricata-eve-python.py" | awk '{print $2}')

if [ -z "$PYTHON_PID" ]; then
    logger -t "$LOG_TAG" "Python forwarder not running, starting..."
    nohup "$FORWARDER_SCRIPT" > /dev/null 2>&1 &
    sleep 2
    PYTHON_PID=$(ps aux | grep "[f]orward-suricata-eve-python.py" | awk '{print $2}')
    if [ -n "$PYTHON_PID" ]; then
        logger -t "$LOG_TAG" "Python forwarder started successfully (PID: $PYTHON_PID)"
    else
        logger -t "$LOG_TAG" "ERROR: Failed to start Python forwarder"
    fi
else
    # Process is running - just log status
    CPU_USAGE=$(ps aux | grep "[f]orward-suricata-eve-python.py" | awk '{print $3}' | head -1)
    logger -t "$LOG_TAG" "Python forwarder running normally (PID: $PYTHON_PID, CPU: ${CPU_USAGE}%)"
fi
```

### 2. Configure SIEM Server IP

Edit `forward-suricata-eve-python.py` and change:
```python
GRAYLOG_SERVER = "192.168.210.10"  # CHANGE THIS
```

Replace `192.168.210.10` with your actual SIEM server IP.

### 3. Deploy to pfSense

```bash
# Copy Python forwarder
scp forward-suricata-eve-python.py root@YOUR_PFSENSE_IP:/usr/local/bin/
ssh root@YOUR_PFSENSE_IP 'chmod +x /usr/local/bin/forward-suricata-eve-python.py'

# Copy wrapper script
scp forward-suricata-eve.sh root@YOUR_PFSENSE_IP:/usr/local/bin/
ssh root@YOUR_PFSENSE_IP 'chmod +x /usr/local/bin/forward-suricata-eve.sh'

# Copy watchdog script
scp suricata-forwarder-watchdog.sh root@YOUR_PFSENSE_IP:/usr/local/bin/
ssh root@YOUR_PFSENSE_IP 'chmod +x /usr/local/bin/suricata-forwarder-watchdog.sh'
```

### 4. Start the Forwarder

```bash
# SSH to pfSense
ssh root@YOUR_PFSENSE_IP

# Start forwarder in background
nohup /usr/local/bin/forward-suricata-eve.sh > /dev/null 2>&1 &

# Verify it's running
ps aux | grep forward-suricata-eve-python.py | grep -v grep

# Check syslog for startup message
grep suricata-forwarder /var/log/system.log | tail -5
```

Expected output in syslog:
```
Nov 24 12:32:15 firewall suricata-forwarder: Starting Python forwarder from /var/log/suricata/suricata_ix055721/eve.json to 192.168.210.10:5140
```

### 5. Install Watchdog Cron Job

```bash
# SSH to pfSense
ssh root@YOUR_PFSENSE_IP

# Add cron job via pfSense web UI:
# 1. Go to System > Cron
# 2. Click "Add"
# 3. Configure:
#    - Minute: */1 (every minute)
#    - Hour: *
#    - Day of Month: *
#    - Month: *
#    - Day of Week: *
#    - User: root
#    - Command: /usr/local/bin/suricata-forwarder-watchdog.sh
# 4. Save

# Or add manually to crontab (not recommended, won't persist across reboots)
echo "* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh" | crontab -
```

**Important**: Use the pfSense web UI method to ensure the cron job persists across reboots and firmware updates.

## Verification

### Check Forwarder Status

```bash
# On pfSense
ssh root@YOUR_PFSENSE_IP

# Check if process is running
ps aux | grep forward-suricata-eve-python.py | grep -v grep

# Check system log for forwarder messages
grep suricata-forwarder /var/log/system.log | tail -10

# Check watchdog is running (wait 1 minute after cron job installation)
grep suricata-forwarder-watchdog /var/log/system.log | tail -5
```

### Verify Events Reaching SIEM

On your SIEM server:

```bash
# Check event count (should be increasing)
curl -s http://localhost:9200/suricata-*/_count | jq .count

# Check latest events
curl -s "http://localhost:9200/suricata-*/_search?size=3&sort=@timestamp:desc" | jq -r '.hits.hits[] | ._source | {timestamp: ."@timestamp", event_type: .suricata.eve.event_type, src_ip: .suricata.eve.src_ip}'

# Monitor real-time (press Ctrl+C to stop)
watch -n 2 'curl -s http://localhost:9200/suricata-*/_count | jq .count'
```

Expected output - event count should increase every few seconds:
```
{
  "timestamp": "2025-11-24T17:38:24.348Z",
  "event_type": "tls",
  "src_ip": "75.188.212.77"
}
```

### Test Event Flow

Generate test traffic on pfSense:

```bash
# From pfSense, generate DNS query
nslookup google.com

# From pfSense, generate HTTPS connection
fetch https://www.pfsense.org

# Wait 5 seconds
sleep 5

# Check SIEM for new events
curl -s "http://YOUR_SIEM_IP:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source.suricata.eve.event_type'
```

## Troubleshooting

### Forwarder Not Starting

```bash
# Check if Python exists
which python3.11
# Should output: /usr/local/bin/python3.11

# Try running manually to see errors
/usr/local/bin/forward-suricata-eve-python.py

# Check file permissions
ls -la /usr/local/bin/forward-suricata-eve*
# All should be executable (rwxr-xr-x)
```

### No Events in SIEM

```bash
# 1. Check if Suricata is generating events
tail -f /var/log/suricata/suricata_*/eve.json
# Should see JSON events appearing

# 2. Check if forwarder is actually running
ps aux | grep forward-suricata-eve-python.py

# 3. Test UDP connectivity from pfSense to SIEM
echo '{"test":"event"}' | nc -u -w1 YOUR_SIEM_IP 5140

# 4. Check SIEM received test event
curl -s "http://YOUR_SIEM_IP:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq
```

### Events Have Wrong Timestamp

The forwarder preserves Suricata's original timestamp. Check pfSense timezone:

```bash
# On pfSense
date
cat /etc/localtime

# Suricata timestamps include timezone offset
tail -1 /var/log/suricata/suricata_*/eve.json | jq .timestamp
```

### High CPU Usage

The Python forwarder should use <1% CPU normally. If higher:

```bash
# Check process stats
ps aux | grep forward-suricata-eve-python.py

# Check if Suricata is generating too many events
wc -l /var/log/suricata/suricata_*/eve.json

# Check network connectivity issues
netstat -s | grep -i udp
```

### Watchdog Not Running

```bash
# Check cron configuration
crontab -l -u root | grep watchdog

# Run watchdog manually to test
/usr/local/bin/suricata-forwarder-watchdog.sh

# Check syslog for watchdog output
grep watchdog /var/log/system.log | tail -20
```

## Maintenance

### Restart Forwarder

```bash
# SSH to pfSense
ssh root@YOUR_PFSENSE_IP

# Kill current process
pkill -f forward-suricata-eve-python.py

# Watchdog will auto-restart within 1 minute
# Or start manually:
nohup /usr/local/bin/forward-suricata-eve.sh > /dev/null 2>&1 &
```

### Update Configuration

```bash
# Edit Python script to change SIEM IP or port
vi /usr/local/bin/forward-suricata-eve-python.py

# Restart forwarder
pkill -f forward-suricata-eve-python.py
nohup /usr/local/bin/forward-suricata-eve.sh > /dev/null 2>&1 &
```

### Monitor Performance

```bash
# Check forwarder resource usage
ps aux | grep forward-suricata-eve-python.py

# Check network traffic
netstat -s | grep -A 10 "Udp:"

# Check event rate in syslog
grep suricata-forwarder-watchdog /var/log/system.log | tail -20
```

## Files Summary

| File | Location | Purpose |
|------|----------|---------|
| `forward-suricata-eve-python.py` | `/usr/local/bin/` | Main forwarder (Python) |
| `forward-suricata-eve.sh` | `/usr/local/bin/` | Wrapper script |
| `suricata-forwarder-watchdog.sh` | `/usr/local/bin/` | Monitoring/restart script |
| Cron job | System > Cron | Runs watchdog every minute |

## Next Steps

Continue to:
- **[Dashboard Installation](INSTALL_DASHBOARD.md)** - Set up Grafana dashboard
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues and solutions

## Why Python Instead of Shell Scripts?

The original approach used shell scripts with `tail | while read | nc` but this was **fundamentally broken** on pfSense:
- Shell while-read loops have buffering issues
- Pipe chaining corrupts data
- Manual tests worked but automated scripts failed
- Events arrived as single "X" characters

The Python solution:
- ✅ Single reliable process
- ✅ No pipe/buffer issues
- ✅ Proper error handling
- ✅ Built-in to pfSense 2.8.1+
- ✅ Easy to debug and maintain
