# Telegraf Plugins for pfSense

Small scripts that print InfluxDB line protocol, meant to be run by Telegraf's `[[inputs.exec]]` on a pfSense firewall. Installation, the `inputs.exec` blocks, restart procedure and troubleshooting are all in **[docs/pfsense/TELEGRAF_ON_PFSENSE.md](../docs/pfsense/TELEGRAF_ON_PFSENSE.md)**; this file is only the index.

## Installing

- `./install_plugins.sh` (from a clone of this repository) copies the plugins you pick to `/usr/local/bin/` on the firewall over SSH and marks them executable. Files in `/usr/local` are not part of `config.xml`, so they are not included in configuration backups and may need to be re-copied after a pfSense upgrade or a restore to a fresh install.
- The durable alternative is the **Filer** package: one entry per plugin, full path (e.g. `/usr/local/bin/telegraf_pfifgw.php`), paste the contents, mode **0755** (the default 0644 is not executable). Filer stores the file inside `config.xml` and rewrites it at boot.
- `install_plugins.sh` also looks for `config/additional_config.conf`. That file is **not shipped**; put the `inputs.exec` blocks in the GUI **Services → Telegraf → Additional Configuration** box instead, which is the only place where they persist.

## The plugins

| Plugin | Emits | Prerequisites |
|--------|-------|---------------|
| **`telegraf_pfifgw.php`** | `interface` — one point per assigned interface with tags for IPv4/IPv6 address and subnet, MAC, real and friendly name, and a numeric `status` field (1 up, 0 down, 2 unknown). `gateways` — one point per gateway with `monitor`, `source`, `defaultgw`, `gwdescr`, `delay`, `stddev`, `loss`, `status`, `status_code` (0 online, 1 down, 2 unknown) and `substatus`. | Runs under `/usr/local/bin/php-cgi` and includes pfSense's `config.inc`, `gwlb.inc` and `interfaces.inc`. It calls `return_gateways_status(true)` (not the older `return_gateways_status_text()`) and reads the legacy `$config` global. These internals change across major pfSense releases; run the script by hand after an upgrade to make sure it still works. |
| **`telegraf_temperature.sh`** | `temperature` — one point per `dev.cpu.N` core and per `hw.acpi.thermal.tzN` zone, field `degrees`. | **System → Advanced → Miscellaneous → Thermal Sensors** must be set to the module for your CPU (`coretemp` for Intel, `amdtemp` for AMD); otherwise `sysctl dev.cpu` has no temperature entries and the script prints nothing. |
| **`telegraf_unbound.sh`** | Whatever `unbound-control` prints for the sub-command you pass (use `stats_noreset`), with per-thread lines removed — `key=value` lines, so use `data_format = "logfmt"` plus a `name_override` (e.g. `unbound`). Every Unbound counter becomes a field. | DNS Resolver (Unbound) enabled. Calls `/usr/local/sbin/unbound-control -c /var/unbound/unbound.conf`, so Unbound's remote-control interface must be enabled in the generated config; pfSense does this by default. Verify with `unbound-control -c /var/unbound/unbound.conf status`. |
| **`telegraf_unbound_lite.sh`** | `unbound_lite` — only `total.num.cachehits` and `total.num.cachemiss`. | Same as above. Use this if you only want a cache hit ratio and do not want hundreds of Unbound counters in InfluxDB. |
| **`telegraf_arp_mac_vendor.php`** | `arp_table` — one point per ARP entry; tags `host`, `mac`, `vendor`, `interface`, `ip`; fields `expires` (seconds), `permanent` (0/1). | An OUI database: install the **nmap** package from the GUI package manager (`/usr/local/share/nmap/nmap-mac-prefixes`), or place an IEEE `oui.txt` at `/usr/local/share/oui.txt`. Both formats are parsed. See [docs/pfsense/MAC_VENDOR_LOOKUP_SETUP.md](../docs/pfsense/MAC_VENDOR_LOOKUP_SETUP.md). |

## Wiring them into Telegraf

Paste blocks like this into **Services → Telegraf → Additional Configuration** and click Save (which regenerates `/usr/local/etc/telegraf.conf` and restarts the service):

```toml
[[inputs.exec]]
  commands = ["/usr/local/bin/telegraf_pfifgw.php"]
  timeout = "15s"
  data_format = "influx"

[[inputs.exec]]
  commands = ["/usr/local/bin/telegraf_unbound.sh stats_noreset"]
  timeout = "10s"
  data_format = "logfmt"
  name_override = "unbound"
```

Telegraf on pfSense runs as root by design, so none of these scripts need extra permissions. Test any of them first by running it from a root shell; it should print line protocol and nothing on stderr.

## License

All plugins are MPL-2.0 (see the SPDX headers). Several descend from community pfSense Telegraf plugins; see the acknowledgements in the [main README](../README.md).
