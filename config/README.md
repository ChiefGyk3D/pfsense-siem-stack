# Configuration Files

This directory contains the SIEM-side configuration files for the pfSense SIEM stack (Logstash pipeline, OpenSearch index templates) plus the Suricata SID tuning lists and a pfBlockerNG DNSBL whitelist that live on the pfSense side.

---

## 📋 Core Configuration Files

### logstash-suricata.conf

**Logstash pipeline for Suricata EVE JSON logs**

**Purpose:**
- Receives Suricata events via UDP from the pfSense forwarder
- Parses the JSON to **flat root-level fields** (`event_type`, `src_ip`, `dest_ip`, `in_iface`, `alert.signature`, `geoip_src.location`, ...). Nothing is nested under a `suricata.eve.*` prefix; the dashboards query the flat names.
- Indexes to OpenSearch with daily indices (`suricata-YYYY.MM.DD`)

**Deployment:**
```bash
sudo cp config/logstash-suricata.conf /etc/logstash/conf.d/suricata.conf
sudo systemctl restart logstash
```

**Configuration options:**
- `port => 5140` - UDP listen port (must match the forwarder)
- `hosts => ["http://localhost:9200"]` - OpenSearch endpoint
- `index => "suricata-%{[@metadata][index_date]}"` - Index naming pattern

**See inline comments** in the file for detailed documentation.

### opensearch-index-template.json

**OpenSearch index template for `suricata-*` indices** — installed as `_index_template/suricata-template`

**Purpose:**
- Defines field mappings (geo_point, keyword, ip, integer)
- Configures index settings (1 shard, 0 replicas, 5 s refresh)
- Ensures proper GeoIP mapping for geomap panels

**Deployment:**
```bash
# Automated (recommended) — applies both templates and the auto-create setting
./scripts/install-opensearch-config.sh

# Manual
curl -X PUT "http://localhost:9200/_index_template/suricata-template" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-index-template.json
```

**Key mappings (flat root-level fields):**
- `geoip_src.location` / `geoip_dest.location` - geo_point (for geomap)
- `in_iface`, `event_type`, `proto`, `alert.category`, `alert.action` - keyword (for aggregations)
- `alert.signature` - text with a `.keyword` sub-field; `alert.signature_id` - integer
- `src_ip`, `dest_ip` - ip

### opensearch-pfblockerng-template.json

**OpenSearch index template for `pfblockerng-*` indices** — installed as `_index_template/pfblockerng`

**Purpose:**
- Maps pfBlockerNG tag fields as `keyword` type for aggregations
- Uses `dynamic_templates` for `tag.*`, `tail_ip_block_log.*` and `tail_dnsbl_log.*` fields
- Ensures proper field types for the Grafana dashboard panels

**Deployment:**
```bash
# Automated (recommended)
./scripts/install-opensearch-config.sh

# Manual
curl -X PUT "http://localhost:9200/_index_template/pfblockerng" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-pfblockerng-template.json
```

**Data pipeline:** Telegraf `[[outputs.opensearch]]` on pfSense → OpenSearch `pfblockerng-*` indices. See [Telegraf pfBlockerNG Setup](../docs/pfsense/TELEGRAF_PFBLOCKER_SETUP.md).

> **Important:** Do NOT use `[[outputs.elasticsearch]]` for pfBlockerNG data — it is incompatible with OpenSearch 2.x. Use `[[outputs.opensearch]]` (Telegraf ≥ 1.28).

---

## 📄 Optional Configuration Files

### dnsbl_whitelist.txt

**DNS blocklist whitelist** - Domains to exclude from pfBlockerNG DNSBL blocking

**Usage:** Curated list of domains whitelisted in the maintainer's pfBlockerNG DNSBL configuration to prevent false positives for legitimate services (identity providers, CDNs, certificate validation, streaming, gaming, productivity tools, ...). Review it and remove anything you do not use before importing.

**Format:**
```
example.com
subdomain.example.com
.example.com    # wildcard
```

**Integration:** Firewall → pfBlockerNG → DNSBL → create a group with List Action *Whitelist* and paste the contents (or point it at the raw GitHub URL). The categories and the privacy notes behind them are explained in [docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md](../docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md#whitelisting-guide).

### pfBlockerNG guides (moved)

The pfBlockerNG feed catalog that used to live in this directory as `pfblockerng_optimization.md` is now [docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md](../docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md). The shorter strategy guide is [docs/pfsense/PFBLOCKERNG_OPTIMIZATION.md](../docs/pfsense/PFBLOCKERNG_OPTIMIZATION.md).

---

## 🗂️ Subdirectories

### sid/

**Suricata SID management lists** for the pfSense Suricata package:

```
config/sid/
├── README.md                       # What the lists do, how they were derived, how to build and apply your own
├── disable/disablesid.conf         # 218 SIDs that are never loaded (protocol anomalies, chat/P2P, INFO noise, ...)
├── drop/dropsid-minimal-safe.conf  # Six high-confidence classtypes to convert from alert to drop (start here)
├── drop/dropsid-comprehensive.conf # Tiered classtype drop list for more aggressive inline IPS
└── suppress/suppress.conf          # 2 example IP-specific suppressions (replace with your own)
```

They are applied through **Services → Suricata → SID Mgmt** (and the **Suppress** tab), which stores them in `config.xml` so they survive rule updates and pfSense upgrades. See [sid/README.md](sid/README.md).

---

## OpenSearch Configuration

### Index Templates

| Template name | Index pattern | Source file | Purpose |
|---------------|---------------|-------------|---------|
| `suricata-template` | `suricata-*` | `opensearch-index-template.json` | Suricata EVE events (geo_point, keyword, ip mappings) |
| `pfblockerng` | `pfblockerng-*` | `opensearch-pfblockerng-template.json` | pfBlockerNG IP block & DNSBL events (keyword mappings) |

Apply both:
```bash
./scripts/install-opensearch-config.sh
```

### Auto-Create Index Setting

**CRITICAL:** OpenSearch must be allowed to auto-create new daily indices for both `suricata-*` and `pfblockerng-*`, otherwise ingestion stops at midnight UTC when the index name changes. `install-opensearch-config.sh` sets this. To set or check it by hand:

```bash
curl -XPUT "http://<SIEM_IP>:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }'

curl -s "http://<SIEM_IP>:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"
```

Background, symptoms and emergency recovery: [docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md](../docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md).

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
sudo cp config/logstash-suricata.conf /etc/logstash/conf.d/suricata.conf

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
# Apply both index templates and the auto-create setting
./scripts/install-opensearch-config.sh

# Or manually:
curl -X PUT "http://localhost:9200/_index_template/suricata-template" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-index-template.json

curl -X PUT "http://localhost:9200/_index_template/pfblockerng" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-pfblockerng-template.json

# Verify templates
curl -s "http://localhost:9200/_index_template/suricata-template" | jq
curl -s "http://localhost:9200/_index_template/pfblockerng" | jq

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
echo '{"timestamp":"2025-11-27T12:00:00.000000-0500","event_type":"test","src_ip":"192.0.2.10","in_iface":"igc0"}' | nc -u localhost 5140

# Check in OpenSearch (wait 2-3 seconds)
curl -s "http://localhost:9200/suricata-*/_search?q=event_type:test" | jq '.hits.total.value'
```

**pfBlockerNG:**
```bash
curl -s "http://localhost:9200/pfblockerng-*/_count" | jq '.count'
```

### Verify Field Mapping

```bash
# geoip_src.location must be geo_point (flat structure, no suricata.eve prefix)
curl -s "http://localhost:9200/suricata-*/_mapping" | jq '.[].mappings.properties.geoip_src.properties.location'
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

**Also update the forwarder** on pfSense (`scripts/forward-suricata-eve.py`):
```python
LOGSTASH_PORT = 5140  # Match Logstash port
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

Then update the index pattern in `opensearch-index-template.json`, the `action.auto_create_index` list, and the Grafana datasource (`myindex-*`).

---

## 🐛 Troubleshooting

### Logstash Not Receiving Data

```bash
# Check UDP listener
sudo ss -ulnp | grep 5140

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

New daily index not auto-created. Re-run `./scripts/install-opensearch-config.sh` or apply the `action.auto_create_index` setting shown above, then check Logstash for `index_not_found_exception`. Full write-up: [docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md](../docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md).

### Index Template Not Applied

```bash
# Delete and recreate both templates
curl -X DELETE "http://localhost:9200/_index_template/suricata-template"
curl -X DELETE "http://localhost:9200/_index_template/pfblockerng"
./scripts/install-opensearch-config.sh

# Templates only apply to indices created after them. To remap existing
# indices you must delete them (WARNING: deletes data!)
curl -X DELETE "http://localhost:9200/suricata-*"
curl -X DELETE "http://localhost:9200/pfblockerng-*"
```

---

## 📚 Related Documentation

- **[Logstash Pipeline](logstash-suricata.conf)** - See inline comments for detailed config
- **[Suricata Template](opensearch-index-template.json)** - Suricata field mappings
- **[pfBlockerNG Template](opensearch-pfblockerng-template.json)** - pfBlockerNG field mappings
- **[SID Management](sid/README.md)** - Suricata disable/drop/suppress lists
- **[Telegraf pfBlockerNG Setup](../docs/pfsense/TELEGRAF_PFBLOCKER_SETUP.md)** - OpenSearch output config
- **[Configuration Guide](../docs/reference/CONFIGURATION.md)** - All config.env options
- **[SIEM Installation](../docs/install/INSTALL_SIEM_STACK.md)** - Full setup guide
- **[OpenSearch Auto-Create](../docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md)** - Fix midnight UTC issue
- **[Troubleshooting](../docs/troubleshooting/TROUBLESHOOTING.md)** - Common config issues

---

**For complete documentation, see [docs/DOCUMENTATION_INDEX.md](../docs/DOCUMENTATION_INDEX.md)**
