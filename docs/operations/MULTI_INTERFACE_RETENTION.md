# Multi-Interface Support & Data Retention

## Overview

This document covers two operational features of the Suricata monitoring stack:

1. **Multi-Interface Support**: one forwarder monitors every Suricata instance on pfSense
   (WAN, LAN, VLANs, lagg members) and the per-interface field you filter on in Grafana.
2. **Data Retention**: automatic deletion of old indices via OpenSearch Index State
   Management (ISM) to keep disk usage bounded.

---

## Multi-Interface Support

### How it works

The forwarder (`forward-suricata-eve.py`) globs `/var/log/suricata/*/eve.json` at startup
and starts one tailing thread per file. All threads share a single UDP socket to Logstash.
Each thread handles its own log rotation (inode change, truncation, file disappearing) and
restarts itself after an error, so one misbehaving interface does not stall the others.

Suricata on pfSense writes one log directory per instance, named after the interface plus
a numeric suffix:

```
/var/log/suricata/suricata_igc012345/eve.json   -> WAN instance
/var/log/suricata/suricata_igc167890/eve.json   -> LAN instance
/var/log/suricata/suricata_lagg0.10024680/eve.json -> VLAN instance
```

The forwarder does **not** add its own interface field. It does not need to: every EVE
event already carries Suricata's `in_iface` field (the capture interface, e.g. `igc0`,
`lagg0.100`), and the Logstash pipeline indexes events **flat at the root**, so
`in_iface` is queryable directly. There is no `suricata.interface` or
`suricata_interface` field in this stack.

### Deployment

The standard setup handles any number of interfaces:

```bash
./setup.sh
```

(Configure `PFSENSE_HOST` and `SIEM_HOST` in `config.env` first.) setup.sh counts the
`eve.json` files it finds and reports "N Suricata interfaces". Interfaces added to
Suricata later are picked up the next time the forwarder starts:
`ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'`.

### Checking which interfaces are monitored

From the SIEM server:

```bash
./tests/test-multi-interface.sh <PFSENSE_IP>
```

Or manually on pfSense:

```bash
# One "Monitoring <dir>" line per interface at startup
grep "suricata-forwarder" /var/log/system.log | tail -20

# Files the running process has open
lsof -p $(cat /var/run/suricata_forwarder.pid) | grep eve.json
```

You should see `Starting — N interface(s)` followed by N `Monitoring ...` lines.

### Using the interface field in Grafana

The OpenSearch datasource exposes `in_iface` as text and `in_iface` for exact
match and aggregations. The shipped `Suricata_Per_Interface.json` dashboard is built on
this field and uses a dashboard variable to repeat panels per interface.

**Filter to one interface (Lucene query):**

```
event_type:alert AND in_iface:"igc0"
```

**Count by interface (terms aggregation):**

```json
{
  "type": "terms",
  "field": "in_iface",
  "size": 20
}
```

**Panel ideas:** pie chart of alerts by interface, table of top signatures per interface,
time series of alert rate per interface.

Other fields you will use alongside it are also flat at the root: `event_type`,
`src_ip`, `dest_ip`, `alert.signature`, `alert.severity`, `geoip_src.location`.

---

## Data Retention

### How it works

Retention is enforced by OpenSearch ISM, not by the forwarder or Logstash. A policy named
`delete-after-<N>d` has two states:

1. **active**: the default; ISM checks the index age on every run.
2. **delete**: entered when `min_index_age` reaches `<N>d`; the index is deleted.

The policy carries an `ism_template` for the `suricata-*` pattern, so newly created
daily indices pick it up automatically. Existing indices are attached when the script
runs.

### Configuring retention

```bash
./scripts/configure-retention-policy.sh [DAYS] [INDEX_PATTERN]
```

- `DAYS` defaults to **90** if omitted. There is no interactive prompt.
- `INDEX_PATTERN` defaults to `suricata-*`.
- The script reads `SIEM_HOST` / `OPENSEARCH_PORT` from `config.env`.
- `RETENTION_DAYS` in `config.env` (default **30**) is what `install.sh` and the
  `pfsense-siem` console pass to this script; the console also writes your choice back to
  `config.env`.

Examples:

```bash
./scripts/configure-retention-policy.sh 30                  # 30 days on suricata-*
./scripts/configure-retention-policy.sh 90                  # 90 days on suricata-*
./scripts/configure-retention-policy.sh 180 'pfblockerng-*' # 180 days on pfBlockerNG indices
```

The script creates (or reports as existing) the `delete-after-<N>d` policy, attaches it to
every existing index matching the pattern, and prints the policy for verification.

> **pfBlockerNG indices:** `pfblockerng-*` is written by Telegraf, not the forwarder, and is
> not covered by the default `suricata-*` run. Apply retention to it separately with the
> second argument as shown above.

> **Changing the period:** a new value creates a new policy (`delete-after-30d` next to
> `delete-after-90d`, for example). Indices already attached to the old policy keep it until
> you change them; ISM does not switch a managed index's policy on its own. To move existing
> indices, remove the old policy first:
> ```bash
> curl -s -X POST "http://<SIEM_IP>:9200/_plugins/_ism/remove/suricata-*"
> ./scripts/configure-retention-policy.sh 30
> ```

### Verifying the policy

```bash
# Which policy each index is on, and its current state
curl -s "http://<SIEM_IP>:9200/_plugins/_ism/explain/suricata-*" | python3 -m json.tool

# All policies defined
curl -s "http://<SIEM_IP>:9200/_plugins/_ism/policies" | python3 -m json.tool

# One policy in full (replace 90 with your value)
curl -s "http://<SIEM_IP>:9200/_plugins/_ism/policies/delete-after-90d" | python3 -m json.tool
```

Each index in the explain output should show `"policy_id": "delete-after-<N>d"` and a
`state.name` of `active` (or `delete` shortly before it disappears).

### Sizing

Disk usage is roughly `events/day x bytes/event x retention days`. Measure your own rate
rather than guessing:

```bash
# Documents and on-disk size per daily index
curl -s "http://<SIEM_IP>:9200/_cat/indices/suricata-*?v&s=index&h=index,docs.count,store.size"
```

As a worked example, a small network producing ~30k events/day at ~350 bytes each
stores about 10 MB/day:

| Retention | Approx. storage |
|-----------|-----------------|
| 7 days    | ~75 MB          |
| 30 days   | ~315 MB         |
| 90 days   | ~950 MB         |
| 180 days  | ~1.9 GB         |
| 365 days  | ~3.8 GB         |

Event volume scales with the number of monitored interfaces and with how noisy your
rulesets are (flow and DNS event types dominate if enabled), so check the `_cat/indices`
numbers after a week and adjust. Hardware guidance is in
[HARDWARE_REQUIREMENTS.md](../install/HARDWARE_REQUIREMENTS.md).

### Manual index management

```bash
# List indices with sizes
curl -s "http://<SIEM_IP>:9200/_cat/indices/suricata-*?v&s=index"

# Delete one index by hand (emergency only; ISM normally does this)
curl -s -X DELETE "http://<SIEM_IP>:9200/suricata-2026.06.01"

# Export an index before it ages out (small indices only; use a snapshot repository for anything large)
curl -s "http://<SIEM_IP>:9200/suricata-2026.06.01/_search?size=10000" > suricata-2026.06.01.json
```

---

## Troubleshooting

### Multi-interface

**Forwarder not starting:**
```bash
ssh admin@<PFSENSE_IP> 'tail -20 /var/log/system.log | grep suricata-forwarder'
ssh admin@<PFSENSE_IP> 'tail -20 /var/log/suricata-forwarder.log'
```
`No EVE JSON logs found` means Suricata is not running or is logging elsewhere.

**Only some interfaces appear in Grafana:**
- Interface added after the forwarder started: `service suricata_forwarder.sh restart` on pfSense.
- Suricata instance not actually writing: `ls -l /var/log/suricata/*/eve.json` and compare timestamps.
- Panel queries an old field name: dashboards must use `in_iface` / `in_iface`.

**`in_iface` missing from events:** the field comes from Suricata itself. Check the raw
`eve.json` line contains `"in_iface"`; if it does but OpenSearch does not, Logstash is not
using the shipped `config/logstash-suricata.conf` (flat JSON parse). See
[CONFIGURATION.md](../reference/CONFIGURATION.md) and restart Logstash.

### Retention

**Indices not being deleted:**
```bash
curl -s "http://<SIEM_IP>:9200/_plugins/_ism/explain/suricata-2026.06.01" | python3 -m json.tool
```
Look at `policy_id` (is it attached at all?) and `info.message`. Indices created before the
policy existed need `./scripts/configure-retention-policy.sh <N>` re-run to attach them.

**New indices not picking up the policy:** the `ism_template` only applies to indices
created *after* the policy; re-run the script once and future daily indices are covered.

**Wrong retention on some indices:** see "Changing the period" above; remove the old policy
from those indices, then re-run the script.

---

## Related Documentation

- [INSTALL_PFSENSE_FORWARDER.md](../install/INSTALL_PFSENSE_FORWARDER.md): forwarder deployment
- [SURICATA_FORWARDER_MONITORING.md](SURICATA_FORWARDER_MONITORING.md): how the forwarder runs and recovers
- [CONFIGURATION.md](../reference/CONFIGURATION.md): Logstash pipeline and field layout
- [HARDWARE_REQUIREMENTS.md](../install/HARDWARE_REQUIREMENTS.md): storage sizing
- [TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md): common issues
- [scripts/README.md](../../scripts/README.md): utility scripts

---

## Quick Reference

```bash
# Deploy / redeploy the forwarder (all interfaces)
./setup.sh

# Confirm interface detection
./tests/test-multi-interface.sh <PFSENSE_IP>

# Set retention (days, default 90)
./scripts/configure-retention-policy.sh 90
./scripts/configure-retention-policy.sh 90 'pfblockerng-*'

# Check retention status
curl -s "http://<SIEM_IP>:9200/_plugins/_ism/explain/suricata-*" | python3 -m json.tool

# Events by interface in the last hour
curl -s "http://<SIEM_IP>:9200/suricata-*/_search" -H 'Content-Type: application/json' -d '{
  "size": 0,
  "query": {"range": {"@timestamp": {"gte": "now-1h"}}},
  "aggs": {"by_interface": {"terms": {"field": "in_iface", "size": 50}}}
}' | jq '.aggregations.by_interface.buckets'
```
