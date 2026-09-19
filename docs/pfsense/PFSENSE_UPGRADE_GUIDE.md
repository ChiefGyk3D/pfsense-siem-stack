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
2. **ZFS boot environment** — if the box is on ZFS (default since 2.6), System →
   Boot Environments → *Create* (name it `pre-2.9.0`). Rolling back is then a
   reboot away.
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
   not, boot the previous ZFS boot environment from the loader menu.

---

## Part 2 — What this stack puts on pfSense, and what survives

pfSense guarantees only `config.xml`. Everything else is best-effort: files that no
package owns normally survive an in-place upgrade, but they are not in your backup,
a reinstall-and-restore drops them, and a package update can regenerate a file you
edited. The repo's pfSense-side pieces:

| Piece | Where | Installed by | In `config.xml`? | After upgrade |
|-------|-------|--------------|------------------|---------------|
| EVE forwarder | `/usr/local/bin/forward-suricata-eve.py` (shebang set to the Python detected at deploy time) | `setup.sh` | No | Usually present. Fails to start if the Python path changed (`python3.11` → newer). **Re-run `./setup.sh`**; it re-detects the interpreter and rewrites the shebang and rc.d script. |
| rc.d service | `/usr/local/etc/rc.d/suricata_forwarder.sh` | `setup.sh` | No | Usually present. pfSense starts `*.sh` scripts in this directory at boot. Older deployments installed `suricata_forwarder` *without* `.sh` — that file was never started at boot (the watchdog covered it); `setup.sh` now removes it. |
| Watchdog | `/usr/local/bin/suricata-forwarder-watchdog.sh` + a `* * * * *` line in **root's crontab** (`/var/cron/tabs/root`) | `setup.sh` | No | Root's crontab survives reboots and in-place upgrades unless `/var` is a RAM disk (System → Advanced → Miscellaneous → RAM Disk Settings). It is not in pfSense backups. Check with `crontab -l`. For a durable alternative add the same command in Services → **Cron** (Cron package), which is stored in `config.xml`. |
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
  crontab -l | grep watchdog
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

Boot the `pre-2.9.0` ZFS boot environment (System → Boot Environments, or the
loader menu), then re-run `./setup.sh` once more so the forwarder's shebang matches
the old interpreter again.

---

## Known gaps this repo still has for upgrades (tracked in [ROADMAP.md](../../ROADMAP.md))

- The watchdog cron is installed in root's crontab rather than via the Cron
  package, so it is not in `config.xml` backups.
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
