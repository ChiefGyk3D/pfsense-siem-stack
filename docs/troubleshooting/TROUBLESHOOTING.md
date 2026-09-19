# Troubleshooting Guide

Common issues and solutions for the pfSense Suricata monitoring stack. This is
the master runbook; the other files in this directory go deep on single issues
and are linked from the relevant sections.

Placeholders: `<PFSENSE_IP>` is your firewall, `<SIEM_IP>` the server running
OpenSearch/Logstash/Grafana. Commands prefixed `sudo` run on the SIEM server;
commands wrapped in `ssh admin@<PFSENSE_IP> '...'` run on pfSense.

## Table of Contents
- [Start Here](#start-here)
- [No Data in Dashboard](#no-data-in-dashboard)
- [Forwarder Issues](#forwarder-issues)
- [OpenSearch Issues](#opensearch-issues)
- [Logstash Issues](#logstash-issues)
- [Grafana Issues](#grafana-issues)
- [Performance Issues](#performance-issues)
- [Network Issues](#network-issues)
- [Common Error Messages](#common-error-messages)
- [After a pfSense Upgrade](#after-a-pfsense-upgrade)
- [Getting Help](#getting-help)
- [Preventive Maintenance](#preventive-maintenance)

## Start Here

Two scripts do most of the work. Run them from your repo checkout (they read
`config.env`):

```bash
./scripts/status.sh                 # read-only health report: services, indices, forwarder, watchdog
./scripts/diagnose-and-repair.sh    # walks the whole chain and fixes the safe things itself
```

`diagnose-and-repair.sh` checks connectivity → OpenSearch → Logstash → forwarder
→ Grafana, then sends a test event end to end. It will enable auto-create,
install a missing index template, and restart the forwarder service on its own;
for everything else it prints the exact command. If neither script points at the
problem, use the manual checks below.

```bash
# Services on the SIEM server
sudo systemctl status opensearch logstash grafana-server

# Event count and latest event
curl -s 'http://localhost:9200/suricata-*/_count' | jq .count
curl -s 'http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc' \
  | jq '.hits.hits[0]._source | {ts: ."@timestamp", event_type, src_ip, in_iface}'

# Forwarder on pfSense
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'

# Logstash is listening
sudo ss -ulnp | grep 5140
```

## No Data in Dashboard

**Symptom:** panels show "No data".

Work out which of three situations you are in:

```bash
curl -s 'http://localhost:9200/suricata-*/_count' | jq .count
curl -s 'http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc' | jq -r '.hits.hits[0]._source."@timestamp"'
```

1. **Count is 0** – nothing is being indexed. Go to [Forwarder Issues](#forwarder-issues) and [Logstash Issues](#logstash-issues).
2. **Count is growing but the latest event is old** – the flow stopped. If it
   stopped at exactly midnight UTC, read
   [OPENSEARCH_AUTO_CREATE.md](OPENSEARCH_AUTO_CREATE.md). Otherwise check the
   forwarder and Logstash logs.
3. **Recent events exist but panels are empty** – a Grafana-side problem: time
   range, datasource, or field names. Confirm the datasource
   (Connections → Data sources → the OpenSearch one: index `suricata-*`, time
   field `@timestamp`, "Save & test" green) and that documents are flat
   (`jq '.hits.hits[0]._source | keys'` should list `event_type`, `src_ip`, ...
   at the top level, not a `suricata` wrapper).

The full triage for case 3, including the older nested-layout migration, lives
in [DASHBOARD_NO_DATA_FIX.md](DASHBOARD_NO_DATA_FIX.md). It is not repeated here.

## Forwarder Issues

The forwarder is `/usr/local/bin/forward-suricata-eve.py`, run as the rc.d
service `suricata_forwarder.sh` under `daemon(8)`, with a cron watchdog every
minute that restarts the service if the process is gone. Logs:
`/var/log/suricata-forwarder.log` (stdout/stderr) and syslog tags
`suricata-forwarder` / `suricata-watchdog` in `/var/log/system.log`.

### Forwarder Not Running

**Symptom:**
```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'
# suricata_forwarder is not running.
```

**Diagnosis:**
```bash
# Service and script present?
ssh admin@<PFSENSE_IP> 'ls -l /usr/local/etc/rc.d/suricata_forwarder.sh /usr/local/bin/forward-suricata-eve.py'

# Why did it stop?
ssh admin@<PFSENSE_IP> 'tail -30 /var/log/suricata-forwarder.log'
ssh admin@<PFSENSE_IP> 'grep -E "suricata-(forwarder|watchdog)" /var/log/system.log | tail -20'

# Run it in the foreground to see errors directly (stop the service first)
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh stop; python3 /usr/local/bin/forward-suricata-eve.py'

# Is the watchdog installed?
ssh admin@<PFSENSE_IP> 'crontab -l | grep watchdog'
# expected: * * * * * /usr/local/bin/suricata-forwarder-watchdog.sh
```

Typical causes: `ERROR: No EVE JSON files found` (Suricata is not running on any
interface, enable it first); `interpreter ... not found — re-run setup.sh`
(a pfSense upgrade replaced Python, see
[After a pfSense Upgrade](#after-a-pfsense-upgrade)); the rc.d script or crontab
entry missing (setup.sh was never run, or was run before the `.sh` service
existed).

**Solutions:**
```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh start'

# If the service files are missing or stale, redeploy everything from your workstation:
./setup.sh
```

### Forwarder Running But No Events

**Symptom:** `status` says running, OpenSearch count is not increasing.

**Diagnosis:**
```bash
# 1. Is Suricata writing events at all?
ssh admin@<PFSENSE_IP> 'tail -3 /var/log/suricata/*/eve.json'

# 2. Which files does the forwarder have open? (should be eve.json, not eve.json.*)
ssh admin@<PFSENSE_IP> 'lsof -p $(cat /var/run/suricata_forwarder.child.pid) | grep eve.json'

# 3. Where is it sending?
ssh admin@<PFSENSE_IP> 'grep "^SIEM_HOST\|^LOGSTASH_PORT" /usr/local/bin/forward-suricata-eve.py'

# 4. Can pfSense reach Logstash?
ssh admin@<PFSENSE_IP> 'echo "{\"event_type\":\"test\",\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000000+0000)\"}" | nc -u -w1 <SIEM_IP> 5140'
curl -s 'http://localhost:9200/suricata-*/_search?q=event_type:test&size=1' | jq .hits.total.value

# 5. Firewall on the SIEM server
sudo ufw status | grep 5140
```

**Solutions:**
```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'   # also picks up newly enabled interfaces
sudo ufw allow from <PFSENSE_IP> to any port 5140 proto udp
./setup.sh                                                          # if SIEM_HOST/port baked into the script are wrong
```

If the forwarder holds a rotated file (`eve.json.*`) open for more than a few
seconds, see [LOG_ROTATION_FIX.md](LOG_ROTATION_FIX.md).

### Duplicate Forwarders

Two forwarder processes send every event twice. This happens when a forwarder
started by hand (or by one of the legacy scripts) runs alongside the service.

```bash
ssh admin@<PFSENSE_IP> 'pgrep -fl forward-suricata-eve.py'
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh stop; pkill -f forward-suricata-eve.py; sleep 1; service suricata_forwarder.sh start'
```

Do not leave the legacy cron entries from `setup_forwarder_monitoring.sh` or
`unified-monitoring-watchdog.sh` in place; they fight the service.

### Events Have _jsonparsefailure Tag

**Diagnosis:**
```bash
curl -s 'http://localhost:9200/suricata-*/_search?q=tags:_jsonparsefailure&size=1' | jq '.hits.hits[0]._source'
```

If `message` holds valid JSON, the deployed pipeline is not the shipped one;
redeploy `config/logstash-suricata.conf` (see [Logstash Issues](#logstash-issues)).
If `message` is truncated, the event exceeded the 64 KB UDP datagram limit
(large `fileinfo`/`http` payloads); these are rare and safe to ignore, or
disable that EVE type in Suricata.

## OpenSearch Issues

`install.sh` puts OpenSearch in `/opt/opensearch` (config
`/opt/opensearch/config/opensearch.yml`, JVM `/opt/opensearch/config/jvm.options`,
data `/opt/opensearch/data`, logs `/opt/opensearch/logs`).

### OpenSearch Not Starting

**Diagnosis:**
```bash
sudo journalctl -u opensearch -n 100
sudo tail -100 /opt/opensearch/logs/pfsense-monitoring.log
# Common errors:
# - "OutOfMemoryError"                → heap too large for the machine, or too small for the data
# - "max virtual memory areas ... too low" → vm.max_map_count
# - "failed to obtain node locks"     → another instance running or stale lock
```

**Solutions:**

Heap (min and max must match; never above 31 GB):
```bash
sudo sed -i 's/^-Xms.*/-Xms4g/; s/^-Xmx.*/-Xmx4g/' /opt/opensearch/config/jvm.options
sudo systemctl restart opensearch
```

`vm.max_map_count`:
```bash
sudo sysctl -w vm.max_map_count=262144
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/90-opensearch.conf
sudo systemctl restart opensearch
```

Port in use:
```bash
sudo ss -tlnp | grep 9200
```

### OpenSearch Running Slow

```bash
curl -s http://localhost:9200/_cluster/health | jq
curl -s 'http://localhost:9200/_cat/nodes?v&h=heap.percent,heap.current,heap.max'
curl -s 'http://localhost:9200/_cat/indices/suricata-*?v&s=store.size:desc' | head
```

Fixes, in order of effort: shorten the Grafana time range; set retention so old
indices are deleted (`./scripts/configure-retention-policy.sh 30`); raise the heap
(above); force-merge indices that are no longer written to
(`curl -X POST 'http://localhost:9200/suricata-YYYY.MM.*/_forcemerge?max_num_segments=1'`).

## Logstash Issues

Pipeline: `/etc/logstash/conf.d/suricata.conf` (from
`config/logstash-suricata.conf`). Log: `/var/log/logstash/logstash-plain.log`.

### Logstash Not Starting

**Diagnosis:**
```bash
sudo tail -50 /var/log/logstash/logstash-plain.log
# - "Address already in use"                              → UDP 5140 taken
# - "Couldn't find any output plugin named 'opensearch'"  → plugin lost in an upgrade
# - "Expected one of ..." / pipeline error                → config syntax
# - "Permission denied ... /usr/share/logstash/data"      → ownership after upgrade
```

**Solutions:**
```bash
# Plugin missing (happens after apt upgrade of logstash)
sudo /usr/share/logstash/bin/logstash-plugin install logstash-output-opensearch

# Data dir ownership
sudo chown -R logstash:logstash /usr/share/logstash/data

# Config test
sudo /usr/share/logstash/bin/logstash --config.test_and_exit -f /etc/logstash/conf.d/suricata.conf

sudo systemctl restart logstash
```

More post-upgrade fixes (including the Gemfile.lock case) are in
[CONFIGURATION.md → Logstash maintenance](../reference/CONFIGURATION.md#logstash-maintenance).

### Logstash Not Receiving Data

```bash
sudo ss -ulnp | grep 5140
echo '{"event_type":"test","timestamp":"2026-09-19T12:00:00.000000+0000"}' | nc -u -w1 localhost 5140
sleep 3; curl -s 'http://localhost:9200/suricata-*/_search?q=event_type:test&size=1' | jq .hits.total.value
curl -s localhost:9600/_node/stats/pipelines | jq '.pipelines.main.events'
```

If the local test works but nothing arrives from pfSense, it is the network or
the forwarder's baked-in target (see [Forwarder Running But No Events](#forwarder-running-but-no-events)).

**UDP buffer too small** (bursts dropped; `netstat -su | grep -i 'receive errors'`
climbs):
```bash
echo 'net.core.rmem_max=33554432' | sudo tee /etc/sysctl.d/90-logstash-udp.conf
sudo sysctl --system
sudo systemctl restart logstash    # pipeline already requests receive_buffer_bytes => 33554432
```

### Nested-Layout Config Still Deployed

If `grep -c 'suricata\]\[eve' /etc/logstash/conf.d/suricata.conf` returns more
than 0, the SIEM server is running the old pipeline. Redeploy:
```bash
./setup.sh      # step 3 copies config/logstash-suricata.conf and restarts Logstash
```
Then read the appendix in [DASHBOARD_NO_DATA_FIX.md](DASHBOARD_NO_DATA_FIX.md)
about the data written before the switch.

## Grafana Issues

### Can't Login to Grafana

The default credentials are `admin` / `admin` and Grafana asks you to change the
password on first login; do so, and put the new value in `GRAFANA_ADMIN_PASS` in
`config.env` so the scripts keep working. Reset if lost:
```bash
sudo grafana-cli admin reset-admin-password '<newpassword>'
```

### OpenSearch Datasource Fails Test

```bash
curl http://localhost:9200                     # from the Grafana host
sudo tail -50 /var/log/grafana/grafana.log
sudo grafana-cli plugins ls | grep opensearch  # plugin present?
```

Fixes: install the plugin (`sudo grafana-cli plugins install grafana-opensearch-datasource && sudo systemctl restart grafana-server`);
set the datasource URL to `http://localhost:9200` when Grafana and OpenSearch
share a host; set Flavor to *OpenSearch* and the version to what `curl` reports.

### Dashboard Imported But Panels Reference a Missing Datasource

`setup.sh` rewrites the datasource uid in every panel when it imports
`dashboards/Suricata_IDS_IPS.json` and `dashboards/Suricata_Per_Interface.json`.
If you imported through the Grafana UI instead, pick your OpenSearch datasource
in the import dialog's dropdown; no manual JSON editing is required. Re-import
through `./setup.sh` if in doubt.

### Panels Show "Unknown Visualization" or Odd Results

Some panel types behave poorly with the OpenSearch datasource (notably stat
panels driven by raw-document queries). `tests/test-panel-compatibility.sh`
exercises the combinations that are known to work. Switch the panel to *Table*
or *Time series* as a workaround. For the pf information panel on the pfSense
system dashboard see [Telegraf on pfSense → Troubleshooting](../pfsense/TELEGRAF_ON_PFSENSE.md);
for Telegraf interface-name quirks see
[TELEGRAF_PFBLOCKER_SETUP.md](../pfsense/TELEGRAF_PFBLOCKER_SETUP.md).

## Performance Issues

### High CPU Usage

OpenSearch: usually queries over too wide a time range or too many indices.
Check `curl -s 'http://localhost:9200/_tasks?actions=*search&detailed' | jq`;
shorten ranges and retention.

Logstash: `curl -s localhost:9600/_node/stats/pipelines | jq`. Add
`pipeline.workers: 4` to `/etc/logstash/logstash.yml` if `filtered` lags `in`.

Forwarder on pfSense: `ssh admin@<PFSENSE_IP> 'ps -o %cpu,rss,etime -p $(cat /var/run/suricata_forwarder.child.pid)'`.
A few percent is normal; sustained high CPU with debug enabled means turn debug
off (`DEBUG_ENABLED=false` in `config.env`, re-run `./setup.sh`).

### High Memory Usage

```bash
curl -s 'http://localhost:9200/_cat/nodes?v&h=heap.percent,heap.max'
```
Above ~85 % sustained: raise the heap (see above), or reduce retention.

### Disk Space Issues

```bash
df -h /opt/opensearch/data
curl -s 'http://localhost:9200/_cat/indices/suricata-*?v&s=store.size:desc' | head -20
```

Set or shorten retention rather than deleting by hand:
```bash
./scripts/configure-retention-policy.sh 30                # suricata-*
./scripts/configure-retention-policy.sh 30 'pfblockerng-*'
```

Emergency: `curl -X DELETE 'http://localhost:9200/suricata-YYYY.MM.*'` for a
month you no longer need.

## Network Issues

### Can't Access Grafana from Browser

```bash
sudo systemctl status grafana-server
sudo ss -tlnp | grep 3000
sudo ufw status | grep 3000
sudo ufw allow from 203.0.113.0/24 to any port 3000 proto tcp
```

### pfSense Can't Reach SIEM Server

```bash
ssh admin@<PFSENSE_IP> 'ping -c 3 <SIEM_IP>'
sudo ufw allow from <PFSENSE_IP> to any port 5140 proto udp
```

Also check pfSense's own outbound rules on the interface facing the SIEM server,
and that nothing NATs the source (the ufw rule matches on `<PFSENSE_IP>`).

## Common Error Messages

### "max file descriptors [4096] for opensearch process is too low"

`install.sh` writes the `nofile 65536` limits to `/etc/security/limits.conf`,
and the systemd unit sets `LimitNOFILE=65536`. If you see this, the unit was
edited; `sudo systemctl edit opensearch` and restore it.

### "flood stage disk watermark [95%] exceeded"

OpenSearch has made every index read-only. Free space (delete old indices, set
retention), then clear the block:
```bash
curl -X PUT 'http://localhost:9200/_all/_settings' -H 'Content-Type: application/json' \
  -d '{"index.blocks.read_only_allow_delete": null}'
```

### "failed to obtain node locks"

```bash
sudo systemctl stop opensearch
sudo pgrep -f org.opensearch.bootstrap && echo "still running; kill it first"
sudo rm -f /opt/opensearch/data/nodes/*/node.lock
sudo systemctl start opensearch
```

### "index_not_found_exception: no such index [suricata-YYYY.MM.DD]"

Auto-create is off. [OPENSEARCH_AUTO_CREATE.md](OPENSEARCH_AUTO_CREATE.md).

### "Could not index event ... mapper_parsing_exception ... geoip_src.location"

An index was created before the template was applied, so `location` was mapped
as a float array instead of `geo_point`. Apply the template
(`./scripts/install-opensearch-config.sh`); today's index must be deleted or
reindexed for the fix to take effect.

## After a pfSense Upgrade

pfSense upgrades can change the Python interpreter path, reset the crontab, or
remove `/usr/local/etc/rc.d/suricata_forwarder.sh`. Symptoms are a forwarder
that never comes back after reboot, or `suricata-watchdog: FAILED to start`
every minute in `system.log`.

```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status; crontab -l | grep watchdog; ls /usr/local/bin/python3*'
./setup.sh      # re-detects the interpreter and regenerates the service, watchdog and cron entry
```

The full checklist (Suricata package, Telegraf, GeoIP databases, SSH keys) is in
[PFSENSE_UPGRADE_GUIDE.md](../pfsense/PFSENSE_UPGRADE_GUIDE.md).

## Getting Help

1. **Gather diagnostic info:**
```bash
./scripts/diagnose-and-repair.sh > /tmp/diagnose.txt 2>&1
sudo journalctl -u opensearch -n 100 > /tmp/opensearch.log
sudo journalctl -u logstash -n 100 > /tmp/logstash.log
ssh admin@<PFSENSE_IP> 'tail -50 /var/log/suricata-forwarder.log; grep -E "suricata-(forwarder|watchdog)" /var/log/system.log | tail -50' > /tmp/forwarder.log
```
Scrub public IPs before sharing.

2. **Check documentation:**
   - OpenSearch: https://opensearch.org/docs/
   - Logstash: https://www.elastic.co/guide/en/logstash/current/index.html
   - Grafana OpenSearch plugin: https://grafana.com/grafana/plugins/grafana-opensearch-datasource/

3. **Open a GitHub issue** at https://github.com/ChiefGyk3D/pfsense-siem-stack/issues with the diagnostic output.

## Preventive Maintenance

**Weekly**
```bash
./scripts/status.sh
df -h /opt/opensearch/data
```

**Monthly**
```bash
curl -s http://localhost:9200/_cluster/health | jq .status
curl -s 'http://localhost:9200/_plugins/_ism/explain/suricata-*' | jq '.[] | select(type=="object") | .policy_id' | sort | uniq -c
sudo apt list --upgradable 2>/dev/null | grep -E 'logstash|grafana'   # read "Logstash maintenance" before upgrading
```

**After any pfSense or Suricata package update:** see
[After a pfSense Upgrade](#after-a-pfsense-upgrade).

**Related runbooks:** [DASHBOARD_NO_DATA_FIX.md](DASHBOARD_NO_DATA_FIX.md) ·
[OPENSEARCH_AUTO_CREATE.md](OPENSEARCH_AUTO_CREATE.md) ·
[LOG_ROTATION_FIX.md](LOG_ROTATION_FIX.md) (Suricata eve.json rotation) ·
[PFSENSE_FILTERLOG_ROTATION_FIX.md](PFSENSE_FILTERLOG_ROTATION_FIX.md) (pfSense filter.log rotation, affects pfBlockerNG panels) ·
[Telegraf on pfSense → Troubleshooting](../pfsense/TELEGRAF_ON_PFSENSE.md)
