# Configuration Reference

Every knob in the pfSense SIEM stack, where it lives, and which script reads it.
This is a reference, not a tutorial; for the install order see
[QUICK_START.md](../../QUICK_START.md). Field names and types for querying are in
[FIELD_REFERENCE.md](FIELD_REFERENCE.md).

## Contents

- [config.env](#configenv)
- [Forwarder (pfSense)](#forwarder-pfsense)
- [Logstash pipeline](#logstash-pipeline)
- [OpenSearch](#opensearch)
- [Grafana datasources](#grafana-datasources)
- [Tuning](#tuning)
- [Logstash maintenance](#logstash-maintenance)
- [Security](#security)

---

## config.env

`config.env` lives in the repository root, is created from `config.env.example`,
and is git-ignored. `setup.sh`, `preflight.sh`, `status.sh`,
`diagnose-and-repair.sh`, `install-opensearch-config.sh`,
`configure-retention-policy.sh` and the `tests/test-*.sh` scripts all `source`
it. (`install.sh` does **not** read it; it asks its own questions interactively.)

```bash
cp config.env.example config.env
nano config.env      # at minimum: SIEM_HOST, PFSENSE_HOST
```

| Variable | Default | Read by | Purpose |
|----------|---------|---------|---------|
| `SIEM_HOST` | `192.168.1.10` (example) | setup, preflight, status, diagnose, install-opensearch-config, configure-retention, tests | IP of the server running OpenSearch/Logstash/Grafana. **Required.** Baked into the forwarder as its UDP target. |
| `OPENSEARCH_PORT` | `9200` | setup, preflight, status, diagnose, install-opensearch-config, configure-retention | OpenSearch HTTP port. |
| `LOGSTASH_UDP_PORT` | `5140` | setup, status, diagnose | UDP port Logstash listens on. Must match `port =>` in the pipeline. Baked into the forwarder. |
| `GRAFANA_PORT` | `3000` | setup, diagnose, tests | Grafana HTTP port. |
| `GRAFANA_ADMIN_USER` | `admin` | setup, diagnose, tests | Grafana user used for API calls (datasource creation, dashboard import). |
| `GRAFANA_ADMIN_PASS` | `admin` | setup, diagnose, tests | Password for that user. Change it in Grafana on first login and update here. |
| `SIEM_SSH_USER` | your local username | setup, preflight, diagnose | SSH user on the SIEM server. Used by setup step 3 to deploy the Logstash pipeline and by step 5 to install the Grafana plugin; without SSH those steps print manual instructions instead. |
| `PFSENSE_HOST` | `192.168.1.1` (example) | setup, preflight, status, diagnose, tests | pfSense IP. **Required.** |
| `PFSENSE_USER` | `admin` | setup, preflight, status, diagnose, tests | SSH user on pfSense (`admin` on pfSense CE 2.7+, `root` on older releases). Key-based auth is required (`ssh-copy-id`). |
| `DEBUG_ENABLED` | `false` | setup → forwarder | Baked into the forwarder as its `DEBUG_ENABLED` default. `true` writes the debug log below. |
| `DEBUG_LOG` | `/var/log/suricata_forwarder_debug.log` | forwarder (env only) | Debug log path. Only honoured if exported into the forwarder's environment; `setup.sh` does not currently rewrite this default. |
| `INDEX_PREFIX` | `suricata` | setup, status, diagnose | Prefix of the daily Suricata indices (`suricata-YYYY.MM.DD`). Changing it also requires editing `index =>` in the Logstash pipeline, the `index_patterns` in the template, `action.auto_create_index`, and the Grafana datasource pattern; the shipped files assume `suricata`. |
| `RETENTION_DAYS` | `30` | setup (display only) | Shown in the setup banner. **Not applied automatically** by `setup.sh`; run `./scripts/configure-retention-policy.sh $RETENTION_DAYS` (default 90 if omitted). `install.sh` asks for its own value and applies it. |
| `INFLUXDB_HOST` / `INFLUXDB_PORT` / `INFLUXDB_DATABASE` | `localhost` / `8086` / `pfsense` | none | Reference values for the InfluxDB datasource used by the pfSense system dashboard. No script reads them; see [Grafana datasources](#grafana-datasources). |
| `INFLUXDB_USER` / `INFLUXDB_PASS` | commented out | none | Same, if your InfluxDB has auth. |
| `GEOIP_DB_PATH` | commented out | none (yet) | Reserved for pointing the forwarder at a non-standard GeoIP database. The shipped forwarder finds databases by searching a fixed list (below); leave this commented unless a future `setup.sh` documents otherwise. |

---

## Forwarder (pfSense)

Source: `scripts/forward-suricata-eve.py`. Deployed by `setup.sh` step 4 to
`/usr/local/bin/forward-suricata-eve.py`.

### What setup.sh does to it

1. Rewrites the three `os.getenv(...)` defaults at the top of the file with your
   `SIEM_HOST`, `LOGSTASH_UDP_PORT` and `DEBUG_ENABLED`.
2. Rewrites the shebang to the interpreter it found on pfSense (it tries
   `/usr/local/bin/python3`, then `python3.13`, `3.12`, `3.11`, then
   `/usr/bin/python3`). The file in the repo has a generic `#!/usr/bin/env python3`.
3. Installs an rc.d script at `/usr/local/etc/rc.d/suricata_forwarder.sh`. The
   `.sh` suffix matters: pfSense's `rc.start_packages` only runs
   `/usr/local/etc/rc.d/*.sh` at boot, and pfSense does not manage
   `/etc/rc.conf`, so the script defaults `suricata_forwarder_enable` to `YES`
   itself. It runs the forwarder under `daemon(8)` with `-r` (respawn on exit),
   pid files `/var/run/suricata_forwarder.pid` (supervisor) and
   `/var/run/suricata_forwarder.child.pid` (the forwarder), and stdout/stderr in
   `/var/log/suricata-forwarder.log`.
4. Installs `/usr/local/bin/suricata-forwarder-watchdog.sh` in root's crontab
   (`* * * * *`). If no forwarder process exists it starts the service and logs
   to syslog with tag `suricata-watchdog`.

```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'
ssh admin@<PFSENSE_IP> 'tail -f /var/log/suricata-forwarder.log'
ssh admin@<PFSENSE_IP> 'grep -E "suricata-(forwarder|watchdog)" /var/log/system.log | tail -20'
```

Re-run `./setup.sh` after a pfSense upgrade: the interpreter path may change and
the rc.d script refuses to start with a clear message if it has. See
[PFSENSE_UPGRADE_GUIDE.md](../pfsense/PFSENSE_UPGRADE_GUIDE.md).

### Runtime environment

| Variable | Default | Notes |
|----------|---------|-------|
| `SIEM_HOST` | `192.168.1.100` in the repo; your value after setup | Logstash host |
| `LOGSTASH_UDP_PORT` | `5140` | Logstash UDP port |
| `DEBUG_ENABLED` | `False` | `true` / `1` / `yes` enable |
| `DEBUG_LOG` | `/var/log/suricata_forwarder_debug.log` | Written only when debug is on |

Environment variables win over the baked-in defaults, which is handy for a
one-off test: `SIEM_HOST=203.0.113.20 DEBUG_ENABLED=true python3 /usr/local/bin/forward-suricata-eve.py`
(stop the service first, or you will have two forwarders).

### Behaviour

- **Discovery.** `find_eve_logs()` globs `/var/log/suricata/*/eve.json` once at
  start and starts one thread per file, all sharing one UDP socket. An interface
  enabled in Suricata *after* the forwarder started is picked up on the next
  restart (`service suricata_forwarder.sh restart`). No files at all is a fatal
  error.
- **Tail semantics.** Each thread seeks to the end of its file on open, so
  events written before start-up are never back-filled.
- **Rotation.** Each thread sleeps 0.1 s when idle; after
  `ROTATION_CHECK_CYCLES = 50` idle cycles (about five seconds without new lines)
  it re-checks the file's inode and size. Inode changed or file gone → reopen;
  size smaller than the read position → seek to the new end. A missing file is
  polled every five seconds. Details in
  [LOG_ROTATION_FIX.md](../troubleshooting/LOG_ROTATION_FIX.md).
- **GeoIP.** If `import maxminddb` succeeds (bundled with pfSense 2.8.1+), the
  first existing path from this list is opened, City databases first because
  only they include coordinates:
  `/usr/local/share/ntopng/GeoLite2-City.mmdb`,
  `/usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb`,
  `/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb`,
  `/usr/local/share/GeoIP/GeoLite2-City.mmdb`,
  `/usr/local/share/GeoIP/GeoLite2-Country.mmdb`,
  `/var/unbound/usr/local/share/GeoIP/GeoLite2-{City,Country}.mmdb`,
  `/var/db/GeoIP/GeoLite2-City.mmdb`, `/usr/share/GeoIP/GeoLite2-City.mmdb`.
  Public `src_ip`/`dest_ip` get `geoip_src`/`geoip_dest` objects (`country_code`,
  `country_name`, `continent_code`, and with a City DB `city_name`, `region_name`,
  `location` as `[lon, lat]`). Private, loopback, link-local and reserved
  addresses are skipped. Without a module or database the forwarder logs a
  warning and runs unenriched. Setup: [GEOIP_SETUP.md](../install/GEOIP_SETUP.md).
- **Transport.** One UDP datagram per event, raw JSON, no framing. Events over
  64 KB (rare; large `fileinfo`/`http` bodies) will be truncated by the network
  and dropped by Logstash as `_jsonparsefailure`.
- **Logging.** Syslog tag `suricata-forwarder` for lifecycle and rotation
  messages; debug log for per-1000-event progress and GeoIP hits.

---

## Logstash pipeline

Source: `config/logstash-suricata.conf`. Deployed to
`/etc/logstash/conf.d/suricata.conf` by `install.sh` (copy) and `setup.sh` step 3
(copy with the `hosts =>` line rewritten to `http://<SIEM_HOST>:<OPENSEARCH_PORT>`,
followed by `systemctl restart logstash`). The file is short and fully commented;
read it rather than a copy here. `config/README.md` covers deploying and editing
it by hand.

The important design point: **events are indexed flat**. The `json` filter
parses the datagram straight into the event root, so documents look like
`{"@timestamp": ..., "event_type": "alert", "src_ip": ..., "alert": {"signature": ...}, "geoip_src": {...}}`.
Nothing is nested under `suricata.eve.*`. The reasons:

- Grafana's OpenSearch datasource builds terms/histogram aggregations far more
  reliably on short keyword paths (`event_type`, `in_iface`, `alert.category`)
  than on deep object paths, and its field picker stays usable.
- The index template can map exactly the fields Suricata emits, with no wrapper
  object to keep in sync.
- Lucene queries in panels and alerts are shorter and match the field names in
  Suricata's own documentation.

An earlier revision of this project did nest under `suricata.eve`; if you are
upgrading from it, see the appendix in
[DASHBOARD_NO_DATA_FIX.md](../troubleshooting/DASHBOARD_NO_DATA_FIX.md).

Other pipeline facts worth knowing: `@timestamp` is taken from Suricata's own
`timestamp` field (not Logstash receive time); the raw `message` is removed
after parsing; the output index is `suricata-%{+YYYY.MM.dd}` in UTC, which is why
indices roll at midnight UTC.

Logs: `/var/log/logstash/logstash-plain.log`. Test a config change before
restarting:

```bash
sudo /usr/share/logstash/bin/logstash --config.test_and_exit -f /etc/logstash/conf.d/suricata.conf
sudo systemctl restart logstash
```

---

## OpenSearch

`install.sh` installs the OpenSearch 2.19.4 tarball, not the package:

| Item | Location |
|------|----------|
| Install | `/opt/opensearch` |
| Config | `/opt/opensearch/config/opensearch.yml` |
| JVM options | `/opt/opensearch/config/jvm.options` |
| Data | `/opt/opensearch/data` |
| Logs | `/opt/opensearch/logs` |
| Service | `opensearch.service` (systemd unit written by install.sh, runs as user `opensearch`) |

`opensearch.yml` as written by `install.sh`:

```yaml
cluster.name: pfsense-monitoring
node.name: siem-node-1
path.data: /opt/opensearch/data
path.logs: /opt/opensearch/logs
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
plugins.security.disabled: true
```

`network.host: 0.0.0.0` with the security plugin disabled means **anyone who can
reach TCP 9200 can read, write and delete every index**. Read
[Security](#security) before exposing the server beyond a trusted LAN.

### Index templates

Two composable index templates, both applied by `setup.sh` step 2 and by
`./scripts/install-opensearch-config.sh`:

| Template name | Pattern | Source file |
|---------------|---------|-------------|
| `suricata-template` | `suricata-*` | `config/opensearch-index-template.json` |
| `pfblockerng` | `pfblockerng-*` | `config/opensearch-pfblockerng-template.json` |

Both use 1 shard / 0 replicas / 5 s refresh. The Suricata template maps
`geoip_src.location` and `geoip_dest.location` as `geo_point`, `src_ip`/`dest_ip`
as `ip`, and the fields the dashboards aggregate on as `keyword`. The pfBlockerNG
template uses `dynamic_templates` to force every `tag.*`, `tail_ip_block_log.*` and
`tail_dnsbl_log.*` field that Telegraf produces to `keyword`. There is no
`filterlog` template. Full field list: [FIELD_REFERENCE.md](FIELD_REFERENCE.md).

Templates only affect indices created *after* they are applied. To fix an
existing index's mapping you must reindex or delete it.

### Auto-create

Both writers (Logstash and Telegraf) rely on OpenSearch creating each day's index
on first write. `setup.sh` / `install-opensearch-config.sh` set:

```
action.auto_create_index: pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*
```

as a persistent cluster setting. Why it matters and how to verify:
[OPENSEARCH_AUTO_CREATE.md](../troubleshooting/OPENSEARCH_AUTO_CREATE.md).

### Retention

`./scripts/configure-retention-policy.sh [DAYS] [PATTERN]` (defaults `90`,
`suricata-*`) creates an ISM policy `delete-after-<DAYS>d` whose `ism_template`
attaches it to new indices and applies it to existing ones. `install.sh` runs it
with the retention you chose. Run it a second time with `pfblockerng-*` if you
want the same for pfBlockerNG data. See
[MULTI_INTERFACE_RETENTION.md](../operations/MULTI_INTERFACE_RETENTION.md).

---

## Grafana datasources

Grafana 12.3.0 from the Grafana OSS apt repo; config `/etc/grafana/grafana.ini`,
logs `/var/log/grafana/grafana.log`. The `grafana-opensearch-datasource` plugin
is installed by `install.sh` and, if missing, by `setup.sh` step 5 over SSH.

| Datasource name | Type | Index / database | Time field | Created by |
|-----------------|------|------------------|------------|------------|
| `OpenSearch-Suricata` | `grafana-opensearch-datasource` | `suricata-*` | `@timestamp` | `setup.sh` if no OpenSearch datasource exists yet (uid `opensearch-suricata`); otherwise the first existing OpenSearch datasource is reused |
| `OpenSearch-pfBlockerNG` | `grafana-opensearch-datasource` | `pfblockerng-*` | `@timestamp` | `setup.sh` (URL `http://localhost:9200`, PPL enabled) |
| `InfluxDB-pfSense` | `influxdb` (InfluxQL) | database `pfsense` | n/a | you, by hand; needed only for the pfSense system dashboard fed by Telegraf's InfluxDB output |
| `Prometheus` | `prometheus` | n/a | n/a | optional; only for the extra `prometheus_stats.json` / `windows_exporter.json` dashboards |

For every OpenSearch datasource set **Flavor: OpenSearch**, **Version: 2.19.4**
(or whatever `curl http://<SIEM_IP>:9200` reports), and leave *Log message field*
empty.

Dashboards: `setup.sh` imports `dashboards/Suricata_IDS_IPS.json` (uid
`suricata_ids_ips`) and `dashboards/Suricata_Per_Interface.json` (uid
`suricata_per_interface`), rewriting every panel's datasource reference to the
real OpenSearch datasource uid, so no manual `sed` of `${DS_OPENSEARCH}` is
needed. `dashboards/pfsense_pfblockerng_system.json` needs the InfluxDB
datasource and is imported by hand. See [dashboards/README.md](../../dashboards/README.md).

---

## Tuning

**OpenSearch heap.** `install.sh` sets `-Xms`/`-Xmx` in
`/opt/opensearch/config/jvm.options` to half of RAM, capped at 16 GB. Rules: min
equals max; never above 31 GB (compressed object pointers stop working); leave
the rest for the page cache, which is what makes searches fast.

```bash
sudo sed -i 's/^-Xms.*/-Xms8g/; s/^-Xmx.*/-Xmx8g/' /opt/opensearch/config/jvm.options
sudo systemctl restart opensearch
curl -s 'http://localhost:9200/_cat/nodes?v&h=heap.percent,heap.max'
```

**Logstash heap.** `/etc/logstash/jvm.options`, default 1 GB. 2 GB is plenty for
tens of thousands of events per minute; more only if you see GC warnings in
`logstash-plain.log`. Workers: `pipeline.workers` in `/etc/logstash/logstash.yml`
(defaults to CPU count).

**UDP receive buffer.** The pipeline asks for a 32 MB socket buffer
(`receive_buffer_bytes => 33554432`), but the kernel silently caps it at
`net.core.rmem_max`, which is 208 KB on stock Ubuntu. Raise the cap or bursts
from several Suricata interfaces will be dropped before Logstash sees them:

```bash
echo 'net.core.rmem_max=33554432' | sudo tee /etc/sysctl.d/90-logstash-udp.conf
sudo sysctl --system
sudo systemctl restart logstash
```

Check for drops with `netstat -su | grep -i 'receive errors'` (or `ss -u -m` on
the 5140 socket). `install.sh` also sets `vm.max_map_count=262144`,
`vm.swappiness=1` and the `nofile`/`memlock` limits OpenSearch needs.

**Suricata side.** Fewer EVE types (drop `flow` and `stats` if you never chart
them) is the cheapest way to cut event volume; see
[SURICATA_OPTIMIZATION_GUIDE.md](../pfsense/SURICATA_OPTIMIZATION_GUIDE.md).

---

## Logstash maintenance

Logstash 8.19.7 comes from the Elastic 8.x apt repo, so `apt upgrade` will move
it. Three things break after an upgrade and are worth checking before you go
hunting for data-flow bugs:

1. **Output plugin missing.** `logstash-output-opensearch` is a third-party
   plugin and is not preserved across package upgrades. Symptom in
   `logstash-plain.log`: `Couldn't find any output plugin named 'opensearch'`.
   ```bash
   sudo /usr/share/logstash/bin/logstash-plugin install logstash-output-opensearch
   sudo systemctl restart logstash
   ```
2. **Data directory ownership.** The package sometimes leaves
   `/usr/share/logstash/data` owned by root, and the service (user `logstash`)
   fails with `Permission denied` on `.lock` or `uuid`.
   ```bash
   sudo chown -R logstash:logstash /usr/share/logstash/data
   ```
3. **Gemfile.lock out of sync.** If plugin install fails with a bundler
   "Gemfile.lock" conflict, remove the lock and let Logstash regenerate it:
   ```bash
   sudo rm /usr/share/logstash/Gemfile.lock
   sudo /usr/share/logstash/bin/logstash-plugin install logstash-output-opensearch
   ```

To pin the version and avoid surprises: `sudo apt-mark hold logstash`.

---

## Security

The stack as installed is designed for a **trusted management LAN**. Three
things to do before anything else can reach it:

**Restrict ports with ufw.** `install.sh` opens 9200/tcp, 5140/udp and 3000/tcp
to everyone. Tighten them to the hosts that need them (Grafana talks to
OpenSearch over `localhost`, so 9200 rarely needs to be open at all):

```bash
sudo ufw delete allow 9200/tcp
sudo ufw allow from <ADMIN_WORKSTATION_IP> to any port 9200 proto tcp comment 'OpenSearch admin'
sudo ufw delete allow 5140/udp
sudo ufw allow from <PFSENSE_IP> to any port 5140 proto udp comment 'Suricata forwarder'
sudo ufw delete allow 3000/tcp
sudo ufw allow from 203.0.113.0/24 to any port 3000 proto tcp comment 'Grafana LAN'
sudo ufw status numbered
```

Remember that `setup.sh`, `status.sh` and `diagnose-and-repair.sh` need 9200 from
wherever you run them.

**Change the Grafana admin password** on first login (Grafana prompts), or with
`sudo grafana-cli admin reset-admin-password '<new>'`, then update
`GRAFANA_ADMIN_PASS` in `config.env`. `install.sh` sets it for you if you gave it
one.

**OpenSearch security plugin.** It is disabled (`plugins.security.disabled: true`)
because enabling it means TLS on 9200, users and roles, and matching changes in
the Logstash output (`user`/`password`/`ssl`), the Grafana datasources (basic
auth) and Telegraf's `[[outputs.opensearch]]`. That is on the
[ROADMAP.md](../../ROADMAP.md); until then treat network access to 9200 as
administrative access to all data. Do not put the SIEM server on a network
segment that untrusted devices can reach.

---

## See also

- [config/README.md](../../config/README.md): deploying and editing the config files by hand
- [scripts/README.md](../../scripts/README.md): what every helper script does
- [FIELD_REFERENCE.md](FIELD_REFERENCE.md): field names and types
- [TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md)
- [INSTALL_SIEM_STACK.md](../install/INSTALL_SIEM_STACK.md) and [INSTALL_PFSENSE_FORWARDER.md](../install/INSTALL_PFSENSE_FORWARDER.md)
