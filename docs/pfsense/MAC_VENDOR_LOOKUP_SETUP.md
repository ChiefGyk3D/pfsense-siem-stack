# MAC Vendor Lookup in Grafana

## Overview

This guide adds MAC address vendor/manufacturer lookup to your pfSense Grafana dashboards, similar to what UniFi controllers show. A small Telegraf exec plugin reads the firewall's ARP table, resolves each MAC's OUI (first three octets) against an OUI database, and writes the result to InfluxDB so you can see which manufacturers' devices are on each network segment.

It works on any pfSense box running the Telegraf package; nothing here depends on the rest of the SIEM stack.

## Features

- **MAC vendor identification** from the OUI prefix
- **ARP table monitoring**: every device currently known to the firewall
- **Interface mapping**: which interface/VLAN each device sits behind
- **Lease expiry**: seconds until the ARP entry expires
- **Tens of thousands of vendors** via nmap's `nmap-mac-prefixes` or the IEEE `oui.txt`

## Prerequisites

- pfSense CE 2.7+ / pfSense Plus 23.x+ with the **Telegraf** package installed and working (see [TELEGRAF_ON_PFSENSE.md](TELEGRAF_ON_PFSENSE.md))
- SSH access to pfSense (for installing and testing the plugin)
- An OUI database: the **nmap** package (recommended) or a downloaded `oui.txt`

---

## Installation Steps

### Step 1: Install the nmap package

The nmap package ships `/usr/local/share/nmap/nmap-mac-prefixes`, a plain-text OUI list of roughly 1 MB.

1. Log in to the pfSense web GUI
2. **System → Package Manager → Available Packages**
3. Search for **nmap**, click **Install** on `pfSense-pkg-nmap`, confirm

Install it through the GUI, not with `pkg install` from the shell: GUI-installed packages are recorded in `config.xml` and are reinstalled automatically after a pfSense upgrade or restore; a shell `pkg install` is not.

Verify:

```bash
ssh admin@<PFSENSE_IP> "ls -lh /usr/local/share/nmap/nmap-mac-prefixes"
```

### Step 2: Install the plugin

From a clone of this repository on your workstation:

```bash
./install_plugins.sh
# choose 5) telegraf_arp_mac_vendor.php
```

This copies the script to **`/usr/local/bin/telegraf_arp_mac_vendor.php`** on the firewall and makes it executable. (Files in `/usr/local` are not part of `config.xml`; if you want the plugin to survive a restore onto a fresh install, store it with the Filer package instead, as described in [TELEGRAF_ON_PFSENSE.md](TELEGRAF_ON_PFSENSE.md#42-files-in-usrlocal-are-not-backed-up).)

Test it:

```bash
ssh admin@<PFSENSE_IP> "/usr/local/bin/telegraf_arp_mac_vendor.php"
```

Expected output (one line per ARP entry):

```
arp_table,host=pfsense.example.com,mac=00:11:22:33:44:55,vendor=Espressif\ Inc.,interface=igc1.20,ip=10.10.20.15 expires=630,permanent=0
arp_table,host=pfsense.example.com,mac=00:11:22:33:44:66,vendor=Apple\,\ Inc.,interface=igc1.10,ip=10.10.10.23 expires=1190,permanent=0
```

If it prints `Warning: MAC vendor database not found` on stderr, Step 1 did not complete.

### Step 3: Add the exec input to Telegraf

Go to **Services → Telegraf**, scroll to **Additional Configuration**, and paste:

```toml
[[inputs.exec]]
  commands = ["/usr/local/bin/telegraf_arp_mac_vendor.php"]
  timeout = "10s"
  data_format = "influx"
  interval = "60s"
```

Click **Save**. pfSense regenerates `/usr/local/etc/telegraf.conf` from `config.xml` and restarts Telegraf. Do **not** edit `/usr/local/etc/telegraf.conf` by hand; it is overwritten on every save and on every upgrade. The Additional Configuration box is the only place where this block persists.

Settings explained:

- `commands`: path to the plugin
- `timeout`: maximum run time (raise to `30s` for ARP tables with hundreds of entries)
- `data_format`: InfluxDB line protocol
- `interval`: run once a minute; the ARP table does not change fast enough to justify the global 10 s interval

### Step 4: Confirm Telegraf picked it up

Saving the Telegraf page already restarted the service. If you need to restart manually, use **Status → Services** or `/usr/local/etc/rc.d/telegraf.sh restart`; see [TELEGRAF_ON_PFSENSE.md](TELEGRAF_ON_PFSENSE.md#5-restarting-telegraf-correctly) for why `service telegraf restart` is the wrong command on pfSense.

```bash
ssh admin@<PFSENSE_IP> "grep -A4 telegraf_arp_mac_vendor /usr/local/etc/telegraf.conf"
ssh admin@<PFSENSE_IP> "ps -axo user,command | grep '[t]elegraf'"
```

### Step 5: Verify data in InfluxDB

Wait a minute for the first collection, then from the SIEM server (or anywhere with the `influx` CLI):

```bash
influx -host <SIEM_IP> -database pfsense -execute "SHOW MEASUREMENTS" | grep arp
# arp_table

influx -host <SIEM_IP> -database pfsense -execute "SELECT * FROM arp_table WHERE time > now() - 5m LIMIT 10"
```

Schema written by the plugin:

- **Tags**: `host`, `mac`, `vendor`, `interface`, `ip`
- **Fields**: `expires` (seconds until the ARP entry expires), `permanent` (0 or 1)

---

## Grafana Dashboard Panels

All queries use the InfluxDB datasource and the `pfsense` database.

### Panel 1: Active devices by vendor

```sql
SELECT COUNT(DISTINCT("mac"))
FROM "arp_table"
WHERE $timeFilter
GROUP BY "vendor"
```

**Visualization:** Pie chart or bar gauge. Shows the top manufacturers on your network.

### Panel 2: Device list with vendors

```sql
SELECT LAST("expires"), "vendor", "interface", "ip"
FROM "arp_table"
WHERE $timeFilter
GROUP BY "mac"
```

**Visualization:** Table with columns MAC, IP, Vendor, Interface, Expires (s).

### Panel 3: Vendor activity over time

```sql
SELECT COUNT(DISTINCT("mac"))
FROM "arp_table"
WHERE $timeFilter AND "vendor" =~ /$vendor/
GROUP BY time($__interval), "vendor" fill(null)
```

**Visualization:** Time series. Add a `vendor` dashboard variable (`SHOW TAG VALUES FROM "arp_table" WITH KEY = "vendor"`) to drive the regex.

### Panel 4: Unknown devices

```sql
SELECT "mac", "ip", "interface", LAST("expires")
FROM "arp_table"
WHERE $timeFilter AND "vendor" = 'Unknown'
GROUP BY "mac", "ip"
```

**Visualization:** Table. Flags MACs with no OUI match, which are usually randomized/locally administered addresses (see [Troubleshooting](#vendor-shows-as-unknown)) but occasionally something worth a look.

---

## Alternative: use an OUI file instead of the nmap package

If you would rather not install nmap, the plugin also reads these files, in this order, and stops at the first one it finds:

1. `/usr/local/share/nmap/nmap-mac-prefixes` (nmap format: `000C29 VMware`)
2. `/usr/local/share/oui.txt` (IEEE format: `00-0C-29   (hex)    VMware, Inc.`)
3. `/var/db/oui.txt` (IEEE format)

Both formats are parsed as-is; no changes to the plugin are needed.

```bash
ssh admin@<PFSENSE_IP>

# nmap's list without the nmap package (~1 MB)
mkdir -p /usr/local/share/nmap
fetch -o /usr/local/share/nmap/nmap-mac-prefixes https://raw.githubusercontent.com/nmap/nmap/master/nmap-mac-prefixes

# or the IEEE registry (several MB, more entries)
fetch -o /usr/local/share/oui.txt https://standards-oui.ieee.org/oui/oui.txt
```

A downloaded file is not in `config.xml` and is not refreshed automatically; you will need to re-fetch it after a fresh install and occasionally to pick up new vendors. The nmap package is the lower-maintenance option.

---

## Troubleshooting

### No data in InfluxDB

```bash
# Is the exec block in the generated config?
ssh admin@<PFSENSE_IP> "grep -c telegraf_arp_mac_vendor /usr/local/etc/telegraf.conf"

# Does Telegraf log an error for it?
ssh admin@<PFSENSE_IP> "grep -i arp_mac /var/log/telegraf/telegraf.log | tail -20"

# Does the plugin run cleanly by hand?
ssh admin@<PFSENSE_IP> "/usr/local/bin/telegraf_arp_mac_vendor.php | head -3"

# One-shot test of the whole Telegraf config without writing to outputs
ssh admin@<PFSENSE_IP> "telegraf --test --config /usr/local/etc/telegraf.conf 2>&1 | grep arp_table | head"
```

### Vendor shows as "Unknown"

Check the database is present:

```bash
ssh admin@<PFSENSE_IP> "ls -lh /usr/local/share/nmap/nmap-mac-prefixes /usr/local/share/oui.txt 2>/dev/null"
```

Some devices legitimately have no vendor:

- **Randomized / locally administered MACs** (second-least-significant bit of the first octet set; e.g. first octet `x2`, `x6`, `xA`, `xE`). Modern phones and laptops do this per Wi-Fi network by default.
- Very new OUI assignments not yet in the database
- Virtual machines and containers with generated MACs

### Plugin timeout

For ARP tables with several hundred entries, raise `timeout` in the exec block to `30s`.

### Too much data

At the default 60 s interval, each device produces one point per minute. If you have 1000+ ARP entries, raise `interval` to `300s`, or skip permanent entries by adding `if ($permanent) { continue; }` inside `get_arp_table()` in the plugin.

---

## OS Detection (not implemented)

pfSense does not expose operating system fingerprints in its logs. Options, roughly in order of practicality:

1. **Suricata HTTP user agents** (if you already run Suricata and forward `http` events): `event_type:http AND http.http_user_agent:*`. User agents reveal `Windows NT 10.0`, `Macintosh; Intel Mac OS X`, `Linux; Android`, `iPhone; CPU iPhone OS`, and so on. Only works for plaintext HTTP.
2. **TTL heuristics** (128 Windows, 64 Linux/Android/macOS/iOS, 255 network gear): cheap but low accuracy and easily wrong.
3. **DHCP fingerprinting** (Option 55 parameter request lists matched against a fingerprint database): accurate but a significant amount of new code.

Vendor lookup already gives you most of the practical value (an "Espressif" or "Tuya" device is an IoT gadget; "Apple" is an Apple device), so OS detection is left as a future enhancement.

---

## Performance Impact

- **CPU**: negligible (a PHP script reading `arp -an` once a minute)
- **Memory**: a few MB while the OUI table is loaded, released when the script exits
- **Disk**: the `nmap-mac-prefixes` file is about 1 MB; the nmap package as a whole is a few tens of MB. The IEEE `oui.txt` is several MB.
- **InfluxDB**: roughly 100-500 bytes per device per collection. For 100 devices at 60 s that is on the order of 5-10 MB/day, or a few hundred MB per month before retention-policy compaction.

---

## Related Documentation

- [TELEGRAF_ON_PFSENSE.md](TELEGRAF_ON_PFSENSE.md) — installing Telegraf, the Additional Configuration box, restart procedure, troubleshooting
- [plugins/README.md](../../plugins/README.md) — index of all Telegraf plugins in this repository
- [TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md) — pfBlockerNG log collection

---

## Summary

After following this guide:

- MAC addresses in the ARP table are enriched with vendor names
- You can see which manufacturers' devices are on each interface/VLAN
- Randomized-MAC devices show up as "Unknown", which is itself useful signal
- Everything persists across upgrades as long as the exec block lives in the GUI Additional Configuration box and nmap was installed through the package manager
