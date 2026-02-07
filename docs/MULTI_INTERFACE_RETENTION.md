# Multi-Interface Support & Data Retention

## Overview

This document covers two important features added to the Suricata monitoring stack:

1. **Multi-Interface Support** - Monitor multiple network interfaces running Suricata simultaneously
2. **Data Retention** - Automatic deletion of old indices to manage disk space

---

## Multi-Interface Support

### What Changed

The Python forwarder now:
- **Monitors ALL interfaces** running Suricata (not just the first one found)
- **Uses threading** to follow multiple EVE JSON logs simultaneously
- **Adds interface field** to each event: `suricata.interface`
- **Auto-restarts threads** if they crash for any reason

### Interface Detection

The forwarder automatically finds all Suricata instances:
```
/var/log/suricata/igb0_12345/eve.json  → interface: igb0
/var/log/suricata/igb1_67890/eve.json  → interface: igb1
/var/log/suricata/lagg0_99999/eve.json → interface: lagg0
```

### Deployment

Use the same deployment script - it automatically handles multiple interfaces:

```bash
./deploy-pfsense-forwarder.sh PFSENSE_IP SIEM_IP
```

Example:
```bash
./deploy-pfsense-forwarder.sh 192.168.1.1 192.168.210.10
```

### Testing Multi-Interface Setup

Check which interfaces are being monitored:

```bash
./scripts/test-multi-interface.sh PFSENSE_IP
```

Or manually on pfSense:
```bash
# See forwarder process
ps aux | grep forward-suricata-eve-python.py

# Check syslog for startup message
grep "suricata-forwarder" /var/log/system.log | tail -5
```

You should see: `Found N interface(s) to monitor`

### Using Interface Field in Grafana

You can now filter by interface in Grafana queries:

**Filter to specific interface:**
```
suricata.interface.keyword: "igb0"
```

**Count by interface:**
```
{
  "type": "terms",
  "field": "suricata.interface.keyword",
  "size": 10
}
```

**Panel Examples:**
- **Pie Chart** - Distribution by interface
- **Table** - Top events per interface
- **Time Series** - Alert count per interface over time

---

## Data Retention (90 Days)

### What Changed

OpenSearch now automatically deletes indices older than 90 days using Index State Management (ISM).

### How It Works

1. **Policy Applied**: All `suricata-*` indices use the `delete-after-90d` policy
2. **Age Check**: OpenSearch checks index ages every few minutes
3. **Automatic Deletion**: Indices older than 90 days are deleted automatically
4. **No Manual Cleanup**: Set it and forget it

### Current Configuration

- **Retention Period**: 90 days
- **Index Patterns**: `suricata-*` and `pfblockerng-*`
- **Policy Name**: `delete-after-90d`
- **Status**: Active on all current indices

> **Note:** The same retention policy should be applied to both `suricata-*` and `pfblockerng-*` indices. If you only applied it to `suricata-*`, extend it:
> ```bash
> # Apply retention policy to pfBlockerNG indices
> curl -s http://192.168.210.10:9200/_plugins/_ism/add/pfblockerng-* \
>   -H 'Content-Type: application/json' \
>   -d '{"policy_id": "delete-after-90d"}'
> ```

### Verify Retention Policy

Check policy status:
```bash
curl -s http://192.168.210.10:9200/_plugins/_ism/explain/suricata-* | python3 -m json.tool
```

Check all policies:
```bash
curl -s http://192.168.210.10:9200/_plugins/_ism/policies | python3 -m json.tool
```

### Change Retention Period

Re-run the configuration script with different days:

```bash
# Change to 30 days
./scripts/configure-retention-policy.sh 30

# Change to 180 days (6 months)
./scripts/configure-retention-policy.sh 180

# Change to 365 days (1 year)
./scripts/configure-retention-policy.sh 365
```

The script will:
1. Delete the old policy
2. Create new policy with updated retention
3. Apply to all existing indices
4. Apply to future indices automatically

### Storage Estimates

Based on current rates (~30k events/day = 10.5 MB/day):

| Retention | Storage Required |
|-----------|------------------|
| 7 days    | ~74 MB          |
| 30 days   | ~315 MB         |
| 90 days   | ~945 MB         |
| 180 days  | ~1.9 GB         |
| 365 days  | ~3.8 GB         |

**Note:** With multiple interfaces, multiply these estimates by the number of interfaces.

### Manual Index Management

List all indices with sizes:
```bash
curl -s http://192.168.210.10:9200/_cat/indices/suricata-*?v&s=index
```

Manually delete old index (emergency only):
```bash
curl -X DELETE http://192.168.210.10:9200/suricata-2024.08.01
```

---

## Troubleshooting

### Multi-Interface Issues

**Forwarder not starting:**
```bash
# Check syslog on pfSense
ssh root@PFSENSE_IP 'tail -20 /var/log/system.log | grep suricata-forwarder'
```

**Only one interface monitored:**
- Old forwarder version still running
- Deploy updated forwarder: `./deploy-pfsense-forwarder.sh PFSENSE_IP SIEM_IP`

**Interface field missing in events:**
- Logstash not updated with new config
- Update Logstash config: see CONFIGURATION.md
- Restart Logstash: `sudo systemctl restart logstash`

### Retention Policy Issues

**Indices not being deleted:**
```bash
# Check ISM explain for specific index
curl -s http://192.168.210.10:9200/_plugins/_ism/explain/suricata-2024.08.01 | python3 -m json.tool
```

**Policy not applied to new indices:**
```bash
# Re-apply policy to all indices
./scripts/configure-retention-policy.sh 90
```

**Want to keep old data before enabling retention:**
```bash
# Export old indices before deletion
curl -s http://192.168.210.10:9200/suricata-2024.08.01/_search?size=10000 > old-data.json
```

---

## Implementation Details

### Python Forwarder Changes

Key improvements in `forward-suricata-eve-python.py`:

1. **Thread per Interface**: Each EVE JSON file gets its own thread
2. **Shared Socket**: All threads use same UDP socket (thread-safe)
3. **JSON Enhancement**: Adds `suricata_interface` field before sending
4. **Auto-Recovery**: Main thread restarts dead threads
5. **Interface Extraction**: Parses interface name from log path

### Logstash Changes

Added to `logstash-suricata.conf`:

```ruby
# Extract suricata_interface if present
if raw.key?("suricata_interface")
  event.set("[suricata][interface]", raw.delete("suricata_interface"))
end
```

This moves `suricata_interface` from raw JSON to structured field `suricata.interface`.

### ISM Policy Structure

The retention policy has two states:

1. **active** - Default state, checks age every execution
2. **delete** - Triggered when `min_index_age: 90d` is met

Policy applies to all indices matching `suricata-*` pattern automatically.

---

## Related Documentation

- [INSTALL_PFSENSE_FORWARDER.md](INSTALL_PFSENSE_FORWARDER.md) - Forwarder deployment
- [CONFIGURATION.md](CONFIGURATION.md) - Logstash configuration details
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
- [scripts/README.md](../scripts/README.md) - Utility scripts

---

## Quick Reference Commands

```bash
# Deploy updated multi-interface forwarder
./deploy-pfsense-forwarder.sh PFSENSE_IP SIEM_IP

# Test multi-interface detection
./scripts/test-multi-interface.sh PFSENSE_IP

# Configure 90-day retention
./scripts/configure-retention-policy.sh 90

# Check retention policy status
curl -s http://192.168.210.10:9200/_plugins/_ism/policies/delete-after-90d | python3 -m json.tool

# View events by interface in OpenSearch
curl -s http://192.168.210.10:9200/suricata-*/_search -H 'Content-Type: application/json' -d '{
  "size": 0,
  "aggs": {
    "by_interface": {
      "terms": {"field": "suricata.interface.keyword"}
    }
  }
}'
```
