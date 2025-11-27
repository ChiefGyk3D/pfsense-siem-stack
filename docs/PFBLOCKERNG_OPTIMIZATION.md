# PfBlockerNG Optimization Guide

## Overview

PfBlockerNG is a powerful package for pfSense that provides DNS-based and IP-based blocklisting to reduce attack surface and noise **before traffic reaches Suricata**. Proper configuration reduces load on your IDS/IPS and improves detection quality.

---

## Why Use PfBlockerNG with Suricata?

1. **Upstream Filtering**: Block known bad actors before they generate Suricata alerts
2. **Reduced Noise**: Fewer false positives from known malicious sources
3. **Performance**: Less traffic to inspect = better Suricata performance
4. **Layered Defense**: Multiple detection mechanisms (DNS, IP, IDS signatures)

---

## Recommended Blocklists

### IP Blocklists (High Priority)

**Abuse.ch Feodo Tracker**
- **Feed**: https://feodotracker.abuse.ch/downloads/ipblocklist.txt
- **Purpose**: C&C servers for banking trojans
- **Action**: Deny Inbound + Deny Outbound
- **Update**: Every 1 hour

**Abuse.ch URLhaus**
- **Feed**: https://urlhaus.abuse.ch/downloads/text_ips/
- **Purpose**: Malware distribution servers
- **Action**: Deny Both
- **Update**: Every 4 hours

**Spamhaus DROP/EDROP**
- **Feed**: Built-in
- **Purpose**: Hijacked netblocks, botnets, spam sources
- **Action**: Deny Inbound
- **Update**: Daily

**Emerging Threats**
- **Feeds**: 
  - Compromised IPs
  - Known scanners
  - Tor exit nodes (optional, depending on policy)
- **Action**: Deny Inbound (or log/alert only for Tor)
- **Update**: Every 12 hours

### DNS Blocklists (Optional but Recommended)

**Steven Black's Unified Hosts**
- **Purpose**: Ads, malware, tracking domains
- **Action**: NXDOMAIN or redirect to sinkhole
- **Use Case**: Reduce outbound noise and protect internal clients

**Abuse.ch ThreatFox**
- **Purpose**: Malware C&C domains
- **Action**: NXDOMAIN
- **Update**: Every 4 hours

---

## Configuration Best Practices

### 1. PfBlockerNG IP Settings

**Firewall → pfBlockerNG → IP → IPv4**

- **Enable Suppression**: YES
  - Whitelist your trusted networks (RFC1918 ranges you control)
  - Whitelist upstream DNS (1.1.1.1, 8.8.8.8, your ISP DNS)
  - Whitelist your SIEM server to prevent accidental blocks

- **Logging**:
  - Enable logging for "Deny Both" rules
  - Log to local syslog
  - Optional: Forward to SIEM server for centralized alerting

- **Alias Update Frequency**:
  - Critical feeds (Feodo, URLhaus): 1-4 hours
  - General feeds (Spamhaus, ET): 12-24 hours
  - Balance between freshness and update load

### 2. List Action Configuration

| Feed Type | Action | Reason |
|-----------|--------|--------|
| C&C Servers | Deny Both | Prevent inbound attacks AND outbound beaconing |
| Scanners/Bruteforce | Deny Inbound | Block reconnaissance, allow your traffic out |
| Spam Sources | Deny Inbound | Block spam, allow your mail servers out |
| Malware Distribution | Deny Both | Prevent downloads AND prevent infected hosts from calling home |

### 3. Suricata Integration

**Ensure proper rule order:**

1. **PfBlockerNG rules** (top of firewall rules)
   - Applied BEFORE Suricata sees traffic
   - Blocks known bad IPs immediately

2. **Floating Rules for Suricata**
   - Applied to interfaces where Suricata is running
   - Ensure traffic flows through Suricata AFTER pfBlockerNG

**Check rule order:**
```bash
# SSH to pfSense
ssh root@192.168.1.1

# View firewall rules (simplified)
pfctl -sr | grep -E 'pfB|suricata'
```

Expected order: pfBlockerNG rules → Suricata inline → Regular rules

---

## Monitoring & Validation

### 1. Check Blocklist Status

**Firewall → pfBlockerNG → Reports → Alerts**

- Review blocked connections
- Identify false positives (add to whitelist if needed)
- Monitor top blocked sources

### 2. Verify Suricata Load Reduction

Before PfBlockerNG:
```bash
# Check Suricata alert rate
tail -f /var/log/suricata/suricata_ix055721/eve.json | grep -c alert
```

After PfBlockerNG (expect 20-40% reduction):
```bash
# Repeat same check, compare rates
```

### 3. Dashboard Integration

**Create pfBlockerNG panel in Grafana:**

If forwarding pfBlockerNG logs to Logstash, add a panel:
- Query: `_exists_:pfblocker.action`
- Visualization: Pie chart (top blocked countries)
- Aggregation: Terms on `pfblocker.list` (which list triggered block)

---

## Troubleshooting

### Issue: Legitimate Site Blocked

**Solution:**
1. Identify blocking list: **Firewall → pfBlockerNG → Reports**
2. Add to whitelist: **Firewall → pfBlockerNG → IP → IPv4 → {Feed} → Custom List → Add IP**
3. Force update: **Firewall → pfBlockerNG → Update → Run**

### Issue: pfBlockerNG Not Blocking

**Check:**
1. pfBlockerNG enabled: **Firewall → pfBlockerNG → General → Enable**
2. Feeds updated: **Firewall → pfBlockerNG → Update → View Update Status**
3. Rule order: pfBlockerNG rules must be ABOVE other rules

**Verify rules exist:**
```bash
pfctl -sr | grep pfB | head -10
```

Should see pfB_* rules at the top.

### Issue: High Update Load

**Solution:**
- Reduce update frequency for non-critical feeds
- Use MaxMind GeoIP blocking instead of large IP lists
- Consolidate feeds (e.g., use Steven Black Unified instead of multiple DNS lists)

---

## Performance Tips

1. **Use Aliases, Not Inline Rules**
   - pfBlockerNG uses aliases (more efficient than thousands of individual rules)
   - Verify: **Firewall → Aliases → IP** should show pfB_* aliases

2. **Limit List Size**
   - Don't enable every possible list
   - Prioritize quality over quantity (Feodo > random "bad IPs" lists)

3. **Schedule Updates Off-Peak**
   - **Firewall → pfBlockerNG → Update → Cron Settings**
   - Run updates during low-traffic hours (3-5 AM)

4. **Monitor Memory Usage**
   - Large blocklists consume RAM
   - **Diagnostics → System Activity → Memory**
   - Keep usage under 80%

---

## Integration with This Project

PfBlockerNG works **upstream** of the Suricata forwarder:

```
Internet
  ↓
PfBlockerNG (block known bad IPs)
  ↓
Suricata (inspect remaining traffic)
  ↓
Forwarder (send to SIEM)
  ↓
OpenSearch/Grafana
```

**Result**: Cleaner Suricata logs, fewer alerts, better signal-to-noise ratio.

---

## Recommended Configuration for This Stack

**Quick Setup (High Security):**

1. Enable feeds:
   - Abuse.ch Feodo (C&C)
   - Abuse.ch URLhaus (Malware)
   - Spamhaus DROP (Hijacked netblocks)
   - ET Compromised IPs

2. Action: **Deny Both** for all

3. Update frequency: **4 hours**

4. Enable suppression, whitelist:
   - Your LAN subnets
   - Your SIEM server IP
   - Upstream DNS servers

5. Enable logging, forward to SIEM (optional)

**Validation:**
```bash
# Check if pfBlockerNG is blocking
pfctl -s rules | grep pfB | wc -l
# Should show >0 rules

# Check blocked connections
pfctl -s states | grep pfB | head
# Should show blocked states if under attack
```

---

## Further Reading

- **pfBlockerNG Official Docs**: https://docs.netgate.com/pfsense/en/latest/packages/pfblocker.html
- **Abuse.ch Feeds**: https://abuse.ch/
- **Spamhaus Lists**: https://www.spamhaus.org/drop/
- **Emerging Threats Intelligence**: https://rules.emergingthreats.net/

---

**Next Steps**: Combine with [Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md) for complete threat detection stack.
