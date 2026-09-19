# pfSense Forwarder Installation Guide

Complete guide for deploying the Python-based Suricata log forwarder on pfSense.

> **Use `./setup.sh`.** Step 4 of `setup.sh` deploys the forwarder, the watchdog, the cron
> entry and the rc.d service to pfSense over SSH, and starts it. Everything below the
> [Configuration](#configuration) section is reference material and a manual fallback for
> when you cannot run `setup.sh`. Do not mix the two: if you installed manually, re-running
> `./setup.sh` later is safe and will replace your manual copies.

## Prerequisites

- pfSense 2.7.2 or later (2.8.1 tested; 2.9.0 supported with the caveats in the
  [pfSense Upgrade Guide](../pfsense/PFSENSE_UPGRADE_GUIDE.md))
- Suricata installed and running on at least one interface
- SSH access to pfSense (enable in System > Advanced > Secure Shell), key-based
  (`ssh-copy-id admin@<PFSENSE_IP>`) — the scripts never prompt for passwords
- Network connectivity from pfSense to the SIEM server on UDP 5140

> **Python**: pfSense ships Python 3 with the Suricata package (python3.11 on 2.8.x).
> `setup.sh` detects the interpreter on pfSense and rewrites the forwarder's shebang to
> match, so the commands in this guide use `/usr/local/bin/python3` generically.
> `maxminddb` (for GeoIP) comes with the Suricata/pfBlockerNG packages; no pip install is
> needed, and the forwarder runs without GeoIP if the module is missing.

## Overview

`setup.sh` installs four pieces on pfSense:

1. **Python forwarder** — `/usr/local/bin/forward-suricata-eve.py`. Tails every
   `/var/log/suricata/suricata_*/eve.json`, enriches with GeoIP, sends events to Logstash
   over UDP.
2. **rc.d service** — `/usr/local/etc/rc.d/suricata_forwarder.sh`. Starts the forwarder at
   boot under `daemon(8)` with a pidfile in `/var/run/suricata_forwarder.pid` and stdout/stderr
   in `/var/log/suricata-forwarder.log`. pfSense only auto-starts rc.d scripts whose name
   ends in `.sh`, hence the suffix. Control it with
   `service suricata_forwarder.sh start|stop|restart|status`.
3. **Watchdog** — `/usr/local/bin/suricata-forwarder-watchdog.sh`. Checks whether the
   forwarder process exists and restarts the service if it is gone.
4. **Cron entry** — `* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh` in **root's
   crontab** (`crontab -l`, stored in `/var/cron/tabs/root`). Runs the watchdog every
   minute.

### Features
- **Multi-interface support**: monitors ALL Suricata instances automatically
- **GeoIP enrichment**: adds country/city data using maxminddb (no pip install needed)
- **Auto-restart**: rc.d service at boot, watchdog every minute
- **Low overhead**: usually well under 5% CPU

### What survives a reboot, upgrade or restore

Only `config.xml` is guaranteed to survive a pfSense reinstall or configuration restore.
The files above live outside `config.xml`: they normally survive a reboot and an in-place
upgrade, but they are **not** part of pfSense backups and can be removed by an upgrade or a
package reinstall. Do not edit `/etc/crontab` directly — pfSense regenerates that file and
your entry will be lost; the root crontab that `setup.sh` uses is the right place.

**After upgrading pfSense, re-run `./setup.sh` and then `./scripts/status.sh`.** Details in
the [pfSense Upgrade Guide](../pfsense/PFSENSE_UPGRADE_GUIDE.md).

## Quick Installation (Recommended)

From the workstation or SIEM server where you cloned the repository:

```bash
cp config.env.example config.env     # set SIEM_HOST, PFSENSE_HOST, PFSENSE_USER
./scripts/preflight.sh               # SSH, Python on pfSense, OpenSearch, GeoIP
./setup.sh                           # runs preflight again, then deploys everything
```

`setup.sh` bakes `SIEM_HOST` and `LOGSTASH_UDP_PORT` from `config.env` into the copy of the
forwarder it uploads, so no editing on pfSense is required. Verify:

```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'
ssh admin@<PFSENSE_IP> 'crontab -l | grep watchdog'
./scripts/status.sh
```

## Configuration

### SIEM Server IP (Environment Variables)

The forwarder reads configuration from environment variables with defaults that `setup.sh`
replaces at deploy time:

| Variable | Default | Description |
|----------|---------|-------------|
| `SIEM_HOST` | value of `SIEM_HOST` in config.env | SIEM/Logstash server IP |
| `LOGSTASH_UDP_PORT` | `5140` | UDP port for Logstash |
| `DEBUG_ENABLED` | `False` | Enable debug logging |
| `DEBUG_LOG` | `/var/log/suricata_forwarder_debug.log` | Debug log path |

To change the SIEM server:

**Option 1: Edit config.env and re-run `./setup.sh`** (recommended, persistent)

**Option 2: Edit the script on pfSense** (persistent until the next `setup.sh`)
```bash
ssh admin@<PFSENSE_IP>
vi /usr/local/bin/forward-suricata-eve.py
# Change: SIEM_HOST = os.getenv("SIEM_HOST", "<SIEM_IP>")
service suricata_forwarder.sh restart
```

**Option 3: Environment variable for a one-off test run** (stop the service first so two
copies do not run)
```bash
ssh admin@<PFSENSE_IP>
service suricata_forwarder.sh stop
SIEM_HOST=198.51.100.20 /usr/local/bin/python3 /usr/local/bin/forward-suricata-eve.py
# Ctrl+C when done, then:
service suricata_forwarder.sh start
```

### GeoIP Database Priority

The forwarder searches for a GeoLite2 database in this order and uses the first that exists:

1. `/usr/local/share/ntopng/GeoLite2-City.mmdb` (ntopng — best for geomaps)
2. `/usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb`
3. `/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb`
4. `/usr/local/share/GeoIP/GeoLite2-City.mmdb` (pfBlockerNG)
5. `/usr/local/share/GeoIP/GeoLite2-Country.mmdb` (pfBlockerNG)
6. `/var/unbound/usr/local/share/GeoIP/GeoLite2-City.mmdb`
7. `/var/unbound/usr/local/share/GeoIP/GeoLite2-Country.mmdb`
8. `/var/db/GeoIP/GeoLite2-City.mmdb`
9. `/usr/share/GeoIP/GeoLite2-City.mmdb`

**Country vs City database:**
- **Country**: provides country_code, country_name, continent_code
- **City**: also provides city_name, region_name, latitude/longitude (required for geomap panels)

The forwarder needs no MaxMind account; the package that downloads the database (ntopng or
pfBlockerNG) needs a free license key. See [GeoIP Setup](GEOIP_SETUP.md).

## Manual Installation (fallback)

Use this only if you cannot run `setup.sh` (for example, no SSH from the SIEM host to
pfSense). Replace `<SIEM_IP>` with your SIEM server IP. All commands run **on pfSense**
after `ssh admin@<PFSENSE_IP>` unless noted.

### 1. Copy the forwarder and watchdog

From your workstation:

```bash
scp scripts/forward-suricata-eve.py admin@<PFSENSE_IP>:/usr/local/bin/
scp scripts/suricata-forwarder-watchdog.sh admin@<PFSENSE_IP>:/usr/local/bin/
ssh admin@<PFSENSE_IP> 'chmod +x /usr/local/bin/forward-suricata-eve.py /usr/local/bin/suricata-forwarder-watchdog.sh'
```

On pfSense, set the SIEM address and make sure the shebang matches the installed interpreter:

```bash
sed -i '' 's/"SIEM_HOST", "[^"]*"/"SIEM_HOST", "<SIEM_IP>"/' /usr/local/bin/forward-suricata-eve.py
PY=$(for p in /usr/local/bin/python3 /usr/local/bin/python3.13 /usr/local/bin/python3.12 /usr/local/bin/python3.11 /usr/bin/python3; do [ -x "$p" ] && echo "$p" && break; done)
sed -i '' "1s|^#!.*|#!${PY}|" /usr/local/bin/forward-suricata-eve.py
```

### 2. Install the rc.d service

`setup.sh` generates the service script; the simplest manual route is to copy it from a host
where `setup.sh` has already run, or write it yourself with these properties:

- Path `/usr/local/etc/rc.d/suricata_forwarder.sh` (mode 755; the `.sh` suffix is required
  for pfSense to run it at boot)
- `name="suricata_forwarder"`, `rcvar="suricata_forwarder_enable"`
- Starts `/usr/local/bin/forward-suricata-eve.py` via
  `/usr/sbin/daemon -f -p /var/run/suricata_forwarder.pid -o /var/log/suricata-forwarder.log`
- `stop` kills the pid in the pidfile; `status` reports on it

Then enable and start it:

```bash
sysrc suricata_forwarder_enable=YES
service suricata_forwarder.sh start
service suricata_forwarder.sh status
grep suricata-forwarder /var/log/system.log | tail -5
```

Expected syslog lines:
```
suricata-forwarder: Loaded GeoIP from /usr/local/share/ntopng/GeoLite2-City.mmdb
suricata-forwarder: Starting forwarder for 13 interface(s) to <SIEM_IP>:5140 (GeoIP: enabled)
```

### 3. Install the watchdog cron job

Add the entry to **root's crontab** — not `/etc/crontab`, which pfSense regenerates:

```bash
(crontab -l 2>/dev/null | grep -v suricata-forwarder-watchdog; echo "* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh") | crontab -
crontab -l | grep watchdog
```

The GUI alternative is **Services > Cron** (Cron package), which stores the job in
`config.xml` and therefore *does* survive backups and restores.

## Verification

### Check Forwarder Status

```bash
# On pfSense
service suricata_forwarder.sh status
pgrep -fl forward-suricata-eve

# Recent forwarder messages
grep suricata-forwarder /var/log/system.log | tail -10

# Watchdog activity (only logs when it has to restart something)
grep suricata-watchdog /var/log/system.log | tail -5
```

### Enable Debug Mode (Troubleshooting)

```bash
# Stop the service so the watchdog does not start a second copy alongside your debug run
service suricata_forwarder.sh stop

# Run in the foreground with debug logging (Ctrl+C to stop)
DEBUG_ENABLED=true /usr/local/bin/python3 /usr/local/bin/forward-suricata-eve.py &
tail -f /var/log/suricata_forwarder_debug.log

# When finished
pkill -f forward-suricata-eve.py
service suricata_forwarder.sh start
```

Debug output shows:
- GeoIP database loaded
- Each interface being monitored
- IPs being enriched with country codes
- Event counts per interface

### Verify Events Reaching SIEM

On your SIEM server:

```bash
# Check event count (should be increasing)
curl -s http://localhost:9200/suricata-*/_count | jq .count

# Check latest events
curl -s "http://localhost:9200/suricata-*/_search?size=3&sort=@timestamp:desc" | jq -r '.hits.hits[] | ._source | {timestamp: ."@timestamp", event_type: .event_type, src_ip: .src_ip}'

# Monitor real-time (press Ctrl+C to stop)
watch -n 2 'curl -s http://localhost:9200/suricata-*/_count | jq .count'
```

Expected output — event count should increase every few seconds:
```
{
  "timestamp": "2026-09-19T17:38:24.348Z",
  "event_type": "tls",
  "src_ip": "203.0.113.45"
}
```

### Test Event Flow

Generate test traffic on pfSense:

```bash
# From pfSense, generate DNS query
nslookup google.com

# From pfSense, generate HTTPS connection
fetch -o /dev/null https://www.pfsense.org

# Wait 5 seconds
sleep 5

# Check SIEM for new events
curl -s "http://<SIEM_IP>:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source.event_type'
```

## Troubleshooting

### Forwarder Not Starting

```bash
# Check the interpreter the shebang points at exists
head -1 /usr/local/bin/forward-suricata-eve.py
ls -l /usr/local/bin/python3*

# Run it in the foreground to see errors
service suricata_forwarder.sh stop
/usr/local/bin/forward-suricata-eve.py

# Check service log and permissions
tail -20 /var/log/suricata-forwarder.log
ls -la /usr/local/bin/forward-suricata-eve.py /usr/local/etc/rc.d/suricata_forwarder.sh
```

### No Events in SIEM

```bash
# 1. Check if Suricata is generating events (the number is instance-specific)
tail -f /var/log/suricata/suricata_igc012345/eve.json

# 2. Check if forwarder is actually running
service suricata_forwarder.sh status

# 3. Test UDP connectivity from pfSense to SIEM
echo '{"test":"event"}' | nc -u -w1 <SIEM_IP> 5140

# 4. Check SIEM received test event
curl -s "http://<SIEM_IP>:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq
```

### Events Have Wrong Timestamp

The forwarder preserves Suricata's original timestamp. Check pfSense timezone:

```bash
# On pfSense
date

# Suricata timestamps include timezone offset
tail -1 /var/log/suricata/suricata_igc012345/eve.json | jq .timestamp
```

### High CPU Usage

The forwarder should use a few percent CPU at most. If higher:

```bash
# Check process stats
ps aux | grep forward-suricata-eve.py

# Check if Suricata is generating too many events
wc -l /var/log/suricata/suricata_*/eve.json

# Check network connectivity issues
netstat -s -p udp
```

### Watchdog Not Running

```bash
# Check root's crontab
crontab -l | grep watchdog

# Run watchdog manually to test
/usr/local/bin/suricata-forwarder-watchdog.sh

# Check syslog for watchdog output
grep suricata-watchdog /var/log/system.log | tail -20
```

If the entry is missing after a pfSense upgrade, re-run `./setup.sh`.

## Maintenance

### Restart Forwarder

```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'
```

If you kill the process instead (`pkill -f forward-suricata-eve.py`), the watchdog restarts
it within a minute.

### Update Configuration

Edit `config.env` and re-run `./setup.sh`; it uploads a fresh copy of the forwarder and
restarts the service. To change only the script on pfSense:

```bash
vi /usr/local/bin/forward-suricata-eve.py
service suricata_forwarder.sh restart
```

### Monitor Performance

```bash
# Check forwarder resource usage
ps aux | grep forward-suricata-eve.py

# Check UDP statistics
netstat -s -p udp

# Watchdog restarts (frequent entries mean the forwarder is crashing)
grep suricata-watchdog /var/log/system.log | tail -20
```

For deeper monitoring (alerting on forwarder silence, unified watchdog) see
[Suricata Forwarder Monitoring](../operations/SURICATA_FORWARDER_MONITORING.md).

## Files Summary

| File | Location on pfSense | Purpose |
|------|---------------------|---------|
| `forward-suricata-eve.py` | `/usr/local/bin/` | Main forwarder (Python) |
| `suricata_forwarder.sh` | `/usr/local/etc/rc.d/` | rc.d service; starts at boot, `service suricata_forwarder.sh ...` |
| `suricata-forwarder-watchdog.sh` | `/usr/local/bin/` | Restarts the forwarder if the process is gone |
| Cron job (`* * * * *`) | root's crontab (`/var/cron/tabs/root`) | Runs the watchdog every minute |
| `suricata_forwarder.pid` | `/var/run/` | Pidfile written by the rc.d service |
| `suricata-forwarder.log` | `/var/log/` | stdout/stderr of the daemonized forwarder |
| `suricata_forwarder_debug.log` | `/var/log/` | Debug log (only with `DEBUG_ENABLED=true`) |

None of these are in `config.xml`; re-run `./setup.sh` after a pfSense upgrade or reinstall.

## Next Steps

Continue to:
- **[Dashboard Installation](INSTALL_DASHBOARD.md)** - Set up Grafana dashboards
- **[GeoIP Setup](GEOIP_SETUP.md)** - Get the attack map working
- **[Troubleshooting Guide](../troubleshooting/TROUBLESHOOTING.md)** - Common issues and solutions

## Why Python Instead of Shell Scripts?

The original approach used shell scripts with `tail | while read | nc` but this was
**fundamentally broken** on pfSense:
- Shell while-read loops have buffering issues
- Pipe chaining corrupts data
- Manual tests worked but automated scripts failed
- Events arrived as single "X" characters

The Python solution:
- ✅ Single reliable process
- ✅ No pipe/buffer issues
- ✅ Proper error handling
- ✅ Uses the Python already on pfSense
- ✅ Easy to debug and maintain
