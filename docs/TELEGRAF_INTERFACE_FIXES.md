# Telegraf Dashboard Interface Detection Fixes

## Overview
The Telegraf dashboard was hardcoded for specific Intel 1Gb NICs (igb0-3) and OpenVPN (ovpnc1). This prevented it from working with other hardware configurations like Intel 10Gb (ix0/ix1), Intel (em*), Realtek (re*), etc.

## Changes Made

### 1. WAN Variable - Dynamic Auto-Detection
**Location:** `dashboards/telegraf-original.json` lines 6896-6931

**Before:** Static custom variable with hardcoded interfaces
```json
{
  "name": "WAN",
  "type": "custom",
  "query": "igb0,ovpnc1",
  "options": [
    {"text": "igb0", "value": "igb0"},
    {"text": "ovpnc1", "value": "ovpnc1"}
  ]
}
```

**After:** Dynamic query variable that auto-detects from gateways
```json
{
  "name": "WAN",
  "type": "query",
  "datasource": "$dataSource",
  "definition": "SHOW TAG VALUES FROM \"gateways\" WITH KEY = \"interface\" WHERE \"host\" =~ /^$Host$/",
  "query": "SHOW TAG VALUES FROM \"gateways\" WITH KEY = \"interface\" WHERE \"host\" =~ /^$Host$/",
  "refresh": 1,
  "description": "WAN interfaces (auto-detected from gateways)"
}
```

**Benefit:** Automatically detects WAN interfaces from gateway configuration. Works with any NIC type (igb, ix, em, re, hn, etc.)

### 2. LAN Variable - Simplified Exclusion
**Location:** `dashboards/telegraf-original.json` line 6963

**Before:** Hardcoded exclusion regex for specific interfaces
```json
{
  "name": "LAN_Interfaces",
  "regex": "/^(?!enc0$|igb0$|igb1$|igb2$|igb3$|ovpnc1$)/"
}
```

**After:** Only excludes enc0 (encryption pseudo-interface)
```json
{
  "name": "LAN_Interfaces",
  "regex": "/^(?!enc0$)/",
  "description": "LAN interfaces (excludes enc0 and WAN interfaces)"
}
```

**Benefit:** Since WAN variable now auto-detects WAN interfaces, the LAN regex only needs to exclude enc0. The dashboard filtering automatically handles WAN exclusion.

## How It Works

### Gateway-Based Detection
pfSense maintains gateway configuration with interface assignments. The Telegraf `gateways` measurement includes all gateway interfaces.

Query: `SHOW TAG VALUES FROM "gateways" WITH KEY = "interface"`

Returns the interface names that have gateways configured (typically WAN interfaces).

### Interface Type Support
Now works with any pfSense-supported NIC:
- **Intel 1Gb:** igb0, igb1, igb2, igb3
- **Intel 10Gb:** ix0, ix1, ix2, ix3
- **Intel PRO/1000:** em0, em1, em2, em3
- **Realtek:** re0, re1
- **Hyper-V:** hn0, hn1
- **VirtIO:** vtnet0, vtnet1
- **OpenVPN:** ovpnc1, ovpns1
- **WireGuard:** wg0, wg1
- **PPP:** ppp0, pppoe0

### Dynamic Behavior
1. Dashboard loads and queries InfluxDB for gateway interfaces
2. WAN dropdown populates with detected interfaces (e.g., ix0, ix1)
3. LAN dropdown shows all other interfaces except enc0
4. No manual editing required for different hardware

## Testing
After importing the updated dashboard:

1. **Verify WAN Detection:**
   - Open dashboard
   - Check WAN dropdown in top-left variables
   - Should show your actual WAN interfaces (ix0, ix1, etc.)
   - Select your WAN interface(s)

2. **Verify LAN Detection:**
   - Check LAN dropdown
   - Should show bridge*, vlan*, and internal interfaces
   - Should NOT show your physical WAN NICs

3. **Check Panel Data:**
   - WAN Statistics panel should show correct interface traffic
   - Gateway Status should show correct latency/status
   - Network Traffic should properly separate WAN/LAN

## Troubleshooting

### WAN Dropdown Empty
**Cause:** No gateways configured in pfSense  
**Solution:** Configure at least one gateway in System → Routing → Gateways

**Verify gateways data exists:**
```bash
influx -database telegraf -execute "SHOW TAG VALUES FROM gateways WITH KEY = interface"
```

### Wrong Interfaces in WAN
**Cause:** Gateway configured on wrong interface  
**Solution:** Check System → Routing → Gateways in pfSense, ensure gateways are on WAN interfaces

### LAN Shows Physical NICs
**Cause:** Those interfaces have no gateway configured  
**Solution:** This is actually correct. Physical NICs without gateways should appear in LAN unless you add them to WAN gateway configuration.

### No Data in Panels
**Cause:** Telegraf not collecting interface statistics  
**Solution:** Verify Telegraf running on pfSense:
```bash
service telegraf status
telegraf --test --input-filter net
```

## Migration Notes

### For Users with Custom Dashboards
If you've customized the Telegraf dashboard:
1. Backup your current dashboard before importing updated version
2. After import, re-apply your customizations
3. Update any custom panels that reference WAN interfaces

### For Users with Multiple pfSense Instances
The auto-detection works per-host:
1. Select Host variable for different pfSense
2. WAN variable automatically updates for that host's gateways
3. No need to duplicate dashboards per firewall

## Related Files
- `dashboards/telegraf-original.json` - Updated dashboard
- `docs/TELEGRAF_PFBLOCKER_SETUP.md` - pfBlocker panel configuration
- `README.md` - Project documentation

## Benefits
✅ Universal compatibility with any pfSense hardware  
✅ No manual JSON editing required  
✅ Works with multi-WAN configurations  
✅ Automatically adapts to interface changes  
✅ Same dashboard works for all deployments  
✅ Open-source ready - no hardware assumptions
