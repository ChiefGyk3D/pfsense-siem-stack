# Telegraf pfBlockerNG Setup — OpenSearch Pipeline

## Overview

pfBlockerNG data (IP blocks and DNSBL events) is collected by Telegraf on pfSense and sent **directly to OpenSearch** using the `[[outputs.opensearch]]` plugin. This bypasses InfluxDB entirely for pfBlockerNG data, avoiding high-cardinality issues that plague time-series databases.

### Architecture

```
pfSense pfBlockerNG logs
  → Telegraf tail input (grok parsing)
    → Telegraf opensearch output
      → OpenSearch (pfblockerng-* indices)
        → Grafana (OpenSearch-pfBlockerNG datasource)
```

> **Note**: System metrics (CPU, RAM, interfaces, gateways) continue to flow through InfluxDB via Telegraf's standard `[[outputs.influxdb]]` output. Only pfBlockerNG data goes to OpenSearch.

## Prerequisites

1. **pfBlockerNG-devel** installed on pfSense (System → Package Manager)
2. **Telegraf** package installed on pfSense (System → Package Manager)
3. **OpenSearch** running on SIEM server with `pfblockerng-*` auto-create enabled
4. **Index template** applied (run `./scripts/install-opensearch-config.sh`)

## Telegraf Configuration on pfSense

Telegraf on pfSense is configured via the WebUI at **Services → Telegraf**. The raw config is stored base64-encoded in `/conf/config.xml` under `<telegraf_raw_config>`.

### Required: OpenSearch Output Plugin

Add this to Telegraf's **Additional Configuration** section on pfSense:

```toml
[[outputs.opensearch]]
  urls = ["http://<SIEM_IP>:9200"]
  index_name = "pfblockerng-{{.Time.Format \"2006.01.02\"}}"
  manage_template = false
  template_name = "pfblockerng"
  timeout = "5s"
  enable_gzip = true
  health_check_interval = "10s"
  namepass = ["tail_ip_block_log", "tail_dnsbl_log"]
```

Replace `<SIEM_IP>` with your SIEM server IP (e.g., `192.168.210.10`).

**Key fields:**
- `namepass`: Only sends pfBlockerNG measurements to OpenSearch (not system metrics)
- `manage_template = false`: We manage the index template ourselves
- `index_name`: Creates daily indices like `pfblockerng-2025.02.07`

> **Warning**: Do NOT use `[[outputs.elasticsearch]]` — it has version incompatibilities with OpenSearch 2.x. Telegraf ships with a dedicated `[[outputs.opensearch]]` plugin that works correctly.

### Required: Tail Inputs for pfBlockerNG Logs

Add these tail inputs to parse pfBlockerNG log files:

```toml
# pfBlocker IP Block Log
[[inputs.tail]]
  files = ["/var/log/pfblockerng/ip_block.log"]
  from_beginning = false
  pipe = false
  name_override = "tail_ip_block_log"
  watch_method = "inotify"

  data_format = "grok"
  grok_patterns = ['%{SYSLOGTIMESTAMP:timestamp:ts-syslog} %{WORD:action},%{WORD:direction:tag},%{WORD:interface},%{WORD:ip_version},%{WORD:protocolid},%{DATA:protocol:tag},%{IP:src_ip:tag},%{IP:dest_ip},%{NUMBER:src_port},%{NUMBER:dest_port:tag},%{NUMBER:rulenum},%{DATA:ip_alias_name},%{DATA:ip_evaluated},%{DATA:feed_name:tag},%{DATA:resolvedhostname},%{DATA:clienthostname},%{DATA:ASN},%{DATA:duplicateeventstatus},%{DATA:friendlyname},%{GREEDYDATA:geoip_code:tag}']
  grok_timezone = "Local"

# pfBlocker DNSBL Log
[[inputs.tail]]
  files = ["/var/log/pfblockerng/dnsbl.log"]
  from_beginning = false
  pipe = false
  name_override = "tail_dnsbl_log"
  watch_method = "inotify"

  data_format = "grok"
  grok_patterns = ['%{SYSLOGTIMESTAMP:timestamp:ts-syslog} %{WORD:blocktype},%{DATA:blocksubtype},%{DATA:tld:tag},%{DATA:domain},%{IP:src_ip:tag},%{DATA:blockmethod},%{DATA:blocklist:tag},%{DATA:feed_name:tag},%{DATA:duplicateeventstatus},%{GREEDYDATA:req_agent}']
  grok_timezone = "Local"
```

> **Important**: The `:tag` annotations (e.g., `src_ip:tag`) tell Telegraf to treat these fields as tags. For the OpenSearch output, this causes them to be nested under `tag.*` (e.g., `tag.src_ip`). All other fields go under the measurement name (e.g., `tail_ip_block_log.dest_ip`). The Grafana dashboard queries are built around this structure.

### Restart Telegraf

After configuration changes on pfSense:
```bash
# Via pfSense WebUI: Services → Telegraf → Save
# Or via SSH:
pfSsh.php playback svc restart telegraf
```

## OpenSearch Setup (SIEM Server)

### 1. Apply Index Template

The index template ensures all pfBlockerNG fields are mapped as `keyword` type for aggregation:

```bash
# Automated (recommended)
OPENSEARCH_HOST=<SIEM_IP> ./scripts/install-opensearch-config.sh

# Or manually:
curl -XPUT "http://localhost:9200/_index_template/pfblockerng" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-pfblockerng-template.json
```

### 2. Verify auto_create_index

Confirm `pfblockerng-*` is in the allowed list:

```bash
curl -s "http://localhost:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"
```

Expected output should include `pfblockerng-*`:
```json
{
  "persistent": {
    "action": {
      "auto_create_index": "pfblockerng-*,suricata-*,.monitoring-*,..."
    }
  }
}
```

If not, update it:
```bash
curl -XPUT "http://localhost:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }'
```

## Grafana Datasource

A dedicated OpenSearch datasource is used for pfBlockerNG data:

| Setting | Value |
|---------|-------|
| **Name** | OpenSearch-pfBlockerNG |
| **Type** | grafana-opensearch-datasource |
| **URL** | http://localhost:9200 |
| **Index** | pfblockerng-* |
| **Time field** | @timestamp |
| **Version** | 2.19.4 |

The `setup.sh` script creates this datasource automatically. To create manually:
1. Grafana → Configuration → Data Sources → Add data source
2. Search for "OpenSearch"
3. Fill in the settings above

## OpenSearch Field Structure

Telegraf's opensearch output nests data as follows:

### IP Block Events (`measurement_name: tail_ip_block_log`)

| Field Path | Type | Description |
|------------|------|-------------|
| `tag.src_ip` | keyword | Source IP (blocked) |
| `tag.dest_port` | keyword | Destination port |
| `tag.protocol` | keyword | Protocol (TCP/UDP/ICMP) |
| `tag.geoip_code` | keyword | Country code |
| `tag.feed_name` | keyword | Blocklist feed name |
| `tag.host` | keyword | pfSense hostname |
| `tail_ip_block_log.direction` | keyword | in/out |
| `tail_ip_block_log.dest_ip` | keyword | Destination IP |
| `tail_ip_block_log.src_port` | keyword | Source port |
| `tail_ip_block_log.action` | keyword | Block action |
| `tail_ip_block_log.interface` | keyword | Interface name |
| `tail_ip_block_log.ASN` | text/keyword | AS number |

### DNSBL Events (`measurement_name: tail_dnsbl_log`)

| Field Path | Type | Description |
|------------|------|-------------|
| `tag.src_ip` | keyword | Client IP making DNS request |
| `tag.tld` | keyword | Top-level domain blocked |
| `tag.feed_name` | keyword | DNSBL feed name |
| `tag.blocklist` | keyword | Blocklist name |
| `tag.host` | keyword | pfSense hostname |
| `tail_dnsbl_log.domain` | keyword | Full domain blocked |
| `tail_dnsbl_log.blockmethod` | keyword | Block method |
| `tail_dnsbl_log.blocktype` | keyword | Block type |
| `tail_dnsbl_log.req_agent` | text/keyword | User agent |

## Dashboard Panels

The pfSense System Dashboard (`pfsense_pfblockerng_system.json`) includes 16 pfBlockerNG panels, all using the OpenSearch-pfBlockerNG datasource:

### pfBlocker Stats Row
1. **IP - Top 10 Blocked - IN** — Source IPs blocked inbound
2. **IP - Top 10 Blocked - OUT** — Source IPs blocked outbound
3. **IP - Blocked Packet Stats** — Time series of IN vs OUT blocks
4. **IP - Blocked by GeoIP** — Blocks by country code
5. **DNSBL - Blocked Domain Queries** — Time series of DNS blocks
6. **DNSBL - Source IP Top 10** — Clients making most blocked DNS queries
7. **DNSBL - Top 10 Blocked Domains** — Most-blocked domains (TLD)

### pfBlocker Details Row
8. **IP - Top 10 IN (By Host/Port)** — Blocked IPs with port breakdown
9. **Port - Top 10 IN** — Most targeted inbound ports
10. **Top 10 DNSBL Feeds** — Most active DNSBL feeds
11. **Port - Top 10 OUT** — Most targeted outbound ports
12. **IP - Top 10 OUT (By Host/Port)** — Outbound blocks with port breakdown
13. **IP - Top 10 IN (By Host/Protocol)** — Inbound blocks with protocol breakdown
14. **Protocol - Top 10 IN** — Protocol distribution for inbound blocks
15. **Protocol - Top 10 OUT** — Protocol distribution for outbound blocks
16. **IP - Top 10 OUT (By Host/Protocol)** — Outbound blocks with protocol breakdown

## Verification

### Check Data is Flowing

```bash
# Count total events
curl -s "http://localhost:9200/pfblockerng-*/_count" | jq '.count'

# Check latest event
curl -s "http://localhost:9200/pfblockerng-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source'

# Check field mappings are keyword
curl -s "http://localhost:9200/pfblockerng-*/_mapping" | jq '.. | .tag? // empty | .properties | keys'
```

### Run Status Check

```bash
./scripts/status.sh
```

The status check now includes pfBlockerNG OpenSearch data validation.

## Troubleshooting

### No pfBlockerNG Data in OpenSearch

1. **Check Telegraf is running on pfSense:**
   ```bash
   ssh admin@<pfsense-ip> 'ps aux | grep telegraf'
   ```

2. **Check pfBlockerNG logs exist:**
   ```bash
   ssh admin@<pfsense-ip> 'ls -la /var/log/pfblockerng/*.log'
   ```

3. **Check Telegraf config includes opensearch output:**
   ```bash
   ssh admin@<pfsense-ip> 'grep -A5 "outputs.opensearch" /usr/local/etc/telegraf.conf'
   ```

4. **Check OpenSearch auto_create_index includes pfblockerng-*:**
   ```bash
   curl -s "http://localhost:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"
   ```

### Fields Mapped as Text Instead of Keyword

If Grafana shows "No data" even though events exist, the fields may be mapped as `text` type:

```bash
# Check mapping
curl -s "http://localhost:9200/pfblockerng-*/_mapping" | jq '.. | .src_ip? // empty'
```

If type is `text`, re-apply the template and recreate the index:
```bash
# Apply template
curl -XPUT "http://localhost:9200/_index_template/pfblockerng" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-pfblockerng-template.json

# Delete old index (data will be lost!)
TODAY=$(date -u +%Y.%m.%d)
curl -XDELETE "http://localhost:9200/pfblockerng-${TODAY}"

# New index will be created automatically with correct mappings
```

### Why OpenSearch Instead of InfluxDB?

pfBlockerNG data has **high cardinality** in fields like `src_ip`, `dest_ip`, `domain`, and `ASN`. InfluxDB stores tags in an inverted index, so high-cardinality tags cause:
- Excessive memory usage (series cardinality explosion)
- Slow queries
- Potential OOM crashes

If these fields are stored as InfluxDB *fields* instead of tags, they can't be used in `GROUP BY` queries, making Top-N panels impossible.

OpenSearch handles high-cardinality data natively with its inverted index architecture. Every field can be both searched and aggregated without cardinality penalties.

## Migration from InfluxDB

If you previously had pfBlockerNG data in InfluxDB:

1. The dashboard panels have been updated to use OpenSearch queries
2. InfluxDB pfBlockerNG measurements (`tail_ip_block_log`, `tail_dnsbl_log`) can be dropped
3. System metrics (CPU, RAM, interfaces) remain in InfluxDB — no changes needed
4. The Telegraf `[[outputs.influxdb]]` section still works for system metrics
5. Only the `namepass` filter on `[[outputs.opensearch]]` controls what goes to OpenSearch
