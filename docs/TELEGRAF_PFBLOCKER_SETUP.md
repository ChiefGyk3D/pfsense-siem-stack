# Telegraf pfBlocker Panel Setup

## Issue
The 8 pfBlocker Detail panels in the Telegraf dashboard show no data.

## Root Cause
The pfBlocker panels query InfluxDB measurements that come from Telegraf's **tail input plugin** reading pfBlockerNG log files:
- `tail_ip_block_log` - IP block events
- `tail_dnsbl_log` - DNS block list events

## Requirements

### 1. pfBlockerNG Must Be Installed
The panels require pfBlockerNG package to be installed and active on pfSense:
```bash
# On pfSense, check if installed
pkg info | grep pfblocker
```

### 2. Telegraf Configuration Required
Telegraf on pfSense needs tail input configuration added to monitor pfBlocker logs.

Add to `/usr/local/etc/telegraf.conf`:

```toml
# pfBlocker IP Block Log
[[inputs.tail]]
  files = ["/var/log/pfblockerng/ip_block.log"]
  from_beginning = false
  pipe = false
  
  data_format = "grok"
  grok_patterns = [
    '%{SYSLOGTIMESTAMP:timestamp} %{WORD:action},%{IPORHOST:direction},%{IPORHOST:interface},%{WORD:protocol},%{IPORHOST:src_ip},%{IPORHOST:dest_ip},%{NUMBER:src_port},%{NUMBER:dest_port},%{WORD:tcp_flags},%{NUMBER:protocolid},%{NUMBER:length},%{GREEDYDATA:feed_name}'
  ]
  
  grok_timezone = "Local"
  
  [inputs.tail.tags]
    tail_file = "ip_block_log"

# pfBlocker DNSBL Log
[[inputs.tail]]
  files = ["/var/log/pfblockerng/dnsbl.log"]
  from_beginning = false
  pipe = false
  
  data_format = "grok"
  grok_patterns = [
    '%{SYSLOGTIMESTAMP:timestamp},%{WORD:blockmethod},%{IPORHOST:domain},%{IPORHOST:src_ip},%{GREEDYDATA:feed_name}'
  ]
  
  grok_timezone = "Local"
  
  [inputs.tail.tags]
    tail_file = "dnsbl_log"
```

### 3. Restart Telegraf
After configuration changes:
```bash
# On pfSense
service telegraf restart
```

### 4. Verify Data in InfluxDB
Check if measurements exist:
```bash
# On SIEM server
influx -database telegraf -execute "SHOW MEASUREMENTS" | grep -E "tail_ip_block_log|tail_dnsbl_log"
```

Check recent data:
```bash
influx -database telegraf -execute "SELECT * FROM tail_ip_block_log ORDER BY time DESC LIMIT 5"
influx -database telegraf -execute "SELECT * FROM tail_dnsbl_log ORDER BY time DESC LIMIT 5"
```

## Dashboard Panels
The "pfBlocker Details" section contains 8 panels:
1. **IP - Top 10 Blocked - IN (By Host/Port)** - Inbound IP blocks by source
2. **Port - Top 10 Blocked - IN** - Most blocked inbound ports
3. **Top 10 DNSBL Feeds** - DNS blocklist feed statistics
4. **Port - Top 10 Blocked - OUT** - Most blocked outbound ports
5. **IP - Top 10 Blocked - OUT (By Host/Port)** - Outbound IP blocks by destination
6. **IP - Top 10 Blocked - IN (By Host/Protocol)** - Inbound blocks by protocol
7. **Protocol - Top 10 Blocked - IN** - Protocol distribution inbound
8. **Protocol - Top 10 Blocked - OUT** - Protocol distribution outbound

## Troubleshooting

### No pfBlockerNG Installed
If you don't use pfBlockerNG:
- Panels will remain empty
- Consider hiding the "pfBlocker Details" row in the dashboard
- pfBlockerNG is optional - other dashboard sections still work

### pfBlockerNG Installed But No Data
1. **Check log files exist:**
   ```bash
   ls -lh /var/log/pfblockerng/
   ```

2. **Verify logging is enabled** in pfSense UI:
   - Firewall → pfBlockerNG → Settings
   - Enable "Enable Logging"
   - Save and Apply

3. **Check log format** matches grok pattern:
   ```bash
   tail -5 /var/log/pfblockerng/ip_block.log
   tail -5 /var/log/pfblockerng/dnsbl.log
   ```

4. **Test Telegraf parsing:**
   ```bash
   telegraf --config /usr/local/etc/telegraf.conf --test --input-filter tail
   ```

### Data Stopped Flowing
1. Check Telegraf is running:
   ```bash
   service telegraf status
   ```

2. Check for errors:
   ```bash
   tail -50 /var/log/telegraf.log
   ```

3. Verify log files are being written:
   ```bash
   ls -lh /var/log/pfblockerng/*.log
   stat /var/log/pfblockerng/ip_block.log
   ```

## Alternative: Hide pfBlocker Panels
If you don't need pfBlocker monitoring:
1. Open Grafana dashboard
2. Click row title "pfBlocker Details"
3. Click gear icon → Remove Row
4. Save dashboard

Or collapse the row by clicking the row title.
