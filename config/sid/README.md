# Suricata SID Management - suppress.conf vs disablesid.conf

## Key Differences

### **disablesid.conf** (Disable List)
- **Purpose**: Completely disables rules - they are NOT loaded into memory
- **Scope**: Global across all traffic
- **Performance**: Better - disabled rules don't consume resources
- **Use Case**: Rules that are always false positives or not relevant to your environment
- **Example**: `1:2029322` (completely removes Telegram detection)
- **Applied**: Via pfSense web UI (Services → Suricata → SID Mgmt) or in `suricata.yaml`

### **suppress.conf** (Suppression List)
- **Purpose**: Rules still run but alerts are suppressed based on conditions
- **Scope**: Can be conditional (by IP, by_src, by_dst, track criteria)
- **Performance**: Worse - rules still consume CPU/memory, alerts just hidden
- **Use Case**: Rules that are only false positives for specific IPs/conditions
- **Example**: `suppress gen_id 1, sig_id 2221034, track by_dst, ip 52.96.79.200`
  - Rule still runs but doesn't alert for traffic to 52.96.79.200
- **Applied**: Via `threshold.config` or pfSense Suppress Lists

---

## Current Configuration Analysis

### Overlap (5 SIDs in BOTH files - REDUNDANT)
These SIDs are **disabled globally** AND **suppressed** - the suppress is unnecessary:

```
1:2000334  # ET P2P BitTorrent peer sync
1:2008578  # ET SCAN Sipvicious Scan  
1:2011716  # ET SCAN Sipvicious User-Agent Detected
1:2012252  # ET SHELLCODE Common 0a0a0a0a Heap Spray String
1:2221034  # SURICATA HTTP Request unrecognized authorization method
```

**Recommendation**: Remove these from `suppress.conf` - already disabled globally

---

### SIDs ONLY in disablesid.conf (151 total)
These are globally disabled - appropriate for:
- Protocol anomaly detection (TCP stream, TLS, QUIC)
- Chat/IM applications (IRC, Skype, Facebook)
- P2P/BitTorrent traffic
- Informational alerts (Java version, user-agents)

**Status**: ✅ Correct usage - these are always false positives

---

### SIDs ONLY in suppress.conf (67 total)
These rules **still run** but alerts are suppressed. Analysis:

#### **Potentially Should Be Disabled Instead:**

**Preprocessor Rules (gen_id 119, 120, 138, 140, 141, 137)**
```bash
gen_id 119: HTTP Inspect preprocessor (7 rules)
gen_id 120: HTTP Inspect preprocessor (5 rules)
gen_id 138: JavaScript obfuscation (5 rules)
gen_id 140: SIP preprocessor (1 rule)
gen_id 141: IMAP preprocessor (1 rule)
gen_id 137: SSL preprocessor (1 rule)
```
These are **always** suppressed (no conditions), wasting resources.

**Recommendation**: Consider disabling these entirely if they're never useful.

#### **Legitimate Suppression (Conditional):**

```
# Only suppressed for specific IP - CORRECT usage
suppress gen_id 1, sig_id 2221034, track by_dst, ip 52.96.79.200
suppress gen_id 1, sig_id 2038669, track by_src, ip 13.59.225.146
```

These should **stay in suppress.conf** - they're only suppressed for specific IPs.

#### **Global Suppressions (Should Be Disabled):**

All other SIDs in suppress.conf without `track by_*` or `ip` conditions:
```
1:536, 1:648, 1:653, 1:1390, 1:2452, 1:8375, 1:11192, 1:12286,
1:15147, 1:15306, 1:15362, 1:16313, 1:16482, 1:17458, 1:20583,
1:23098, 1:23256, 1:24889, 1:2000419, 1:2003195, 1:2008120,
1:2010516, 1:2010935, 1:2010937, 1:2012086, 1:2012088, 1:2012141,
1:2012758, 1:2013222, 1:2013414, 1:2013504, 1:2014518, 1:2014520,
1:2014726, 1:2014819, 1:2015561, 1:2100366, 1:2100368, 1:2100651,
1:2101390, 1:2101424, 1:2102314, 1:2103134, 1:2103192, 1:2406003,
1:2406067, 1:2406069, 1:2406424, 1:2500056, 1:100000230, 1:2033077,
1:2033078 (duplicated 4 times)
```

**Recommendation**: Move these to `disablesid.conf` to improve performance.

---

## Optimization Completed ✅

**Date**: 2025-11-27

All global suppressions have been moved from `suppress.conf` to `disablesid.conf` for optimal performance.

### Changes Made:

1. **Moved 65 SIDs** from suppress.conf to disablesid.conf:
   - 52 standard Suricata rules (gen_id 1)
   - 13 preprocessor rules (gen_id 3, 119, 120, 137, 138, 140, 141)
   
2. **Kept only 2 conditional suppressions** in suppress.conf:
   - `1:2221034` - Microsoft IP (52.96.79.200) - HTTP auth method
   - `1:2038669` - AWS IP (13.59.225.146) - Realtek exploit false positive

3. **Added descriptions** to all disabled SIDs explaining what each rule detects

### Performance Impact:

**Before Optimization:**
- disablesid.conf: 151 rules NOT loaded ✅
- suppress.conf: 67 rules loaded but alerts hidden ⚠️ (wasted resources)
- **Total**: 218 SIDs (67 still consuming CPU/memory)

**After Optimization:**
- disablesid.conf: 216 rules NOT loaded ✅ (improved from 151)
- suppress.conf: 2 rules loaded with conditions ✅ (reduced from 67)
- **Total**: 218 SIDs (only 2 consuming resources, 65 saved!)

**CPU/Memory Savings**: Freed up resources from 65 unnecessarily loaded rules

---

## How to Apply Changes

### Update disablesid.conf:
```bash
# In pfSense: Services → Suricata → Interface → SID Mgmt
# Paste updated disablesid.conf contents → Save → Update Rules
```

### Update suppress.conf:
```bash
# Remove redundant entries
# Keep only conditional suppressions (by IP)
```

### Restart Suricata:
```bash
# pfSense: Services → Suricata → Interface → Restart
```

---

## Files Location

```
config/sid/
├── disable/
│   └── disablesid.conf    # Global disables (151 SIDs)
├── suppress/
│   └── suppress.conf      # Conditional suppressions (67 SIDs)
└── README.md             # This file
```
