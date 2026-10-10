# Suricata Forwarder: Running, Watchdog and Recovery

How the Suricata EVE JSON forwarder (`forward-suricata-eve.py`) runs on pfSense, how
it is kept alive, and the day-2 commands you will actually use.

Everything described here is installed by `./setup.sh`. You do not need to hand-edit
crontabs or write your own keepalive loop.

## Table of Contents
- [How the forwarder runs](#how-the-forwarder-runs)
- [The watchdog](#the-watchdog)
- [What setup.sh installs](#what-setupsh-installs)
- [Day-2 quick reference](#day-2-quick-reference)
- [Verifying data flow end to end](#verifying-data-flow-end-to-end)
- [After Suricata restarts or rule reloads](#after-suricata-restarts-or-rule-reloads)
- [What survives reboot and upgrade](#what-survives-reboot-and-upgrade)
- [Uninstall](#uninstall)
- [Troubleshooting](#troubleshooting)

---

## How the forwarder runs

The forwarder is a single Python process that tails every `/var/log/suricata/*/eve.json`
(one thread per file), enriches events with GeoIP, and sends each event as a UDP
datagram to Logstash on `SIEM_HOST:LOGSTASH_UDP_PORT` (default 5140). It detects log
rotation itself (inode change, truncation, file disappearing) and reopens files without
a restart.

On pfSense it runs as an rc.d service:

| Component | Path |
|-----------|------|
| Forwarder | `/usr/local/bin/forward-suricata-eve.py` |
| rc.d service | `/usr/local/etc/rc.d/suricata_forwarder.sh` |
| PID files | `/var/run/suricata_forwarder.pid` (the `daemon(8)` supervisor) and `/var/run/suricata_forwarder.child.pid` (the forwarder itself) |
| Daemon log (stdout/stderr) | `/var/log/suricata-forwarder.log` |
| Syslog tags | `suricata-forwarder` (forwarder), `suricata-watchdog` (watchdog) in `/var/log/system.log` |
| Debug log (only when `DEBUG_ENABLED=true`) | `/var/log/suricata_forwarder_debug.log` |

Two pfSense-specific details explain the design:

- **The service file ends in `.sh`.** pfSense only auto-starts `*.sh` scripts in
  `/usr/local/etc/rc.d/` at boot (via `rc.start_packages`); a plain `suricata_forwarder`
  file would be ignored on reboot.
- **It is supervised by FreeBSD `daemon(8)`.** The rc.d script runs
  `daemon -f -P <supervisor pidfile> -p <child pidfile> -o <logfile> -r <python> <forwarder>`, which detaches the process from your SSH
  session, writes the PID file, captures output to `/var/log/suricata-forwarder.log` and
  restarts the child if it exits. This replaces the earlier unsupervised
  `nohup python3.11 ... &` start.

setup.sh detects the pfSense Python interpreter at deploy time and bakes it into the
rc.d script. If a pfSense upgrade removes that interpreter (for example 3.11 replaced by
3.12), the rc.d script falls back to the newest `python3.N` it finds, prints which one it
used, and warns when `maxminddb` cannot be imported by it (GeoIP enrichment would then
be off). It does not silently stay dead, which is what happens when the path is simply
missing. Re-run `./setup.sh --forwarder-only` afterwards to bake the new path in.

---

## The watchdog

The rc.d service covers boot. The watchdog covers crashes.

`/usr/local/bin/suricata-forwarder-watchdog.sh` runs **every minute from the pfSense Cron
package** (Services > Cron). That entry lives in `config.xml`, so it survives upgrades
and configuration restores; pfSense writes it into `/etc/crontab` as:

```
*	*	*	*	*	root	/usr/local/bin/suricata-forwarder-watchdog.sh
```

Each run looks for a root-owned forwarder process (an anchored match on
`python3.N /usr/local/bin/forward-suricata-eve.py`, so a shell whose command line merely
mentions the file name never counts). If none exists it runs the rc.d `stop` (to clear
any half-dead supervisor) and then `start`, and logs the result to syslog under the
`suricata-watchdog` tag. Otherwise it exits, so the cost is one `pgrep` per minute.

Why not root's own crontab: on a live pfSense 2.8.1 box root had no crontab at all, and
the forwarder had been dead for more than two months without anyone noticing. Entries in
`crontab -` are not part of `config.xml` and were not there after upgrades.

The recovery chain, in order of what catches what:

```
pfSense boot          -> rc.d (/usr/local/etc/rc.d/suricata_forwarder.sh) starts it
Process crash/kill    -> watchdog cron restarts it within 60 seconds
pfSense upgrade       -> re-run ./setup.sh (see "What survives reboot and upgrade")
```

Check the watchdog is installed and see what it has done recently:

```bash
ssh admin@<PFSENSE_IP> 'grep suricata-forwarder-watchdog /etc/crontab'
ssh admin@<PFSENSE_IP> 'grep suricata-watchdog /var/log/system.log | tail -20'
```

Test it deliberately (measured: it restarted a stopped forwarder at the next cron minute,
leaving exactly one supervisor and one forwarder process):

```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh stop'
sleep 70
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'
# expected: suricata_forwarder is running (pid=NNNN)
```

`service suricata_forwarder.sh stop` is the clean way to stop it. It finds the forwarder
by process as well as by pidfile, so a lost pidfile cannot leave an orphaned `daemon`
supervisor respawning an unmanaged forwarder (that exact state was reproduced once during
testing: `status` said "not running" while a supervisor kept a forwarder alive).
Do **not** use `killall python3.11`: it kills every Python process on the firewall and
silently does nothing at all once pfSense ships a different interpreter version.

---

## What setup.sh installs

Everything below is deployed by `./setup.sh` (Step 4, "Deploy Forwarder to pfSense")
and is idempotent, so re-running it is always safe:

| Installed | Purpose |
|-----------|---------|
| `/usr/local/bin/forward-suricata-eve.py` | the forwarder, with `SIEM_HOST`, `LOGSTASH_UDP_PORT`, `DEBUG_ENABLED` from `config.env` baked in |
| `/usr/local/etc/rc.d/suricata_forwarder.sh` (enabled by default — pfSense does not manage `/etc/rc.conf`, so no `sysrc` is needed) | boot start, `service` control |
| `/usr/local/bin/suricata-forwarder-watchdog.sh` | crash recovery |
| a pfSense Cron-package entry (`scripts/pfsense-add-watchdog-cron.php`, stored in `config.xml`) | runs the watchdog every minute; any old root-crontab line is removed first. If the Cron package is not installed, setup.sh says so and skips it (the rc.d unit still starts at boot and respawns the child). |

Nothing else is required. The following exist in the repository but are **not**
installed by setup.sh:

- `scripts/setup_forwarder_monitoring.sh`: legacy interactive installer, superseded by
  setup.sh's watchdog. It writes cron lines that start the forwarder with a hardcoded
  `python3.11` and recover with `killall python3.11`. Do not run it on a system deployed
  with setup.sh; the two schemes will fight over the process.
- `scripts/suricata-restart-hook.sh`: legacy post-Suricata-restart hook. Same problems
  (`killall python3.11`, hardcoded interpreter), which is why setup.sh does not install
  it. See [After Suricata restarts or rule reloads](#after-suricata-restarts-or-rule-reloads).
- The pfSense `shellcmd` package: not needed. The rc.d script handles boot.

---

## Day-2 quick reference

All commands run on pfSense (`ssh admin@<PFSENSE_IP>`) unless noted. From the SIEM
server, `./pfsense-siem` options 9-11 wrap the most common ones.

| Task | Command |
|------|---------|
| Is it running? | `service suricata_forwarder.sh status` |
| Start / stop / restart | `service suricata_forwarder.sh start` / `stop` / `restart` |
| PID and start time | `ps -p $(cat /var/run/suricata_forwarder.child.pid) -o pid,lstart,%cpu,%mem,command` |
| Which eve.json files it has open | `procstat -f $(cat /var/run/suricata_forwarder.child.pid) \| grep eve.json` (`lsof` is not in pfSense base) |
| Forwarder syslog (startup, rotation, errors) | `grep suricata-forwarder /var/log/system.log \| tail -50` |
| Follow live | `tail -f /var/log/system.log \| grep suricata` |
| Daemon stdout/stderr (Python tracebacks) | `tail -50 /var/log/suricata-forwarder.log` |
| Watchdog activity | `grep suricata-watchdog /var/log/system.log \| tail -20` |
| Watchdog cron line present? | `grep suricata-forwarder-watchdog /etc/crontab` |
| Boot start enabled? | `ls /usr/local/etc/rc.d/suricata_forwarder.sh` — pfSense runs every `*.sh` there at boot; the script defaults `suricata_forwarder_enable=YES` |
| Duplicate processes? | `pgrep -fl forward-suricata-eve.py` (expect exactly one line) |
| Hard kill (last resort) | `pkill -f forward-suricata-eve.py` then `service suricata_forwarder.sh start` |
| Run in the foreground to see errors | `service suricata_forwarder.sh stop; /usr/local/bin/forward-suricata-eve.py` (Ctrl+C, then `start` again) |
| Redeploy after editing the script or config.env | on the SIEM server: `./setup.sh` |
| Redeploy only the pfSense side (after a pfSense upgrade, or when the workstation cannot reach OpenSearch) | `./setup.sh --forwarder-only` (verifies delivery from the pfSense side) |
| Is data still arriving? (exit 0 fresh, 1 stale, 2 cannot query) | `./scripts/check-siem-freshness.sh [--max-age MINUTES] [--via-pfsense]` |
| Full health check | on the SIEM server: `./scripts/status.sh` |

A healthy startup looks like this in `/var/log/system.log` (N = number of Suricata
interfaces):

```
suricata-forwarder: Loaded GeoIP from /usr/local/share/GeoIP/GeoLite2-City.mmdb
suricata-forwarder: Starting — N interface(s), target=<SIEM_IP>:5140, GeoIP=enabled
suricata-forwarder: Monitoring suricata_igc012345 (/var/log/suricata/suricata_igc012345/eve.json) — GeoIP: enabled
suricata-forwarder: Monitoring suricata_igc167890 (/var/log/suricata/suricata_igc167890/eve.json) — GeoIP: enabled
```

---

## Verifying data flow end to end

1. **One command from the SIEM server.** `./scripts/status.sh` checks OpenSearch,
   the Logstash UDP port, the forwarder process, the watchdog cron line, the eve.json
   files and the age of the newest event, and exits non-zero if anything is wrong.

2. **Event count and freshness in OpenSearch:**

   ```bash
   # Total events
   curl -s "http://<SIEM_IP>:9200/suricata-*/_count" | jq .count

   # Newest event timestamp (should be within the last few minutes on a busy network)
   curl -s "http://<SIEM_IP>:9200/suricata-*/_search" -H 'Content-Type: application/json' \
     -d '{"size":1,"sort":[{"@timestamp":"desc"}],"_source":["@timestamp","event_type","in_iface"]}' \
     | jq '.hits.hits[0]._source'
   ```

3. **Events per interface** (confirms every Suricata instance is being forwarded):

   ```bash
   curl -s "http://<SIEM_IP>:9200/suricata-*/_search" -H 'Content-Type: application/json' \
     -d '{"size":0,"query":{"range":{"@timestamp":{"gte":"now-1h"}}},
          "aggs":{"by_iface":{"terms":{"field":"in_iface","size":50}}}}' \
     | jq '.aggregations.by_iface.buckets'
   ```

4. **Generate a known alert.** From any host behind pfSense run `curl http://testmyids.com`
   and look for the `GPL ATTACK_RESPONSE id check returned root` signature in Grafana
   within about 30 seconds.

Process running but the count not moving? Check, in order: Suricata is writing
(`ls -l /var/log/suricata/*/eve.json`), the SIEM firewall allows UDP 5140, the baked-in
target is right (`grep 'SIEM_HOST =' /usr/local/bin/forward-suricata-eve.py`), and Logstash
is not tagging `_jsonparsefailure`
([TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md#forwarder-issues)).

---

## After Suricata restarts or rule reloads

A Suricata restart (rule update, interface config change, pfSense package upgrade)
rewrites the `eve.json` files. The forwarder handles the common case on its own: it
notices the inode change or truncation and reopens the file, logging
`Rotation detected, reopening`.

The one case it does not handle live is a **new interface**: the list of eve.json
files is discovered at startup, so an interface added to Suricata after the forwarder
started is picked up on the next forwarder start. Just restart it:

```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'
```

`scripts/suricata-restart-hook.sh` tried to automate this from Suricata's post-install
hook. It is kept for reference but **not installed** by setup.sh: it recovers with
`killall python3.11` and a hardcoded interpreter path. If you want automation, schedule
`service suricata_forwarder.sh restart` in a pfSense Cron-package job after your rule
updates instead.

---

## What survives reboot and upgrade

pfSense only guarantees `config.xml` across a reinstall or configuration restore. The
forwarder pieces live on the filesystem, so:

| Event | Forwarder + rc.d + watchdog cron | Notes |
|-------|----------------------------------|-------|
| Reboot | Survive | rc.d (`.sh` suffix) starts the forwarder; the Cron-package entry is regenerated from `config.xml` |
| In-place pfSense upgrade (e.g. 2.8.x to 2.9.x) | Cron entry survives (in `config.xml`); files may or may not | Files under `/usr/local/bin` and `/usr/local/etc/rc.d` can be removed, and the Python version can change; the rc.d script falls back to the newest `python3.N` |
| Reinstall or restore from backup | Cron entry restored; files lost | The files are not part of `config.xml`; run `./setup.sh --forwarder-only` |

After any pfSense upgrade, reinstall or restore:

```bash
./setup.sh --forwarder-only          # redeploys forwarder, rc.d, watchdog; re-detects Python
./scripts/check-siem-freshness.sh --via-pfsense   # newest event should be minutes old
./scripts/status.sh                  # full health check
```

The full procedure, including what to check before upgrading, is in
[PFSENSE_UPGRADE_GUIDE.md](../pfsense/PFSENSE_UPGRADE_GUIDE.md).

Two notes on cron:

- Do not hand-edit `/etc/crontab`; pfSense regenerates that file from `config.xml` and the
  line vanishes. Add jobs through the Cron package (Services > Cron), which is what
  setup.sh does for you.
- A forwarder can be dead for months with nothing noticing it, so also schedule
  `scripts/check-siem-freshness.sh` somewhere that can alert (for example a cron job on the
  SIEM host that logs or mails when it exits non-zero).

---

## Uninstall

On pfSense:

```bash
service suricata_forwarder.sh stop
rm -f /usr/local/etc/rc.d/suricata_forwarder.sh
rm -f /usr/local/bin/suricata-forwarder-watchdog.sh /usr/local/bin/forward-suricata-eve.py
rm -f /var/run/suricata_forwarder.pid /var/run/suricata_forwarder.child.pid /var/log/suricata-forwarder.log /var/log/suricata_forwarder_debug.log
```

Then delete the watchdog job in Services > Cron. If a legacy install
(`setup_forwarder_monitoring.sh`) was ever used on this box, also remove its lines:
`crontab -l | grep -v forward-suricata-eve.py | crontab -`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Watchdog restarts it every minute | It starts and dies. Run it in the foreground (`service suricata_forwarder.sh stop; /usr/local/bin/forward-suricata-eve.py`) and read the error: no `eve.json` files (Suricata not running), shebang pointing at a Python removed by an upgrade (re-run `./setup.sh`), or `maxminddb` missing (`python3 -c 'import maxminddb'`). |
| More than one forwarder process | Leftover from a manual start or the legacy cron scheme. `pkill -f forward-suricata-eve.py`, remove any `forward-suricata-eve.py` lines from `crontab -l`, then `service suricata_forwarder.sh start`. |
| Nothing restarts it after a crash | `grep suricata-forwarder-watchdog /etc/crontab` must show the line; if not, install the Cron package and run `./setup.sh --forwarder-only`. Also `service cron status`. |
| `status` says not running but events still arrive | An unmanaged forwarder from a lost pidfile. Current rc.d `stop` removes it; on an older install run `pgrep -fl forward-suricata-eve` and kill the `daemon:` supervisor by PID first, then the forwarder, then `service suricata_forwarder.sh start`. |
| Silence in the SIEM and nobody noticed | Run `./scripts/check-siem-freshness.sh --via-pfsense`; schedule it so it alerts. |
| Not running after reboot | the file must be `/usr/local/etc/rc.d/suricata_forwarder.sh` (with `.sh` — older deployments installed it without the suffix and were never started at boot). Re-run `./setup.sh` if not. The watchdog starts it within a minute anyway, so this shows up as a 60 s gap. |
| Events stop after a Suricata restart, process alive | `procstat -f $(cat /var/run/suricata_forwarder.child.pid) \| grep eve.json` listing rotated files (`eve.json.2026_...`) instead of the live `eve.json`: restart the service; see [LOG_ROTATION_FIX.md](../troubleshooting/LOG_ROTATION_FIX.md). |

---

## Related Documentation

- [INSTALL_PFSENSE_FORWARDER.md](../install/INSTALL_PFSENSE_FORWARDER.md): initial deployment and manual install steps
- [PFSENSE_UPGRADE_GUIDE.md](../pfsense/PFSENSE_UPGRADE_GUIDE.md): what to do around a pfSense upgrade
- [MULTI_INTERFACE_RETENTION.md](MULTI_INTERFACE_RETENTION.md): per-interface fields and index retention
- [TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md): broader stack troubleshooting
- [MANAGEMENT_CONSOLE.md](MANAGEMENT_CONSOLE.md): the `pfsense-siem` menu that wraps these commands
