# Config Files

Configuration files for the pfSense Suricata → OpenSearch → Grafana pipeline.

All of these are deployed automatically by `./setup.sh`. You normally don't need to edit them manually.

## Files

| File | Purpose | Deployed To |
|------|---------|-------------|
| `logstash-suricata.conf` | Logstash pipeline — receives UDP from forwarder, parses JSON, writes to OpenSearch | `/etc/logstash/conf.d/suricata.conf` on SIEM server |
| `opensearch-index-template.json` | Index template — defines field types (keyword, ip, geo_point) for `suricata-*` indices | Applied via OpenSearch API |

## Field Structure

All Suricata fields are stored at the **root level** (flat structure):

```
event_type    → keyword
src_ip        → ip
dest_ip       → ip
in_iface      → keyword
proto         → keyword
alert.*       → nested (signature, category, severity, etc.)
dns.*         → nested (rrname, rrtype, etc.)
http.*        → nested (hostname, url, etc.)
tls.*         → nested (subject, issuer, etc.)
flow.*        → nested (bytes_toserver, pkts_toclient, etc.)
geoip_src.*   → geo enrichment (country_code, location as geo_point)
geoip_dest.*  → geo enrichment
```

> **Note:** Older versions of this project used a nested structure (`suricata.eve.*`). That is deprecated. The current flat structure is simpler and matches the Grafana dashboard queries directly.

## Manual Deployment

If `setup.sh` can't SSH to your SIEM server automatically:

```bash
# Deploy Logstash config
scp config/logstash-suricata.conf user@siem-server:/etc/logstash/conf.d/suricata.conf
# Edit the hosts line to point to your OpenSearch URL
ssh user@siem-server "sudo systemctl restart logstash"

# Apply index template
curl -XPUT "http://your-siem:9200/_index_template/suricata-template" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-index-template.json

# Enable auto-create (CRITICAL — without this, new daily indices won't be created)
curl -XPUT "http://your-siem:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{"persistent":{"action.auto_create_index":"suricata-*,.monitoring-*"}}'
```
