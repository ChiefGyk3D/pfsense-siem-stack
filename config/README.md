# Configuration Files

This directory contains all configuration files for the pfSense SIEM stack.

---

## 📋 Core Configuration Files

### logstash-suricata.conf

**Logstash pipeline for Suricata EVE JSON logs**

**Purpose:**
- Receives Suricata events via UDP from pfSense forwarder
- Parses JSON and nests under `suricata.eve.*` namespace
- Indexes to OpenSearch with daily indices (`suricata-YYYY.MM.DD`)

**Deployment:**
```bash
sudo cp config/logstash-suricata.conf /etc/logstash/conf.d/
sudo systemctl restart logstash
```

**Configuration options:**
- `port => 5140` - UDP listen port (must match forwarder)
- `hosts => ["http://localhost:9200"]` - OpenSearch endpoint
- `index => "suricata-%{[@metadata][index_date]}"` - Index naming pattern

**See inline comments** in the file for detailed documentation.

### opensearch-index-template.json

**OpenSearch index template for suricata-* indices**

**Purpose:**
- Defines field mappings (geo_point, keyword, nested)
- Configures analyzers and index settings
- Ensures proper GeoIP mapping for geomap panels

**Deployment:**
```bash
# Automated (recommended)
./scripts/install-opensearch-config.sh

# Manual
curl -X PUT "http://localhost:9200/_index_template/suricata" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-index-template.json
```

**Key mappings:**
- `suricata.eve.geoip_src.location` - geo_point (for geomap)
- `suricata.eve.in_iface` - keyword (for aggregations)
- `suricata.eve` - nested object (preserves structure)

### opensearch-pfblockerng-template.json

**OpenSearch index template for pfblockerng-* indices**

**Purpose:**
- Maps pfBlockerNG tag fields as `keyword` type for aggregations
- Uses `dynamic_templates` for `tag.*`, `tail_ip_block_log.*`, and `tail_dnsbl_log.*` fields
- Ensures proper field types for Grafana dashboard panels

**Deployment:**
```bash
# Automated (recommended) — applies both templates
./scripts/install-opensearch-config.sh

# Manual
curl -X PUT "http://localhost:9200/_index_template/pfblockerng-template" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-pfblockerng-template.json
```

**Data pipeline:** Telegraf `[[outputs.opensearch]]` → OpenSearch `pfblockerng-*` indices

> **Important:** Do NOT use `[[outputs.elasticsearch]]` for pfBlockerNG data — it is incompatible with OpenSearch 2.x. Use `[[outputs.opensearch]]` instead.

---

## 📄 Optional Configuration Files

### dnsbl_whitelist.txt

**DNS blocklist whitelist** - Domains to exclude from DNSBL blocking

**Usage:** Reference list of domains whitelisted in pfBlockerNG DNSBL suppression to prevent false positives for legitimate services (Microsoft login, Google accounts, certificate authorities, Datadog monitoring, etc.)

**Format:**
```
example.com
subdomain.example.com
.example.com    # wildcard
```

**Integration:** Applied in pfBlockerNG → DNSBL → DNSBL Whitelist

### pfblockerng_optimization.md

**PfBlockerNG configuration guide** - Moved to main docs

**See:** [docs/PFBLOCKERNG_OPTIMIZATION.md](../docs/PFBLOCKERNG_OPTIMIZATION.md)

---

## 🗂️ Subdirectories

### suricata_inline_drop/

**Suricata inline IPS drop configuration**

**Purpose:** Configuration files for enabling inline mode with drop rules

**Contents:**
- Drop rule examples
- Suricata.yaml snippets for inline mode
- Integration scripts

**Usage:** Apply drop rules dynamically based on alert severity

See subdirectory README for details.

---

## OpenSearch Configuration

### Index Templates

Two index templates are used:

| Template | Index Pattern | Purpose |
|----------|---------------|---------|
| `suricata-template` | `suricata-*` | Suricata EVE events (geo_point mapping) |
| `pfblockerng-template` | `pfblockerng-*` | pfBlockerNG IP block & DNSBL events |

Apply both templates:
```bash
./scripts/install-opensearch-config.sh
```

### Auto-Create Index Setting

**CRITICAL:** OpenSearch must be configured to auto-create new daily indices for both Suricata and pfBlockerNG.

By default, OpenSearch has `action.auto_create_index` set to `false`, which prevents automatic index creation even when an index template exists.

#### Enable auto-create:
```bash
curl -XPUT "http://192.168.210.10:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }'
```

#### Verify the setting:
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

### Troubleshooting

#### Symptom: Dashboard stops receiving data at midnight UTC

**Cause:** New daily index not being auto-created

**Check Logstash errors:**
```bash
ssh chiefgyk3d@192.168.210.10 'journalctl -u logstash --since "10 minutes ago" | grep index_not_found'
```

**Fix:** Verify auto-create setting includes both `pfblockerng-*` and `suricata-*`.

---

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
# Apply both index templates
./scripts/install-opensearch-config.sh

# Or manually:
curl -X PUT "http://localhost:9200/_index_template/suricata" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-index-template.json

curl -X PUT "http://localhost:9200/_index_template/pfblockerng-template" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-pfblockerng-template.json

# Verify templates
curl -s "http://localhost:9200/_index_template/suricata" | jq
curl -s "http://localhost:9200/_index_template/pfblockerng-template" | jq

# Check indices
curl -s "http://localhost:9200/_cat/indices/suricata-*?v"
curl -s "http://localhost:9200/_cat/indices/pfblockerng-*?v"
```

---

## 🔍 Validation

### Test Data Flow

**Suricata:**
```bash
# Send test event to Logstash
echo '{"timestamp":"2025-11-27T12:00:00.000000-0500","event_type":"test","src_ip":"1.2.3.4","in_iface":"ix0"}' | nc -u localhost 5140

# Check in OpenSearch (wait 2-3 seconds)
curl -s "http://localhost:9200/suricata-*/_search?q=event_type:test" | jq '.hits.total.value'
```

**pfBlockerNG:**
```bash
# Check pfBlockerNG events
curl -s "http://localhost:9200/pfblockerng-*/_count" | jq '.count'
```

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

**Fix:** Enable auto-create for both index patterns:

```bash
curl -XPUT "http://localhost:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }'
```

See [docs/OPENSEARCH_AUTO_CREATE.md](../docs/OPENSEARCH_AUTO_CREATE.md) for details.

### Index Template Not Applied

```bash
# Delete and recreate both templates
curl -X DELETE "http://localhost:9200/_index_template/suricata"
curl -X DELETE "http://localhost:9200/_index_template/pfblockerng-template"
./scripts/install-opensearch-config.sh

# Delete indices to reapply (WARNING: deletes data!)
curl -X DELETE "http://localhost:9200/suricata-*"
curl -X DELETE "http://localhost:9200/pfblockerng-*"

# Wait for new indices to be created with correct mapping
```

---

## 📚 Related Documentation

- **[Logstash Pipeline](logstash-suricata.conf)** - See inline comments for detailed config
- **[Suricata Template](opensearch-index-template.json)** - Suricata field mappings
- **[pfBlockerNG Template](opensearch-pfblockerng-template.json)** - pfBlockerNG field mappings
- **[Telegraf pfBlockerNG Setup](../docs/TELEGRAF_PFBLOCKER_SETUP.md)** - OpenSearch output config
- **[Configuration Guide](../docs/CONFIGURATION.md)** - All config.env options
- **[SIEM Installation](../docs/INSTALL_SIEM_STACK.md)** - Full setup guide
- **[OpenSearch Auto-Create](../docs/OPENSEARCH_AUTO_CREATE.md)** - Fix midnight UTC issue
- **[Troubleshooting](../docs/TROUBLESHOOTING.md)** - Common config issues

---

**For complete documentation, see [docs/DOCUMENTATION_INDEX.md](../docs/DOCUMENTATION_INDEX.md)**
