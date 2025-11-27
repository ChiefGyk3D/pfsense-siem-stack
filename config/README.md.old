# OpenSearch Configuration

## Index Template

The `opensearch-index-template.json` file defines the mapping for all `suricata-*` indices.

### Apply the template:
```bash
curl -XPUT "http://192.168.210.10:9200/_index_template/suricata-template" \
  -H 'Content-Type: application/json' \
  -d @opensearch-index-template.json
```

## Auto-Create Index Setting

**CRITICAL:** OpenSearch must be configured to auto-create new daily indices.

By default, OpenSearch has `action.auto_create_index` set to `false`, which prevents automatic index creation even when an index template exists. This causes Logstash to fail silently when writing to new daily indices (e.g., `suricata-2025.11.26`).

### Enable auto-create for Suricata indices:
```bash
curl -XPUT "http://192.168.210.10:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }'
```

### Verify the setting:
```bash
curl -s "http://192.168.210.10:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"
```

Expected output:
```json
{
  "persistent": {
    "action": {
      "auto_create_index": "suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }
}
```

## Troubleshooting

### Symptom: Dashboard stops receiving data at midnight UTC
**Cause:** New daily index not being auto-created

**Check Logstash errors:**
```bash
ssh chiefgyk3d@192.168.210.10 'journalctl -u logstash --since "10 minutes ago" | grep index_not_found'
```

**Fix:** Manually create the index and verify auto-create setting:
```bash
# Get current date in UTC
date -u

# Create today's index (adjust date as needed)
curl -XPUT "http://192.168.210.10:9200/suricata-2025.11.26" \
  -H 'Content-Type: application/json' \
  -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}'

# Verify auto-create setting is enabled
curl -s "http://192.168.210.10:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"
```

## Logstash Configuration

The `logstash-suricata.conf` file configures Logstash to:
- Listen on UDP port 5140 for Suricata events
- Parse timestamps
- Forward to OpenSearch with daily index pattern `suricata-%{+YYYY.MM.dd}`

Apply configuration:
```bash
sudo cp logstash-suricata.conf /etc/logstash/conf.d/
sudo systemctl restart logstash
```
