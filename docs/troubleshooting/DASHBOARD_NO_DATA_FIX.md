# Fixing "No Data" in Grafana Dashboards

## Problem Overview

Panels show "No Data" even though Suricata is running, the forwarder is sending,
Logstash is receiving and OpenSearch holds documents. This page is the single
triage for that situation; [TROUBLESHOOTING.md](TROUBLESHOOTING.md) only
summarises it.

Before anything else, confirm you really are in this situation:

```bash
curl -s 'http://<SIEM_IP>:9200/suricata-*/_count' | jq .count
curl -s 'http://<SIEM_IP>:9200/suricata-*/_search?size=1&sort=@timestamp:desc' \
  | jq '.hits.hits[0]._source | {ts: ."@timestamp", event_type, src_ip, in_iface}'
```

If the count is 0 or the latest event is stale, the problem is upstream: see the
Forwarder, Logstash and auto-create sections of
[TROUBLESHOOTING.md](TROUBLESHOOTING.md). If recent documents exist, continue.

`./scripts/diagnose-and-repair.sh` performs most of the checks below and reports
which one failed.

## Root Causes

### 1. Panels Point at a Datasource That Does Not Exist

**Symptom:** *all* panels show "No Data" or a red "datasource not found" corner.

**Cause:** the dashboard JSON was imported in a way that did not resolve the
datasource. The shipped dashboards use a `${DS_OPENSEARCH}` template variable so
they can be imported anywhere.

**How to identify:**
```bash
curl -s -u admin:<password> 'http://<SIEM_IP>:3000/api/dashboards/uid/suricata_ids_ips' \
  | jq '.dashboard.panels[0].datasource'
# problem if uid is "${DS_OPENSEARCH}" or does not match one of:
curl -s -u admin:<password> 'http://<SIEM_IP>:3000/api/datasources' \
  | jq '.[] | select(.type=="grafana-opensearch-datasource") | {name, uid}'
```

**Fix:** re-import through `./setup.sh` (step 5). It removes `__inputs`, sets
the uid to `suricata_ids_ips` / `suricata_per_interface`, and rewrites every
panel's datasource to the real OpenSearch datasource uid, so there is nothing to
edit by hand. If you must import through the Grafana UI, choose your OpenSearch
datasource in the import dialog's dropdown.

### 2. Datasource Misconfigured

**Symptom:** the datasource "Save & test" is red, or green but every query
returns nothing.

Check in Connections → Data sources → your OpenSearch datasource:

| Setting | Value |
|---------|-------|
| URL | `http://localhost:9200` (Grafana and OpenSearch on the same host) or `http://<SIEM_IP>:9200` |
| Index name | `suricata-*` (`pfblockerng-*` for the pfBlockerNG datasource) |
| Pattern | No pattern |
| Time field name | `@timestamp` |
| Flavor / Version | OpenSearch / what `curl http://<SIEM_IP>:9200` reports (2.19.4 with `install.sh`) |
| Log message field | leave empty |

### 3. Time Range

**Symptom:** the dashboard is empty on "Last 24 hours" but a wider or narrower
range shows data.

Compare the dashboard's range with the latest event timestamp from the check at
the top. Common cases: the forwarder was only just (re)started and Suricata is
quiet; the SIEM server's clock is wrong (`timedatectl`); or pfSense's clock is
wrong, which puts events in the future where a "Last N" range never looks.
`@timestamp` is taken from Suricata's own timestamp, so a skewed pfSense clock
shows up here.

### 4. Field Name Mismatch

**Symptom:** some panels work, others (usually the terms/pie panels) are empty.

Events are indexed **flat**: `event_type`, `src_ip`, `in_iface`, `alert.signature`,
`geoip_src.location`, and so on, at the document root. Confirm:

```bash
curl -s 'http://<SIEM_IP>:9200/suricata-*/_search?size=1&sort=@timestamp:desc' | jq '.hits.hits[0]._source | keys'
# expected: ["@timestamp", "alert", "dest_ip", "dest_port", "event_type", "flow_id", "in_iface", "proto", "src_ip", ...]
```

Then check the field *type* the aggregation needs. The index template maps the
aggregated fields as `keyword` (no `.keyword` suffix needed), `alert.signature`
as `text` with a `.keyword` sub-field, and `geoip_*.location` as `geo_point`:

```bash
curl -s 'http://<SIEM_IP>:9200/suricata-*/_mapping' \
  | jq '.[].mappings.properties | {event_type, in_iface, sig: .alert.properties.signature, loc: .geoip_src.properties.location}' | head -40
```

If a field shows `"type": "text"` where the panel aggregates on it directly, the
index was created before the template was applied. Apply the template
(`./scripts/install-opensearch-config.sh`) and either wait for tomorrow's index
or delete/reindex today's. Field-by-field reference:
[FIELD_REFERENCE.md](../reference/FIELD_REFERENCE.md).

### 5. Alert Panels Empty, Everything Else Fine

**Symptom:** DNS, TLS, HTTP and flow panels populate; alert panels do not.

**Cause A – no alerts yet.** The forwarder tails from the end of `eve.json`, so
alerts logged before it started are never indexed. Check:
```bash
ssh admin@<PFSENSE_IP> 'grep -h "\"event_type\":\"alert\"" /var/log/suricata/*/eve.json | tail -3 | jq -r .timestamp'
ssh admin@<PFSENSE_IP> 'ps -o lstart= -p $(cat /var/run/suricata_forwarder.child.pid)'
```
If every alert predates the forwarder start, wait, or generate a benign test
alert (for example fetch `http://testmynids.org/uid/index.html` from a LAN host;
ET Open rule 2100498 fires on it).

**Cause B – IPS drops not logged as alerts.** In inline IPS mode Suricata can log
blocked traffic as `event_type: "drop"` only. In pfSense: Services → Suricata →
Interface → *EVE Output Settings*, make sure **Alert** is among the EVE log types.
Blocked alerts then carry `alert.action: "blocked"`.

### 6. pfBlockerNG Panels Empty

Those panels read `pfblockerng-*`, which is written by Telegraf on pfSense, not
by the Suricata forwarder. Check `curl -s 'http://<SIEM_IP>:9200/pfblockerng-*/_count'`.
Zero means Telegraf's `[[outputs.opensearch]]` is not configured
([TELEGRAF_PFBLOCKER_SETUP.md](../pfsense/TELEGRAF_PFBLOCKER_SETUP.md)); a stale
latest event usually means pfSense's `filterlog` stopped writing after log
rotation ([PFSENSE_FILTERLOG_ROTATION_FIX.md](PFSENSE_FILTERLOG_ROTATION_FIX.md)).

## Verification

```bash
# 1. Flat documents
curl -s 'http://<SIEM_IP>:9200/suricata-*/_search?size=1&sort=@timestamp:desc' | jq '.hits.hits[0]._source | keys'

# 2. Recent alerts
curl -s 'http://<SIEM_IP>:9200/suricata-*/_count' -H 'Content-Type: application/json' \
  -d '{"query":{"bool":{"filter":[{"term":{"event_type":"alert"}},{"range":{"@timestamp":{"gte":"now-1h"}}}]}}}' | jq .count

# 3. Per-interface distribution (the Per-Interface dashboard's main query)
curl -s 'http://<SIEM_IP>:9200/suricata-*/_search' -H 'Content-Type: application/json' \
  -d '{"size":0,"query":{"range":{"@timestamp":{"gte":"now-15m"}}},"aggs":{"ifaces":{"terms":{"field":"in_iface"}}}}' \
  | jq '.aggregations.ifaces.buckets'

# 4. Dashboard datasource resolved
curl -s -u admin:<password> 'http://<SIEM_IP>:3000/api/dashboards/uid/suricata_ids_ips' | jq '.dashboard.panels[0].datasource.uid'

# 5. Open http://<SIEM_IP>:3000/d/suricata_ids_ips
```

## Prevention

1. Deploy with `./setup.sh`; it applies the template before data flows and imports dashboards with the datasource resolved.
2. Run `./scripts/status.sh` after any change to Logstash, OpenSearch or the forwarder.
3. Keep the pfSense and SIEM clocks in sync (both should use NTP).
4. When editing panels, aggregate on the `keyword`-mapped fields listed in [FIELD_REFERENCE.md](../reference/FIELD_REFERENCE.md).

---

## Appendix: Migrating from the old nested layout (pre-2025-11)

*Historical. Only relevant if your OpenSearch still holds indices written by a
pipeline from before November 2025.*

Early versions of this project's Logstash pipeline nested every field under
`suricata.eve.*` (`suricata.eve.event_type`, `suricata.eve.src_ip`, ...). The
current pipeline, dashboards and index template all use the flat layout, and a
mix of both in one index pattern makes panels show partial data depending on the
time range.

Check whether any nested documents remain:
```bash
curl -s 'http://<SIEM_IP>:9200/suricata-*/_search?size=0' -H 'Content-Type: application/json' \
  -d '{"aggs":{"nested":{"filter":{"exists":{"field":"suricata.eve.event_type"}}},"flat":{"filter":{"exists":{"field":"event_type"}}}}}' \
  | jq '.aggregations | {nested: .nested.doc_count, flat: .flat.doc_count}'
```

If `nested` is non-zero, first make sure the deployed pipeline is current
(`./setup.sh` step 3 redeploys `config/logstash-suricata.conf`). Then either
wait for the old indices to age out under your retention policy, delete them,
or reindex them into the flat shape:

```bash
curl -X POST 'http://<SIEM_IP>:9200/_reindex?wait_for_completion=false' -H 'Content-Type: application/json' -d '
{
  "source": { "index": "suricata-*", "query": { "exists": { "field": "suricata.eve.event_type" } } },
  "dest":   { "index": "suricata-reindexed" },
  "script": { "lang": "painless",
              "source": "ctx._source.putAll(ctx._source.suricata.eve); ctx._source.remove(\"suricata\")" }
}'
curl -s 'http://<SIEM_IP>:9200/_tasks?detailed=true&actions=*reindex' | jq
```

`suricata-reindexed` matches the `suricata-*` pattern, so it receives the flat
template mapping and is picked up by the dashboards. Reindexing millions of
documents takes hours; deleting the old daily indices is usually the better
trade.
