# Field Reference — Suricata and pfBlockerNG indices

> The single authoritative description of what is stored in OpenSearch. If a
> dashboard query, curl example, or troubleshooting doc disagrees with this page,
> this page wins — please open an issue.

## The one rule: fields are flat

The Logstash pipeline (`config/logstash-suricata.conf`) parses each EVE JSON event
straight to the **root** of the document. A Suricata alert is stored exactly as
Suricata wrote it, plus two enrichment objects added by the forwarder:

```json
{
  "@timestamp": "2026-09-19T14:02:11.318Z",
  "timestamp":  "2026-09-19T10:02:11.318412-0400",
  "event_type": "alert",
  "in_iface":   "igc0",
  "src_ip":     "203.0.113.45",
  "src_port":   51234,
  "dest_ip":    "198.51.100.10",
  "dest_port":  443,
  "proto":      "TCP",
  "app_proto":  "tls",
  "flow_id":    1234567890123456,
  "alert": { "signature": "ET SCAN ...", "signature_id": 2001219, "severity": 2,
             "category": "Attempted Information Leak", "action": "allowed" },
  "geoip_src": { "country_code": "US", "country_name": "United States",
                 "city_name": "Ashburn", "region_name": "Virginia",
                 "continent_code": "NA", "location": [-77.48, 39.04] }
}
```

Nothing is nested under `suricata.eve.*`. That layout existed in an early version
of the pipeline and was dropped because Grafana's OpenSearch datasource aggregates
far better on flat keyword fields. Any document, command, or dashboard that still
uses `suricata.eve.` is stale.

## Index: `suricata-*` (template `suricata-template`)

Daily indices `suricata-YYYY.MM.DD`. Mapped fields (from
`config/opensearch-index-template.json`); everything else Suricata emits is
dynamically mapped (strings become `text` with a `.keyword` sub-field).

### Core

| Field | Type | Notes |
|-------|------|-------|
| `@timestamp` | date | Set from Suricata's `timestamp` by Logstash; use this as the Grafana time field |
| `timestamp` | date | Suricata's original local-time string |
| `event_type` | keyword | `alert`, `dns`, `http`, `tls`, `flow`, `fileinfo`, `stats`, `anomaly`, ... |
| `in_iface` | keyword | pfSense interface the instance listens on (`igc0`, `igc1.20`, `lagg0.100`). **This is the per-interface field** — there is no `suricata.interface`. Mapped as `keyword`, so aggregate on `in_iface` (not `in_iface.keyword`). |
| `src_ip`, `dest_ip` | ip | Range and CIDR queries work (`src_ip:[10.0.0.0 TO 10.255.255.255]`) |
| `src_port`, `dest_port` | integer | |
| `proto` | keyword | `TCP`, `UDP`, `ICMP`, ... |
| `app_proto` | keyword | Detected application protocol |
| `flow_id` | long | Correlate alert/http/tls/flow records of one flow |

### `alert.*` (event_type = alert)

| Field | Type | Notes |
|-------|------|-------|
| `alert.signature` | text + `.keyword` | Aggregate on `alert.signature.keyword` |
| `alert.signature_id` | integer | SID — what you disable/suppress in `config/sid/` |
| `alert.gid`, `alert.rev` | integer | |
| `alert.category` | keyword | ET/Snort classtype description |
| `alert.severity` | integer | 1 = high, 2 = medium, 3 = low |
| `alert.action` | keyword | `allowed` or `blocked` (inline IPS drop) |

### GeoIP enrichment (added by the forwarder, public IPs only)

`geoip_src.*` and `geoip_dest.*` each contain: `country_code`, `country_name`,
`continent_code`, `city_name`, `region_name` (all keyword) and `location`
(geo_point, `[lon, lat]`). City and location are present only when a GeoLite2
**City** database was found; the Country database gives country/continent only.
Private (RFC 1918) addresses are never looked up.

### Protocol records

| Object | Mapped fields |
|--------|---------------|
| `http.*` | `hostname`, `url` (text+keyword), `http_method`, `http_content_type`, `status`, `length`, `http_user_agent` (text+keyword) |
| `dns.*` | `query`, `rrname`, `rrtype`, `rcode`, `type` — **Suricata 8 changes the DNS record to EVE v3 (`dns.queries[]`, `dns.answers[]`)**; re-check DNS panels after a major Suricata bump |
| `tls.*` | `sni`, `version`, `subject`, `issuerdn`, `ja3.hash` |
| `flow.*` | `pkts_toserver`, `pkts_toclient`, `bytes_toserver`, `bytes_toclient` |

### Useful queries

```text
event_type:alert AND alert.severity:1
event_type:alert AND in_iface:"igc1.20"
event_type:alert AND alert.action:blocked
event_type:tls AND NOT tls.sni:*
```

```bash
# Top signatures in the last 24h
curl -s "http://<SIEM_IP>:9200/suricata-*/_search?size=0" -H 'Content-Type: application/json' -d '{
  "query": {"bool": {"filter": [{"term": {"event_type": "alert"}},
            {"range": {"@timestamp": {"gte": "now-24h"}}}]}},
  "aggs": {"sigs": {"terms": {"field": "alert.signature.keyword", "size": 20}}}}' | jq '.aggregations.sigs.buckets'

# Verify the geo_point mapping the map panel needs
curl -s "http://<SIEM_IP>:9200/suricata-*/_mapping" \
  | jq '.[].mappings.properties.geoip_src.properties.location.type' | sort -u
```

## Index: `pfblockerng-*` (template `pfblockerng`)

Written by **Telegraf on pfSense** (`[[inputs.tail]]` + grok →
`[[outputs.opensearch]]`), not by Logstash. See
[Telegraf pfBlockerNG Pipeline](../pfsense/TELEGRAF_PFBLOCKER_SETUP.md).
Telegraf's line-protocol shape is preserved: tags under `tag.*`, fields under the
measurement name.

| Field | Type | Notes |
|-------|------|-------|
| `@timestamp` | date | |
| `measurement_name` | keyword | `tail_ip_block_log` or `tail_dnsbl_log` |
| `tag.src_ip`, `tag.dest_port`, `tag.protocol` | keyword | IP block events |
| `tag.feed_name`, `tag.blocklist` | keyword | Which feed/alias matched |
| `tag.geoip_code` | keyword | pfBlockerNG's own country code |
| `tag.tld`, `tag.host` | keyword | DNSBL events |
| `tag.path` | keyword | Source log file |
| `tail_ip_block_log.*` | keyword | `dest_ip`, `src_port`, `action`, `direction`, `interface`, `friendlyname`, `rulenum`, `resolvedhostname`, `clienthostname`, `ASN` (text+keyword), ... |
| `tail_dnsbl_log.*` | keyword | DNSBL details (domain, group, agent, ...) |

Dynamic templates force every `tag.*`, `tail_ip_block_log.*` and
`tail_dnsbl_log.*` field to `keyword`. If an index was created **before** the
template was applied, those fields are `text` and Grafana will refuse to aggregate
("Text fields are not optimised for operations that require per-document field
data"). Re-apply the template (`./scripts/install-opensearch-config.sh`) and reindex
the affected day — see [Troubleshooting](../troubleshooting/TROUBLESHOOTING.md).

## Other indices you may see

| Index | Written by | Used by |
|-------|-----------|---------|
| `wazuh-alerts-4.x-*` | Wazuh indexer (in [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack)) | `dashboards/wazuh/*.json` |
| `.opendistro-ism-config` etc. | OpenSearch ISM | retention policies from `scripts/configure-retention-policy.sh` |

## Auto-create

New daily indices are only created if `action.auto_create_index` allows them.
`scripts/install-opensearch-config.sh` sets it to
`pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*`.
If data stops at midnight UTC, start at
[OpenSearch Auto-Create](../troubleshooting/OPENSEARCH_AUTO_CREATE.md).
