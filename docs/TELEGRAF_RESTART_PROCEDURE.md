# Telegraf Restart Procedure for pfSense

## Important: pfSense Telegraf Runs as Root

On pfSense, Telegraf is configured to run **as root** via a custom startup script. This is different from standard Linux installations where Telegraf runs as a dedicated `telegraf` user.

### Why Telegraf Runs as Root on pfSense

1. **PF Firewall Access**: The `pf` input plugin requires full access to `/dev/pf` and kernel firewall statistics
2. **pfSense Integration**: pfSense's service management generates custom startup scripts
3. **Multi-Plugin Requirements**: Various plugins need access to system resources restricted to root

### Startup Scripts

pfSense has **TWO** Telegraf startup scripts:

1. **`/usr/local/etc/rc.d/telegraf`** - Standard FreeBSD rc.d script (runs as `telegraf` user)
2. **`/usr/local/etc/rc.d/telegraf.sh`** - pfSense-generated custom script (runs as `root`)

**The `.sh` script is the one pfSense uses** for auto-start and service management.

---

## How to Restart Telegraf (CORRECT METHOD)

### Method 1: Using the Custom .sh Script (RECOMMENDED)

This is how pfSense expects Telegraf to be managed:

```bash
# SSH to pfSense
ssh root@pfsense

# Stop any running Telegraf instances
pkill -f telegraf
sleep 2

# Start using the custom script (properly backgrounded)
nohup /usr/local/etc/rc.d/telegraf.sh start > /dev/null 2>&1 &

# Verify it's running as root
ps aux | grep telegraf | grep -v grep
# Should show: root ... /usr/local/bin/telegraf
```

### Method 2: One-Liner from Remote Host

```bash
ssh root@pfsense "pkill -f telegraf; sleep 2; nohup /usr/local/etc/rc.d/telegraf.sh start > /dev/null 2>&1 &" && sleep 5 && ssh root@pfsense "ps aux | grep telegraf | grep -v grep"
```

---

## What NOT to Do

### ❌ WRONG: Using `service telegraf restart`

```bash
# This uses the WRONG script and runs as telegraf user
service telegraf restart  # DON'T USE THIS
```

**Problem:** The `service` command uses `/usr/local/etc/rc.d/telegraf` which runs Telegraf as the `telegraf` user. This causes:
- PF Information panel to fail (permission denied on /dev/pf)
- Possible issues with other system-level metrics

### ❌ WRONG: Using telegraf.sh without backgrounding

```bash
# This will hang your terminal with continuous output
/usr/local/etc/rc.d/telegraf.sh start  # Will hang terminal
```

**Problem:** The script outputs to stdout/stderr, keeping your SSH session attached. Always use `nohup` with output redirection.

---

## Troubleshooting

### Check if Telegraf is Running

```bash
ssh root@pfsense "ps aux | grep telegraf | grep -v grep"
```

**Expected output:**
```
root    15405   0.5  1.1 5742864 187320  -  S    22:43   0:00.57 /usr/local/bin/telegraf -config=/usr/local/etc/telegraf.conf
root    15402   0.0  0.0   14084   2544   -  Ss   22:43   0:00.00 daemon: /usr/local/bin/telegraf[15405] (daemon)
```

Key indicators:
- ✅ First column shows **`root`** (not `telegraf`)
- ✅ Two processes: daemon parent + telegraf child
- ✅ Using `/usr/local/etc/telegraf.conf`

### Check PF Plugin is Working

```bash
# From SIEM server
influx -host <pfsense_ip> -database pfsense -execute "SELECT * FROM pf WHERE time > now() - 1m LIMIT 1"
```

**If no data:** Telegraf is probably running as wrong user. Restart using Method 1.

### Check Telegraf Logs

```bash
ssh root@pfsense "tail -50 /var/log/telegraf/telegraf.log"
```

**Common errors if running as wrong user:**
```
Error in plugin: error running "pfctl": exit status 1 - pfctl: /dev/pf: Permission denied
```

---

## What Happened (Nov 25, 2025 Incident)

### Timeline

1. **Before 22:17**: Telegraf running as root via `.sh` script, all panels working
2. **22:17**: Investigating pfBlocker permission issue, ran `pkill -9 -f telegraf` to restart
3. **22:17**: Restarted using `service telegraf onestart` (WRONG - uses standard rc.d script)
4. **22:17-22:40**: Telegraf running as `telegraf` user, PF Information panel broken
5. **22:40**: Discovered the issue, restarted using `.sh` script properly
6. **After 22:40**: Telegraf running as root again, all panels working

### Root Cause

When troubleshooting the pfBlocker log permission issue, we restarted Telegraf using the **wrong startup method**. The `service` command used the standard FreeBSD rc.d script which runs Telegraf as the `telegraf` user, breaking the PF plugin.

### Lesson Learned

**Always restart pfSense Telegraf using the custom `.sh` script**, not the standard `service` command.

---

## On Reboot

pfSense's service management will automatically start Telegraf on reboot using the correct `.sh` script. No manual intervention needed.

To verify after reboot:
```bash
ssh root@pfsense "ps aux | grep telegraf | head -2"
```

Should show Telegraf running as `root`.

---

## Security Considerations

### Is Running Telegraf as Root Safe?

**On pfSense: Yes, this is the expected configuration.**

Reasons:
1. ✅ pfSense is a dedicated firewall appliance (not a general-purpose server)
2. ✅ Limited attack surface (firewall rules restrict access)
3. ✅ pfSense generates and manages the startup script
4. ✅ Required for full system metrics (pf, interfaces, gateways)
5. ✅ All pfSense system daemons run as root by default

### Alternative Approach (Not Recommended)

If you want to run Telegraf as non-root:
- Disable the `pf` input plugin (lose PF Information panel)
- Use the standard rc.d script: `service telegraf enable && service telegraf start`
- Add `telegraf` user to necessary groups for log access
- Accept loss of some system metrics

**This is NOT recommended** - you lose functionality and go against pfSense's design.

---

## Quick Reference

### Start Telegraf
```bash
ssh root@pfsense "nohup /usr/local/etc/rc.d/telegraf.sh start > /dev/null 2>&1 &"
```

### Stop Telegraf
```bash
ssh root@pfsense "pkill -f telegraf"
```

### Restart Telegraf
```bash
ssh root@pfsense "pkill -f telegraf; sleep 2; nohup /usr/local/etc/rc.d/telegraf.sh start > /dev/null 2>&1 &"
```

### Check Status
```bash
ssh root@pfsense "ps aux | grep '[t]elegraf'"
```

### Verify Data Flow
```bash
# From SIEM server
influx -host 192.168.210.10 -database pfsense -execute "SELECT COUNT(*) FROM pf WHERE time > now() - 1m"
```

---

## Related Documentation

- [PF_INFORMATION_PANEL_ISSUE.md](PF_INFORMATION_PANEL_ISSUE.md) - Why PF plugin needs root access
- [SETUP_FILTERLOG_MONITORING_CRON.md](SETUP_FILTERLOG_MONITORING_CRON.md) - pfBlocker log permissions (separate issue)
- [PFSENSE_FILTERLOG_ROTATION_FIX.md](PFSENSE_FILTERLOG_ROTATION_FIX.md) - Filterlog rotation bug

---

## Summary

- ✅ Telegraf on pfSense runs as **root** by design
- ✅ Use `/usr/local/etc/rc.d/telegraf.sh start` for restarts (with nohup)
- ✅ Never use `service telegraf restart` (wrong user)
- ✅ This is normal and expected for pfSense
- ✅ Auto-starts correctly on reboot
