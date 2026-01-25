# pfSense Forwarder Installation Guide

Complete guide for deploying the Python-based Suricata log forwarder on pfSense 2.8.1+.

## Prerequisites

- pfSense 2.8.1 or later (includes Python 3.11 and maxminddb)
- Suricata installed and running on at least one interface
- SSH access to pfSense (enable in System > Advanced > Secure Shell)
- Network connectivity between pfSense and SIEM server

> **Note**: No pip installation required! The forwarder uses `maxminddb` which is pre-installed with pfSense 2.8.1+ (via Suricata package).

## Overview

The forwarder consists of two components:
1. **Python Forwarder** (`forward-suricata-eve-python.py`) - Reads Suricata EVE JSON, enriches with GeoIP, sends to Logstash via UDP
2. **Watchdog Script** (`suricata-forwarder-watchdog.sh`) - Monitors forwarder and restarts if stopped

### Features
- **Multi-interface support**: Monitors ALL Suricata instances automatically
- **GeoIP enrichment**: Adds country/city data using maxminddb (no pip install needed)
- **Auto-restart**: Watchdog ensures forwarder stays running
- **Low overhead**: Uses ~2-5% CPU on typical deployments

## Quick Installation (Recommended)

The easiest way to install is using the scripts from this repository:

```bash
# From your workstation (not pfSense)
cd /path/to/pfsense-siem-stack

# Copy forwarder scripts to pfSense
scp scripts/forward-suricata-eve-python.py admin@YOUR_PFSENSE_IP:/usr/local/bin/
scp scripts/suricata-forwarder-watchdog.sh admin@YOUR_PFSENSE_IP:/usr/local/bin/

# Make executable
ssh admin@YOUR_PFSENSE_IP 'chmod +x /usr/local/bin/forward-suricata-eve-python.py /usr/local/bin/suricata-forwarder-watchdog.sh'

# Add watchdog to cron (runs every minute)
ssh admin@YOUR_PFSENSE_IP 'grep -q suricata-forwarder-watchdog /etc/crontab || echo "* * * * * root /usr/local/bin/suricata-forwarder-watchdog.sh" >> /etc/crontab'

# Restart cron and start forwarder
ssh admin@YOUR_PFSENSE_IP 'service cron restart && nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve-python.py > /dev/null 2>&1 &'

# Verify it's running
ssh admin@YOUR_PFSENSE_IP 'pgrep -fl forward-suricata'
```

The forwarder will:
- Auto-detect all Suricata EVE log files
- Load GeoIP database from pfSense (Suricata/pfBlockerNG/ntopng)
- Send enriched events to 192.168.210.10:5140 (default, configurable via environment variables)

## Configuration

### SIEM Server IP (Environment Variables)

The forwarder reads configuration from environment variables with sensible defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `SIEM_HOST` | `192.168.210.10` | SIEM/Logstash server IP |
| `LOGSTASH_UDP_PORT` | `5140` | UDP port for Logstash |
| `DEBUG_ENABLED` | `False` | Enable debug logging |
| `DEBUG_LOG` | `/var/log/suricata_forwarder_debug.log` | Debug log path |

To change the SIEM server, either:

**Option 1: Edit the script** (persistent)
```bash
ssh admin@YOUR_PFSENSE_IP
vi /usr/local/bin/forward-suricata-eve-python.py
# Change: GRAYLOG_SERVER = os.getenv("SIEM_HOST", "YOUR_NEW_IP")
```

**Option 2: Use environment variables** (for testing)
```bash
ssh admin@YOUR_PFSENSE_IP
SIEM_HOST=10.0.0.100 /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve-python.py
```

### GeoIP Database Priority

The forwarder searches for GeoIP databases in this order:
1. `/usr/local/share/ntopng/GeoLite2-City.mmdb` (ntopng - best for geomaps)
2. `/usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb`
3. `/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb` (Suricata default)
4. `/usr/local/share/GeoIP/GeoLite2-City.mmdb` (pfBlockerNG)
5. `/usr/local/share/GeoIP/GeoLite2-Country.mmdb`

**Country vs City database:**
- **Country**: Provides country_code, country_name, continent_code
- **City**: Also provides city_name, region_name, latitude/longitude (required for geomap panels)

## Manual Installation Steps

Replace `192.168.210.10` with your actual SIEM server IP.
If you prefer to install step-by-step instead of using the quick install above:

### 1. Copy Scripts to pfSense

```bash
# Copy Python forwarder
scp scripts/forward-suricata-eve-python.py admin@YOUR_PFSENSE_IP:/usr/local/bin/
ssh admin@YOUR_PFSENSE_IP 'chmod +x /usr/local/bin/forward-suricata-eve-python.py'

# Copy watchdog script
scp scripts/suricata-forwarder-watchdog.sh admin@YOUR_PFSENSE_IP:/usr/local/bin/
ssh admin@YOUR_PFSENSE_IP 'chmod +x /usr/local/bin/suricata-forwarder-watchdog.sh'
```

### 2. Start the Forwarder

```bash
# SSH to pfSense
ssh admin@YOUR_PFSENSE_IP

# Start forwarder in background
nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve-python.py > /dev/null 2>&1 &

# Verify it's running
pgrep -fl forward-suricata

# Check syslog for startup message
grep suricata-forwarder /var/log/system.log | tail -5
```

Expected output in syslog:
```
Jan 24 12:32:15 firewall suricata-forwarder: Loaded GeoIP database from /usr/local/share/GeoIP/GeoLite2-Country.mmdb
Jan 24 12:32:15 firewall suricata-forwarder: Starting forwarder for 13 interface(s) to 192.168.210.10:5140 (GeoIP: enabled)
```

### 3. Install Watchdog Cron Job

```bash
# SSH to pfSense
ssh admin@YOUR_PFSENSE_IP

# Add cron job directly to /etc/crontab (persists across reboots)
grep -q suricata-forwarder-watchdog /etc/crontab || echo "* * * * * root /usr/local/bin/suricata-forwarder-watchdog.sh" >> /etc/crontab

# Restart cron to pick up changes
service cron restart
```

**Alternative (GUI method)**: Use pfSense web UI at **System > Cron** to add the job.

## Verification

### Check Forwarder Status

```bash
# On pfSense
ssh admin@YOUR_PFSENSE_IP

# Check if process is running
pgrep -fl forward-suricata

# Check system log for forwarder messages
grep suricata-forwarder /var/log/system.log | tail -10

# Check watchdog is running (wait 1 minute after cron job installation)
grep -i watchdog /var/log/system.log | tail -5
```

### Enable Debug Mode (Troubleshooting)

```bash
# Kill current forwarder
pkill -f forward-suricata-eve-python.py

# Start with debug logging
DEBUG_ENABLED=true nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve-python.py > /dev/null 2>&1 &

# View debug log
tail -f /var/log/suricata_forwarder_debug.log
```

Debug output shows:
- GeoIP database loaded
- Each interface being monitored
- IPs being enriched with country codes
- Event counts per interface

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
