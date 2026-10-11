# Upgrading pfSense with this stack installed (2.8.1 → 2.9.0)

> **Applies to any pfSense box**, whether or not you run the SIEM stack: the first
> half is a general upgrade checklist for pfSense CE with Suricata, pfBlockerNG and
> Telegraf installed. The second half covers the pieces this repo adds and how to
> bring them back if the upgrade removes them.

pfSense CE 2.9.0 was released in August 2026. The pieces that matter for a
monitoring/IDS deployment:

| Change in 2.9.0 | Why it matters here |
|-----------------|---------------------|
| Base OS moved to **FreeBSD 16-CURRENT** (2.8.x was 15-CURRENT), **PHP 8.5**, **OpenSSL 3.5**, **OpenSSH 10.3** | Every package is rebuilt. Python and its site-packages directory (where `maxminddb` lives) may move; PHP extension paths change; Telegraf exec plugins written in PHP run under a new PHP. |
| **sshd algorithm tightening** — weak key exchange, cipher and MAC algorithms removed, post-quantum KEX added | Old SSH clients, old `ssh-rsa`-only keys, or hardcoded `-o KexAlgorithms=` options can stop connecting. Every script in this repo drives pfSense over SSH. |
| **TLS certificate strength enforcement** and automatic GUI certificate regeneration if the current one is weak/expired | Anything that pinned the old GUI certificate (a Grafana infinity panel, a monitoring probe, a browser exception) needs re-trusting. |
| **Telegraf package broken on 2.9.0** — the package writes `ssl_ca` and `fielddrop` into `telegraf.conf`; Telegraf ≥ 1.35 rejects the config and the service never starts ([Redmine #16674](https://redmine.pfsense.org/issues/16674)) | pfSense system metrics (InfluxDB) **and** the pfBlockerNG → OpenSearch pipeline both stop until you apply the workaround below or the fixed package lands. |
| Some Celeron J (and similar) hardware **kernel-panics on boot** | Set `hint.acpi_spmc.0.disabled=1` in `/boot/loader.conf.local` *before* upgrading if you have that hardware (see the release notes). |
| Netgate recommends `pkg bootstrap -f` after a major OS jump | Package tooling itself is rebuilt for the new ABI. |
| New "Port Restricted Cone" outbound NAT mode (experimental) | Not relevant to logging; leave the default unless you need it. |

Official reference: the pfSense 2.9.0 release notes and Upgrade Guide at
docs.netgate.com, and the release thread on forum.netgate.com. Read them before
you start — they list the complete change set (150+ items), this page only lists
what affects this stack.

---

## Part 1 — General pfSense upgrade checklist

Works for any pfSense CE upgrade; the 2.9.0-specific notes are marked.

### Before

1. **Backup** — Diagnostics → Backup & Restore → download `config.xml` (tick
   *Backup extra data* to include package data such as pfBlockerNG feeds and
   Suricata rules). Store it off the firewall. This is the only artifact pfSense
   guarantees to restore.
2. **ZFS boot environment** — if the box is on ZFS (default since 2.6), snapshot it
   from the shell (SSH or console): `bectl create pre-2.9.0`, then confirm with
   `bectl list`. pfSense **CE has no Boot Environments page in the GUI**: Netgate
   documents that page for pfSense Plus only. `bectl` still works on a CE ZFS
   install; verify that `bectl list` shows your snapshot before you rely on it.
   Rolling back is `bectl activate pre-2.9.0` and a reboot, or choose it from the
   loader's boot environments menu.
3. **Note your package list** — System → Package Manager → Installed Packages.
   The upgrader reinstalls them, but you want the list if something is missing
   afterwards. Typical for this stack: `suricata`, `pfBlockerNG-devel`, `Telegraf`,
   `ntopng`, `Service_Watchdog`, `Cron`, `nut`.
4. **Record versions** you will compare after:
   ```sh
   ssh admin@<PFSENSE_IP> '
     cat /etc/version
     pkg info | grep -E "^(python3|py3|php8|suricata|telegraf|pfSense-pkg-(suricata|Telegraf|pfBlockerNG))"
     ls -l /usr/local/bin/python3*
   '
   ```
5. **(2.9.0) Check your SSH client** — from the workstation you run the scripts on:
   `ssh -V`. OpenSSH 8.x+ negotiates fine with OpenSSH 10.3. If you use a very old
   client, an appliance, or a key type other than `ed25519`/`rsa-sha2`, generate an
   ed25519 key now and add it to the admin user *before* upgrading:
   `ssh-keygen -t ed25519 && ssh-copy-id admin@<PFSENSE_IP>`.
6. **(2.9.0) Hardware panic tunable** — Celeron J/N class boards: add
   `hint.acpi_spmc.0.disabled=1` to `/boot/loader.conf.local` (Diagnostics →
   Edit File; create the file if absent).
7. **Reboot first** — a clean reboot before upgrading flushes RAM disks and
   surfaces any pre-existing boot problem while you still know it isn't the upgrade.
8. **Disable Suricata blocking temporarily** if you run inline IPS on WAN and the
   upgrade window is remote: an interface that comes up before Suricata does is
   fine, but a Suricata that fails to start with netmap on a new kernel can leave
   the interface in an odd state. Services → Suricata → Interfaces → uncheck
   *Enable* on the WAN instance until you have verified the new kernel.

### Upgrade

- GUI: System → Update → Confirm. Or from the console/SSH:
  `pfSense-upgrade -d` (shows progress; expect two reboots on a major upgrade).
- Do not interrupt package reinstallation after the first reboot; it can take
  several minutes per package with Suricata rulesets.

### After

1. **Version and packages**
   ```sh
   ssh admin@<PFSENSE_IP> 'cat /etc/version; pkg info | grep -E "^pfSense-pkg"'
   ```
   All packages you noted should be back. If any is missing, reinstall from
   System → Package Manager (its settings are still in `config.xml`).
2. **(2.9.0) Package tooling** — `pkg bootstrap -f` if `pkg` complains about the
   ABI or package operations fail.
3. **Suricata** — Services → Suricata → Interfaces: every instance running? Check
   Logs View for startup errors. Rulesets: Updates → *Force* an update once. Your
   SID Mgmt lists (disable/drop/suppress) live in `config.xml` and survive; custom
   `.rules` files you copied into an instance directory by hand do **not**. If the
   package moved to **Suricata 8**, note that the DNS EVE record changed to v3
   (`dns.queries[]` instead of `dns.query`) — dashboards' DNS panels may need
   updating; alerts, HTTP and TLS records are unchanged.
4. **pfBlockerNG** — Firewall → pfBlockerNG → Update → *Force Reload All*. Confirm
   DNSBL is answering (`drill blocked.example @127.0.0.1` or the Reports tab).
   pfBlockerNG uses its own Python (`py3xx-maxminddb`, `py3xx-sqlite3`); errors in
   `/var/log/pfblockerng/py_error.log` after an upgrade usually mean the package
   needs a reinstall.
5. **Telegraf (2.9.0 breakage)** — Status → Services: if Telegraf is stopped and
   `/var/log/telegraf/telegraf.log` shows `plugin outputs.influxdb: line N: configuration specified the fields ["ssl_ca"]`
   (or `fielddrop`), apply the interim fix until the package update ships:
   ```sh
   ssh admin@<PFSENSE_IP> "sed -i '' 's/ssl_ca/tls_ca/g; s/fielddrop/fieldexclude/g' /usr/local/pkg/telegraf.inc"
   ```
   then open Services → Telegraf and **Save** (that regenerates
   `/usr/local/etc/telegraf.conf` from the patched include) and start the service.
   This edit is lost the next time the Telegraf package is reinstalled — which is
   fine once the fixed package is what gets reinstalled. Check the current status
   of Redmine #16674 before applying.
6. **SSH from your scripts host** — `./scripts/preflight.sh`. If SSH fails with
   `no matching key exchange method` or `no mutual signature algorithm`, update the
   client or add an ed25519 key via the GUI (System → User Manager → admin →
   Authorized SSH Keys) using the console.
7. **GUI certificate** — if the browser now warns, 2.9.0 regenerated a weak GUI
   certificate. Re-trust it, or issue one from your internal CA under System →
   Certificates and select it in System → Advanced → Admin Access.
8. **Cron package jobs** — Services → Cron: your jobs are still listed (they are in
   `config.xml`). Anything you added with `crontab -e` or by editing `/etc/crontab`
   directly is *not* managed by pfSense — see Part 2.
9. **Reboot once more** and verify everything comes up unattended. If the box does
   not, boot the previous ZFS boot environment (loader menu, or `bectl activate`).

---

## Part 2 — What this stack puts on pfSense, and what survives

pfSense guarantees only `config.xml`. Everything else is best-effort: files that no
package owns normally survive an in-place upgrade, but they are not in your backup,
a reinstall-and-restore drops them, and a package update can regenerate a file you
edited. The repo's pfSense-side pieces:

| Piece | Where | Installed by | In `config.xml`? | After upgrade |
|-------|-------|--------------|------------------|---------------|
| EVE forwarder | `/usr/local/bin/forward-suricata-eve.py` (shebang set to the Python detected at deploy time) | `setup.sh` | No | Usually present. If the Python path changed (`python3.11` → newer) the rc.d script falls back to the newest `python3.N` and warns if `maxminddb` is not importable. **Run `./setup.sh --forwarder-only`** to bake the new interpreter in and verify delivery. |
| rc.d service | `/usr/local/etc/rc.d/suricata_forwarder.sh` | `setup.sh` | No | Usually present. pfSense starts `*.sh` scripts in this directory at boot. Older deployments installed `suricata_forwarder` *without* `.sh` — that file was never started at boot (the watchdog covered it); `setup.sh` now removes it. |
| Watchdog | `/usr/local/bin/suricata-forwarder-watchdog.sh` + a Cron-package job (Services → Cron) | `setup.sh` | Cron job yes (`config.xml`); script no | Root's own crontab is **not** a safe place: it was empty on a live 2.8.1 box and the forwarder had been dead for over two months. `setup.sh` now schedules the job through the Cron package. Check with `grep suricata-forwarder-watchdog /etc/crontab`. |
| GeoIP database | `/usr/local/share/ntopng/GeoLite2-City.mmdb` (or pfBlockerNG's `/usr/local/share/GeoIP/`) | ntopng / pfBlockerNG packages | Settings yes, DB file no | Re-downloaded by the owning package on its next update if your MaxMind key is configured. The forwarder logs `No GeoIP database found` and runs without enrichment until then. |
| `maxminddb` Python module | `py3xx-maxminddb` in the current Python's `site-packages` | Dependency of the Suricata/pfBlockerNG packages | n/a | Reinstalled for the *new* Python by the package upgrade. A forwarder still pinned to the old interpreter will not see it → re-run `setup.sh`. |
| Telegraf plugins | `/usr/local/bin/telegraf_*.php`, `telegraf_*.sh` | `install_plugins.sh` | No (unless you used the **Filer** package) | Usually present; re-run `./install_plugins.sh` if missing. PHP plugins run under the new PHP 8.5 — test with `telegraf --test`. |
| Telegraf extra config | *Additional Configuration* box in Services → Telegraf | you, in the GUI | **Yes** | Survives. Anything you put directly in `/usr/local/etc/telegraf.conf` is regenerated away on every save. |
| Suricata SID lists | Services → Suricata → interface → SID Mgmt | you, in the GUI (from `config/sid/`) | **Yes** | Survives. |
| Suricata drop rules from `apply-suricata-drop-rules.sh` / `enable-selective-blocking.sh` | inside `/usr/local/etc/suricata/suricata_*/` | those scripts | No | Overwritten by the Suricata package on rule update or reinstall. Redo via SID Mgmt (`dropsid.conf`) instead. |
| Filterlog auto-restart job | Services → Cron | you, per [PFSENSE_FILTERLOG_ROTATION_FIX](../troubleshooting/PFSENSE_FILTERLOG_ROTATION_FIX.md) | **Yes** | Survives. |

### Post-upgrade procedure for the SIEM pieces

From the workstation that holds `config.env`:

```bash
./scripts/preflight.sh          # SSH still works? Python found? OpenSearch reachable?
./setup.sh                      # re-detects Python, redeploys forwarder + rc.d + watchdog, re-applies templates (idempotent)
./scripts/status.sh             # forwarder running, watchdog cron present, events arriving, indices fresh
```

Then on pfSense:

```sh
ssh admin@<PFSENSE_IP> '
  service suricata_forwarder.sh status
  tail -5 /var/log/suricata-forwarder.log
  grep suricata-forwarder-watchdog /etc/crontab
  /usr/local/etc/rc.d/telegraf.sh status 2>/dev/null || pgrep -fl telegraf
'
```

And in Grafana: the IDS/IPS dashboard should show new events within a minute, the
pfSense System dashboard's Telegraf panels within the Telegraf interval, and the
pfBlockerNG panels after the next block event. If a panel is empty, start at
[Dashboard shows "No Data"](../troubleshooting/DASHBOARD_NO_DATA_FIX.md).

### If SSH is the thing that broke

The forwarder keeps running without SSH — nothing on the SIEM side depends on it.
Fix the client (or key) at your leisure; until then use the pfSense console/GUI
Diagnostics → Command Prompt for the checks above.

### Rolling back

Boot the `pre-2.9.0` ZFS boot environment (`bectl activate pre-2.9.0` and reboot, or the
loader menu), then re-run `./setup.sh` once more so the forwarder's shebang matches
the old interpreter again.

---

## A real run: 2.8.1 to 2.9.0 on a tuned box (2026-10-10)

What actually happened on the reference firewall (4-core Xeon D, 2.5G WAN, 16 Suricata instances, pfBlockerNG with
3.5 million DNSBL domains, Telegraf, CrowdSec, the forwarder from this repo). Use it to set expectations; the numbers are
from one box.

**Timeline.** Started 20:35, first reboot 20:38, back on 2.9.0 at 20:43 (about 5 minutes down), package reinstall pass done
by 20:50 with no second reboot. Download was 571 MB; the dry run (`pfSense-upgrade -n -y`) predicted 50 packages removed,
50 installed and 51 reinstalled, which is the normal mass ABI change from FreeBSD 15 to 16.

**Getting offered the upgrade.** `pfSense-upgrade -c` said "up to date" until the update branch was switched in
System > Update > Update Settings to *Current Stable Version (2.9.0)* and saved. The dynamic repository list
(`pfSense-repoc -p`) already showed 2.9.0 as current stable and 2.8.1 as the default; nothing upgrades until the branch is
selected. Run the dry run before you start: it lists every package and any removals.

**What survived untouched** (diffed against a baseline captured before the upgrade): the ruleset hash, all limiter pipes
and queue sizes, flow control (`dev.igc.N.fc` 0, so the loader tunables persist), the 16 Suricata instance configs, the
pfBlockerNG feed list, whitelist and TOP1M file, Kea, NTP, gateways, the Cron-package watchdog entry, and the EVE
forwarder (it started by itself at boot on the same Python 3.11 with `maxminddb` 2.8.2).

**What did not, and the fix:**

| Symptom after the upgrade | Cause | Fix |
|---|---|---|
| DNS blocking silently off (a listed ad domain resolved normally) | the package reinstall reset pfBlockerNG's DNSBL data store (`pfb_py_dnsbl.sqlite` 8 KB, `pfb_py_data.txt` gone) while the resolver, VIP and config were intact | `php /usr/local/www/pfblockerng/pfblockerng.php updatednsbl` and wait (about 15 minutes with 3.5 million domains); the data file came back at 194 MB |
| Telegraf restarted every minute by Service Watchdog | Telegraf 1.39 rejects the `ssl_ca` option the package still writes (Redmine #16674); `telegraf --test` printed the exact line | back up `/usr/local/pkg/telegraf.inc`, `sed` `ssl_ca` to `tls_ca` and `fielddrop` to `fieldexclude`, then run `telegraf_resync_config()` from PHP (the same as the GUI's Save); it was stable afterwards and records reached OpenSearch |
| Telegraf netstat input errors | `lsof` was removed by the base upgrade | `pkg install lsof` (it is still in the repository) |
| CrowdSec gone (service, firewall tables) | `pfSense-pkg-crowdsec` is not in the pfSense repository, so the upgrade removes it | reinstall from the vendor's release archive for FreeBSD 16: download `freebsd-16-amd64.tar` from the `pfSense-pkg-crowdsec` releases, **verify the SHA-256 that GitHub publishes for the asset**, then `pkg add -f` the three packages in order (`crowdsec-firewall-bouncer`, `crowdsec`, `pfSense-pkg-crowdsec`), as the vendor's install script does. Old configuration is kept. Re-check in the GUI that it is pulling decisions |

**Suricata 7.0.11 to 8.0.5.** Plan for it: it is a major version. On this box:
- Rules loaded: 59,719 on the WAN instance, 50 failed (JA3 rules because JA3 is off in the config, and a few regular
  expressions the new parser rejects), 0 skipped; the cell instance was the same (59,720 loaded, 50 failed).
- Startup is slow: the instance sat at roughly one core for about two minutes before "Engine started"; traffic through an
  inline instance is slow until then, so do not benchmark during it.
- The DNS EVE record stayed at version 2 (the package configures it), so SIEM dashboards were unaffected, but Suricata now
  logs that version 2 is deprecated and will be removed in 9.0.
- Inline IPS throughput on Suricata 8: sustained about 840 Mbit/s through the WAN instance (8 parallel flows, three
  rounds), worker threads at 10 to 25% CPU, 0 capture drops, 0 packet loss while an inline instance started.
- Disabling the two inline instances (WAN, cell) for the upgrade window and re-enabling them one at a time after
  verifying, with a timed switch-off as a safety net, worked well.

**Smaller notes.** PHP went 8.3 to 8.5 and the Telegraf PHP interface plugin still ran. A new built-in `_nat64reserved_`
firewall table appeared (the ruleset grew by a few lines for that and for CrowdSec). `pfSsh.php playback svc status`
threw a PHP 8.5 type error while the real service list worked, so use `get_services()` or the GUI. Several per-VLAN
limiter child queues were still running at the 50-slot default before the pre-upgrade reboot and only picked up their
configured size after it, which is the incremental-loading effect described in the shaping notes.

**Testing from a laptop can mislead.** The first throughput checks after the upgrade looked terrible (about 35 Mbit/s).
The firewall itself measured about 380 Mbit/s, and the laptop turned out to be on a weak Wi-Fi link (-76 dBm) with its
Ethernet port down. Check the client link before blaming the firewall, and test from a wired host.

---

## Known gaps this repo still has for upgrades (tracked in [ROADMAP.md](../../ROADMAP.md))

- Several legacy scripts under `scripts/` (`setup_forwarder_monitoring.sh`,
  `suricata-restart-hook.sh`, `unified-monitoring-watchdog.sh`,
  `suricata-eve-forwarder.sh`) still hardcode `python3.11` and use
  `killall python3.11`; they are not installed by `setup.sh` and should not be used
  on 2.9.0 until updated.
- `plugins/telegraf_pfifgw.php` reads the legacy `$config` global; pfSense is
  migrating internals to `config_get_path()`, so this plugin is the most likely PHP
  breakage on a future release.
- No automated check compares the Suricata package version before/after an upgrade
  to warn about EVE schema changes.

---

## Part 3 — What is verified, what is reported, and what to re-test

Sources: the [Netgate announcement](https://www.netgate.com/blog/netgate-releases-pfsense-community-edition-version-2.9.0),
the [2.9.0 release notes](https://docs.netgate.com/pfsense/en/latest/releases/2-9-0.html) and the
[Upgrade Guide](https://docs.netgate.com/pfsense/en/latest/install/upgrade-guide.html).

**Confirmed in the official release notes**

- Base OS FreeBSD 16-CURRENT, PHP 8.5.7, OpenSSL 3.5.7, OpenSSH 10.3p1.
- DHCP: Kea 3.0.2; the `client-class` parameter is deprecated.
- Gateways: recovery for the default failover group; the shaper notes list a fix for
  **limiter behavior with gateway groups**. If you run limiter rules that name a gateway, re-test
  them after the upgrade (see below).
- Hardware: Celeron J panic tunable (`hint.acpi_spmc.0.disabled=1`). The notes do not mention `igc`, `igb` or `ix` drivers.
- Weak or expired GUI certificates are regenerated during the upgrade; older SSH clients may fail to connect.
- The notes do **not** list package-specific known issues (Suricata, pfBlockerNG, Telegraf, WireGuard).

**Telegraf** — [Redmine #16674](https://redmine.pfsense.org/issues/16674): the Telegraf service page writes the
`ssl_ca` parameter that Telegraf 1.35 deprecated, and the package now ships Telegraf 1.36.2, so the service fails to
start when the InfluxDB output is selected. The interim `sed` in Part 1 is the workaround.

**Reported but not verified here** (found through search summaries; the tracker needs a login to read, so check the
primary issues before relying on them)

- A failed post-reboot stage when upgrading 2.8.1 to 2.9.0, leaving a mix of 2.9.0 core and 2.8.1 metadata with a
  wrong `pkg` OSVERSION.
- Suricata being removed during the base upgrade (attributed to a `pkg rquery` bug that newer `pkg` fixes).

Treat both as risks, not facts: take the boot environment snapshot first, have console or IPMI access ready, upgrade
from the console (`pfSense-upgrade -d`) so you can watch it, and afterwards check
`pkg info | grep -E "pfSense-pkg|suricata"` against the list you saved.

**If you use limiters and ALTQ** — before and after, capture `dnctl pipe show`, `dnctl queue show` and the count of
`pfctl -sr` lines, then repeat a loaded-latency test. See
[Optimizing pfSense traffic shaping on a gigabit cable line](SHAPING_OPTIMIZATION_NOTES.md) for the method.

### Tuned-box checklist: capture before, compare after

If you have applied the tuning in [October 2026 Tuning Results](TUNING_RESULTS_2026-10.md), record these before the upgrade
and compare afterwards. Each item was a real way for a tuned box to silently lose a change.

| Item | Capture / check | Expected after |
|---|---|---|
| Boot environment | `bectl create pre-2.9.0` (CE has no GUI page for it) | exists; remember `bectl activate` is the rollback |
| pf ruleset size | `pfctl -sr \| wc -l` | within a few lines of before (pfBlockerNG rules regenerate) |
| Limiters | `dnctl pipe show`, `dnctl queue show`; repeat a loaded-latency test | same pipes, queue sizes and weights; loaded latency within noise of before |
| Flow control | `sysctl dev.igc.0.fc dev.igc.1.fc dev.igb.0.fc dev.igb.1.fc` | all `0`; if not, the tunables did not survive, re-apply them |
| DNSBL | resolve a listed domain, `grep -i 'vip' /var/log/pfblockerng/pfblockerng.log`, `pfSsh.php` check of the VIP | listed domain answers `0.0.0.0` (Python mode); log does not say the VIP is missing. A package reinstall once dropped the VIP silently. |
| pfBlockerNG feeds | the feed-health loop in [pfBlockerNG guide](PFBLOCKERNG_OPTIMIZATION.md#6-are-the-feeds-themselves-alive) | no new placeholder-only tables |
| Suricata instances | `ps -axo command \| grep -c '[s]uricata'` per instance; `suricata --dump-config` diff against the pre-upgrade dump | same instances running; only intended keys differ; any pass-through (BPF filter) still present |
| Suricata drops | per-instance `kernel_drops` in `stats.log` after a loaded test | still 0 |
| Forwarder | `service suricata_forwarder.sh status`, then `./scripts/check-siem-freshness.sh --via-pfsense` | running; newest event minutes old. If not: `./setup.sh --forwarder-only` |
| Watchdog | `grep suricata-forwarder-watchdog /etc/crontab` | present (it lives in `config.xml`) |
| DHCP | `kea-dhcp4 -t /usr/local/etc/kea/kea-dhcp4.conf`; a known client renews | config valid; Kea 3.0.2 deprecates `client-class`, so check any deny-unknown class setup |
| Gateways | `pfSsh.php playback gatewaystatus` | all gateways online (the release notes mention limiter-with-gateway-group changes) |

Keep the pre-upgrade captures in a private location, since they contain your addressing.
