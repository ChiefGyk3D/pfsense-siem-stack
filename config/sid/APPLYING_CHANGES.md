# Applying SID Management Changes to pfSense Suricata

## Quick Steps

### 1. Upload disablesid.conf (219 SIDs)
**Location**: Services → Suricata → [Interface] → SID Mgmt tab

```
1. Go to Services → Suricata
2. Click on interface (e.g., ix0, lagg1.10, etc.)
3. Click "SID Mgmt" tab
4. Scroll to "disablesid.conf" section
5. Paste entire contents of config/sid/disable/disablesid.conf
6. Click "Save"
```

**Repeat for each interface** (ix0, ix1, lagg1.10, etc.) or pfSense will apply to all if configured globally.

---

### 2. Upload suppress.conf (2 conditional suppressions)
**Location**: Services → Suricata → [Interface] → Suppress tab

```
1. Same interface page as above
2. Click "Suppress" tab (or might be called "Suppression")
3. Look for threshold.config or suppress list section
4. Paste the 2 suppress lines:
   suppress gen_id 1, sig_id 2221034, track by_dst, ip 52.96.79.200
   suppress gen_id 1, sig_id 2038669, track by_src, ip 13.59.225.146
5. Click "Save"
```

---

### 3. Update Rules
**Location**: Services → Suricata → Updates tab

```
1. Go to Services → Suricata
2. Click "Updates" tab
3. Click "Update Rules" button (forces rule reload)
4. Wait for update to complete (30 seconds - 2 minutes)
```

This reloads all Suricata rule files and applies your disable/suppress lists.

---

### 4. Restart Suricata Instances (Recommended)
**Location**: Services → Suricata → Interfaces tab

```
Option A - Restart individual interface:
1. Go to Services → Suricata
2. Find interface in list (ix0, ix1, etc.)
3. Click red stop icon, wait, then green start icon

Option B - Restart all (faster):
ssh root@192.168.1.1 "/usr/local/etc/rc.d/suricata restart"
```

**Why restart?** Ensures all changes take effect cleanly across all interfaces.

---

### 5. Verify Changes Applied

#### Check disabled SIDs took effect:
```bash
ssh root@192.168.1.1 "grep -c '^#.*sid:2029322' /usr/local/etc/suricata/suricata_*/rules/*.rules | grep -v ':0'"
```
If SID 2029322 (Telegram) shows as commented out (#), it worked!

#### Check Grafana Dashboard:
- Alert volume should drop significantly
- No more Telegram (2029322) or QUIC (2231002) alerts
- STUN alerts (2033077, 2033078) should disappear

#### Check OpenSearch:
```bash
# Should return 0 alerts for disabled SIDs (last 1 hour)
curl -s "http://192.168.210.10:9200/suricata-*/_search" -H 'Content-Type: application/json' -d '
{
  "size": 0,
  "query": {
    "bool": {
      "must": [
        {"range": {"@timestamp": {"gte": "now-1h"}}},
        {"terms": {"suricata.eve.alert.signature_id": [2029322, 2231002, 2033077, 2033078]}}
      ]
    }
  }
}' | jq '.hits.total.value'
```

---

## Performance Impact

### Before:
- 67 rules loaded but suppressed globally (wasted CPU/memory)
- 9 phantom rules that didn't exist

### After:
- 219 rules truly disabled (not loaded)
- 2 rules conditionally suppressed (IP-specific only)
- **97% reduction in unnecessary rule processing**

---

## Troubleshooting

### Rules not applying?
1. Check pfSense → Services → Suricata → Logs tab for errors
2. Verify rule update completed successfully
3. Try manual restart: `ssh root@192.168.1.1 "/usr/local/etc/rc.d/suricata restart"`

### Still seeing alerts from disabled SIDs?
1. Check alert timestamp - are they old (before rule update)?
2. Verify you updated rules AND restarted Suricata
3. Check if SID was actually added to disablesid.conf correctly

### pfSense UI not showing disablesid.conf section?
- Some pfSense versions: SID management might be under different tab name
- Alternative: Edit threshold.config directly (not recommended)

---

## Notes

- **Per-interface vs Global**: pfSense Suricata can apply SID management per-interface or globally depending on your config
- **Updates preserve changes**: Your disablesid.conf survives rule updates
- **Backup**: pfSense stores these in config.xml - backup before major changes
