# Critical OpenSearch Configuration

## The Midnight UTC Problem

### Symptom
Dashboard stops receiving new data at exactly **midnight UTC** (7 PM EST). Last event shows timestamp `23:59:59`.

### Root Cause
OpenSearch has `action.auto_create_index` set to `false` by default. This prevents automatic creation of new daily indices.

When Logstash tries to write events to a non-existent index (e.g., `suricata-2025.11.26`), or Telegraf tries to write pfBlockerNG data to a non-existent index (e.g., `pfblockerng-2025.11.26`), it fails with:
```
index_not_found_exception: no such index [suricata-2025.11.26]
```

**Logstash does NOT retry** - it silently drops ALL events.

### Why This Happens
1. Logstash uses daily index pattern: `suricata-%{+YYYY.MM.dd}`
2. At midnight UTC, the date changes (e.g., `2025.11.25` → `2025.11.26`)
3. Logstash/Telegraf tries to write to the new index
4. OpenSearch rejects the write because auto-create is disabled
5. ALL events are lost until index is manually created

## The Solution

### Automated Fix (Recommended)
Run the installer script during initial setup:

```bash
OPENSEARCH_HOST=192.168.210.10 ./scripts/install-opensearch-config.sh
```

This script:
1. ✅ Applies Suricata index template with geo_point mappings
2. ✅ Applies pfBlockerNG index template with keyword mappings
3. ✅ Enables auto-create for `suricata-*` and `pfblockerng-*` indices
4. ✅ Verifies configuration works
5. ✅ Creates initial index

### Manual Fix

#### 1. Enable Auto-Create
```bash
curl -XPUT "http://192.168.210.10:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }'
```

#### 2. Create Today's Index
```bash
TODAY=$(date -u +%Y.%m.%d)
curl -XPUT "http://192.168.210.10:9200/suricata-${TODAY}" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    }
  }'
```

#### 3. Verify Setting
```bash
curl -s "http://192.168.210.10:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"
```

Expected output:
```json
{
  "persistent": {
    "action": {
      "auto_create_index": "pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }
}
```

## Verification

### Check for the Problem
```bash
# Check if auto-create is disabled
curl -s "http://192.168.210.10:9200/_cluster/settings" | jq '.persistent.action.auto_create_index'

# If it returns null or "false", you have the problem
```

### Check Logstash Errors
```bash
ssh chiefgyk3d@192.168.210.10 'journalctl -u logstash --since "10 minutes ago" | grep index_not_found'
```

If you see errors like:
```
Could not index event to OpenSearch. {:status=>404, :action=>["index", {:_index=>"suricata-2025.11.26"
```

The index doesn't exist and auto-create is disabled.

### Verify Fix is Working
```bash
# 1. Check the setting is enabled
curl -s "http://192.168.210.10:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"

# 2. Check indices exist
curl -s "http://192.168.210.10:9200/_cat/indices/suricata-*?v&s=index"

# 3. Verify today's index exists
TODAY=$(date -u +%Y.%m.%d)
curl -s "http://192.168.210.10:9200/suricata-${TODAY}" | jq .

# 4. Check event count is increasing
curl -s "http://192.168.210.10:9200/suricata-*/_count" | jq '.count'
sleep 10
curl -s "http://192.168.210.10:9200/suricata-*/_count" | jq '.count'
# Count should increase
```

## Why Use `action.auto_create_index` Pattern?

The setting accepts a comma-separated list of index patterns:
- `pfblockerng-*` - pfBlockerNG events (via Telegraf opensearch output)
- `suricata-*` - Our Suricata events (via Logstash)
- `.monitoring-*` - OpenSearch monitoring indices
- `.watches` - Alerting watches
- `.triggered_watches` - Alert triggers
- `.watcher-history-*` - Alert history
- `.ml-*` - Machine learning indices

This allows these indices to auto-create while keeping auto-create disabled for everything else (security best practice).

## Alternative: Enable Auto-Create Globally

⚠️ **Not recommended for production** - less secure

```bash
curl -XPUT "http://192.168.210.10:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "true"
    }
  }'
```

## Emergency Recovery

If you discover the problem after midnight and have lost events:

```bash
# 1. Create today's index immediately
TODAY=$(date -u +%Y.%m.%d)
curl -XPUT "http://192.168.210.10:9200/suricata-${TODAY}" \
  -H 'Content-Type: application/json' \
  -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}'

# 2. Enable auto-create
curl -XPUT "http://192.168.210.10:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{"persistent":{"action.auto_create_index":"pfblockerng-*,suricata-*,.monitoring-*"}}'

# 3. Verify data is flowing
sleep 10
curl -s "http://192.168.210.10:9200/suricata-${TODAY}/_count" | jq '.count'
```

**Note**: Events written during the downtime are LOST. The forwarder uses tail -f behavior (starts at EOF), so it only forwards events written AFTER it starts. Historical events in the Suricata log files are not backfilled.

## Prevention Checklist

✅ Run `install-opensearch-config.sh` during initial setup  
✅ Verify auto-create is enabled after installation  
✅ Add monitoring for event flow (alert if count stops increasing)  
✅ Test the configuration by manually checking at midnight UTC  
✅ Document the OpenSearch URL in your runbook  

## Troubleshooting

### Problem: Setting doesn't persist after OpenSearch restart
**Cause**: Using `transient` instead of `persistent` settings  
**Fix**: Always use `persistent` settings block (as shown above)

### Problem: Template not applying to new indices
**Cause**: Index created before template or template priority too low  
**Fix**: Delete and recreate index, or apply template with higher priority:
```bash
curl -XPUT "http://192.168.210.10:9200/_index_template/suricata-template" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-index-template.json
```

### Problem: Geo map not working on new indices
**Cause**: Template not applied, missing geo_point mapping  
**Fix**: Verify template with:
```bash
curl -s "http://192.168.210.10:9200/suricata-2025.11.26/_mapping" | \
  jq '.["suricata-2025.11.26"].mappings.properties.suricata.properties.eve.properties.geoip_src.properties.location.type'
```

Should return: `"geo_point"`

## References

- [OpenSearch Documentation: Index Auto-Create](https://opensearch.org/docs/latest/api-reference/index-apis/create-index/)
- [Logstash OpenSearch Output Plugin](https://github.com/opensearch-project/logstash-output-opensearch)
- [Index Templates](https://opensearch.org/docs/latest/im-plugin/index-templates/)

## Support

If you encounter this issue in production:

1. **Immediate**: Create today's index manually (see Emergency Recovery)
2. **Short-term**: Enable auto-create setting
3. **Long-term**: Add monitoring/alerting for event flow
4. **Best practice**: Run installer script on all deployments

This configuration is **CRITICAL** for production deployments. Do not skip it!
