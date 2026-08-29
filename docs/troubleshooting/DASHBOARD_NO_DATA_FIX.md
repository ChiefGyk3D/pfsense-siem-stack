# Fixing "No Data" in Grafana Dashboard

## Problem Overview

The most common issue users face is Grafana dashboard panels showing "No Data" even though:
- ✅ Suricata is running and generating events
- ✅ Forwarder is sending data
- ✅ Logstash is receiving events  
- ✅ OpenSearch has documents

This guide explains the root causes and solutions.

## Root Causes

### 1. Datasource Variable Not Resolved

**Symptom**: ALL panels show "No Data"

**Cause**: Dashboard uses `${DS_OPENSEARCH}` variable but no datasource is configured

**How to identify**:
```bash
# Check if dashboard is using a variable
curl -s -u admin:admin "http://localhost:3000/api/dashboards/uid/suricata-complete" | \
  jq '.dashboard.panels[0].datasource'

# If you see: {"type": "grafana-opensearch-datasource", "uid": "${DS_OPENSEARCH}"}
# This is the problem!
```

**Fix**:
1. Get your actual datasource UID:
   ```bash
   curl -s -u admin:admin "http://localhost:3000/api/datasources" | \
     jq '.[] | select(.type == "grafana-opensearch-datasource") | {name, uid}'
   ```

2. Replace variable with actual UID in dashboard JSON:
   ```bash
   cd dashboards/
   sed 's/\${DS_OPENSEARCH}/bf53unpmdj0u8c/g' "Suricata IDS_IPS Dashboard.json" > "Suricata IDS_IPS Dashboard_fixed.json"
   ```
   (Replace `bf53unpmdj0u8c` with your actual UID)

3. Re-import dashboard:
   ```bash
   curl -X POST -H "Content-Type: application/json" -u admin:admin \
     "http://localhost:3000/api/dashboards/db" \
     -d @<(jq 'del(.id) | {dashboard: ., overwrite: true}' "Suricata IDS_IPS Dashboard_fixed.json")
   ```

### 2. Field Structure Mismatch

**Symptom**: Some panels work, others show "No Data"

**Cause**: Dashboard queries use different field paths than actual data structure

There are two possible data structures:

#### Flat Structure (RECOMMENDED)
```json
{
  "@timestamp": "2025-11-26T20:14:51.920Z",
  "event_type": "alert",
  "src_ip": "75.188.212.77",
  "dest_ip": "149.154.167.220",
  "alert": {
    "signature": "ET CINS Active Threat Intelligence",
    "severity": 3
  }
}
```
Dashboard queries: `event_type`, `src_ip`, `alert.signature`

#### Nested Structure (OLD - NOT RECOMMENDED)
```json
{
  "@timestamp": "2025-11-26T20:14:51.920Z",
  "suricata": {
    "eve": {
      "event_type": "alert",
      "src_ip": "75.188.212.77",
      "alert": {
        "signature": "ET CINS Active Threat Intelligence"
      }
    }
  }
}
```
Dashboard queries: `suricata.eve.event_type`, `suricata.eve.src_ip`

**How to identify which structure you have**:
```bash
curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | \
  jq '.hits.hits[0]._source | keys[0:10]'

# Flat structure: ["@timestamp", "event_type", "src_ip", "dest_ip", "alert"]
# Nested structure: ["@timestamp", "suricata"]
```

**Fix for nested → flat conversion**:

1. Update Logstash config (`/etc/logstash/conf.d/suricata.conf`):
   ```ruby
   filter {
     # Parse JSON directly to root level
     if [event][original] {
       json {
         source => "[event][original]"
       }
     } else if [message] {
       json {
         source => "message"
       }
     }
     
     # Handle timestamp
     if [timestamp] {
       date {
         match => [ "timestamp", "ISO8601" ]
         target => "@timestamp"
       }
     }
     
     mutate {
       remove_field => ["message", "[event][original]"]
     }
   }
   ```

2. Restart Logstash:
   ```bash
   sudo systemctl restart logstash
   ```

3. Wait for new data to flow with flat structure

4. Update dashboard if needed (should already use flat structure)

### 3. Alert Events Not Forwarded

**Symptom**: DNS, TLS, HTTP panels work but alert panels empty

**Cause**: Forwarder starts tailing from EOF (end of file), missing historical alerts

**Why this happens**:
The forwarder uses `f.seek(0, 2)` to position at end of file. This is intentional - we don't want to re-send gigabytes of old logs every time the forwarder restarts. However, this means:
- Alerts that existed BEFORE forwarder started won't be indexed
- Only NEW alerts (after forwarder starts) will appear

**How to verify**:
```bash
# Check when forwarder started
ssh root@192.168.1.1 "ps -o lstart -p \$(pgrep -f forward-suricata)"

# Check alert timestamps in eve.json
ssh root@192.168.1.1 "grep '\"event_type\":\"alert\"' /var/log/suricata/suricata_*/eve.json | \
  jq -r '.timestamp' | sort"

# If all alerts are BEFORE forwarder start time, they won't be in OpenSearch
```

**Fix**:
Wait for NEW alerts to be generated, or trigger test alerts:
```bash
# Test with Telegram (if not blocked)
curl -s https://api.telegram.org > /dev/null

# Test with suspicious HTTP patterns
for i in {1..5}; do curl -s http://testmynids.org/uid/index.html > /dev/null; sleep 1; done
```

**Permanent solution - Add custom test rules**:
```bash
# On pfSense, add test rule
ssh root@192.168.1.1
echo 'alert http any any -> any any (msg:"TEST ALERT: HTTP Traffic Detected"; sid:9000001; rev:1;)' >> \
  /usr/local/etc/suricata/suricata_55721_ix0/rules/custom.rules

# Reload rules
/usr/local/bin/suricatasc -c 'reload-rules' /var/run/suricata-ctrl-socket-55721

# Generate test traffic
curl http://example.com
```

### 4. Time Range Issues

**Symptom**: Dashboard shows "No Data" with default 24h range, but data exists

**Cause**: 
- Logstash config changed recently (e.g., nested → flat)
- Old data (24 hours) is one structure, new data (5 minutes) is different structure
- Dashboard queries match only one structure

**How to identify**:
```bash
# Check data distribution
curl -s "http://localhost:9200/_search?size=0" -H 'Content-Type: application/json' \
  -d '{"aggs":{"has_nested":{"filter":{"exists":{"field":"suricata.eve.event_type"}}},"has_flat":{"filter":{"exists":{"field":"event_type"}}}}}'

# Example output:
# nested: 1,110,079 docs (98% of data)
# flat: 20,240 docs (2% of data - last few minutes)
```

**Fix**:
1. **Quick fix**: Adjust Grafana time range to match when new data started flowing
   - Change from "Last 24 hours" to "Last 5 minutes"
   - Gradually increase as more data accumulates

2. **Permanent fix**: Choose one structure and stick with it
   - Recommended: Flat structure (simpler, less nesting)
   - Update Logstash config to flatten
   - Wait for 24 hours of new flat data
   - OR reindex old data (advanced, see below)

### 5. IPS Mode - Drops vs Alerts

**Symptom**: Events flow but no alerts, using IPS mode

**Cause**: Rules set to `drop` action instead of `alert`

Suricata IPS mode can:
- DROP and log as `event_type: "drop"` 
- DROP and log as `event_type: "alert"` (with EVE alert logging enabled)
- ALERT without dropping

**How to identify**:
```bash
# Check rule actions
ssh root@192.168.1.1 "head -20 /usr/local/etc/suricata/suricata_*/rules/suricata.rules | grep -E '^(alert|drop)'"

# All drop? Rules are in IPS mode
# All alert? Rules are in IDS mode
```

**Fix**:
In pfSense GUI:
1. Go to **Services** > **Suricata** > **Interface: ix0 (WAN)**
2. Check **EVE Output Settings** tab
3. Ensure **Alert** is enabled in EVE log types
4. This makes drops also log as alerts for dashboard visibility

## Prevention

### Best Practices

1. **Use flat structure**: Simpler queries, easier debugging
2. **Deploy with setup.sh**: Ensures correct config from start
3. **Monitor forwarder**: Use `./scripts/status.sh` regularly
4. **Test after changes**: Always verify dashboard after Logstash config updates
5. **Document datasource UID**: Save it in config.env for easy reference

### Monitoring Script

Add to cron:
```bash
# /etc/cron.hourly/check-suricata-dashboard
#!/bin/bash
ALERT_COUNT=$(curl -s "http://localhost:9200/suricata-*/_search?size=0" -H 'Content-Type: application/json' \
  -d '{"query":{"bool":{"must":[{"term":{"event_type.keyword":"alert"}},{"range":{"@timestamp":{"gte":"now-1h"}}}]}}}' | \
  jq '.hits.total.value')

if [ "$ALERT_COUNT" -eq 0 ]; then
  echo "WARNING: No alerts in last hour - check dashboard and forwarder"
  # Send notification
fi
```

## Verification

After fixes, verify everything works:

```bash
# 1. Check data structure
curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | \
  jq '.hits.hits[0]._source | keys'

# 2. Check recent alerts
curl -s "http://localhost:9200/suricata-*/_search?size=0" -H 'Content-Type: application/json' \
  -d '{"query":{"bool":{"must":[{"term":{"event_type.keyword":"alert"}},{"range":{"@timestamp":{"gte":"now-5m"}}}]}}}' | \
  jq '.hits.total.value'

# 3. Check datasource in dashboard
curl -s -u admin:admin "http://localhost:3000/api/dashboards/uid/suricata-complete" | \
  jq '.dashboard.panels[0].datasource.uid'

# 4. Open Grafana and verify panels load
# http://localhost:3000/d/suricata-complete
```

All panels should show data within your selected time range!

## Advanced: Reindexing Old Data

If you need historical data with new structure:

```bash
# Create reindex script
curl -X POST "http://localhost:9200/_reindex" -H 'Content-Type: application/json' -d'
{
  "source": {
    "index": "suricata-*",
    "query": {
      "exists": {
        "field": "suricata.eve.event_type"
      }
    }
  },
  "dest": {
    "index": "suricata-reindexed"
  },
  "script": {
    "source": "ctx._source = ctx._source.suricata.eve; ctx._source.remove(\"suricata\")",
    "lang": "painless"
  }
}
'

# Monitor progress
curl "http://localhost:9200/_tasks?detailed=true&actions=*reindex"
```

**Warning**: This can take hours for large indices!

## Summary

The "No Data" issue has multiple causes:
1. **Datasource variable not resolved** → Replace with actual UID
2. **Field structure mismatch** → Update Logstash to flatten
3. **Historical alerts not forwarded** → Wait for new alerts
4. **Time range too broad** → Narrow to recent data
5. **IPS mode logging** → Enable EVE alert output

Most issues are solved by:
- Using the provided Logstash config (flat structure)
- Fixing datasource UID in dashboard JSON
- Adjusting time range to match data availability

The dashboard itself works perfectly - it's all about data structure alignment!
