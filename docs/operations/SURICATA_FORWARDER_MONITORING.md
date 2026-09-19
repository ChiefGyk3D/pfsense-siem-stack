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

setup.sh detects the pfSense Python interpreter (`/usr/local/bin/python3.11` or
`/usr/local/bin/python3`) at deploy time and bakes it into the forwarder's shebang, so a
pfSense release that ships a different Python only requires re-running `./setup.sh`.

---

## The watchdog

The rc.d service covers boot. The watchdog covers crashes.

`/usr/local/bin/suricata-forwarder-watchdog.sh` runs from **root's crontab every minute**:

```
* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh
```

Each run checks for a `forward-suricata-eve.py` process; if none exists it runs
`service suricata_forwarder.sh start` and logs the result to syslog under the
`suricata-watchdog` tag. Otherwise it exits, so the cost is one `pgrep` per minute.

The recovery chain, in order of what catches what:

```
pfSense boot          -> rc.d (/usr/local/etc/rc.d/suricata_forwarder.sh) starts it
Process crash/kill    -> watchdog cron restarts it within 60 seconds
pfSense upgrade       -> re-run ./setup.sh (see "What survives reboot and upgrade")
```

Check the watchdog is installed and see what it has done recently:

```bash
ssh admin@<PFSENSE_IP> 'crontab -l | grep suricata-forwarder-watchdog'
ssh admin@<PFSENSE_IP> 'grep suricata-watchdog /var/log/system.log | tail -20'
```

Test it deliberately:

```bash
ssh admin@<PFSENSE_IP> 'pkill -f forward-suricata-eve.py'
sleep 70
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'
# expected: suricata_forwarder is running (pid=NNNN)
```

Use `pkill -f forward-suricata-eve.py` when you really need to kill the process by hand.
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
| root crontab line `* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh` | runs the watchdog (installed with `crontab -`, old line removed first) |

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
| Watchdog cron line present? | `crontab -l \| grep suricata-forwarder-watchdog` |
| Boot start enabled? | `ls /usr/local/etc/rc.d/suricata_forwarder.sh` — pfSense runs every `*.sh` there at boot; the script defaults `suricata_forwarder_enable=YES` |
| Duplicate processes? | `pgrep -fl forward-suricata-eve.py` (expect exactly one line) |
| Hard kill (last resort) | `pkill -f forward-suricata-eve.py` then `service suricata_forwarder.sh start` |
| Run in the foreground to see errors | `service suricata_forwarder.sh stop; /usr/local/bin/forward-suricata-eve.py` (Ctrl+C, then `start` again) |
| Redeploy after editing the script or config.env | on the SIEM server: `./setup.sh` |
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
| Reboot | Survive | rc.d starts the forwarder; cron reloads root's crontab from `/var/cron/tabs/root` |
| In-place pfSense upgrade (e.g. 2.7.x to 2.8.x) | Usually survive, not guaranteed | Files under `/usr/local/bin` and `/usr/local/etc/rc.d` and root's crontab can be removed or the Python version can change |
| Reinstall or restore from backup | Lost | Not part of config.xml, so not in pfSense backups |

After any pfSense upgrade, reinstall or restore:

```bash
./setup.sh          # redeploys forwarder, rc.d, watchdog; re-detects Python
./scripts/status.sh # confirms everything is back
```

The full procedure, including what to check before upgrading, is in
[PFSENSE_UPGRADE_GUIDE.md](../pfsense/PFSENSE_UPGRADE_GUIDE.md).

Two notes on cron:

- Do not put the watchdog in `/etc/crontab`; pfSense regenerates that file from config.xml
  and the line vanishes. setup.sh uses root's own crontab (`crontab -`) for this reason.
- For a cron entry that is itself durable across reinstall, use the pfSense **Cron**
  package (Services > Cron): those jobs are stored in config.xml and restored with
  backups. Optional, since setup.sh already covers the common cases.

---

## Uninstall

On pfSense:

```bash
service suricata_forwarder.sh stop
rm -f /usr/local/etc/rc.d/suricata_forwarder.sh
crontab -l | grep -v suricata-forwarder-watchdog | crontab -
rm -f /usr/local/bin/suricata-forwarder-watchdog.sh /usr/local/bin/forward-suricata-eve.py
rm -f /var/run/suricata_forwarder.pid /var/run/suricata_forwarder.child.pid /var/log/suricata-forwarder.log /var/log/suricata_forwarder_debug.log
```

If a legacy install (`setup_forwarder_monitoring.sh`) was ever used on this box, also
remove its lines: `crontab -l | grep -v forward-suricata-eve.py | crontab -`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Watchdog restarts it every minute | It starts and dies. Run it in the foreground (`service suricata_forwarder.sh stop; /usr/local/bin/forward-suricata-eve.py`) and read the error: no `eve.json` files (Suricata not running), shebang pointing at a Python removed by an upgrade (re-run `./setup.sh`), or `maxminddb` missing (`python3 -c 'import maxminddb'`). |
| More than one forwarder process | Leftover from a manual start or the legacy cron scheme. `pkill -f forward-suricata-eve.py`, remove any `forward-suricata-eve.py` lines from `crontab -l`, then `service suricata_forwarder.sh start`. |
| Nothing restarts it after a crash | `crontab -l \| grep watchdog` must show the line; if not, re-run `./setup.sh`. Also `service cron status`. |
| Not running after reboot | the file must be `/usr/local/etc/rc.d/suricata_forwarder.sh` (with `.sh` — older deployments installed it without the suffix and were never started at boot). Re-run `./setup.sh` if not. The watchdog starts it within a minute anyway, so this shows up as a 60 s gap. |
| Events stop after a Suricata restart, process alive | `procstat -f $(cat /var/run/suricata_forwarder.child.pid) \| grep eve.json` listing rotated files (`eve.json.2026_...`) instead of the live `eve.json`: restart the service; see [LOG_ROTATION_FIX.md](../troubleshooting/LOG_ROTATION_FIX.md). |

---

## Related Documentation

- [INSTALL_PFSENSE_FORWARDER.md](../install/INSTALL_PFSENSE_FORWARDER.md): initial deployment and manual install steps
- [PFSENSE_UPGRADE_GUIDE.md](../pfsense/PFSENSE_UPGRADE_GUIDE.md): what to do around a pfSense upgrade
- [MULTI_INTERFACE_RETENTION.md](MULTI_INTERFACE_RETENTION.md): per-interface fields and index retention
- [TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md): broader stack troubleshooting
- [MANAGEMENT_CONSOLE.md](MANAGEMENT_CONSOLE.md): the `pfsense-siem` menu that wraps these commands
