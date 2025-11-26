# Suricata Forwarder - Solution Summary

## Problem
The original shell script forwarder using `tail -F | while read | nc` was fundamentally broken on pfSense:
- Shell script while-read loops had buffering/pipe issues
- Events arrived as single "X" characters or null messages
- Manual netcat tests worked, but automated scripts failed
- Multiple rewrites (v2, socat, awk) all produced same failure

## Root Cause
pfSense shell scripting has limitations with:
- Buffering in while-read loops
- IFS handling
- Pipe chaining with tail/nc/while combinations

The `message` field was null but `event.original` contained valid JSON (277 bytes), proving data WAS arriving but being corrupted by the shell script's while loop processing.

## Solution
**Replaced shell script with Python-based forwarder** using `/usr/local/bin/python3.11`

### Python Forwarder (`forward-suricata-eve-python.py`)
- **Single process**: No complex pipes or while loops
- **Reliable**: Direct file reading with `f.readline()` and `f.seek()`
- **Simple UDP sending**: Python socket library `sendto()`
- **Proper logging**: Uses syslog for status messages
- **Error handling**: Try/except blocks for network errors
- **Auto-detects**: Finds eve.json via glob pattern

### Logstash Configuration Update
Modified `/etc/logstash/conf.d/suricata.conf` to parse from `[event][original]` field:
- UDP codec => plain populates `event.original` but not always `message`
- Added fallback to parse from `message` if `event.original` not present
- This ensures compatibility with both direct UDP input and potential future sources

### Watchdog Script Update
Updated `suricata-forwarder-watchdog.sh` to monitor Python process:
- Checks for `forward-suricata-eve-python.py` process
- Restarts if not running
- Logs CPU usage and status every minute
- Runs via cron: `* * * * *` (every minute)

## Results
✅ **14,929 total events** (up from 9,386)
✅ **NO `_jsonparsefailure` tags** - all parsing successful
✅ **All event types working**: TLS (6,177), QUIC (5,069), DNS (2,180), HTTP (549), MQTT (504), fileinfo (251), alerts (49)
✅ **Proper field structure**: `suricata.eve.event_type`, `suricata.eve.src_ip`, `suricata.eve.dest_ip`, etc.
✅ **Single reliable process**: No multiple tail/nc/while processes
✅ **Dashboard displaying data**: http://192.168.210.10:3000/d/suricata-complete/suricata-ids-ips-dashboard

## Files Deployed to pfSense (192.168.210.1)
1. `/usr/local/bin/forward-suricata-eve-python.py` - Main Python forwarder (executable)
2. `/usr/local/bin/forward-suricata-eve.sh` - Wrapper script to start Python forwarder
3. `/usr/local/bin/suricata-forwarder-watchdog.sh` - Watchdog monitor script
4. Cron job: `* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh`

## Files on SIEM Server (192.168.210.10)
1. `/etc/logstash/conf.d/suricata.conf` - Updated to parse from event.original
2. Logstash restarted and processing events correctly

## Key Lessons
1. **Shell scripts on pfSense are unreliable** for complex pipe/loop operations
2. **Python is available** on pfSense 2.8.1+ (`/usr/local/bin/python3.11`)
3. **Use Python for reliability** instead of shell scripts for data processing
4. **UDP input behavior**: Logstash `codec => plain` populates `event.original` but `message` may be null
5. **Always test end-to-end**: Manual tests proved pipeline worked, but automated script had different behavior

## Monitoring
Check forwarder status:
```bash
ssh root@192.168.210.1 'ps aux | grep forward-suricata-eve-python.py | grep -v grep'
```

Check syslog for watchdog messages:
```bash
ssh root@192.168.210.1 'grep suricata-forwarder-watchdog /var/log/system.log | tail -5'
```

Check event count in OpenSearch:
```bash
ssh chiefgyk3d@192.168.210.10 'curl -s http://localhost:9200/suricata-*/_count | jq .count'
```

Check latest events:
```bash
ssh chiefgyk3d@192.168.210.10 'curl -s "http://localhost:9200/suricata-*/_search?size=3&sort=@timestamp:desc" | jq ".hits.hits[]._source | {timestamp, event_type: .suricata.eve.event_type, src: .suricata.eve.src_ip, dest: .suricata.eve.dest_ip}"'
```

## Dashboard Access
http://192.168.210.10:3000/d/suricata-complete/suricata-ids-ips-dashboard
- 12 panels showing event types, protocols, IPs, ports, DNS, TLS, HTTP, alerts
- 24-hour time range
- 30-second auto-refresh
