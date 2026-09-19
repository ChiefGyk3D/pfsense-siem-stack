# Telegraf pfBlockerNG Setup — OpenSearch Pipeline

## Overview

pfBlockerNG data (IP blocks and DNSBL events) is collected by Telegraf on pfSense and sent **directly to OpenSearch** using the `[[outputs.opensearch]]` plugin. This bypasses InfluxDB entirely for pfBlockerNG data, avoiding the high-cardinality problems that source IPs, destination IPs and domains cause in a time-series database.

### Architecture

```
pfSense pfBlockerNG logs (/var/log/pfblockerng/*.log)
  → Telegraf tail input (grok parsing)
    → Telegraf opensearch output
      → OpenSearch (pfblockerng-* daily indices)
        → Grafana (OpenSearch-pfBlockerNG datasource)
```

> **Note**: System metrics (CPU, RAM, interfaces, gateways) continue to flow through InfluxDB via Telegraf's standard `[[outputs.influxdb]]` output. Only pfBlockerNG data goes to OpenSearch.

## Prerequisites

1. **pfBlockerNG-devel** installed on pfSense (System → Package Manager) with IP and/or DNSBL blocking enabled and logging turned on
2. **Telegraf** package installed on pfSense and working — see [TELEGRAF_ON_PFSENSE.md](TELEGRAF_ON_PFSENSE.md). `[[outputs.opensearch]]` requires Telegraf **1.28 or later** (`telegraf version`)
3. **OpenSearch** running on the SIEM server, reachable from pfSense on port 9200
4. **Index template and auto-create setting** applied by running `./scripts/install-opensearch-config.sh` on the SIEM server (details below)

## Telegraf Configuration on pfSense

Telegraf on pfSense is configured entirely through **Services → Telegraf**. The generated `/usr/local/etc/telegraf.conf` is rewritten from `config.xml` on every save, so everything below goes into the **Additional Configuration** box on that page, never into the file directly. See [TELEGRAF_ON_PFSENSE.md](TELEGRAF_ON_PFSENSE.md#2-configure-via-services--telegraf) for the full explanation.

Telegraf runs as root on pfSense, so it can read the pfBlockerNG logs even when the package recreates them with mode `600`. No permission tweaks or cron jobs are needed.

### Required: OpenSearch Output Plugin

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

Replace `<SIEM_IP>` with the address of your SIEM server.

**Key fields:**

- `namepass`: only the two pfBlockerNG measurements go to OpenSearch; system metrics stay in InfluxDB
- `manage_template = false`: the index template is managed on the SIEM side by `install-opensearch-config.sh` (its name there is `pfblockerng`, matching `template_name`)
- `index_name`: daily indices such as `pfblockerng-2025.02.07`

> **Warning**: Do NOT use `[[outputs.elasticsearch]]` — its version handshake fails against OpenSearch 2.x and it refuses to write. Telegraf ≥ 1.28 ships a dedicated `[[outputs.opensearch]]` plugin that works correctly.

### Required: Tail Inputs for pfBlockerNG Logs

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

> **Important**: The `:tag` annotations (e.g. `src_ip:tag`) tell Telegraf to treat those values as tags. The OpenSearch output nests tags under `tag.*` (e.g. `tag.src_ip`) and everything else under the measurement name (e.g. `tail_ip_block_log.dest_ip`). The Grafana dashboard queries are built around this structure, so keep the annotations as shown.

### Apply and restart

Click **Save** on the Telegraf page. That regenerates the config and restarts the service. If you need to restart by hand later, use **Status → Services** or `/usr/local/etc/rc.d/telegraf.sh restart` — see [TELEGRAF_ON_PFSENSE.md](TELEGRAF_ON_PFSENSE.md#5-restarting-telegraf-correctly).

## OpenSearch Setup (SIEM Server)

### Apply the index template and enable auto-create

Run the installer once on the SIEM server:

```bash
OPENSEARCH_HOST=<SIEM_IP> ./scripts/install-opensearch-config.sh
```

It creates two index templates — `_index_template/suricata-template` for `suricata-*` and `_index_template/pfblockerng` for `pfblockerng-*` — and sets `action.auto_create_index` so that both daily index families can be created automatically at midnight UTC. Without the auto-create setting Telegraf's writes fail silently with `index_not_found_exception` as soon as the date changes; see [OPENSEARCH_AUTO_CREATE.md](../troubleshooting/OPENSEARCH_AUTO_CREATE.md) for the background, verification commands and emergency recovery.

To apply just the pfBlockerNG template by hand:

```bash
curl -XPUT "http://<SIEM_IP>:9200/_index_template/pfblockerng" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-pfblockerng-template.json
```

The template maps every `tag.*`, `tail_ip_block_log.*` and `tail_dnsbl_log.*` field as `keyword` so Grafana can aggregate on them.

## Grafana Datasource

A dedicated OpenSearch datasource is used for pfBlockerNG data:

| Setting | Value |
|---------|-------|
| **Name** | OpenSearch-pfBlockerNG |
| **Type** | grafana-opensearch-datasource |
| **URL** | http://localhost:9200 |
| **Index** | pfblockerng-* |
| **Time field** | @timestamp |
| **Version** | 2.x (match your OpenSearch version) |

`setup.sh` creates this datasource automatically. To create it manually: Grafana → Connections → Data sources → Add data source → OpenSearch, then fill in the table above.

## OpenSearch Field Structure

### IP Block Events (`measurement_name: tail_ip_block_log`)

| Field Path | Type | Description |
|------------|------|-------------|
| `tag.src_ip` | keyword | Source IP (blocked) |
| `tag.dest_port` | keyword | Destination port |
| `tag.protocol` | keyword | Protocol (TCP/UDP/ICMP) |
| `tag.geoip_code` | keyword | Country code |
| `tag.feed_name` | keyword | Blocklist feed name |
| `tag.direction` | keyword | in/out |
| `tag.host` | keyword | pfSense hostname |
| `tail_ip_block_log.dest_ip` | keyword | Destination IP |
| `tail_ip_block_log.src_port` | keyword | Source port |
| `tail_ip_block_log.action` | keyword | Block action |
| `tail_ip_block_log.interface` | keyword | Interface name |
| `tail_ip_block_log.ASN` | keyword | AS number |

### DNSBL Events (`measurement_name: tail_dnsbl_log`)

| Field Path | Type | Description |
|------------|------|-------------|
| `tag.src_ip` | keyword | Client IP making the DNS request |
| `tag.tld` | keyword | Top-level domain blocked |
| `tag.feed_name` | keyword | DNSBL feed name |
| `tag.blocklist` | keyword | Blocklist name |
| `tag.host` | keyword | pfSense hostname |
| `tail_dnsbl_log.domain` | keyword | Full domain blocked |
| `tail_dnsbl_log.blockmethod` | keyword | Block method |
| `tail_dnsbl_log.blocktype` | keyword | Block type |
| `tail_dnsbl_log.req_agent` | keyword | User agent (when present) |

## Dashboard Panels

The pfSense System Dashboard (`dashboards/pfsense_pfblockerng_system.json`) contains 16 pfBlockerNG panels (top blocked IPs in/out, blocks by GeoIP, port and protocol breakdowns, DNSBL top domains/clients/feeds, time series of block rates), all using the OpenSearch-pfBlockerNG datasource. The panel list and import instructions are in [dashboards/README.md](../../dashboards/README.md).

## Verification

```bash
# Count total events
curl -s "http://<SIEM_IP>:9200/pfblockerng-*/_count" | jq '.count'

# Latest event
curl -s "http://<SIEM_IP>:9200/pfblockerng-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source'

# Tag fields mapped as keyword?
curl -s "http://<SIEM_IP>:9200/pfblockerng-*/_mapping" | jq '.. | .tag? // empty | .properties | keys'
```

`./scripts/status.sh` also checks that pfBlockerNG data is arriving in OpenSearch.

## Troubleshooting

### No pfBlockerNG Data in OpenSearch

1. **Telegraf running (as root) on pfSense?**
   ```bash
   ssh admin@<PFSENSE_IP> "ps -axo user,command | grep '[t]elegraf'"
   ```
2. **pfBlockerNG logs exist and are growing?**
   ```bash
   ssh admin@<PFSENSE_IP> "ls -la /var/log/pfblockerng/ip_block.log /var/log/pfblockerng/dnsbl.log"
   ```
   If they are empty, enable logging on the IP and DNSBL groups in pfBlockerNG and make sure blocks are actually happening.
3. **Generated config contains the OpenSearch output?**
   ```bash
   ssh admin@<PFSENSE_IP> "grep -A5 'outputs.opensearch' /usr/local/etc/telegraf.conf"
   ```
   If not, the Additional Configuration box was not saved. Paste it again and click Save.
4. **Telegraf errors?**
   ```bash
   ssh admin@<PFSENSE_IP> "tail -50 /var/log/telegraf/telegraf.log | grep -i -E 'opensearch|tail'"
   ```
5. **Auto-create includes `pfblockerng-*`?**
   ```bash
   curl -s "http://<SIEM_IP>:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"
   ```
   If not, re-run `install-opensearch-config.sh` or follow [OPENSEARCH_AUTO_CREATE.md](../troubleshooting/OPENSEARCH_AUTO_CREATE.md).

### Fields Mapped as Text Instead of Keyword

If events exist but Grafana panels show "No data", the index was probably created before the template was applied and the fields were dynamically mapped as `text`:

```bash
curl -s "http://<SIEM_IP>:9200/pfblockerng-*/_mapping" | jq '.. | .src_ip? // empty'
```

If the type is `text`, apply the template (command above) and recreate today's index:

```bash
TODAY=$(date -u +%Y.%m.%d)
curl -XDELETE "http://<SIEM_IP>:9200/pfblockerng-${TODAY}"   # today's pfBlockerNG data is lost
```

The next event Telegraf writes recreates the index with the template's keyword mappings.

### Why OpenSearch Instead of InfluxDB?

pfBlockerNG data has **high cardinality** in `src_ip`, `dest_ip`, `domain` and `ASN`. InfluxDB indexes every tag value, so high-cardinality tags cause series-cardinality explosion, memory pressure and slow queries; storing them as fields instead makes them unusable in `GROUP BY`, which kills every Top-N panel. OpenSearch's inverted index handles high-cardinality values natively, so every field can be both searched and aggregated.

## Migration from InfluxDB

If you previously had pfBlockerNG data in InfluxDB:

1. The dashboard panels now use OpenSearch queries
2. The InfluxDB measurements `tail_ip_block_log` and `tail_dnsbl_log` can be dropped
3. System metrics (CPU, RAM, interfaces) remain in InfluxDB — no changes needed
4. The generated `[[outputs.influxdb]]` block keeps working for system metrics
5. The `namepass` filter on `[[outputs.opensearch]]` alone controls what goes to OpenSearch

## Related

- [TELEGRAF_ON_PFSENSE.md](TELEGRAF_ON_PFSENSE.md) — Telegraf package, Additional Configuration box, restart, troubleshooting
- [PFBLOCKERNG_OPTIMIZATION.md](PFBLOCKERNG_OPTIMIZATION.md) — pfBlockerNG strategy and how it complements Suricata
- [OPENSEARCH_AUTO_CREATE.md](../troubleshooting/OPENSEARCH_AUTO_CREATE.md) — the midnight-UTC problem
- [config/README.md](../../config/README.md) — index templates and Logstash pipeline
