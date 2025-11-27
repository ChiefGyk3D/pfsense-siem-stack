# MAC Vendor Lookup in Grafana

## Overview

This guide enables MAC address vendor/manufacturer lookup in your pfSense Grafana dashboards, similar to the Unifi dashboard functionality. This allows you to see which device manufacturers are on your network (Apple, Samsung, Intel, etc.).

## Features

- ✅ **MAC Vendor Identification**: Lookup manufacturer from MAC address OUI (first 6 hex digits)
- ✅ **ARP Table Monitoring**: Track all devices currently on the network
- ✅ **Interface Mapping**: See which interface each device is connected through
- ✅ **Lease Expiration**: Track DHCP lease expiration times
- ✅ **30,000+ Vendors**: Uses nmap's comprehensive OUI database

## Prerequisites

- pfSense 2.6+ with Telegraf installed
- SSH access to pfSense
- nmap package (for MAC vendor database)

---

## Installation Steps

### Step 1: Install nmap Package on pfSense

The nmap package includes a comprehensive MAC vendor database (`nmap-mac-prefixes`).

**Option A: Via pfSense Web GUI (Recommended)**

1. Login to pfSense web interface
2. Go to **System → Package Manager → Available Packages**
3. Search for **"nmap"**
4. Click **Install** on **pfSense-pkg-nmap**
5. Confirm installation

**Option B: Via SSH**

```bash
# SSH to pfSense
ssh root@pfsense

# Install nmap package
pkg install -y pfSense-pkg-nmap

# Verify installation
ls -l /usr/local/share/nmap/nmap-mac-prefixes
# Should show the database file (~30,000 vendors)
```

### Step 2: Upload the Plugin to pfSense

```bash
# From your workstation
scp plugins/telegraf_arp_mac_vendor.php root@192.168.1.1:/root/

# SSH to pfSense
ssh root@192.168.1.1

# Move to proper location
mv /root/telegraf_arp_mac_vendor.php /root/telegraf_arp_mac_vendor.php

# Make executable
chmod +x /root/telegraf_arp_mac_vendor.php

# Test the plugin
/root/telegraf_arp_mac_vendor.php
```

**Expected output:**
```
arp_table,host=chiefgyk3d.firewall,mac=18:e8:29:4f:90:b9,vendor=Espressif\ Inc.,interface=lagg1,ip=192.168.1.10 expires=630,permanent=0
arp_table,host=chiefgyk3d.firewall,mac=74:ac:b9:44:aa:e0,vendor=Apple\,\ Inc.,interface=lagg1,ip=192.168.1.13 expires=1190,permanent=0
...
```

### Step 3: Configure Telegraf

Add the exec plugin to Telegraf configuration:

```bash
# SSH to pfSense
ssh root@pfsense

# Edit Telegraf config
vi /usr/local/etc/telegraf.conf

# Add at the end (before any [[outputs]] section):
[[inputs.exec]]
  commands = ["/root/telegraf_arp_mac_vendor.php"]
  timeout = "10s"
  data_format = "influx"
  interval = "60s"
  name_suffix = ""
```

**Configuration explained:**
- `commands`: Path to our custom plugin
- `timeout`: Max execution time (10 seconds)
- `data_format`: "influx" (InfluxDB line protocol)
- `interval`: Run every 60 seconds (adjust as needed)
- `name_suffix`: Empty to avoid double naming

### Step 4: Restart Telegraf

```bash
# Use the correct restart method (see TELEGRAF_RESTART_PROCEDURE.md)
pkill -f telegraf
sleep 2
nohup /usr/local/etc/rc.d/telegraf.sh start > /dev/null 2>&1 &

# Verify it's running
ps aux | grep telegraf | grep -v grep
```

### Step 5: Verify Data in InfluxDB

Wait 60 seconds for first collection, then check:

```bash
# From your SIEM server (or any machine with influx CLI)
influx -host 192.168.210.10 -database pfsense -execute "SHOW MEASUREMENTS" | grep arp

# Should show: arp_table

# Query recent data
influx -host 192.168.210.10 -database pfsense -execute "SELECT * FROM arp_table WHERE time > now() - 5m LIMIT 10"
```

**Expected fields:**
- **Tags**: `host`, `mac`, `vendor`, `interface`, `ip`
- **Fields**: `expires` (seconds), `permanent` (0 or 1)

---

## Grafana Dashboard Panels

### Panel 1: Active Devices by Vendor

**Query:**
```sql
SELECT COUNT(DISTINCT("mac")) 
FROM "arp_table" 
WHERE $timeFilter 
GROUP BY "vendor"
```

**Visualization:** Pie Chart or Bar Graph
**Shows:** Top device manufacturers on your network

### Panel 2: Device List with Vendors

**Query:**
```sql
SELECT LAST("expires"), "vendor", "interface", "ip"
FROM "arp_table" 
WHERE $timeFilter 
GROUP BY "mac"
```

**Visualization:** Table
**Columns:**
- MAC Address
- IP Address  
- Vendor/Manufacturer
- Interface
- Expires In (seconds)

### Panel 3: Vendor Activity Over Time

**Query:**
```sql
SELECT COUNT(DISTINCT("mac"))
FROM "arp_table" 
WHERE $timeFilter AND "vendor" =~ /$vendor/
GROUP BY time($__interval), "vendor" fill(null)
```

**Visualization:** Time Series Graph
**Shows:** Device count trends by vendor over time

### Panel 4: Unknown Devices (Security)

**Query:**
```sql
SELECT "mac", "ip", "interface", LAST("expires")
FROM "arp_table" 
WHERE $timeFilter AND "vendor" = 'Unknown'
GROUP BY "mac", "ip"
```

**Visualization:** Table with Alert Threshold
**Purpose:** Flag unregistered/custom MAC addresses (potential security concern)

---

## Alternative: Download OUI Database Directly

If you don't want to install nmap (saves ~50MB), you can download just the OUI database:

```bash
# SSH to pfSense
ssh root@pfsense

# Create directory
mkdir -p /usr/local/share/nmap

# Download nmap MAC prefixes (updated regularly by nmap project)
fetch -o /usr/local/share/nmap/nmap-mac-prefixes https://raw.githubusercontent.com/nmap/nmap/master/nmap-mac-prefixes

# Verify
head -10 /usr/local/share/nmap/nmap-mac-prefixes
# Should show: 000000 Officially Xerox, but 0:0:0:0:0:0 is more common
```

**Or use IEEE's official OUI database:**

```bash
# Download IEEE OUI database (larger, more detailed)
fetch -o /usr/local/share/oui.txt https://standards-oui.ieee.org/oui/oui.txt

# Modify plugin to use this format (already supported in code)
```

---

## Troubleshooting

### No data appearing in InfluxDB

**Check Telegraf is running the exec plugin:**
```bash
ssh root@pfsense "tail -50 /var/log/telegraf/telegraf.log | grep -A5 exec"
```

**Manually test the plugin:**
```bash
ssh root@pfsense "/root/telegraf_arp_mac_vendor.php"
# Should output data in InfluxDB line protocol format
```

**Check for errors:**
```bash
ssh root@pfsense "/root/telegraf_arp_mac_vendor.php 2>&1 | grep -i error"
```

### Vendor shows as "Unknown"

**Verify MAC database is installed:**
```bash
ssh root@pfsense "ls -lh /usr/local/share/nmap/nmap-mac-prefixes"
# Should be ~900KB file

# Check database contents
ssh root@pfsense "head -20 /usr/local/share/nmap/nmap-mac-prefixes"
```

**Some devices will legitimately show "Unknown":**
- Locally administered MAC addresses (bit 2 of first octet set)
- Very new devices not yet in database
- Custom/modified MAC addresses
- Virtual machines with randomized MACs

### High Memory Usage

If you have 1000+ ARP entries, consider:

**Option 1: Increase collection interval**
```conf
[[inputs.exec]]
  ...
  interval = "300s"  # Collect every 5 minutes instead of 60s
```

**Option 2: Filter permanent entries**
Modify the plugin to skip permanent entries (reduces noise):
```php
// In get_arp_table() function, add:
if ($permanent) {
    continue;  // Skip permanent entries
}
```

### Plugin execution timeout

If you have a large ARP table (500+ entries):

```conf
[[inputs.exec]]
  ...
  timeout = "30s"  # Increase from 10s to 30s
```

---

## OS Detection (Future Enhancement)

Currently, pfSense doesn't provide OS detection in firewall logs. For OS visibility, you have these options:

### Option 1: Use Suricata (Already Installed)

Suricata can detect OS via traffic analysis. Check OpenSearch for:
```
event_type: "http" AND http.http_user_agent: *
```

User-Agent strings reveal OS:
- `Windows NT 10.0` = Windows 10/11
- `Macintosh; Intel Mac OS X` = macOS
- `Linux; Android` = Android
- `iPhone; CPU iPhone OS` = iOS

### Option 2: TTL-Based Detection (Low Accuracy)

Could add TTL tracking to the ARP plugin:
- Windows: TTL 128
- Linux/Android: TTL 64
- macOS/iOS: TTL 64
- Network devices: TTL 255

**Limitation:** Many OSes use the same TTL, and TTL can be modified.

### Option 3: DHCP Fingerprinting (Complex)

Would require:
1. Capturing DHCP DISCOVER/REQUEST packets
2. Parsing Option 55 (Parameter Request List)
3. Matching against fingerprint database
4. Much more complex implementation

**Recommendation:** For now, use Suricata HTTP User-Agent data in OpenSearch for OS detection.

---

## Performance Impact

- **CPU**: Minimal (~0.1% CPU every 60 seconds)
- **Memory**: ~2MB for MAC database in memory
- **Disk**: ~1MB for nmap package database
- **Network**: None (reads local ARP table)
- **InfluxDB**: ~100-500 bytes per device per minute

For 100 devices collected every 60 seconds:
- **Daily data**: ~7MB
- **Monthly data**: ~210MB
- **With retention policy** (30 days): Manageable

---

## Related Documentation

- [TELEGRAF_RESTART_PROCEDURE.md](TELEGRAF_RESTART_PROCEDURE.md) - How to restart Telegraf correctly
- [TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md) - pfBlocker log collection
- Unifi Dashboard - Reference for similar MAC vendor displays

---

## Example Dashboard JSON (Optional)

Coming soon: Pre-built Grafana dashboard panels for MAC vendor visualization.

---

## Summary

After following this guide:
- ✅ MAC addresses automatically enriched with vendor names
- ✅ See which manufacturers' devices are on your network
- ✅ Track device connectivity per interface
- ✅ Monitor ARP table changes over time
- ✅ Similar functionality to Unifi dashboards

No OS detection yet (requires more complex implementation), but vendor lookup provides valuable network visibility!
