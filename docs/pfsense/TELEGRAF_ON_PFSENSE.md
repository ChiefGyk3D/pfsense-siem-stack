# Telegraf on pfSense

A from-scratch guide to installing, configuring, extending and troubleshooting the Telegraf package on pfSense. It applies to any pfSense box; only the sections that mention this repository's plugins or its OpenSearch output are specific to the [pfSense SIEM stack](https://github.com/ChiefGyk3D/pfsense-siem-stack).

The single most important thing to understand about Telegraf on pfSense is **where the configuration really lives**: in `config.xml`, written through the GUI. Everything else in this guide follows from that.

---

## Table of Contents

1. [Install the package](#1-install-the-package)
2. [Configure via Services → Telegraf](#2-configure-via-services--telegraf)
3. [The Additional Configuration box](#3-the-additional-configuration-box)
4. [Installing this repository's plugins](#4-installing-this-repositorys-plugins)
5. [Restarting Telegraf correctly](#5-restarting-telegraf-correctly)
6. [Telegraf runs as root by design](#6-telegraf-runs-as-root-by-design)
7. [Troubleshooting](#7-troubleshooting)
8. [Persistence cheat sheet](#8-persistence-cheat-sheet)

---

## 1. Install the package

1. **System → Package Manager → Available Packages**
2. Search for `telegraf`, click **Install**, confirm.
3. When it finishes, a new menu entry appears at **Services → Telegraf**.

Install it through the package manager, not with `pkg install` from the shell. Packages installed through the GUI are recorded in `config.xml` and are reinstalled automatically after a pfSense upgrade or a configuration restore; a bare `pkg install` is not.

---

## 2. Configure via Services → Telegraf

The **Services → Telegraf** page is a form with a handful of fixed fields:

| Field | Notes |
|-------|-------|
| **Enable Telegraf** | Must be checked or nothing starts. |
| **Update Interval** | Collection interval for the built-in inputs (`10s` is a reasonable default). |
| **Hostname** | Leave blank to use the firewall's hostname; it becomes the `host` tag on every metric. |
| **Output: InfluxDB** | Server URL (`http://<SIEM_IP>:8086`), database name, username/password. This is the only output the form knows about. |
| **Input plugins** | Toggles for optional built-in inputs. The core system inputs (`cpu`, `mem`, `system`, `disk`, `net`, `pf`, ...) are emitted by the package template itself; read the generated file to see exactly what your version produces. |
| **Additional Configuration** | A free-text box appended verbatim to the generated config. See [section 3](#3-the-additional-configuration-box). |

### Where the configuration really lives

When you click **Save**, the package:

1. Stores the form values and the Additional Configuration text in `config.xml` (the extra text is base64-encoded under `<telegraf_raw_config>`).
2. **Regenerates `/usr/local/etc/telegraf.conf` from scratch** using the template in `/usr/local/pkg/telegraf.inc`.
3. Restarts the service.

This has two consequences you must internalize:

- **Hand edits to `/usr/local/etc/telegraf.conf` are lost** the next time anyone clicks Save on the Telegraf page, reinstalls the package, or upgrades pfSense. Never `vi /usr/local/etc/telegraf.conf` for anything you want to keep. Use it only to *read* what the package generated.
- Because the configuration is in `config.xml`, it is included in **Diagnostics → Backup & Restore** and survives upgrades and reinstalls. Anything that is *not* in `config.xml` (files you copy to `/usr/local/bin`, edits to rc scripts, `pkg install` from the shell) does not.

---

## 3. The Additional Configuration box

The **Additional Configuration** text area is the **only persistent place** for extra inputs, outputs, processors or aggregators. Whatever you paste there is appended to the generated `telegraf.conf` on every save, so it survives upgrades and package reinstalls along with the rest of `config.xml`.

Paste TOML exactly as you would write it in a normal `telegraf.conf`. Three blocks are commonly used with this repository.

### 3.1 `[[inputs.exec]]` for the repository plugins

The scripts in [`plugins/`](../../plugins/README.md) print InfluxDB line protocol (the full Unbound script prints `key=value` pairs instead), so they are wired in with `inputs.exec`:

```toml
# Interface + gateway status (PHP, uses pfSense internals)
[[inputs.exec]]
  commands = ["/usr/local/bin/telegraf_pfifgw.php"]
  timeout = "15s"
  data_format = "influx"

# CPU / ACPI thermal sensors
[[inputs.exec]]
  commands = ["/usr/local/bin/telegraf_temperature.sh"]
  timeout = "5s"
  data_format = "influx"

# Unbound resolver statistics — full version prints key=value lines, so parse as logfmt
[[inputs.exec]]
  commands = ["/usr/local/bin/telegraf_unbound.sh stats_noreset"]
  timeout = "10s"
  data_format = "logfmt"
  name_override = "unbound"

# ...or the lite version, which prints line protocol itself (pick one of the two)
# [[inputs.exec]]
#   commands = ["/usr/local/bin/telegraf_unbound_lite.sh"]
#   timeout = "10s"
#   data_format = "influx"

# ARP table with MAC vendor lookup
[[inputs.exec]]
  commands = ["/usr/local/bin/telegraf_arp_mac_vendor.php"]
  timeout = "10s"
  interval = "60s"
  data_format = "influx"
```

Each block can carry its own `interval` if the default collection interval is too frequent for it (the ARP plugin, for example, does not need to run every 10 seconds).

### 3.2 `[[inputs.tail]]` for pfBlockerNG logs

pfBlockerNG writes plain-text logs to `/var/log/pfblockerng/`. Telegraf can tail them with grok patterns and ship the parsed events wherever you like:

```toml
[[inputs.tail]]
  files = ["/var/log/pfblockerng/ip_block.log"]
  from_beginning = false
  name_override = "tail_ip_block_log"
  watch_method = "inotify"
  data_format = "grok"
  grok_patterns = ['%{SYSLOGTIMESTAMP:timestamp:ts-syslog} %{WORD:action},%{WORD:direction:tag},%{WORD:interface},...']
  grok_timezone = "Local"
```

The complete grok patterns for both `ip_block.log` and `dnsbl.log`, the OpenSearch output that goes with them, and the index template are in [TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md). Because Telegraf runs as root on pfSense (see [section 6](#6-telegraf-runs-as-root-by-design)), it can read these files even when pfBlockerNG recreates them with mode `600`; no permission fix-ups are needed.

### 3.3 `[[outputs.opensearch]]`

If you want a subset of metrics to land in OpenSearch instead of (or in addition to) InfluxDB:

```toml
[[outputs.opensearch]]
  urls = ["http://<SIEM_IP>:9200"]
  index_name = "pfblockerng-{{.Time.Format \"2006.01.02\"}}"
  manage_template = false
  timeout = "5s"
  enable_gzip = true
  health_check_interval = "10s"
  namepass = ["tail_ip_block_log", "tail_dnsbl_log"]
```

Requirements and caveats:

- `outputs.opensearch` exists in **Telegraf 1.28 and later**. The pfSense package tracks the FreeBSD `telegraf` port, which is well past that on pfSense 2.8.x/2.9.0; check with `telegraf version`.
- **Do not use `[[outputs.elasticsearch]]` against OpenSearch 2.x.** It performs a version handshake that OpenSearch fails, and it will refuse to write.
- Use `namepass` (or `namedrop`) so that only the measurements you intend go to OpenSearch. Without it, every system metric is indexed as a document, which is expensive and useless.
- The `[[outputs.influxdb]]` block generated from the form keeps receiving everything unless you add a matching `namedrop` to it, which you cannot do from the form. In practice this is fine: system metrics belong in InfluxDB, and the OpenSearch output only takes what `namepass` allows.

---

## 4. Installing this repository's plugins

### 4.1 How `install_plugins.sh` works

From your workstation, in a clone of the repository:

```bash
./install_plugins.sh
```

It prompts for the firewall's address and SSH user, lets you pick plugins, and copies each one to **`/usr/local/bin/<plugin>`** on the firewall via `scp`, then `chmod +x`. It offers to restart Telegraf afterwards; that step uses `service telegraf restart`, which does not match the pfSense-generated script name (see [section 5](#5-restarting-telegraf-correctly)), so restart from the GUI or with `/usr/local/etc/rc.d/telegraf.sh restart` instead if it reports a failure.

The script also looks for an optional `config/additional_config.conf` to copy alongside the plugins. That file is **not shipped**; the persistent place for the `inputs.exec` blocks is the GUI Additional Configuration box ([section 3.1](#31-inputsexec-for-the-repository-plugins)).

### 4.2 Files in `/usr/local` are not backed up

`/usr/local/bin/telegraf_*.{php,sh}` are ordinary files on the root filesystem. They are **not** in `config.xml`, so:

- a configuration restore onto a fresh install will not bring them back, and
- a pfSense major upgrade *may* leave them in place, but you should verify and re-run `install_plugins.sh` if any are missing.

The durable alternative is the **Filer** package (System → Package Manager → `Filer`). Filer stores file contents *inside* `config.xml` and rewrites them to disk at boot. Create one entry per plugin with the full path (e.g. `/usr/local/bin/telegraf_pfifgw.php`), paste the file contents, and set the mode to **`0755`** (the default `0644` is not executable).

### 4.3 The plugins and their prerequisites

| Plugin | Measurement(s) | Prerequisites |
|--------|----------------|---------------|
| `telegraf_pfifgw.php` | `interface` (per assigned interface: IPv4/IPv6 address and subnet, MAC, friendly name, `status`), `gateways` (per gateway: monitor IP, source IP, `delay`, `stddev`, `loss`, `status`, `status_code`, `substatus`, default-gateway flag) | Runs under `php-cgi` and includes pfSense's own `config.inc`, `gwlb.inc` and `interfaces.inc`. It calls `return_gateways_status(true)` and reads the legacy `$config` global; these internals change between major pfSense releases, so re-test it after an upgrade. |
| `telegraf_temperature.sh` | `temperature` (one series per `dev.cpu.N` core and per `hw.acpi.thermal` zone, field `degrees`) | Thermal sensor support must be enabled: **System → Advanced → Miscellaneous → Thermal Sensors**, pick the module matching your CPU (`coretemp` for Intel, `amdtemp` for AMD). Without it `sysctl dev.cpu` has no `temperature` lines and the plugin prints nothing. |
| `telegraf_unbound.sh` | Raw `unbound-control` `key=value` output (pass `stats_noreset` as the argument), minus per-thread lines; parse with `data_format = "logfmt"` and a `name_override` | Uses the DNS Resolver (Unbound). It calls `/usr/local/sbin/unbound-control -c /var/unbound/unbound.conf`, so the Unbound remote-control interface must be enabled in the generated config. pfSense enables it by default; verify with `unbound-control -c /var/unbound/unbound.conf status`. |
| `telegraf_unbound_lite.sh` | `unbound_lite` (only `total.num.cachehits` and `total.num.cachemiss`) | Same as above. Use this one if you only want a cache hit ratio. |
| `telegraf_arp_mac_vendor.php` | `arp_table` (tags `host`, `mac`, `vendor`, `interface`, `ip`; fields `expires`, `permanent`) | Needs an OUI database. Install the **nmap** package from the GUI package manager (provides `/usr/local/share/nmap/nmap-mac-prefixes`), or place an IEEE `oui.txt` at `/usr/local/share/oui.txt`. Details in [MAC_VENDOR_LOOKUP_SETUP.md](MAC_VENDOR_LOOKUP_SETUP.md). |

Test any plugin by running it from the shell as root before adding it to Telegraf; it should print one or more lines of line protocol and nothing on stderr.

---

## 5. Restarting Telegraf correctly

pfSense does not use the FreeBSD port's own rc script. The package generates **`/usr/local/etc/rc.d/telegraf.sh`**, and that is what the GUI, the boot process and the service status page use.

Preferred methods, in order:

1. **GUI**: **Status → Services** → restart icon next to `telegraf`. Or simply click **Save** on **Services → Telegraf**, which regenerates the config and restarts.
2. **Shell**:
   ```sh
   /usr/local/etc/rc.d/telegraf.sh restart
   ```
   (`stop`, `start` and `status` also work.)

What *not* to do:

- `service telegraf restart` — this addresses the FreeBSD port's stock `telegraf` rc script, not pfSense's `telegraf.sh`. Depending on the package version it either fails outright or starts a second Telegraf as the unprivileged `telegraf` user without pfSense's flags, which breaks the `pf` input and leaves you with two instances after the next boot. `install_plugins.sh` still offers this command; decline it and restart from the GUI instead.
- `pkill telegraf` followed by running the binary by hand — this works until the next reboot, at which point pfSense starts its own instance and you have two.

Verify:

```sh
ps -axo user,pid,command | grep '[t]elegraf'
# root  <pid>  /usr/local/bin/telegraf -config=/usr/local/etc/telegraf.conf ...
```

---

## 6. Telegraf runs as root by design

On a regular server Telegraf runs as an unprivileged `telegraf` user. **On pfSense it runs as `root`, and that is intentional**, for one concrete reason: the `[[inputs.pf]]` plugin runs `pfctl -s info`, and pf only reports real statistics to root. As a non-root user, even with `/dev/pf` readable and membership in the `proxy` group, `pfctl -s info` returns `Status: Disabled` with zeroed counters, and the plugin fails with:

```
Error in plugin: struct data for tag "searches" not found in pfctl output
```

Running as root also means Telegraf can read pfBlockerNG's `600`-mode logs, Suricata's log directories and anything else on the box without per-file permission work.

Things people try that break on the next package update (do not bother):

- Editing the rc script to run as `telegraf` and adding the user to `proxy`/`wheel`/`unbound` groups. The pf plugin still does not work (pf gates on UID, not on group membership), and the script is regenerated on save/upgrade.
- A cron job to `chmod 644` the pfBlockerNG logs every few minutes. Unnecessary when Telegraf is root; a maintenance burden otherwise.
- A `sudoers.d` rule plus a wrapper script around `pfctl` fed through `inputs.exec`. It works, but `sudo` is not part of base pfSense, the rule lives outside `config.xml`, and the wrapper needs care every time `pfctl` output changes.

If you nonetheless decide to run Telegraf unprivileged, accept that the PF Information dashboard panel will be empty and that you own every permission problem that follows.

---

## 7. Troubleshooting

### PF Information panel is empty

Telegraf is not running as root. Check `ps -axo user,command | grep '[t]elegraf'`. If it shows `telegraf` rather than `root`, someone started it with the wrong script; restart with `/usr/local/etc/rc.d/telegraf.sh restart` ([section 5](#5-restarting-telegraf-correctly)). Confirm the fix from the SIEM side:

```bash
influx -host <SIEM_IP> -database pfsense -execute "SELECT * FROM pf WHERE time > now() - 1m LIMIT 1"
```

### `inputs.exec` timeouts or empty measurements

- Run the command by hand as root; it must print line protocol and exit 0.
- Raise `timeout` in that block (`telegraf_pfifgw.php` can take several seconds on boxes with many interfaces and gateways).
- Look at `/var/log/telegraf/telegraf.log`; each failing exec plugin logs its stderr there.
- After a pfSense major upgrade, run `telegraf_pfifgw.php` manually first: it depends on internal PHP functions that occasionally move.

### Validate the generated config

```sh
telegraf --test --config /usr/local/etc/telegraf.conf
```

`--test` collects one round from every input and prints it to stdout without writing to any output. A config parse error shows up here immediately with a line number that refers to the *generated* file; map it back to the form field or the Additional Configuration block that produced it.

### pfSense 2.9.0: Telegraf refuses to start with `ssl_ca` / `fielddrop` errors

pfSense 2.9.0 ships a newer Telegraf (≥ 1.35) whose config parser rejects two long-deprecated option names that the package template still emits in the generated `telegraf.conf`: `ssl_ca` (now `tls_ca`) and `fielddrop` (now `fieldexclude`). The service fails at startup and the log shows the rejected option. This is tracked as Netgate Redmine **#16674**.

Workaround until the package is fixed:

```sh
sed -i '' 's/ssl_ca/tls_ca/g; s/fielddrop/fieldexclude/g' /usr/local/pkg/telegraf.inc
```

then open **Services → Telegraf** and click **Save** so the config is regenerated from the patched template. This edit is to a package file, not to `config.xml`, so it is **lost when the package is reinstalled or upgraded**; check the Redmine issue for the package version that carries the fix and remove the workaround once you are on it.

### No pfBlockerNG data in OpenSearch

Work through [TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md): log files exist, `outputs.opensearch` is present in the generated config, and the OpenSearch cluster allows auto-creation of `pfblockerng-*` indices.

---

## 8. Persistence cheat sheet

| Where it lives | Survives pfSense upgrade / restore? | Examples |
|----------------|-------------------------------------|----------|
| `config.xml` (anything set through the GUI) | **Yes** | Telegraf form fields and Additional Configuration, Cron package jobs, Filer files, package list |
| Generated files | **No** — regenerated on save | `/usr/local/etc/telegraf.conf`, `/usr/local/etc/rc.d/telegraf.sh` |
| Package files | **No** — replaced on package upgrade/reinstall | `/usr/local/pkg/telegraf.inc` (the 2.9.0 workaround above) |
| Files you copied | **No** — not backed up | `/usr/local/bin/telegraf_*.php`, `/usr/local/share/oui.txt` |

When in doubt, put it in the GUI. See [PFSENSE_UPGRADE_GUIDE.md](PFSENSE_UPGRADE_GUIDE.md) for the full pre- and post-upgrade checklist for this stack.

---

## Related

- [plugins/README.md](../../plugins/README.md) — one-line index of the plugins
- [TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md) — pfBlockerNG logs → Telegraf → OpenSearch pipeline
- [MAC_VENDOR_LOOKUP_SETUP.md](MAC_VENDOR_LOOKUP_SETUP.md) — ARP table with vendor names
- [PFSENSE_UPGRADE_GUIDE.md](PFSENSE_UPGRADE_GUIDE.md) — what survives an upgrade and what does not
