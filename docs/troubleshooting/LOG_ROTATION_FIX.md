# Suricata EVE Log Rotation and the Forwarder

This page explains how `forward-suricata-eve.py` copes with Suricata rotating
`eve.json`, and how to verify it. It is about **Suricata's** log files on
pfSense. The unrelated problem where pfSense's own `filterlog` daemon stops
writing `filter.log` after `newsyslog` rotates it (which empties the pfBlockerNG
panels) is covered in [PFSENSE_FILTERLOG_ROTATION_FIX.md](PFSENSE_FILTERLOG_ROTATION_FIX.md).

## The Problem

Suricata (via pfSense's log-management settings) periodically renames
`eve.json` to `eve.json.<timestamp>` and starts a fresh `eve.json`. A naive
tailer that opened the file once keeps reading the renamed file's inode
forever: the local `eve.json` fills with new events, OpenSearch receives none,
and one interface silently disappears from the dashboards.

**Symptoms of a stuck tailer:**
- The Per-Interface dashboard is missing one or more interfaces while others update.
- `lsof` on the forwarder shows `eve.json.*` (a rotated file) instead of `eve.json`.
- New events are visible with `tail /var/log/suricata/<instance>/eve.json` on pfSense but never reach OpenSearch.

## How the Forwarder Handles It

Each monitored file has its own thread (`tail_log_file()` in
`scripts/forward-suricata-eve.py`). The thread:

1. Waits for the path to exist, records its inode, opens it, and seeks to the end.
2. Reads lines. When there is no new line it sleeps 0.1 s and counts an idle cycle.
3. After `ROTATION_CHECK_CYCLES` (50) consecutive idle cycles, about **five
   seconds of quiet**, it re-stats the path:
   - **Inode changed or file gone** → logs `Rotation detected, reopening`, closes
     the handle, and goes back to step 1, which opens the new `eve.json`.
   - **File smaller than the current read position** → logs
     `Truncation detected, reseeking` and seeks to the new end.
4. If the file disappears mid-read (`FileNotFoundError`) it logs `File gone,
   waiting...` and retries every five seconds.

Two consequences worth knowing:

- The check is triggered by *idleness*, not by a timer. On a busy interface the
  old file keeps being read until Suricata stops writing to it, which happens
  at the moment of rotation, so in practice detection is still within seconds.
- After a reopen the thread starts at the end of the new file. Events written to
  the new `eve.json` between the rotation and the reopen (a few seconds at most)
  are not forwarded. Events still being flushed to the *old* file after the
  rename are read before the idle check fires, so nothing there is lost.

Rotation and truncation events are logged to syslog with tag
`suricata-forwarder`. The unit tests in `tests/python/test_forwarder.py` cover
both the inode-change and truncation paths with temporary files.

## Deployment

Nothing to do by hand. `./setup.sh` deploys the forwarder and runs it as the
`suricata_forwarder.sh` rc.d service under `daemon(8)`. To restart after an
upgrade of the script:

```bash
./setup.sh                                                       # redeploys and restarts
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'   # restart only
```

## Verification

### The forwarder is reading current files

```bash
ssh admin@<PFSENSE_IP> 'lsof -p $(cat /var/run/suricata_forwarder.child.pid) 2>/dev/null | grep eve.json'
```

Good (one line per Suricata instance, all plain `eve.json`):
```
python3  81984 root  6r  VREG ... /var/log/suricata/suricata_igc012345/eve.json
python3  81984 root  7r  VREG ... /var/log/suricata/suricata_igc167890/eve.json
```

Bad (a rotated file still open more than a few seconds after rotation):
```
python3  40727 root  6r  VREG ... /var/log/suricata/suricata_igc012345/eve.json.2026_0919_0400
```

A quick filter for the bad case: append `| grep 'eve.json\.'`; it should print
nothing.

### Every interface is reaching OpenSearch

```bash
curl -s 'http://<SIEM_IP>:9200/suricata-*/_search' -H 'Content-Type: application/json' -d '
{
  "size": 0,
  "query": { "range": { "@timestamp": { "gte": "now-2m" } } },
  "aggs":  { "interfaces": { "terms": { "field": "in_iface", "size": 20 } } }
}' | jq '{total: .hits.total.value, interfaces: .aggregations.interfaces.buckets}'
```

Every Suricata interface with traffic should appear. `in_iface` is mapped as
`keyword` by the index template, so it is aggregated directly (no `.keyword`
suffix).

### Rotation events in syslog

```bash
ssh admin@<PFSENSE_IP> 'grep -E "suricata-forwarder.*(Rotation|Truncation|File gone)" /var/log/system.log | tail -5'
```

### Debug log (only when `DEBUG_ENABLED=true`)

```bash
ssh admin@<PFSENSE_IP> 'grep -iE "opened|inode|rotation" /var/log/suricata_forwarder_debug.log | tail -20'
```

## Forcing a Rotation to Test

pfSense's Suricata package rotates logs from its own cron/GUI settings
(Services → Suricata → Logs Mgmt), so the simplest test is to rotate a file by
hand:

```bash
ssh admin@<PFSENSE_IP> '
  cd /var/log/suricata/suricata_igc012345 &&
  mv eve.json eve.json.$(date +%Y_%m%d_%H%M) &&
  pkill -HUP -f "suricata.*igc0"      # Suricata reopens its log files on SIGHUP
'
sleep 10
ssh admin@<PFSENSE_IP> 'lsof -p $(cat /var/run/suricata_forwarder.child.pid) | grep suricata_igc012345'
ssh admin@<PFSENSE_IP> 'grep "Rotation detected" /var/log/system.log | tail -1'
```

Within roughly five seconds of the interface going idle the forwarder should be
holding the new `eve.json`.

## Troubleshooting

**Still holding a rotated file long after rotation.** The interface may be so
busy that the old file never goes idle before its next rotation, or the process
is a stray copy started outside the service. Restart cleanly:
```bash
ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh stop; pkill -f forward-suricata-eve.py; sleep 1; service suricata_forwarder.sh start'
```

**An interface never appears.** The forwarder discovers `eve.json` files once at
start-up. An interface enabled afterwards needs `service suricata_forwarder.sh restart`.

**Interface appears but with gaps at rotation time.** Expected to be seconds at
most. If gaps are minutes long, check `system.log` for `Error: ... restarting in
5s` from the forwarder and for the watchdog restarting it.

## Alternatives Considered

- **inotify/kqueue watching** – needs an extra module on pfSense; polling every
  five idle seconds is cheap enough.
- **Restart on Suricata's rotation signal** – tight coupling to the pfSense
  Suricata package internals.
- **Periodic scheduled restart** – causes gaps on every restart and hides other
  bugs. This is what the legacy cron scripts did; do not reintroduce them.

Inode/size checking needs no dependencies, recovers on its own and is covered
by unit tests, which is why it is the approach used.
