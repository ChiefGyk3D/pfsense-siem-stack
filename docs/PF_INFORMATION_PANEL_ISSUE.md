# PF Information Panel - Known Issue

## Problem Summary

The "PF Information" panel in the Telegraf dashboard shows "No data" even though pfSense firewall (pf) is running and `pfctl -s info` returns statistics when run as root.

## Root Cause

Telegraf's built-in `[[inputs.pf]]` plugin requires **full root access** to `/dev/pf` to retrieve complete firewall statistics. When Telegraf runs as the `telegraf` user (security best practice), `pfctl` returns limited output that the plugin cannot parse correctly.

### Technical Details

**When run as root:**
```bash
# pfctl -s info
Status: Enabled for 12 days 04:48:33          Debug: Urgent

Interface Stats for lagg1             IPv4             IPv6
  Bytes In                               0                0
  Bytes Out                              0                0
  Packets In
    Passed                          915471                0
    Blocked                            311                0

State Table                          Total             Rate
  current entries                     2012               
  searches                      4301356757         4080.5/s
  inserts                         10078013            9.6/s
  removals                        10248000            9.7/s
Counters
  match                           11099682           10.5/s
  ...
```

**When run as telegraf user (even with proxy group):**
```bash
# su -m telegraf -c 'pfctl -s info'
Status: Disabled                                Debug: None

State Table                          Total             Rate
  current entries                        0               
Counters
```

The output shows "Status: Disabled" with no statistics, causing Telegraf's pf plugin to fail with:
```
Error in plugin: struct data for tag "searches" not found in pfctl output
```

This is a **pfSense security feature** - the pf firewall restricts what non-root users can see, even if they have device access via group membership.

## Timeline

- **Before Nov 25, 2025**: PF Information panel was working (Telegraf likely running with elevated privileges somehow)
- **Nov 25 ~22:17**: Telegraf restarted to fix pfBlocker permission issue
- **After 22:17**: Telegraf started with default `telegraf:telegraf` user/group, lost previous privileges
- **Result**: PF Information panel stopped working, shows "No data"

## Solution Options

### Option 1: Run Telegraf as Root (NOT RECOMMENDED)

**Security Risk:** Running Telegraf as root violates the principle of least privilege. If Telegraf or any of its plugins are compromised, the attacker gains root access to your pfSense firewall.

**Why this is dangerous:**
- Telegraf collects data from multiple sources (network, logs, external APIs)
- It processes untrusted input (log files, network responses)
- A vulnerability in Telegraf or any plugin = root compromise
- Goes against security best practices

**Implementation (if you really want to):**
```bash
# SSH to pfSense
ssh root@pfsense

# Edit rc.d script
vi /usr/local/etc/rc.d/telegraf

# Find line:
: ${telegraf_user:="telegraf"}

# Change to:
: ${telegraf_user:="root"}

# Restart
service telegraf onestop && service telegraf onestart
```

**Verdict:** ❌ **DO NOT USE** - Security risk outweighs dashboard panel benefits

---

### Option 2: Custom Exec Plugin with Sudo (MODERATE COMPLEXITY)

**How it works:** Create a custom script that runs `pfctl` via sudo, configure Telegraf to run it as an exec plugin.

**Setup:**

1. **Create pfctl wrapper script:**
```bash
# SSH to pfSense
ssh root@pfsense

# Create script
cat > /usr/local/bin/telegraf-pfctl.sh << 'EOF'
#!/bin/sh
# Telegraf-safe pfctl wrapper
/sbin/pfctl -s info 2>/dev/null | awk '
BEGIN { 
    entries=0; searches=0; inserts=0; removals=0; match=0;
    bad_offset=0; fragment=0; short=0; normalize=0; memory=0;
    bad_timestamp=0; congestion=0; ip_option=0; proto_cksum=0;
    state_mismatch=0; state_insert=0; state_limit=0; src_limit=0; synproxy=0;
}
/current entries/ { entries=$3 }
/searches/ { searches=$3 }
/inserts/ { inserts=$3 }
/removals/ { removals=$3 }
/^  match/ { match=$2 }
/bad-offset/ { bad_offset=$2 }
/fragment/ { fragment=$2 }
/short/ { short=$2 }
/normalize/ { normalize=$2 }
/memory/ { memory=$2 }
/bad-timestamp/ { bad_timestamp=$2 }
/congestion/ { congestion=$2 }
/ip-option/ { ip_option=$2 }
/proto-cksum/ { proto_cksum=$2 }
/state-mismatch/ { state_mismatch=$2 }
/state-insert/ { state_insert=$2 }
/state-limit/ { state_limit=$2 }
/src-limit/ { src_limit=$2 }
/synproxy/ { synproxy=$2 }
END {
    printf "pf entries=%di,searches=%di,inserts=%di,removals=%di,match=%di", \
        entries, searches, inserts, removals, match;
    printf ",bad-offset=%di,fragment=%di,short=%di,normalize=%di,memory=%di", \
        bad_offset, fragment, short, normalize, memory;
    printf ",bad-timestamp=%di,congestion=%di,ip-option=%di,proto-cksum=%di", \
        bad_timestamp, congestion, ip_option, proto_cksum;
    printf ",state-mismatch=%di,state-insert=%di,state-limit=%di,src-limit=%di,synproxy=%di\n", \
        state_mismatch, state_insert, state_limit, src_limit, synproxy;
}
'
EOF

# Make executable
chmod +x /usr/local/bin/telegraf-pfctl.sh

# Test as root
/usr/local/bin/telegraf-pfctl.sh
```

2. **Configure sudo:**
```bash
# Allow telegraf to run pfctl without password
echo 'telegraf ALL=(root) NOPASSWD: /usr/local/bin/telegraf-pfctl.sh' >> /usr/local/etc/sudoers.d/telegraf
chmod 440 /usr/local/etc/sudoers.d/telegraf
```

3. **Update Telegraf config:**
```bash
vi /usr/local/etc/telegraf.conf

# Replace:
[[inputs.pf]]

# With:
[[inputs.exec]]
  commands = ["sudo /usr/local/bin/telegraf-pfctl.sh"]
  data_format = "influx"
  timeout = "5s"
```

4. **Restart Telegraf:**
```bash
service telegraf onestop && service telegraf onestart
```

**Pros:**
- ✅ Telegraf runs as non-root user (secure)
- ✅ Only pfctl command runs with elevated privileges
- ✅ Sudo provides audit trail
- ✅ More granular than full root access

**Cons:**
- ❌ Requires SSH access and manual configuration
- ❌ Sudo configuration may be overwritten by pfSense updates
- ❌ Custom script needs maintenance if pfctl output changes
- ❌ Still grants privileged access (limited scope)

**Verdict:** ⚠️ **ACCEPTABLE** - Better than root, but requires maintenance

---

### Option 3: Disable PF Information Panel (RECOMMENDED)

**How it works:** Accept that this panel won't work with secure Telegraf configuration, hide/remove it from dashboard.

**Reasoning:**
- PF statistics are also available via pfSense GUI (Status → System → pfInfo)
- Other dashboard panels provide more actionable firewall data:
  - pfBlocker panels show actual blocked IPs/feeds
  - Interface panels show bandwidth usage
  - Gateway panels show latency/packet loss
  - System panels show CPU/memory
- The PF Information panel shows mostly cumulative counters that don't change much

**Implementation:**
1. Open Grafana dashboard in edit mode
2. Find "PF Information" panel
3. Either:
   - Delete the panel (permanent)
   - Set it to "Hidden" in panel settings (can unhide later)
   - Add a note explaining it requires root Telegraf (not recommended)

**Pros:**
- ✅ No security compromise
- ✅ No maintenance overhead
- ✅ No custom scripts or sudo rules
- ✅ Telegraf runs securely as intended
- ✅ Other panels provide more useful data

**Cons:**
- ❌ Lose visibility into pf counters (can still check via pfSense GUI)
- ❌ Dashboard has empty space (can rearrange panels)

**Verdict:** ✅ **RECOMMENDED** - Security and simplicity over one low-value panel

---

## What About Adding Telegraf to Groups?

You might wonder: "Can't we just add telegraf to the right group?"

**We tried this:**
```bash
# Add telegraf to proxy group (for /dev/pf access)
pw groupmod proxy -m telegraf

# Verify
id telegraf
# uid=884(telegraf) gid=884(telegraf) groups=884(telegraf),62(proxy)
```

**Result:** Even WITH proxy group membership and correct `/dev/pf` permissions (`crw-rw---- root:proxy`), `pfctl` still returns "Status: Disabled" when run as non-root. This is pfSense-specific behavior - the firewall kernel module restricts what non-root processes can query, regardless of file permissions or group membership.

---

## Recommended Configuration

For most users, we recommend:

1. ✅ **Keep Telegraf running as `telegraf` user** (secure)
2. ✅ **Use Option 2 from SETUP_FILTERLOG_MONITORING_CRON.md** (cron job) to fix pfBlocker log permissions
3. ✅ **Disable/hide the PF Information panel** in Grafana dashboard
4. ✅ **Use pfSense GUI** for PF statistics when needed (Status → System → pfInfo)

This gives you:
- Secure Telegraf configuration
- Working pfBlocker panels
- Working interface/gateway/system panels
- No security compromises

---

## For Advanced Users Who Need PF Statistics

If you absolutely need PF firewall statistics in Grafana and understand the security implications:

1. Implement **Option 2 (Custom Exec Plugin with Sudo)** above
2. Document the sudo rule in your configuration management
3. Test after every pfSense update (sudo config may be reset)
4. Monitor `/var/log/auth.log` for unexpected sudo usage
5. Consider firewall rules to restrict access to Grafana
6. Use strong authentication on Grafana

---

## Testing

After implementing any solution, test:

**1. Check Telegraf is running as non-root:**
```bash
ps -axo user,command | grep telegraf
# Should show: telegraf /usr/local/bin/telegraf ...
```

**2. Check for pf plugin errors:**
```bash
tail -50 /var/log/telegraf/telegraf.log | grep pf
# Option 3 (disabled): Should see no pf errors (plugin removed)
# Option 2 (exec): Should see no errors, or success messages
```

**3. Check InfluxDB for data:**
```bash
# From SIEM server
influx -host 192.168.210.10 -database pfsense -execute "SELECT * FROM pf WHERE time > now() - 5m LIMIT 1"
# Should return data if Option 2 implemented, empty if Option 3
```

**4. Check Grafana panel:**
- Refresh dashboard
- PF Information panel should either work (Option 2) or be hidden (Option 3)

---

## Related Documentation

- [SETUP_FILTERLOG_MONITORING_CRON.md](SETUP_FILTERLOG_MONITORING_CRON.md) - pfBlocker log permissions (still works!)
- [TELEGRAF_PFBLOCKER_SETUP.md](TELEGRAF_PFBLOCKER_SETUP.md) - pfBlocker panel setup
- [PFSENSE_FILTERLOG_ROTATION_FIX.md](PFSENSE_FILTERLOG_ROTATION_FIX.md) - Filterlog rotation bug fix

---

## Summary

The PF Information panel stopped working because:
1. Telegraf was restarted using the WRONG method (`service telegraf restart`) at ~22:17 on Nov 25
2. The `service` command uses the standard rc.d script which runs Telegraf as `telegraf` user
3. pfSense restricts `pfctl` output for non-root users (security feature)
4. Telegraf's pf plugin cannot parse limited output from non-root execution

## ACTUAL SOLUTION (Nov 25, 2025)

**Telegraf on pfSense is SUPPOSED to run as root** via the custom startup script:

```bash
# Correct restart method:
ssh root@pfsense "pkill -f telegraf; sleep 2; nohup /usr/local/etc/rc.d/telegraf.sh start > /dev/null 2>&1 &"
```

**See [TELEGRAF_RESTART_PROCEDURE.md](TELEGRAF_RESTART_PROCEDURE.md) for complete details.**

This is pfSense's expected configuration - Telegraf runs as root for full system access. The panel works perfectly when Telegraf is started correctly.

## Important

The options listed above (running as root, sudo scripts, etc.) are only relevant if you want to run Telegraf as non-root for some reason. **On pfSense, the default and correct configuration is root**, so just use the proper restart procedure documented in TELEGRAF_RESTART_PROCEDURE.md.
