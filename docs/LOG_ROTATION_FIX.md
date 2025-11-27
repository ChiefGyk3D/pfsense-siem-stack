# Log Rotation Issue Resolution

## Problem

The Suricata EVE forwarder was getting stuck on rotated log files, causing missing data in Grafana dashboards.

**Symptoms:**
- Interface distribution panel missing data from specific interfaces (e.g., ix0/WAN)
- Events visible in local eve.json but not appearing in OpenSearch
- Forwarder showing old rotated files in `lsof` output (e.g., `eve.json.2025_1126_2040`)

**Root Cause:**
The forwarder used `open()` without inode tracking. When Suricata rotates logs:
1. Old `eve.json` → `eve.json.2025_1126_2040` (inode unchanged)
2. New `eve.json` created (new inode)
3. Forwarder continued reading old inode → no new data forwarded

## Solution: Inode Monitoring

The forwarder now checks file inodes on every read cycle and automatically reopens files when rotation is detected.

### Key Changes

**Before:**
```python
def tail_log_file(eve_log, sock):
    with open(eve_log, 'r') as f:
        f.seek(0, 2)  # Seek to end
        while True:
            line = f.readline()
            # Process line...
```

**After:**
```python
def tail_log_file(eve_log, sock):
    file_handle = None
    last_inode = None
    
    while True:
        # Check current inode
        current_inode = os.stat(eve_log).st_ino
        
        # Reopen if inode changed (rotation detected)
        if file_handle is None or last_inode != current_inode:
            if file_handle:
                file_handle.close()
            file_handle = open(eve_log, 'r')
            last_inode = current_inode
        
        line = file_handle.readline()
        # Process line...
```

### Benefits

1. **Automatic recovery** - No manual restart needed after log rotation
2. **No data loss** - Reads new file from start after rotation
3. **Continuous monitoring** - Checks inode every read cycle (0.1s when idle)
4. **Syslog alerts** - Logs rotation events for monitoring

## Deployment

```bash
# 1. Copy updated script to pfSense
scp scripts/forward-suricata-eve.py root@192.168.1.1:/usr/local/bin/

# 2. Make executable
ssh root@192.168.1.1 "chmod +x /usr/local/bin/forward-suricata-eve.py"

# 3. Restart forwarder
ssh root@192.168.1.1 "pkill -f forward-suricata-eve.py && sleep 2 && nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &"

# 4. Verify it's reading current files
ssh root@192.168.1.1 "ps aux | grep forward-suricata-eve.py | grep -v grep | awk '{print \$2}' | xargs -I {} lsof -p {} 2>/dev/null | grep 'eve.json' | grep -v '2025_'"
```

## Verification

### Check Forwarder is Monitoring Current Files

```bash
# Get forwarder PID and check open files
ssh root@192.168.1.1 "ps aux | grep forward-suricata-eve.py | grep -v grep | awk '{print \$2}' | xargs -I {} lsof -p {} 2>/dev/null | grep 'ix055721.*eve.json'"
```

**Good output (current file):**
```
python3.1 81984 root   6r  VREG ... /var/log/suricata/suricata_ix055721/eve.json
```

**Bad output (rotated file):**
```
python3.1 40727 root   6r  VREG ... /var/log/suricata/suricata_ix055721/eve.json.2025_1126_2040
```

### Check Data Flowing to OpenSearch

```bash
# Check last 2 minutes for interface distribution
curl -s -u admin:admin "http://192.168.210.10:9200/suricata-*/_search" -H 'Content-Type: application/json' -d '
{
  "size": 0,
  "query": {
    "range": {
      "@timestamp": {
        "gte": "now-2m",
        "lte": "now"
      }
    }
  },
  "aggs": {
    "interfaces": {
      "terms": {
        "field": "suricata.eve.in_iface.keyword",
        "size": 20
      }
    }
  }
}' | jq '{total: .hits.total.value, interfaces: .aggregations.interfaces.buckets}'
```

**Expected:** All active interfaces visible including ix0/WAN

### Monitor Rotation Events

```bash
# Check syslog for rotation messages
ssh root@192.168.1.1 "grep 'suricata-forwarder.*rotated' /var/log/system.log | tail -5"
```

### Check Debug Log

```bash
# View forwarder debug log
ssh root@192.168.1.1 "tail -50 /var/log/suricata_forwarder_debug.log | grep -i 'rotation\|inode'"
```

## Suricata Log Rotation Schedule

Suricata rotates logs based on:
- **Size**: When eve.json reaches size threshold (default: varies by pfSense Suricata package)
- **Time**: Scheduled rotations (check pfSense Suricata settings)

Check rotation settings:
```bash
ssh root@192.168.1.1 "grep -A 10 'max-file-size\|rotate' /usr/local/etc/suricata/suricata_*.yaml | head -30"
```

## Alternative Solutions (Not Implemented)

### Option 2: Systemd/rc.d Service with Restart Hook
Create service that restarts on Suricata rotation signal (requires more pfSense integration).

### Option 3: Use pyinotify
Monitor directory with inotify for CREATE events (adds dependency, more complex).

### Option 4: Scheduled Restart
Cron job to restart forwarder periodically (crude, causes brief data gaps).

**Why inode monitoring is best:**
- No dependencies
- Zero data loss
- Automatic recovery
- Works with existing Suricata setup

## Troubleshooting

### Forwarder Still Reading Old File

```bash
# Force restart
ssh root@192.168.1.1 "pkill -9 -f forward-suricata-eve.py && sleep 2 && nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &"
```

### Interface Still Missing Data

1. Check Suricata is running on that interface
2. Check local eve.json has recent events
3. Check forwarder is monitoring that file
4. Check OpenSearch for recent data from that interface

### Verify Fix is Working

Trigger a manual rotation and watch forwarder adapt:
```bash
# Cause rotation by sending HUP signal to Suricata
ssh root@192.168.1.1 "pkill -HUP -f 'suricata.*ix0'"

# Wait 5 seconds, then check forwarder still reading current file
sleep 5
ssh root@192.168.1.1 "ps aux | grep forward-suricata-eve.py | grep -v grep | awk '{print \$2}' | xargs -I {} lsof -p {} 2>/dev/null | grep 'ix055721.*eve.json' | grep -v '2025_'"
```

Should show the NEW `eve.json` (not dated file).

## Prevention

With this fix, the issue is **automatically prevented**. The forwarder will:
1. Detect rotation within 0.1 seconds
2. Reopen the new file
3. Continue forwarding without data loss
4. Log the rotation event for monitoring

No manual intervention required after log rotations.
