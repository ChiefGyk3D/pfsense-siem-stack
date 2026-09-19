# pfSense SIEM Stack - Management Console

> Menu-driven front end for the scripts in this repository

## Overview

`pfsense-siem` is an interactive menu that wraps `install.sh`, `setup.sh` and the
utilities in `scripts/`. Every option maps to a script you can also run directly; the
console just saves you remembering names and arguments. This page describes what each
option does and which script it calls.

For the end-to-end first install, follow [QUICK_START.md](../../QUICK_START.md) or the
[New User Checklist](../install/NEW_USER_CHECKLIST.md); this page is the reference you
come back to afterwards.

## Quick Start

```bash
chmod +x pfsense-siem
./pfsense-siem
```

Options 1 and 6 need root (`sudo ./pfsense-siem`). Everything else runs as your normal
user, using SSH to reach pfSense as `PFSENSE_USER`.

---

## Menu Structure

```
═══ Main Menu ═══

Installation:
  1) Install SIEM Stack (OpenSearch + Logstash + Grafana)
  2) Deploy to pfSense (Forwarder + Watchdog)
  3) Configure OpenSearch (Index templates + Settings)
  4) Import Dashboards to Grafana

Management:
  5) Check System Status (Health check all components)
  6) Restart Services (OpenSearch + Logstash + Grafana)
  7) View Logs (OpenSearch / Logstash / Grafana / Forwarder)
  8) Configure Retention Policy

pfSense Operations:
  9) Check Forwarder Status
 10) Restart Forwarder
 11) View Forwarder Logs
 12) Test pfSense Connectivity

Advanced:
 13) Verify Data Flow (End-to-end test)
 14) Configure Custom SIDs (Suricata rules)
 15) Search Suricata Alerts Mentioning Telegram (app)
 16) Backup Configuration
 17) Restore Configuration

Documentation:
 18) View Quick Start Guide
 19) Open Troubleshooting Guide
 20) Show Configuration

Checks:
 21) Preflight Check (run before install/deploy)

  0) Exit
```

If `config.env` is missing, any option that needs it offers to create one from
`config.env.example` and then returns to the menu so you can edit it.

---

## Installation (1-4)

### 1. Install SIEM Stack

Runs `sudo ./install.sh` on the SIEM server: checks RAM/disk/OS, walks through an
interactive configuration (monitoring mode, SIEM IP, pfSense IP, retention days, Grafana
password), installs OpenSearch 2.x, Logstash 8.x and Grafana 12.x, opens firewall ports,
and applies the retention policy. Writes a transcript to
`/var/log/pfsense-monitoring-install.log`.

Requirements: root, Ubuntu 22.04+/Debian 11+, 8 GB RAM (16 GB recommended), 100 GB disk.
Details: [INSTALL_SIEM_STACK.md](../install/INSTALL_SIEM_STACK.md).

### 2. Deploy to pfSense

Runs `./setup.sh`. Against pfSense it detects the Python interpreter, deploys
`/usr/local/bin/forward-suricata-eve.py` with your `config.env` values baked in, installs
the rc.d service `/usr/local/etc/rc.d/suricata_forwarder.sh` (boot start), installs the
watchdog `/usr/local/bin/suricata-forwarder-watchdog.sh` in root's crontab (every minute),
starts the service and confirms a PID. It also applies the OpenSearch template and
deploys the Logstash pipeline, so it is safe and normal to re-run it after a pfSense
upgrade or a config change.

Requirements: `config.env` filled in, SSH to pfSense as `PFSENSE_USER` (key auth
recommended), Suricata installed and running, Python 3 on pfSense (ships with pfSense).
Details: [INSTALL_PFSENSE_FORWARDER.md](../install/INSTALL_PFSENSE_FORWARDER.md) and
[SURICATA_FORWARDER_MONITORING.md](SURICATA_FORWARDER_MONITORING.md).

### 3. Configure OpenSearch

Runs `./scripts/install-opensearch-config.sh`: applies the `suricata-*` index template
(geo_point mapping for the map panels), enables `action.auto_create_index` for
`suricata-*` and `pfblockerng-*`, and sets cluster settings. Run this **before** the first
events arrive; indices created without the template need reindexing to get geo_point.
setup.sh (option 2) does this too, so you only need option 3 on its own if you skipped
setup.sh or changed the template.

### 4. Import Dashboards

Prints the list of dashboards and the manual Grafana import steps (Dashboards > Import >
upload JSON > pick datasource), then opens
[INSTALL_DASHBOARD.md](../install/INSTALL_DASHBOARD.md). It does not call the Grafana API.

Dashboards shipped in `dashboards/` (full inventory and datasource requirements in
[dashboards/README.md](../../dashboards/README.md)):

| File | Datasource(s) | Shows |
|------|---------------|-------|
| `Suricata_IDS_IPS.json` | OpenSearch (`suricata-*`) | WAN-side alerts, top signatures, GeoIP map |
| `Suricata_Per_Interface.json` | OpenSearch (`suricata-*`) | per-interface/VLAN alert views driven by `in_iface` |
| `pfsense_pfblockerng_system.json` | InfluxDB + OpenSearch (`pfblockerng-*`) | pfSense system metrics, interfaces, pfBlockerNG blocks/DNSBL |
| `windows_exporter.json` | Prometheus | Windows hosts via windows_exporter |
| `prometheus_stats.json` | Prometheus | Prometheus server self-metrics |
| `docker_container_monitoring.json` | Prometheus (cAdvisor) | container CPU/memory/network |
| `wazuh/*.json` | OpenSearch (Wazuh indexer) | security overview, vulnerability detection, FIM (see `dashboards/wazuh/README.md`) |

The console's own list only names the first three; the others are imported the same way.

---

## Management (5-8)

### 5. Check System Status

Runs `./scripts/status.sh`, the single most useful command in the repository. It checks,
in order:

- **SIEM server:** OpenSearch reachable and cluster health; auto-create enabled for
  `suricata-*` (and `pfblockerng-*`); Logstash UDP port listening; `suricata-*` index list
  with document counts; total events; newest `@timestamp` and its age.
- **pfBlockerNG:** `pfblockerng-*` document counts (IP block and DNSBL), newest event age.
- **pfSense (over SSH):** forwarder process running with PID (flags duplicates); `eve.json`
  files it has open; watchdog line in root's crontab; number of Suricata `eve.json` files
  and whether they were written in the last 5 minutes; **filterlog health** (filter.log
  age and whether `filterlog` has the file open, see
  [PFSENSE_FILTERLOG_ROTATION_FIX.md](../troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md)).

Exit code `0` means every check passed; otherwise `1`, with the count of failed checks and
common fixes printed in the summary. Suitable for running from a SIEM-side cron.

### 6. Restart Services

Runs `sudo ./scripts/restart-services.sh`: restarts OpenSearch, waits for the cluster,
then Logstash, then Grafana, reporting each service's status. Root required.

### 7. View Logs

Follows one log until Ctrl+C:

| Choice | Command |
|--------|---------|
| 1 OpenSearch | `journalctl -u opensearch -f` |
| 2 Logstash | `journalctl -u logstash -f` |
| 3 Grafana | `journalctl -u grafana-server -f` |
| 4 Forwarder | `ssh PFSENSE_USER@PFSENSE_HOST 'tail -f /var/log/system.log \| grep suricata'` |
| 5 All SIEM | `journalctl -u opensearch -u logstash -u grafana-server -f` |

Choice 4 shows the forwarder's and watchdog's syslog lines. Python tracebacks from a
crashing forwarder go to `/var/log/suricata-forwarder.log` on pfSense instead; see the
[day-2 table](SURICATA_FORWARDER_MONITORING.md#day-2-quick-reference).

### 8. Configure Retention Policy

Prompts for a number of days, runs `./scripts/configure-retention-policy.sh <DAYS>`, and
writes the value back to `RETENTION_DAYS` in `config.env`.

The script creates an OpenSearch **Index State Management (ISM)** policy named
`delete-after-<DAYS>d` that deletes `suricata-*` indices once they reach that age, and
attaches it to existing indices. (OpenSearch uses ISM; there is no Elasticsearch-style ILM
here.) Run directly, the script defaults to 90 days and takes an optional second argument
for the index pattern, e.g. `./scripts/configure-retention-policy.sh 90 'pfblockerng-*'`.
The `config.env` default is 30 days.

Rough sizing: `events/day x bytes/event x days`. Measure with
`curl -s http://<SIEM_IP>:9200/_cat/indices/suricata-*?v&h=index,docs.count,store.size`
after a few days. Details and the policy-change caveats:
[MULTI_INTERFACE_RETENTION.md](MULTI_INTERFACE_RETENTION.md).

---

## pfSense Operations (9-12)

### 9. Check Forwarder Status

Over SSH: finds the `forward-suricata-eve.py` PID, lists the `eve.json` files it has open
(`lsof`), and shows the last 10 `suricata-forwarder` lines from `/var/log/system.log`.

```
✓ Forwarder is running
  PID: 12345

Monitored interfaces:
  • /var/log/suricata/suricata_igc012345/eve.json
  • /var/log/suricata/suricata_igc167890/eve.json
  • /var/log/suricata/suricata_lagg0.10024680/eve.json

Recent activity (last 10 entries):
  Sep 18 10:15:23 pfSense suricata-forwarder: Starting — N interface(s), target=<SIEM_IP>:5140, GeoIP=enabled
  Sep 18 10:15:23 pfSense suricata-forwarder: Monitoring suricata_igc012345 (...) — GeoIP: enabled
```

If it is not running, use option 10; the watchdog will also restart it within a minute on
its own.

### 10. Restart Forwarder

If `/usr/local/etc/rc.d/suricata_forwarder.sh` exists (it does on any setup.sh deployment),
runs `service suricata_forwarder.sh restart` on pfSense and confirms the new PID. On a box
without the rc.d script it falls back to `pkill -f forward-suricata-eve` followed by a
direct start; re-run `./setup.sh` to get the service installed properly.

Use it after editing the forwarder or `config.env` (redeploy with option 2 first), after
adding a Suricata interface (new `eve.json` files are discovered at start), or when the
process is stuck. If the restart fails:

```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'
ssh admin@<PFSENSE_IP> 'tail -50 /var/log/suricata-forwarder.log'   # Python errors
ssh admin@<PFSENSE_IP> 'tail -50 /var/log/system.log | grep suricata'
ssh admin@<PFSENSE_IP> 'ls -la /usr/local/bin/forward-suricata-eve.py; head -1 /usr/local/bin/forward-suricata-eve.py'
```

A shebang pointing at a Python that no longer exists (after a pfSense upgrade) is the
usual cause; `./setup.sh` re-detects it.

### 11. View Forwarder Logs

`tail -f /var/log/system.log | grep suricata` on pfSense until Ctrl+C. You will see
startup lines, one `Monitoring ...` line per interface, `Rotation detected, reopening`
when Suricata rotates a log, send errors, and `suricata-watchdog` lines when the watchdog
had to restart the process.

### 12. Test pfSense Connectivity

Four quick checks against `PFSENSE_HOST`: ICMP ping, non-interactive SSH as
`PFSENSE_USER`, Suricata package present (`pkg info`), and a Python 3 interpreter
(`which python3 || which python3.11`).

```
Testing connection to 192.168.1.1...

  Ping test... ✓
  SSH test... ✓
  Suricata installed... ✓
  Python 3 available... ✓
```

- Ping fails: routing or a pfSense rule blocking ICMP from the SIEM host.
- SSH fails: enable SSH under System > Advanced > Secure Shell, and set up key auth
  (`ssh-copy-id admin@<PFSENSE_IP>`); the check uses `BatchMode`, so password-only access
  shows as a failure even if interactive SSH works.
- Suricata missing: install from System > Package Manager.
- Python missing: pfSense 2.7+ ships Python 3; otherwise `pkg install python311`.

Option 21 (Preflight) does a more thorough version of this.

---

## Advanced (13-17)

### 13. Verify Data Flow

End-to-end check: OpenSearch reachable; `_count` on `suricata-*`; newest `@timestamp`;
forwarder PID on pfSense. Then prints a test you run from a host behind pfSense:

```bash
curl http://testmyids.com
```

which triggers the `GPL ATTACK_RESPONSE id check returned root` signature; it should show
up in Grafana within about 30 seconds.

```
1. OpenSearch connectivity... ✓
2. Checking for events... ✓ 123456 events
3. Latest event age... ✓ 2026-09-18T10:15:30.000Z
4. Forwarder status... ✓ Running (PID: 12345)
```

### 14. Configure Custom SIDs

Runs `./scripts/check_custom_sids.sh` to compare the `disablesid.conf`/`enablesid.conf`
on pfSense with the versions in `config/sid/`. See
[config/sid/README.md](../../config/sid/README.md) and the
[Suricata Optimization Guide](../pfsense/SURICATA_OPTIMIZATION_GUIDE.md).

### 15. Search Suricata Alerts Mentioning Telegram (app)

Runs `./scripts/check-telegram-alerts.sh`. Despite the historical function name, this
has **nothing to do with Telegram notifications**. It searches recent Suricata alerts on
pfSense for signatures whose name contains "Telegram" (the messaging app, e.g. ET POLICY
rules), and prints the matching alerts, the top source IPs, and a per-hour count. It is a
canned example of hunting for one application's traffic in the alert stream.

Note: the script reads `PFSENSE_HOST` and `PFSENSE_USER` from `config.env`; run it directly to override them: `./scripts/check-telegram-alerts.sh <PFSENSE_IP> [PFSENSE_USER]`.

Alerting to Telegram (or anything else) is a Grafana feature: Alerting > Contact points.

### 16. Backup Configuration

Creates `~/pfsense-siem-backups/backup_YYYYMMDD_HHMMSS.tar.gz` containing `config.env`,
`dashboards/` and `config/` (Logstash pipeline, OpenSearch templates, SID lists). It does
**not** include OpenSearch data or Grafana's own database; export dashboards you have
modified in Grafana separately (Dashboard settings > JSON Model).

Equivalent: `tar -czf ~/backup.tar.gz config.env dashboards/ config/`.

### 17. Restore Configuration

Lists the archives in `~/pfsense-siem-backups/`, asks which to restore, and extracts it
over the repository directory, overwriting `config.env`, `dashboards/` and `config/`.
Take a fresh backup (option 16) first if you may want to roll back.

---

## Documentation and Checks (18-21)

- **18. View Quick Start Guide:** opens [QUICK_START.md](../../QUICK_START.md) in `less`.
- **19. Open Troubleshooting Guide:** opens
  [TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md).
- **20. Show Configuration:** prints the effective `config.env` values (SIEM host and ports,
  pfSense host and user, index prefix, retention, debug flag) and the path to the file.
- **21. Preflight Check:** runs `./scripts/preflight.sh`, which validates `config.env`, SSH
  to pfSense and (if set) the SIEM server, Python on pfSense, OpenSearch reachability and
  GeoIP database presence. Run it before options 1-2, or before `install.sh`/`setup.sh`
  from the shell. See [scripts/README.md](../../scripts/README.md).

---

## Configuration File (config.env)

`config.env` is read by the console and by every script. Create it from the example:

```bash
cp config.env.example config.env
nano config.env
```

Every variable in `config.env.example`:

| Variable | Default | Used for |
|----------|---------|----------|
| `SIEM_HOST` | `192.168.1.10` | IP of the server running OpenSearch/Logstash/Grafana; baked into the forwarder as its UDP target. **Required.** |
| `OPENSEARCH_PORT` | `9200` | OpenSearch HTTP port |
| `LOGSTASH_UDP_PORT` | `5140` | Logstash UDP input the forwarder sends to |
| `GRAFANA_PORT` | `3000` | Grafana web UI |
| `GRAFANA_ADMIN_USER` | `admin` | shown in dashboard-import instructions |
| `GRAFANA_ADMIN_PASS` | `admin` | change it; do not run Grafana with the default |
| `SIEM_SSH_USER` | (commented; your current user) | SSH user setup.sh uses to deploy the Logstash pipeline on the SIEM server |
| `PFSENSE_HOST` | `192.168.1.1` | pfSense IP. **Required.** |
| `PFSENSE_USER` | `admin` | SSH user on pfSense (`admin` on pfSense CE 2.7+; `root` on older releases) |
| `DEBUG_ENABLED` | `false` | forwarder writes a verbose per-event debug log on pfSense; troubleshooting only |
| `DEBUG_LOG` | `/var/log/suricata_forwarder_debug.log` | where that debug log goes |
| `INDEX_PREFIX` | `suricata` | index name prefix (`suricata-YYYY.MM.dd`) |
| `RETENTION_DAYS` | `30` | days to keep data; applied through `scripts/configure-retention-policy.sh` |
| `INFLUXDB_HOST` | `localhost` | InfluxDB for pfSense system metrics via Telegraf |
| `INFLUXDB_PORT` | `8086` | InfluxDB port |
| `INFLUXDB_DATABASE` | `pfsense` | InfluxDB database name |
| `INFLUXDB_USER` / `INFLUXDB_PASS` | (commented) | InfluxDB credentials if authentication is enabled |
| `GEOIP_DB_PATH` | (commented; auto-detected) | override only if your GeoLite2 `.mmdb` is in a non-standard location on pfSense |

`pfblockerng-*` indices need no setting here; Telegraf's `[[outputs.opensearch]]` names
them. Field-level detail is in [CONFIGURATION.md](../reference/CONFIGURATION.md).

---

## Common Workflows

**First-time setup:** follow [QUICK_START.md](../../QUICK_START.md). In console terms it is
21 (preflight) > 1 (install, as root) > 2 (deploy; also configures OpenSearch) > 4 (import
dashboards) > 13 (verify). The
[New User Checklist](../install/NEW_USER_CHECKLIST.md) has the long form with validation
steps.

**Daily / weekly:** option 5. It covers the SIEM, the forwarder, the watchdog and
filterlog in one pass and exits non-zero on trouble.

**Something is wrong:**

| Symptom | Try |
|---------|-----|
| No data in Grafana | 13 (where does the chain break?), then 9 and 7/2 (Logstash) |
| Forwarder not running | 10, then 11 to watch it start; if it dies again, see [SURICATA_FORWARDER_MONITORING.md](SURICATA_FORWARDER_MONITORING.md#troubleshooting) |
| pfBlockerNG panels empty | 5 shows filterlog health; fix per [PFSENSE_FILTERLOG_ROTATION_FIX.md](../troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md) |
| SIEM services down | 6, then 5 |
| After a pfSense upgrade | 2 (re-run setup.sh), then 5; see [PFSENSE_UPGRADE_GUIDE.md](../pfsense/PFSENSE_UPGRADE_GUIDE.md) |

Everything else: [TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md).

**Periodic maintenance:** 16 (backup) monthly; 8 (retention) when disk fills or you want
more history; 14 (SIDs) after tuning rules.

---

## Exit Codes

- `0`: success / all checks passed
- `1`: general error, or (for `status.sh`) one or more checks failed; the count is printed

---

## Troubleshooting the Console Itself

- **Garbled menu / colours:** `export TERM=xterm-256color`.
- **`command not found`:** `chmod +x pfsense-siem` and run it as `./pfsense-siem`.
- **Can't find config.env:** `cp config.env.example config.env` and edit it, or accept the
  prompt the console offers.
- **Permission denied:** options 1 and 6 need `sudo ./pfsense-siem` (or `sudo ./install.sh`,
  `sudo ./scripts/restart-services.sh`).
- **SSH prompts for a password inside the console:** set up key auth to pfSense
  (`ssh-copy-id admin@<PFSENSE_IP>`); several checks use `BatchMode=yes` and will report
  failure rather than prompt.

---

## Support & Documentation

- [Main README](../../README.md)
- [Quick Start](../../QUICK_START.md)
- [Troubleshooting](../troubleshooting/TROUBLESHOOTING.md)
- [Documentation Index](../DOCUMENTATION_INDEX.md)
- [Scripts Reference](../../scripts/README.md)

Issues and discussions: https://github.com/ChiefGyk3D/pfsense-siem-stack
