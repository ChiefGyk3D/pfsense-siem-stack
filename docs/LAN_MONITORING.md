# LAN Monitoring & East-West Detection

## Overview

**East-West traffic** refers to lateral movement within your network (between VLANs, hosts on the same subnet, or across internal segments). This is critical for detecting:

- Compromised hosts spreading malware
- Insider threats
- Lateral movement after initial breach
- Internal reconnaissance/scanning

This guide shows how to configure Suricata to monitor **internal traffic** in addition to WAN-facing IDS/IPS.

---

## Architecture

```
Internet → WAN (ix0) [Inline IPS] → pfSense → Internal VLANs
                                                     ↓
                                            [IDS on VLANs]
                                            (lagg1.*, etc.)
                                                     ↓
                                          Detect RFC1918 → RFC1918
```

**Key Principle**: 
- **WAN interfaces**: Inline IPS (block threats)
- **Internal VLANs**: IDS mode (alert only, don't break internal traffic)

---

## Suricata Configuration for LAN Monitoring

### 1. Enable Suricata on Internal Interfaces

**Services → Suricata → Interfaces → Add**

For each internal VLAN (e.g., `lagg1.10`, `lagg1.22`, `lagg1.23`):

| Setting | Value | Reason |
|---------|-------|--------|
| **Interface** | lagg1.10 (or your VLAN) | Interface to monitor |
| **Description** | LAN_VLAN10_IDS | Clear naming |
| **Enable** | ✓ | Activate monitoring |
| **IPS Mode** | ❌ (IDS only) | Don't block internal traffic (alert only) |
| **Promiscuous Mode** | ✓ | See all traffic on segment |
| **HOME_NET** | `192.168.0.0/16,10.0.0.0/8,172.16.0.0/12` | Your internal networks |
| **EXTERNAL_NET** | `!$HOME_NET` | Everything else |

**Repeat for each VLAN** you want to monitor.

### 2. Rule Selection for LAN Monitoring

**Services → Suricata → {Interface} → Rules**

Enable these rulesets for internal monitoring:

| Ruleset | Purpose | Priority |
|---------|---------|----------|
| **ET malware** | Detect C&C beaconing from internal hosts | High |
| **ET exploit** | Detect exploit attempts (lateral movement) | High |
| **ET policy** | Detect policy violations (torrents, etc.) | Medium |
| **ET scan** | Detect internal port scanning | High |
| **ET compromised** | Known compromised host signatures | High |
| **ET worm** | Worm propagation (WannaCry, NotPetya, etc.) | High |

**Disable or tune:**
- `ET INFO` rules (too noisy for internal networks)
- `ET dns` rules (unless you want to monitor internal DNS queries)

**Custom rule example** (detect SMB brute force):
```
alert tcp $HOME_NET any -> $HOME_NET 445 (msg:"ET SCAN SMB Brute Force Attempt"; flow:to_server; content:"|ff|SMB|72|"; offset:4; depth:5; threshold:type threshold, track by_src, count 10, seconds 60; sid:9000001; rev:1;)
```

Add to **Local.rules** for custom detections.

### 3. Configure Interface-Specific Tuning

**Per-VLAN Policy Examples:**

**IoT VLAN (lagg1.22)** - High Security:
- IDS mode (alert only)
- All malware, exploit, scan rules enabled
- Block unexpected outbound connections at firewall level
- Alert on any RFC1918 → RFC1918 traffic (IoT shouldn't talk to other VLANs)

**Corporate VLAN (lagg1.10)** - Balanced:
- IDS mode
- Malware, exploit, compromised rules
- Allow normal business traffic (SMB, RDP within VLAN)
- Alert on cross-VLAN access attempts

**NAS/Server VLAN (lagg1.14)** - Light Monitoring:
- IDS mode
- Exploit and compromised rules only
- Trust internal traffic but alert on anomalies

---

## Grafana Dashboard for LAN Monitoring

### Suricata Per-Interface Dashboard

**Dashboard**: `dashboards/Suricata_Per_Interface.json` ✅ **Production Ready**

This dashboard provides **dynamic per-interface monitoring** with automatically repeating sections for each VLAN/interface you select.

#### Dashboard Features

- **Multi-Select Interface Variable**: Choose one, multiple, or all interfaces
- **Dynamic Row Repeating**: Automatically creates a monitoring section for each selected interface
- **Complete Per-Interface Analytics**: Each interface gets its own set of panels

#### Panels (Per Interface)

1. **Events & Alerts Counter**
   - Total events and alerts for this interface
   - Color-coded thresholds (green/yellow/red)
   - Sparkline showing trend

2. **Top Alert Signatures**
   - Pie chart of most triggered IDS rules
   - Shows signature name and count
   - Hover to see details

3. **Alerts Timeline**
   - Time series graph of alerts over time
   - Identifies attack patterns and spikes

4. **Top Source IPs**
   - Bar chart of internal hosts generating most alerts
   - Useful for identifying compromised devices

5. **Top Destination IPs**
   - Bar chart of most targeted internal hosts
   - Identifies attack targets

6. **Alert Logs Table**
   - Complete alert details per interface
   - Columns: Time, Category, Signature, Action, Severity, Protocol, IPs, Ports, Countries
   - 50 most recent alerts

#### How to Use

1. **Import Dashboard**:
   ```bash
   Grafana → Dashboards → Import → Upload dashboards/Suricata_Per_Interface.json
   ```

2. **Select Interfaces**:
   - Use the interface dropdown at the top
   - Select specific VLANs (e.g., `lagg1.10`, `lagg1.22`)
   - Or select "All" to see all interfaces

3. **Customize Thresholds**:
   - Edit dashboard
   - Adjust threshold values per your traffic volume
   - WAN interfaces: Higher thresholds (500/2000 alerts)
   - LAN interfaces: Lower thresholds (50/200 alerts)

#### Example Use Cases

**Monitor IoT VLAN Only**:
- Interface Variable: Select `lagg1.22` (IoT VLAN)
- See only IoT-specific alerts and events
- Identify compromised IoT devices

**Compare Multiple VLANs**:
- Interface Variable: Select `lagg1.10`, `lagg1.22`, `lagg1.23`
- See side-by-side comparison of alert volumes
- Identify which VLAN has most activity

**Full Network View**:
- Interface Variable: Select "All"
- See every monitored interface with its own section
- Scroll through to review all VLANs

![Per-Interface Dashboard](../media/Suricata%20Per-Interface%20Dashboard.png)
*Example of dynamic interface sections - each VLAN gets complete monitoring*

---

## Detection Use Cases

### 1. Compromised IoT Device

**Scenario**: Smart TV on IoT VLAN gets compromised, tries to scan internal network.

**Detection**:
- Suricata on `lagg1.22` (IoT VLAN) sees scan attempts
- Alert: `ET SCAN Potential Port Scan`
- Dashboard shows unusual traffic from `192.168.22.45` (TV) → `192.168.10.0/24` (Corporate VLAN)

**Response**: Isolate device, investigate

### 2. Lateral Movement After Breach

**Scenario**: Attacker compromises workstation on Corporate VLAN, tries to pivot to Server VLAN.

**Detection**:
- Suricata on `lagg1.10` sees exploit attempt
- Alert: `ET EXPLOIT Windows SMB Remote Code Execution`
- Traffic from `192.168.10.55` → `192.168.14.10` (NAS)

**Response**: Quarantine workstation, check Server VLAN for compromise

### 3. Internal C&C Beaconing

**Scenario**: Malware on workstation tries to beacon to attacker's internal C&C (pivot point).

**Detection**:
- Suricata sees periodic connections to unusual internal IP
- Alert: `ET MALWARE Possible C&C Traffic`
- Repeated connections from `192.168.10.75` → `192.168.10.200` on high port

**Response**: Investigate both hosts, check for lateral spread

---

## Integration with Forwarder

The **forwarder automatically handles all Suricata instances**, including LAN interfaces:

```bash
# Forwarder discovers ALL eve.json files
/var/log/suricata/suricata_ix055721/eve.json      # WAN
/var/log/suricata/suricata_lagg1.1020460/eve.json # VLAN 10
/var/log/suricata/suricata_lagg1.2249359/eve.json # VLAN 22
# ... etc.
```

**No additional configuration needed** — forwarder tails all instances and forwards to Logstash with the same enrichment (GeoIP, interface normalization).

**Verify:**
```bash
# Check forwarder is monitoring LAN interfaces
ssh root@192.168.1.1 "ps aux | grep forward-suricata-eve.py | grep -v grep | awk '{print \$2}' | xargs -I {} lsof -p {} 2>/dev/null | grep 'eve.json'"
```

Should see multiple `eve.json` files (one per interface).

---

## Grafana Filtering for LAN vs WAN

### WAN Dashboard
Filter: `suricata.eve.in_iface:(ix0 OR ix1)`

### LAN Dashboard
Filter: `suricata.eve.in_iface:(lagg* OR vlan*)`

### Lateral Movement Dashboard
Filter: 
```
suricata.eve.src_ip:(192.168.0.0/16 OR 10.0.0.0/8) 
AND suricata.eve.dest_ip:(192.168.0.0/16 OR 10.0.0.0/8)
AND suricata.eve.event_type:alert
```

---

## Performance Considerations

**Internal traffic volume is typically MUCH higher than WAN traffic.**

### Tuning Tips

1. **Use IDS mode** (not inline IPS) on internal interfaces
   - Inline mode adds latency
   - IDS is sufficient for alerting

2. **Selective rule enablement**
   - Don't enable ALL rules on internal interfaces
   - Focus on malware, exploit, scan rules
   - Disable noisy INFO/DNS rules

3. **Tune thresholds**
   - Internal networks have more "chatty" traffic
   - Increase thresholds for port scan rules to avoid false positives
   - Example: Threshold 50 connections/min instead of 10

4. **Exclude trusted internal traffic**
   - **Services → Suricata → {Interface} → Pass Lists**
   - Add trusted server-to-server traffic (e.g., NAS backups)

5. **Monitor Suricata CPU usage**
   ```bash
   ssh root@192.168.1.1 "top -P | grep suricata"
   ```
   Each Suricata instance should stay under 50% CPU. If higher, reduce rules or increase hardware.

---

## Alerting Strategy

### High-Priority Alerts (Immediate Response)

- Exploit attempts between VLANs
- C&C beaconing from internal hosts
- Brute force on critical services (RDP, SSH to servers)
- Worm propagation signatures

**Grafana Alert**:
```
Query: suricata.eve.event_type:alert AND suricata.eve.alert.severity:1 AND suricata.eve.src_ip:192.168.*
Threshold: Count > 5 in 5 minutes
Notification: Slack webhook + email
```

### Medium-Priority Alerts (Review Daily)

- Port scans within VLAN
- Policy violations (torrents, unauthorized protocols)
- Unusual internal DNS queries

**Grafana Alert**:
```
Query: suricata.eve.alert.signature:"*SCAN*" AND suricata.eve.src_ip:192.168.*
Threshold: Count > 20 in 1 hour
Notification: Email summary
```

### Low-Priority Alerts (Review Weekly)

- INFO-level alerts
- Generic policy violations
- Benign reconnaissance

**No alerting** — dashboard review only.

---

## Testing & Validation

### 1. Test Port Scan Detection

From a test workstation on LAN:
```bash
nmap -sS 192.168.X.0/24
```

**Expected**: Suricata alert `ET SCAN Potential Port Scan`

### 2. Test Exploit Detection

Use Metasploit on isolated test VLAN:
```bash
# From Kali VM on test VLAN
msfconsole
use exploit/windows/smb/ms17_010_eternalblue
set RHOST 192.168.X.Y
exploit
```

**Expected**: Suricata alert `ET EXPLOIT MS17-010`

### 3. Test C&C Beaconing

Simulate with curl:
```bash
# From test workstation
while true; do curl -s http://192.168.X.Y:8080/beacon; sleep 60; done
```

**Expected**: Repeated connections visible in dashboard, possibly C&C alert if beacon pattern matches signatures.

---

## Best Practices

1. **Segment your network** with VLANs (IoT, Corporate, Servers, Guest)
2. **Run IDS on all internal VLANs** (alerts only, no blocking)
3. **Tune rules per VLAN** (heavy on untrusted, light on trusted)
4. **Monitor East-West traffic** with dedicated Grafana dashboard
5. **Alert on anomalies** (high-priority only, avoid alert fatigue)
6. **Review alerts weekly** to tune false positives
7. **Test detection** with safe exploit frameworks on isolated VLANs

---

## Further Reading

- [Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md)
- [PfBlockerNG Optimization](PFBLOCKERNG_OPTIMIZATION.md)
- [Dashboard "No Data" Fix](DASHBOARD_NO_DATA_FIX.md)

---

**Next Steps**: 
1. Import `Suricata_Per_Interface.json` dashboard
2. Select interfaces to monitor (LAN VLANs)
3. Test lateral movement detection
4. Tune alert thresholds per VLAN
5. Review dashboard data for anomalies
