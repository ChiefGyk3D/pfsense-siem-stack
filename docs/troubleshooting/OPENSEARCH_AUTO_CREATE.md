# OpenSearch Auto-Create: The Midnight UTC Problem

This is the one place the `action.auto_create_index` requirement is explained.
[config/README.md](../../config/README.md) carries only the command;
`setup.sh`, `install-opensearch-config.sh`, `status.sh` and
`diagnose-and-repair.sh` all check or set it.

## Symptom

The dashboards stop receiving data at exactly **midnight UTC** (whatever that is
in your local time zone). The latest event in OpenSearch is stamped `23:59:5x`
UTC; Suricata, the forwarder and Logstash all look healthy. The pfBlockerNG
panels, fed by Telegraf, stop at the same moment.

## Root Cause

Both writers use daily indices: Logstash writes `suricata-YYYY.MM.DD`
(`index => "suricata-%{[@metadata][index_date]}"`, UTC) and Telegraf writes
`pfblockerng-YYYY.MM.DD`. Neither creates the index explicitly; they rely on
OpenSearch creating it on the first write of the day.

If the cluster setting `action.auto_create_index` does not allow that index
name, the first write after midnight fails:

```
index_not_found_exception: no such index [suricata-YYYY.MM.DD]
```

Logstash's OpenSearch output treats a 404 on index as non-retryable and drops
the event; Telegraf does the same. Every event is lost until the index exists.
On some OpenSearch builds the default already permits any index; on others it is
restricted, and a security-conscious admin may have set it to `false`. The
setting is cheap to make explicit, so this project always sets it.

## The Fix

### Automated (what setup.sh does)

`./setup.sh` step 2, or standalone:

```bash
./scripts/install-opensearch-config.sh
```

That applies the two index templates (`suricata-template` for `suricata-*`,
`pfblockerng` for `pfblockerng-*`), sets auto-create as below, verifies the
template lands on a throw-away test index, and creates today's `suricata-` index.

### Manual

```bash
curl -XPUT "http://<SIEM_IP>:9200/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "action.auto_create_index": "pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
  }'
```

Use `persistent`, not `transient`, or the setting is lost at the next restart.

The value is an allow-list of patterns. `suricata-*` and `pfblockerng-*` are this
project's data; the dot-prefixed patterns are OpenSearch's own alerting,
monitoring and ML indices, which also rely on auto-create. Anything else must be
created explicitly, which is the safer default: a typo in a client's index name
cannot silently create junk indices. Setting the value to `true` allows
everything and is not recommended.

## Verification

```bash
# The setting
curl -s "http://<SIEM_IP>:9200/_cluster/settings?filter_path=persistent.action.auto_create_index"
# expect: {"persistent":{"action":{"auto_create_index":"pfblockerng-*,suricata-*,.monitoring-*,..."}}}

# Today's index exists and is growing
TODAY=$(date -u +%Y.%m.%d)
curl -s "http://<SIEM_IP>:9200/suricata-${TODAY}/_count" | jq .count
sleep 10
curl -s "http://<SIEM_IP>:9200/suricata-${TODAY}/_count" | jq .count

# Recent Logstash failures of this kind
sudo grep -c index_not_found /var/log/logstash/logstash-plain.log
```

`./scripts/status.sh` reports the setting as a pass/fail line for both patterns.

## Emergency Recovery

If you notice after midnight that the flow stopped:

```bash
TODAY=$(date -u +%Y.%m.%d)
# 1. Create today's index right now (the template supplies the mappings)
curl -XPUT "http://<SIEM_IP>:9200/suricata-${TODAY}"
# 2. Set auto-create so it does not happen again tomorrow
curl -XPUT "http://<SIEM_IP>:9200/_cluster/settings" -H 'Content-Type: application/json' \
  -d '{"persistent":{"action.auto_create_index":"pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"}}'
# 3. Confirm
sleep 10; curl -s "http://<SIEM_IP>:9200/suricata-${TODAY}/_count" | jq .count
```

Events dropped during the outage are gone. The forwarder tails from the end of
`eve.json`, so it will not resend them; they are still in Suricata's log files
on pfSense if you need them for an investigation.

## Related Template Problems

These share the "new index created at midnight" mechanism and are often
confused with the auto-create issue.

**Template not applied to new indices.** Templates only affect indices created
after them. Re-apply, then wait for tomorrow's index or delete today's:
```bash
curl -XPUT "http://<SIEM_IP>:9200/_index_template/suricata-template" \
  -H 'Content-Type: application/json' -d @config/opensearch-index-template.json
```

**Geo map empty on new indices.** `geoip_src.location` must be `geo_point`. Check
one index (`suricata-YYYY.MM.DD`) or all at once:
```bash
curl -s "http://<SIEM_IP>:9200/suricata-*/_mapping" \
  | jq '.[].mappings.properties.geoip_src.properties.location.type' | sort | uniq -c
```
Every line should be `"geo_point"`. A `"float"` line means that index was
created before the template existed; delete or reindex it.

## Prevention Checklist

- Run `./setup.sh` (or `install-opensearch-config.sh`) before the first event flows.
- Run `./scripts/status.sh` after any OpenSearch reinstall or restore; it checks the setting.
- Keep `persistent` settings in a backup: `curl -s http://<SIEM_IP>:9200/_cluster/settings > cluster-settings.json`.

## References

- OpenSearch cluster settings: https://opensearch.org/docs/latest/api-reference/cluster-api/cluster-settings/
- Index templates: https://opensearch.org/docs/latest/im-plugin/index-templates/
- logstash-output-opensearch: https://github.com/opensearch-project/logstash-output-opensearch
