# Scripts Reference

Every file in `scripts/`, what it does, where it runs, and whether it is still
current. **Most users only ever run `../setup.sh`** (which calls several of these
for you) plus `status.sh` and `diagnose-and-repair.sh` when something breaks.

Where a script runs:

| Location | Meaning |
|----------|---------|
| **Workstation** | Run from a checkout of this repo on any machine that can reach the SIEM server (HTTP) and pfSense (SSH). Reads `config.env` from the repo root. The SIEM server itself works fine as the "workstation". |
| **SIEM server** | Must run on the Ubuntu host that runs OpenSearch/Logstash/Grafana (uses `systemctl`). |
| **pfSense** | Runs on the firewall. `setup.sh` deploys the current ones for you. |

Status: **current** = used by `setup.sh` or supported as a standalone tool;
**legacy** = kept in the tree for reference only, not installed by `setup.sh`.

---

## Contents

**Workstation**
[preflight.sh](#preflightsh) ·
[status.sh](#statussh) ·
[diagnose-and-repair.sh](#diagnose-and-repairsh) ·
[install-opensearch-config.sh](#install-opensearch-configsh) ·
[configure-retention-policy.sh](#configure-retention-policysh) ·
[enable-selective-blocking.sh](#enable-selective-blockingsh) ·
[check-telegram-alerts.sh](#check-telegram-alertssh) ·
[deploy-wazuh-dashboards.py](#deploy-wazuh-dashboardspy) ·
[check-doc-links.py](#check-doc-linkspy)

**SIEM server**
[restart-services.sh](#restart-servicessh)

**pfSense**
[forward-suricata-eve.py](#forward-suricata-evepy) ·
[suricata-forwarder-watchdog.sh](#suricata-forwarder-watchdogsh) ·
[apply-suricata-drop-rules.sh](#apply-suricata-drop-rulessh) ·
[check_custom_sids.sh](#check_custom_sidssh)

**Legacy (pfSense)**
[setup_forwarder_monitoring.sh](#setup_forwarder_monitoringsh) ·
[suricata-eve-forwarder.sh](#suricata-eve-forwardersh) ·
[suricata-restart-hook.sh](#suricata-restart-hooksh) ·
[suricata-restart-with-forwarder.sh](#suricata-restart-with-forwardersh) ·
[unified-monitoring-watchdog.sh](#unified-monitoring-watchdogsh)

---

## Workstation scripts

### preflight.sh

**Status:** current (run automatically by `setup.sh`; skip with `--skip-preflight`)

Read-only sanity checks to run before `install.sh` / `setup.sh`. Makes no changes
to any host.

```bash
./scripts/preflight.sh
```

Checks: `config.env` exists and defines `SIEM_HOST`, `PFSENSE_HOST` (warns if
`PFSENSE_USER` / `SIEM_SSH_USER` are missing and applies defaults); key-based SSH
to pfSense (hard failure) and to the SIEM server (warning only, since `setup.sh`
can fall back to manual Logstash deployment); `python3` present on pfSense; the
OpenSearch port reachable (warning only, it will not exist before `install.sh`);
a GeoIP database present on pfSense (warning only, enrichment is optional).

Exit status 0 when all hard checks pass, 1 otherwise.

### status.sh

**Status:** current

Quick health report for the whole pipeline. Reads `config.env`; needs `curl`,
`jq`, and SSH access to pfSense for the firewall half.

```bash
./scripts/status.sh
```

Reports: OpenSearch reachability and cluster health; whether
`action.auto_create_index` covers `suricata-*` and `pfblockerng-*`; Logstash UDP
port; `suricata-*` index list, total count and age of the latest event;
pfBlockerNG event counts in `pfblockerng-*` (and, if the `influx` CLI is present,
in the legacy InfluxDB `pfsense` database); on pfSense, the forwarder process and
the eve.json files it has open, the watchdog crontab entry, Suricata log
freshness, and `filter.log` health (age and whether `filterlog` still holds the
file open, see [PFSENSE_FILTERLOG_ROTATION_FIX.md](../docs/troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md)).

Exit status is 0 when everything passed, 1 otherwise. Makes no changes.

### diagnose-and-repair.sh

**Status:** current

Guided diagnosis of the full chain, with a handful of safe automatic fixes.
Reads `config.env` (requires `SIEM_HOST` and `PFSENSE_HOST`); uses SSH to pfSense
and, where possible, to the SIEM server.

```bash
./scripts/diagnose-and-repair.sh
```

Six steps: network connectivity → OpenSearch health → Logstash → pfSense
forwarder → Grafana → an end-to-end test event (`event_type: test_diagnostic`,
sent over UDP and looked up in OpenSearch ten seconds later).

Fixes it applies on its own: enables `action.auto_create_index`, installs the
index template from `config/opensearch-index-template.json` if it is missing or
still has the old nested layout, and starts the forwarder on pfSense (via
`service suricata_forwarder.sh restart` when the rc.d script is installed, else a
one-off `nohup` start with whichever `python3` it finds). Everything else is
reported with the exact command to run. Exit status is the number of errors.

Notes: it looks the Suricata template up under the name `${INDEX_PREFIX}` (i.e.
`suricata`), whereas `setup.sh` and `install-opensearch-config.sh` install it as
`suricata-template`, so it can report the template as missing and create a second
copy with identical mappings; harmless, but do not be alarmed by two templates.

### install-opensearch-config.sh

**Status:** current (the same work is done inline by `setup.sh` step 2; run this
when you only need to redo the OpenSearch side)

```bash
./scripts/install-opensearch-config.sh
# or, without config.env:
OPENSEARCH_HOST=<SIEM_IP> ./scripts/install-opensearch-config.sh
```

Reads `config.env` if present (`SIEM_HOST` / `OPENSEARCH_HOST`, `OPENSEARCH_PORT`;
defaults to `localhost:9200`). Then, against that OpenSearch:

1. `PUT _index_template/suricata-template` from `config/opensearch-index-template.json` (pattern `suricata-*`: flat root-level fields, `geo_point` for `geoip_src.location` / `geoip_dest.location`, `keyword` for `event_type`, `in_iface`, `alert.category`, and so on).
2. `PUT _index_template/pfblockerng` from `config/opensearch-pfblockerng-template.json` (pattern `pfblockerng-*`: keyword mappings for the Telegraf `tag.*`, `tail_ip_block_log.*` and `tail_dnsbl_log.*` fields). Skipped with a warning if the file is missing.
3. Sets the persistent cluster setting `action.auto_create_index` to `pfblockerng-*,suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*`.
4. Verifies by creating a throw-away `suricata-test-<epoch>` index, checking the `geo_point` mapping landed, and deleting it.
5. Creates today's `suricata-YYYY.MM.DD` index if it does not exist.

There are exactly two templates. There is no `filterlog-*` template; pfBlockerNG
data arrives from Telegraf's `[[outputs.opensearch]]`, not Logstash. Why auto-create
matters: [OPENSEARCH_AUTO_CREATE.md](../docs/troubleshooting/OPENSEARCH_AUTO_CREATE.md).

### configure-retention-policy.sh

**Status:** current (called by `install.sh` with the retention you chose)

Creates an OpenSearch ISM (Index State Management) policy that deletes indices
once they are older than N days and attaches it to matching indices, existing and
future. No prompt; arguments are positional.

```bash
./scripts/configure-retention-policy.sh            # 90 days, suricata-*
./scripts/configure-retention-policy.sh 30         # 30 days
./scripts/configure-retention-policy.sh 180 'pfblockerng-*'
```

Reads `config.env` for `SIEM_HOST` / `OPENSEARCH_HOST` and `OPENSEARCH_PORT`
(exits if no host is set). The policy is named `delete-after-<N>d`; its
`ism_template` binds it to the index pattern so new daily indices pick it up
automatically. Re-run with a different number to change retention. Verify with
`curl -s http://<SIEM_IP>:9200/_plugins/_ism/explain/suricata-* | jq`.

### enable-selective-blocking.sh

**Status:** current (interactive; optional)

Writes a `dropsid.conf` into every Suricata instance directory on pfSense
(`/usr/local/etc/suricata/suricata_*/`) listing the Emerging Threats categories
that are safe to switch from alert to drop (botcc, compromised, malware,
exploit_kit, worm, ciarmy, drop, dshield, trojan, phishing, shellcode,
adware_pup, mobile_malware). Everything else stays in alert mode.

```bash
PFSENSE_HOST=<PFSENSE_IP> PFSENSE_USER=admin ./scripts/enable-selective-blocking.sh
```

Reads `PFSENSE_HOST` / `PFSENSE_USER` from the environment (defaults
`192.168.1.1` / `admin`; export them or source `config.env` first). It only writes
the files; you must then enable *Inline* IPS mode and "Auto-manage SID state
lists" per interface in the pfSense GUI and update rules, as the script prints at
the end. See [SURICATA_CONFIGURATION.md](../docs/pfsense/SURICATA_CONFIGURATION.md).

### check-telegram-alerts.sh

**Status:** current (investigation helper; optional)

Despite the name, this has nothing to do with Telegram *notifications*. It
SSHes to pfSense and scans the tail of every `/var/log/suricata/suricata_*/eve.json`
with `jq` for Suricata **alerts whose signature mentions the Telegram messenger
app**, then prints the matching events, the top source IPs and a per-hour count.
It sends nothing anywhere.

```bash
./scripts/check-telegram-alerts.sh [PFSENSE_IP] [PFSENSE_USER]   # defaults to PFSENSE_HOST/PFSENSE_USER from config.env
```

Connects as `root@<PFSENSE_IP>` and needs `jq` on pfSense. If your SSH user is
`admin`, edit the `ssh root@` lines.

### deploy-wazuh-dashboards.py

**Status:** current (only relevant if you also run Wazuh)

Standard-library-only Python that creates the `OpenSearch-Wazuh` datasource in
Grafana, creates a "SIEM Alerts" folder, imports the three dashboards in
`dashboards/wazuh/`, and verifies each panel query returns data.

```bash
python3 scripts/deploy-wazuh-dashboards.py \
  --grafana http://<SIEM_IP>:3000 --user admin --pass '<grafana-password>' \
  --wazuh-url https://<WAZUH_INDEXER>:9200 --wazuh-user admin --wazuh-pass '<indexer-password>'
python3 scripts/deploy-wazuh-dashboards.py --verify-only    # queries only, no changes
```

Flags can also be given as `GRAFANA_URL`, `GRAFANA_USER`, `GRAFANA_PASS`,
`WAZUH_INDEXER_URL`, `WAZUH_INDEXER_USER`, `WAZUH_INDEXER_PASS`; `--skip-verify`
disables TLS verification for a self-signed indexer certificate. See
[dashboards/wazuh/README.md](../dashboards/wazuh/README.md) and
[docs/siem/wazuh/README.md](../docs/siem/wazuh/README.md).

### release.sh

**Runs on:** maintainer workstation, on a clean `main` checkout · **Status:** current

Cuts a release: rolls the `[Unreleased]` section of `CHANGELOG.md` into `[X.Y.Z] - <date>`,
writes `VERSION`, bumps the version string in `pfsense-siem`, commits `release: vX.Y.Z` and
creates the annotated tag `vX.Y.Z`. Nothing is pushed unless you pass `--push`.

```bash
scripts/release.sh 2.1.0            # commit + tag locally, then review with: git show v2.1.0
scripts/release.sh 2.1.0 --push     # also push main and the tag
```

Pushing the tag triggers `.github/workflows/release.yml`, which re-runs the lint checks,
builds `pfsense-siem-stack-X.Y.Z.tar.gz` + `SHA256SUMS`, and publishes a GitHub Release with
the matching CHANGELOG section as notes. Versioning rules: see
[CONTRIBUTING.md → Releases](../CONTRIBUTING.md#%EF%B8%8F-releases-maintainers).

### check-doc-links.py

**Status:** current (run by CI)

Checks every relative link and image reference in git-tracked `*.md` files and
exits 1 if any target does not exist. Skips fenced code blocks, external URLs and
pure `#anchors`; for `file.md#section` only the file is checked.

```bash
python3 scripts/check-doc-links.py
```

---

## SIEM server scripts

### restart-services.sh

**Status:** current

Restarts `opensearch`, `logstash` and `grafana-server` in that order with
`systemctl`, waiting three seconds and confirming each is active. Must run as
root on the SIEM server.

```bash
sudo ./scripts/restart-services.sh
```

On success it prints a reminder to run `./check-system-health.sh`; that script
does not exist. Use `./scripts/status.sh` (from any workstation) instead.

---

## pfSense scripts

### forward-suricata-eve.py

**Status:** current (deployed to `/usr/local/bin/forward-suricata-eve.py` by `setup.sh`)

The production forwarder. Tails **every** `/var/log/suricata/*/eve.json`
(`find_eve_logs()` globs at start-up, one thread per file), optionally adds
GeoIP fields, and sends each event as one UDP datagram of raw JSON to Logstash.
Exits with an error if it finds no eve.json files at all.

**Configuration** is read from environment variables, with defaults that
`setup.sh` rewrites from your `config.env` before copying the file to pfSense:

| Variable | Default in the shipped file | Meaning |
|----------|-----------------------------|---------|
| `SIEM_HOST` | `192.168.1.100` | Logstash host |
| `LOGSTASH_UDP_PORT` | `5140` | Logstash UDP port |
| `DEBUG_ENABLED` | `False` | `true`/`1`/`yes` enables the debug log |
| `DEBUG_LOG` | `/var/log/suricata_forwarder_debug.log` | Debug log path (only written when debug is on) |

`setup.sh` also rewrites the shebang to the Python interpreter it detects on
pfSense, so run it as `python3 /usr/local/bin/forward-suricata-eve.py` or, better,
through the service (below).

**GeoIP.** If the `maxminddb` module imports (it ships with pfSense 2.8.1+), the
forwarder opens the first database that exists from this list, City databases
first because only they carry coordinates for the map panel:

1. `/usr/local/share/ntopng/GeoLite2-City.mmdb`
2. `/usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb`
3. `/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb`
4. `/usr/local/share/GeoIP/GeoLite2-City.mmdb`
5. `/usr/local/share/GeoIP/GeoLite2-Country.mmdb`
6. `/var/unbound/usr/local/share/GeoIP/GeoLite2-City.mmdb`
7. `/var/unbound/usr/local/share/GeoIP/GeoLite2-Country.mmdb`
8. `/var/db/GeoIP/GeoLite2-City.mmdb`
9. `/usr/share/GeoIP/GeoLite2-City.mmdb`

Public `src_ip` / `dest_ip` values get a `geoip_src` / `geoip_dest` object with
`country_code`, `country_name`, `continent_code` and, from a City DB, `city_name`,
`region_name` and `location` as `[lon, lat]` (the GeoJSON order OpenSearch's
`geo_point` expects). Private, loopback, link-local and reserved addresses are
skipped. With no database or no module it logs a warning and forwards without
enrichment. Setup: [GEOIP_SETUP.md](../docs/install/GEOIP_SETUP.md).

**Rotation handling.** Each thread opens its file, seeks to the end (tail -f
behaviour, so nothing is back-filled on start), and reads lines. When no data
arrives it sleeps 0.1 s per cycle; after `ROTATION_CHECK_CYCLES = 50` idle
cycles (about five seconds of quiet) it re-stats the path: a changed or missing
inode means the file was rotated and the thread reopens it; a file shorter than
the current read position means truncation and it seeks to the new end. A
missing file is waited for in five-second steps. Details:
[LOG_ROTATION_FIX.md](../docs/troubleshooting/LOG_ROTATION_FIX.md).

**Logging.** Start-up, per-interface monitoring, rotation, truncation and errors
go to syslog with tag `suricata-forwarder` (`/var/log/system.log` on pfSense).
The debug log additionally records every 1000th forwarded event and GeoIP hits.
Stdout/stderr of the service go to `/var/log/suricata-forwarder.log`.

**Running it.** `setup.sh` installs an rc.d script at
`/usr/local/etc/rc.d/suricata_forwarder.sh` (pfSense only auto-starts rc.d
scripts that end in `.sh`), enables it with `sysrc`, and starts the forwarder
under `daemon(8)`, which restarts it if it dies:

```bash
service suricata_forwarder.sh status
service suricata_forwarder.sh restart
```

To stop a stray copy started some other way: `pkill -f forward-suricata-eve.py`
(the watchdog will bring the service back within a minute).

Unit tests for the rotation and GeoIP logic live in `tests/python/`.

### suricata-forwarder-watchdog.sh

**Status:** current concept; the deployed file is generated by `setup.sh`

Cron-driven safety net for the forwarder. `setup.sh` writes
`/usr/local/bin/suricata-forwarder-watchdog.sh` on pfSense and adds it to
**root's crontab** (via `crontab -`, not `/etc/crontab`) to run **every minute**:

```
* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh
```

The deployed script is short: if no `forward-suricata-eve.py` process exists it
clears stale pid files and runs `/usr/local/etc/rc.d/suricata_forwarder.sh start`.
Because `daemon(8)` already respawns a forwarder that crashes, the watchdog
mainly covers the cases where the supervisor itself is gone (killed by hand, or
the interpreter path changed after a pfSense upgrade, in which case it logs
"FAILED to start — run setup.sh again"). Actions are logged to syslog with tag
`suricata-watchdog`:

```bash
ssh admin@<PFSENSE_IP> 'grep suricata-watchdog /var/log/system.log | tail'
ssh admin@<PFSENSE_IP> 'crontab -l | grep watchdog'
```

Test it by killing the forwarder (`pkill -f forward-suricata-eve.py`) and
checking `service suricata_forwarder.sh status` a minute later.

The copy in `scripts/` is the older standalone version of the same idea. It adds
Suricata-restart detection, but it hard-codes `/usr/local/bin/python3.11`, starts
the forwarder with `nohup` outside the rc.d service, and falls back to
`killall -9 python3.11`. Do not copy it to pfSense by hand; let `setup.sh`
install the generated one.

### apply-suricata-drop-rules.sh

**Status:** current, but **hard-coded to the author's firewall — edit before use**

Works around the pfSense GUI's SID-management quirks by running
`suricata-update --drop-conf drop.conf` for each Suricata instance and copying
the generated `suricata.rules` over the instance's
`rules/suricata.rules`. Runs on pfSense.

Caveats: the `INSTANCES` variable names two specific instance directories
(`suricata_55721_ix0 suricata_50186_ix1`) which will not match yours; and it
**overwrites a rules file that the pfSense Suricata package manages**, so the
next GUI rule update will replace your changes. Use with care, and prefer
`enable-selective-blocking.sh` plus the GUI's SID-management tab where you can.

```bash
ssh admin@<PFSENSE_IP>
vi /usr/local/bin/apply-suricata-drop-rules.sh      # set INSTANCES
sh /usr/local/bin/apply-suricata-drop-rules.sh
```

### check_custom_sids.sh

**Status:** current (one-off investigation tool)

Run **on pfSense**. For a fixed list of SIDs (the ones commonly found in old
"disable these noisy rules" lists), checks whether each actually exists in any
`*.rules` file, in `sid-msg.map`, and in `threshold.config`, so you can drop
entries from `disablesid.conf` that refer to rules you do not have.

```bash
scp scripts/check_custom_sids.sh admin@<PFSENSE_IP>:/tmp/
ssh admin@<PFSENSE_IP> 'sh /tmp/check_custom_sids.sh'
```

Edit `CUSTOM_SIDS` at the top to check your own list. See
[config/sid/README.md](../config/sid/README.md).

---

## Legacy scripts (reference only)

None of these are installed by `setup.sh`. They predate the rc.d service and
watchdog, hard-code `/usr/local/bin/python3.11`, and several stop the forwarder
with `killall python3.11`, which kills **every** Python 3.11 process on the
firewall (including pfSense's own). Do not deploy them alongside the current
setup: two supervisors fighting over one process is a reliable way to get
duplicate forwarders and gaps in the data. They stay in the tree so the history
of the approach is readable; see [docs/ARCHIVE.md](../docs/ARCHIVE.md).

### setup_forwarder_monitoring.sh

Interactive menu that wrote `*/5 * * * *` keepalive and "no eve.json activity →
`killall python3.11` and restart" entries into root's crontab, with Hybrid /
Simple / 24-7 / Business-hours presets. Superseded by the every-minute watchdog.
Option 6 removes its own entries if you have them left over.

### suricata-eve-forwarder.sh

An earlier FreeBSD rc.d script (`suricata_eve_forwarder`) that ran the forwarder
under `daemon -r` with `pkill -9` pre/post hooks. Superseded by the
`suricata_forwarder.sh` rc.d script that `setup.sh` generates. (Not a shell
forwarder: the forwarder has always been the Python file.)

### suricata-restart-hook.sh

Intended to be dropped into the Suricata package's post-install hooks to restart
the forwarder after a Suricata restart, logging to
`/var/log/suricata-forwarder-restart.log`. Uses `killall python3.11`. Superseded
by the watchdog's restart detection.

### suricata-restart-with-forwarder.sh

Wrapper around `/usr/local/etc/rc.d/suricata.sh {start|stop|restart}` that also
restarted the forwarder (plus `forwarder-only` and `status` sub-commands).
Superseded by `service suricata_forwarder.sh restart`.

### unified-monitoring-watchdog.sh

Combined Telegraf + forwarder watchdog that restarted either when missing,
restarted the forwarder when Suricata PIDs changed, and (with the `activity`
argument, 09:00–23:00) when no eve.json had been modified for 15 minutes; logged
to `/var/log/unified-watchdog.log`. Uses `killall python3.11`. The forwarder half
is superseded by `suricata-forwarder-watchdog.sh`; for Telegraf see
[TELEGRAF_ON_PFSENSE.md](../docs/pfsense/TELEGRAF_ON_PFSENSE.md).

---

## Quick reference

Install and deploy: follow [QUICK_START.md](../QUICK_START.md) (`install.sh` on
the SIEM server, then `config.env` + `setup.sh`).

```bash
./scripts/status.sh                     # is everything up and flowing?
./scripts/diagnose-and-repair.sh        # find and fix the broken link in the chain
sudo ./scripts/restart-services.sh      # on the SIEM server
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'
ssh admin@<PFSENSE_IP> 'grep -E "suricata-(forwarder|watchdog)" /var/log/system.log | tail -20'
```

Related: [TROUBLESHOOTING.md](../docs/troubleshooting/TROUBLESHOOTING.md) ·
[CONFIGURATION.md](../docs/reference/CONFIGURATION.md) ·
[INSTALL_PFSENSE_FORWARDER.md](../docs/install/INSTALL_PFSENSE_FORWARDER.md)
