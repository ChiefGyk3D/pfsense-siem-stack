# Configuration Files# OpenSearch Configuration



This directory contains all configuration files for the pfSense SIEM stack.## Index Template



---The `opensearch-index-template.json` file defines the mapping for all `suricata-*` indices.



## 📋 Core Configuration Files### Apply the template:

```bash

### logstash-suricata.confcurl -XPUT "http://192.168.210.10:9200/_index_template/suricata-template" \

**Logstash pipeline for Suricata EVE JSON logs**  -H 'Content-Type: application/json' \

  -d @opensearch-index-template.json

**Purpose:**```

- Receives Suricata events via UDP from pfSense forwarder

- Parses JSON and nests under `suricata.eve.*` namespace## Auto-Create Index Setting

- Indexes to OpenSearch with daily indices (`suricata-YYYY.MM.DD`)

**CRITICAL:** OpenSearch must be configured to auto-create new daily indices.

**Deployment:**

```bashBy default, OpenSearch has `action.auto_create_index` set to `false`, which prevents automatic index creation even when an index template exists. This causes Logstash to fail silently when writing to new daily indices (e.g., `suricata-2025.11.26`).

sudo cp config/logstash-suricata.conf /etc/logstash/conf.d/

sudo systemctl restart logstash### Enable auto-create for Suricata indices:

``````bash

curl -XPUT "http://192.168.210.10:9200/_cluster/settings" \

**Configuration options:**  -H 'Content-Type: application/json' \

- `port => 5140` - UDP listen port (must match forwarder)  -d '{

- `hosts => ["http://localhost:9200"]` - OpenSearch endpoint    "persistent": {

- `index => "suricata-%{[@metadata][index_date]}"` - Index naming pattern      "action.auto_create_index": "suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"

    }

**See inline comments** in the file for detailed documentation.  }'

```

### opensearch-index-template.json

**OpenSearch index template for suricata-* indices**### Verify the setting:

```bash

**Purpose:**curl -s "http://192.168.210.10:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"

- Defines field mappings (geo_point, keyword, nested)```

- Configures analyzers and index settings

- Ensures proper GeoIP mapping for geomap panelsExpected output:

```json

**Deployment:**{

```bash  "persistent": {

# Automated (recommended)    "action": {

./scripts/install-opensearch-config.sh      "auto_create_index": "suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"

    }

# Manual  }

curl -X PUT "http://localhost:9200/_index_template/suricata" \}

  -H 'Content-Type: application/json' \```

  -d @config/opensearch-index-template.json

```## Troubleshooting



**Key mappings:**### Symptom: Dashboard stops receiving data at midnight UTC

- `suricata.eve.geoip_src.location` - geo_point (for geomap)**Cause:** New daily index not being auto-created

- `suricata.eve.in_iface` - keyword (for aggregations)

- `suricata.eve` - nested object (preserves structure)**Check Logstash errors:**

```bash

---ssh chiefgyk3d@192.168.210.10 'journalctl -u logstash --since "10 minutes ago" | grep index_not_found'

```

## 📄 Optional Configuration Files

**Fix:** Manually create the index and verify auto-create setting:

### dnsbl_whitelist.txt```bash

**DNS blocklist whitelist** - Domains to exclude from blocking# Get current date in UTC

date -u

**Usage:** Add legitimate domains that are incorrectly blocked

# Create today's index (adjust date as needed)

**Format:**curl -XPUT "http://192.168.210.10:9200/suricata-2025.11.26" \

```  -H 'Content-Type: application/json' \

example.com  -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}'

subdomain.example.com

```# Verify auto-create setting is enabled

curl -s "http://192.168.210.10:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"

**Integration:** Used by pfBlockerNG or custom DNS filtering```



### pfblockerng_optimization.md## Logstash Configuration

**PfBlockerNG configuration guide** - Moved to main docs

The `logstash-suricata.conf` file configures Logstash to:

**See:** [docs/PFBLOCKERNG_OPTIMIZATION.md](../docs/PFBLOCKERNG_OPTIMIZATION.md)- Listen on UDP port 5140 for Suricata events

- Parse timestamps

---- Forward to OpenSearch with daily index pattern `suricata-%{+YYYY.MM.dd}`



## 🗂️ SubdirectoriesApply configuration:

```bash

### suricata_inline_drop/sudo cp logstash-suricata.conf /etc/logstash/conf.d/

**Suricata inline IPS drop configuration**sudo systemctl restart logstash

```

**Purpose:** Configuration files for enabling inline mode with drop rules

**Contents:**
- Drop rule examples
- Suricata.yaml snippets for inline mode
- Integration scripts

**Usage:** Apply drop rules dynamically based on alert severity

See subdirectory README for details.

---

## ⚙️ Configuration Workflow

### Initial Setup

1. **Install SIEM stack:**
   ```bash
   sudo ./install.sh
   ```

2. **Configure environment:**
   ```bash
   cp config.env.example config.env
   nano config.env  # Set SIEM_HOST and PFSENSE_HOST
   ```

3. **Deploy configuration:**
   ```bash
   ./setup.sh  # Automated deployment
   ```

### Manual Configuration

**Logstash:**
```bash
# Copy config
sudo cp config/logstash-suricata.conf /etc/logstash/conf.d/

# Test config
sudo /usr/share/logstash/bin/logstash -f /etc/logstash/conf.d/suricata.conf --config.test_and_exit

# Restart
sudo systemctl restart logstash

# Verify
sudo systemctl status logstash
tail -f /var/log/logstash/logstash-plain.log
```

**OpenSearch:**
```bash
# Apply index template
curl -X PUT "http://localhost:9200/_index_template/suricata" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-index-template.json

# Verify template
curl -s "http://localhost:9200/_index_template/suricata" | jq

# Check indices
curl -s "http://localhost:9200/_cat/indices/suricata-*?v"
```

---

## 🔍 Validation

### Test Data Flow

```bash
# Send test event to Logstash
echo '{"timestamp":"2025-11-27T12:00:00.000000-0500","event_type":"test","src_ip":"1.2.3.4","in_iface":"ix0"}' | nc -u localhost 5140

# Check in OpenSearch (wait 2-3 seconds for indexing)
curl -s "http://localhost:9200/suricata-*/_search?q=event_type:test" | jq '.hits.total.value'
```

Expected: `1` (test event found)

### Verify Field Mapping

```bash
# Check suricata.eve.geoip_src.location is geo_point
curl -s "http://localhost:9200/suricata-*/_mapping" | jq '.[].mappings.properties.suricata.properties.eve.properties.geoip_src.properties.location'
```

Expected:
```json
{
  "type": "geo_point"
}
```

### Check Nested Structure

```bash
# Query nested field
curl -s "http://localhost:9200/suricata-*/_search" -H 'Content-Type: application/json' -d '
{
  "query": {"exists": {"field": "suricata.eve.event_type"}},
  "size": 1
}' | jq '.hits.hits[0]._source.suricata.eve | keys'
```

Expected: Array of Suricata fields (timestamp, event_type, src_ip, etc.)

---

## 🛠️ Customization

### Change Logstash UDP Port

Edit `config/logstash-suricata.conf`:
```
input {
  udp {
    port => 5140  # Change to your port
```

**Also update forwarder** on pfSense:
```python
GRAYLOG_PORT = 5140  # Match Logstash port
```

### Add Authentication to OpenSearch

Edit `config/logstash-suricata.conf`:
```
output {
  opensearch {
    hosts => ["http://localhost:9200"]
    user => "admin"           # Add username
    password => "admin"       # Add password
    ssl => true               # Enable SSL
```

### Change Index Naming

Edit `config/logstash-suricata.conf`:
```
output {
  opensearch {
    index => "myindex-%{+YYYY.MM.dd}"  # Custom prefix
```

**Also update Grafana queries:**
```
Index name: myindex-*
```

---

## 🐛 Troubleshooting

### Logstash Not Receiving Data

```bash
# Check UDP listener
sudo netstat -ulnp | grep 5140

# Check firewall
sudo ufw status | grep 5140

# Allow if needed
sudo ufw allow 5140/udp

# Test with tcpdump
sudo tcpdump -i any -n udp port 5140
```

### Events Not Appearing in OpenSearch

```bash
# Check Logstash logs
tail -f /var/log/logstash/logstash-plain.log | grep -i error

# Check pipeline stats
curl -s localhost:9600/_node/stats/pipelines | jq

# Verify OpenSearch reachable
curl -s http://localhost:9200/_cluster/health
```

### Dashboard Stops at Midnight UTC

**Cause:** New daily index not auto-created

**Fix:** Enable auto-create for suricata-* indices

```bash
curl -XPUT "http://localhost:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }'
```

See [docs/OPENSEARCH_AUTO_CREATE.md](../docs/OPENSEARCH_AUTO_CREATE.md) for details.

### Index Template Not Applied

```bash
# Delete and recreate template
curl -X DELETE "http://localhost:9200/_index_template/suricata"
./scripts/install-opensearch-config.sh

# Delete indices to reapply (WARNING: deletes data!)
curl -X DELETE "http://localhost:9200/suricata-*"

# Wait for new indices to be created with correct mapping
```

---

## 📚 Related Documentation

- **[Logstash Pipeline](logstash-suricata.conf)** - See inline comments for detailed config
- **[OpenSearch Template](opensearch-index-template.json)** - Field mappings
- **[Configuration Guide](../docs/CONFIGURATION.md)** - All config.env options
- **[SIEM Installation](../docs/INSTALL_SIEM_STACK.md)** - Full setup guide
- **[OpenSearch Auto-Create](../docs/OPENSEARCH_AUTO_CREATE.md)** - Fix midnight UTC issue
- **[Troubleshooting](../docs/TROUBLESHOOTING.md)** - Common config issues

---

**For complete documentation, see [docs/DOCUMENTATION_INDEX.md](../docs/DOCUMENTATION_INDEX.md)**
