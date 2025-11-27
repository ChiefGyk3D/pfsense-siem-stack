# Suricata IDS/IPS Optimization Guide for pfSense

Complete guide to configuring and optimizing Suricata on pfSense for homelab and small business environments.

## Table of Contents
- [Initial Setup](#initial-setup)
- [Interface Configuration](#interface-configuration)
- [Rule Selection Strategy](#rule-selection-strategy)
- [Performance Tuning](#performance-tuning)
- [Log Management](#log-management)
- [IDS vs IPS Mode](#ids-vs-ips-mode)
- [Testing and Validation](#testing-and-validation)
- [Maintenance](#maintenance)

---

## Initial Setup

### Installation

1. **Install Suricata Package**
   - Navigate to **System > Package Manager > Available Packages**
   - Search for "Suricata"
   - Click **Install**

2. **Enable Suricata on Interfaces**
   - Go to **Services > Suricata > Interfaces**
   - Click **Add** to add an interface
   - Start with WAN interface first

### Hardware Requirements

**Minimum (Home Lab):**
- CPU: 2 cores @ 2.0 GHz
- RAM: 4 GB
- Network: 100 Mbps

**Recommended (Home Lab):**
- CPU: 4+ cores @ 2.5+ GHz
- RAM: 8 GB+
- Network: 1 Gbps with Intel NICs

**Optimal (Small Business):**
- CPU: 6+ cores @ 3.0+ GHz
- RAM: 16 GB+
- Network: 10 Gbps with Intel ix series NICs
- Hardware: Netgate appliance or server-grade hardware

---

## Interface Configuration

### Which Interfaces to Monitor?

**Home Lab / Family Network:**
```
✅ WAN - Monitor all inbound threats
⚠️ LAN - Optional, only if you want internal monitoring
❌ VLAN interfaces - Usually not needed (too much overhead)
```

**Small Business:**
```
✅ WAN - Essential
✅ DMZ - If you have one
✅ Guest Network - If publicly accessible
⚠️ LAN - For insider threat detection
```

**Our Homelab Example:**
- **ix0 (WAN)** - Primary internet connection monitoring
- **ix1 (WAN_CELL)** - Backup cellular WAN
- **lagg1.22 (High Security VLAN)** - Critical devices segment

### Interface Settings

**For each interface, configure:**

1. **Enable Interface:** ✅ Checked
2. **Interface:** Select your interface (e.g., ix0, em0)
3. **Description:** Descriptive name (e.g., "WAN IDS", "Guest Network IDS")

**IDS/IPS Mode:**
- **IDS Mode (Alert Only):** Recommended for new users
  - Detects threats but doesn't block
  - Learn your network first
  - Review alerts before enabling blocking
  
- **IPS Mode (Inline Blocking):** Advanced users only
  - Can block legitimate traffic if misconfigured
  - Requires careful tuning
  - See [IDS vs IPS Mode](#ids-vs-ips-mode) section

**Performance Settings:**
- **Inline Mode:** Use "Inline" (best performance with Intel NICs)
- **Legacy Mode:** Only if Inline causes issues
- **Promiscuous Mode:** Rarely needed on pfSense

---

## Rule Selection Strategy

### Understanding Rule Categories

**Rule Sources:**
1. **Emerging Threats (ET) - FREE**
   - Community-maintained
   - Updated daily
   - Good coverage for common threats
   
2. **Snort Rules - PAID (Subscription Required)**
   - Commercial-grade signatures
   - Faster updates for new threats
   - Lower false positive rate

### Recommended Ruleset for Homelab

Based on our testing with extensive rule deployment:

#### **Phase 1: Starting Out (First Month)**

**Emerging Threats (Enable ~42 categories):**

**Core Security (MUST ENABLE):**
```
✅ emerging-malware.rules           # Malware detection
✅ emerging-botcc.rules             # Botnet C2
✅ emerging-exploit.rules           # Exploit attempts
✅ emerging-exploit_kit.rules       # Exploit frameworks
✅ emerging-shellcode.rules         # Shellcode patterns
✅ emerging-worm.rules              # Worm propagation
✅ emerging-compromised.rules       # Known bad hosts
✅ emerging-attack_response.rules   # Successful attacks
✅ emerging-current_events.rules    # Zero-days
✅ emerging-phishing.rules          # Phishing attempts
```

**Web Security:**
```
✅ emerging-web_server.rules        # Web server attacks
✅ emerging-web_client.rules        # Browser attacks
✅ emerging-web_specific_apps.rules # Vulnerable apps
✅ emerging-activex.rules           # ActiveX exploits
```

**Network Protocols:**
```
✅ emerging-dns.rules               # DNS attacks/tunneling
✅ emerging-smtp.rules              # Email attacks
✅ emerging-sql.rules               # SQL injection
✅ emerging-netbios.rules           # SMB/NetBIOS exploits
✅ emerging-icmp.rules              # ICMP attacks
✅ emerging-ftp.rules               # FTP attacks
✅ emerging-telnet.rules            # Telnet (IoT devices)
```

**Additional Threats:**
```
✅ emerging-dos.rules               # DoS attacks
✅ emerging-scan.rules              # Port scanning
✅ emerging-hunting.rules           # Threat hunting
✅ emerging-mobile_malware.rules    # Mobile threats
✅ emerging-user_agents.rules       # Malicious UAs
✅ emerging-adware_pup.rules        # Adware/PUPs
✅ emerging-chat.rules              # Chat-based threats
✅ emerging-p2p.rules               # P2P threats
✅ emerging-games.rules             # Game hacking tools
```

**Reputation Lists:**
```
✅ emerging-ciarmy.rules            # IP reputation
✅ emerging-botcc.portgrouped.rules # Botnet C2 (optimized)
```

**DISABLE These (Too Noisy or Not Applicable):**
```
❌ emerging-coinminer.rules         # If you mine crypto
❌ emerging-drop.rules              # Redundant with pfBlocker
❌ emerging-dshield.rules           # Redundant with pfBlocker
❌ emerging-info.rules              # Too noisy
❌ emerging-ja3.rules               # Complex, needs tuning
❌ emerging-retired.rules           # Obsolete
❌ emerging-dyn_dns.rules           # If you use DynDNS
❌ emerging-remote_access.rules     # If you use TeamViewer/AnyDesk
❌ emerging-tor.rules               # If you use Tor
❌ emerging-file_sharing.rules      # Optional, try enabling
```

#### **Phase 2: Snort Rules (If You Have Subscription)**

**Essential (21 NEW rules to add):**
```
✅ content-replace.rules            # MITM detection
✅ file-executable.rules            # Malicious executables
✅ file-java.rules                  # Java exploits
✅ file-office.rules                # Office malware
✅ file-pdf.rules                   # PDF exploits
✅ indicator-compromise.rules       # IOC detection
✅ indicator-shellcode.rules        # Shellcode patterns
✅ server-webapp.rules              # Web app attacks
✅ web-attacks.rules                # XSS, CSRF
✅ web-php.rules                    # PHP exploits
✅ web-client.rules                 # Browser attacks
✅ sql.rules                        # SQL injection
✅ exploit-kit.rules                # Exploit frameworks
✅ shellcode.rules                  # Generic shellcode
✅ dns.rules                        # DNS attacks
✅ smtp.rules                       # Email attacks
✅ mysql.rules                      # MySQL exploits
✅ specific-threats.rules           # APT detection
✅ netbios.rules                    # NetBIOS/SMB
✅ bad-traffic.rules                # Malformed packets
✅ other-ids.rules                  # IDS evasion
```

**Plus Your Existing 25 Snort Rules:**
```
✅ browser-chrome/firefox/ie/other/plugins/webkit
✅ malware-backdoor/cnc/other/tools
✅ botnet-cnc, blacklist, ddos
✅ os-linux/mobile/windows/other
✅ pua-adware/other/toolbars
✅ dos, exploit, phishing-spam, spyware-put, virus
```

**Total Recommended: 46 Snort rules**

---

## Performance Tuning

### CPU Allocation

**Suricata CPU Usage by Ruleset:**
- ~150 ET rules: 15-30% CPU per interface
- ~150 ET + 46 Snort rules: 25-40% CPU per interface
- 3 interfaces: 75-120% CPU total (1-2 cores fully loaded)

**Optimization Tips:**
1. **Disable unused rulesets** - Every rule costs CPU
2. **Use Inline mode** - Better performance than Legacy
3. **Enable Netmap** - Hardware offloading for Intel NICs
4. **Limit interfaces** - Only monitor critical interfaces

### Memory Management

**RAM Usage:**
- Base Suricata: 200-400 MB per instance
- With full ruleset: 500-800 MB per instance
- 3 instances: ~1.5-2.5 GB total

**Settings (per interface):**
- Navigate to **Services > Suricata > Interface Settings > [Interface] > Advanced**
- **Stream Memory Limit:** 64 MB (default)
- **Reassembly Memory Limit:** 128 MB (default)
- Increase only if you see "memcap" errors in logs

### Network Performance

**Inline Mode Configuration:**
1. Go to **Services > Suricata > Interface Settings > [Interface]**
2. **IPS Mode:** Select "Inline"
3. **Enable Netmap:** ✅ (auto-enables with Intel NICs)
4. Save

**QUIC Protocol Handling:**
If you see "QUIC crypto fragments too long" warnings:
1. Go to **Advanced Settings** tab
2. Find **QUIC Configuration**
3. Set **QUIC Crypto Max Length:** 65536 (64 KB)
4. Save and restart Suricata

---

## Log Management

### Automatic Log Management

**ALWAYS ENABLE** automatic log management:

1. Go to **Services > Suricata > Global Settings**
2. ✅ Check "Enable automatic unattended management of Suricata logs"
3. Configure retention settings

### Recommended Log Settings

Based on our deployment with 3 interfaces + OpenSearch forwarding:

```
Log Type          | Max Size | Retention | Reason
------------------|----------|-----------|------------------
eve-json          | 10 MB    | 1 DAY     | Forwarded to OpenSearch
alert             | 1 MB     | 7 DAYS    | Alert summary
block             | 1 MB     | 7 DAYS    | Blocked IPs
http              | 2 MB     | 7 DAYS    | HTTP sessions
tls               | 1 MB     | 7 DAYS    | TLS handshakes
sid_changes       | 250 KB   | 14 DAYS   | Rule changes (useful)
stats             | 1 MB     | 7 DAYS    | Performance stats
Captured Files    | 500 MB   | 1 DAY     | Large, rarely needed
TLS Certs         | -        | 7 DAYS    | Small, useful
PCAP Files        | -        | 1 DAY     | Huge, troubleshooting only
```

**Why these settings?**
- **eve-json (1 day):** Forwarded to OpenSearch for long-term storage
- **Larger sizes:** 3 interfaces generate 3x the logs
- **Shorter retention:** Saves disk space on /var partition
- **PCAPs (1 day):** Only for active troubleshooting

### Log Forwarding

For long-term analysis and visualization:
- Forward logs to OpenSearch/Logstash (this project!)
- Keeps local logs as 1-7 day buffer
- Central SIEM for historical analysis
- See [SURICATA_FORWARDER_MONITORING.md](./SURICATA_FORWARDER_MONITORING.md)

---

## IDS vs IPS Mode

### IDS Mode (Alert Only) - RECOMMENDED FOR NEW USERS

**Configuration:**
- Enable Inline mode for performance
- Keep all rules as **ALERT** (default)
- Review alerts in Grafana/OpenSearch
- No automatic blocking

**Pros:**
- ✅ Safe - won't break legitimate traffic
- ✅ Learn your network baseline
- ✅ Review before blocking
- ✅ Good for family networks

**Cons:**
- ❌ No automatic blocking
- ❌ Must manually block threats via pfBlocker

**Best for:**
- Home labs
- Family networks
- Learning phase (first 1-3 months)
- Networks with diverse applications

---

### IPS Mode (Inline Blocking) - ADVANCED USERS

**Configuration:**
1. Enable Inline mode
2. Convert specific rules from ALERT to DROP
3. Use SID Management (dropsid.conf)
4. Test thoroughly

**How to Enable Blocking:**

**Method 1: Snort Rules (Easy)**
- Go to **Categories** tab
- Enable **IPS Policy Mode**
- Select policy: Connectivity, Balanced, Security, or Max Detect
- Snort rules marked DROP in policy will auto-block

**Method 2: Manual (Emerging Threats)**
- Go to **SID MGMT** tab
- Create **dropsid.conf** file
- List SIDs to convert to DROP:

```bash
# Block known malware C2
re:emerging-malware.*
re:emerging-botcc.*

# Block exploit kits
re:emerging-exploit_kit.*

# Block compromised hosts
re:emerging-compromised.*
```

**Testing IPS Mode:**
1. Enable on one interface first (Guest VLAN recommended)
2. Monitor for 1 week
3. Check for broken services
4. Whitelist false positives
5. Expand to other interfaces

**Pros:**
- ✅ Real-time blocking
- ✅ True IPS protection
- ✅ Automated defense

**Cons:**
- ❌ Can break legitimate traffic
- ❌ Requires careful tuning
- ❌ False positives cause outages
- ❌ May block: VPNs, remote access, cloud services, gaming

**Best for:**
- Experienced administrators
- After 1-3 months in IDS mode
- Networks with well-documented applications
- When you have time for tuning

---

## Testing and Validation

### Verify Suricata is Running

```bash
ssh root@pfsense
ps aux | grep suricata | grep -v grep
```

Should show running processes for each enabled interface.

### Check Logs are Being Generated

```bash
ls -lh /var/log/suricata/suricata_*/eve.json
```

Files should be growing in size.

### Test Alert Generation

**Safe test methods:**
1. Visit test site: https://testmyids.com
2. Or trigger test rule:
   ```bash
   curl http://testmyids.com/
   ```
3. Check for alerts in Grafana or:
   ```bash
   tail -f /var/log/suricata/suricata_*/eve.json | grep alert
   ```

### Monitor Performance

1. **CPU Usage:**
   ```bash
   top | grep suricata
   ```

2. **Memory Usage:**
   ```bash
   ps aux | grep suricata | awk '{print $6,$11}'
   ```

3. **Check for Drops:**
   - Go to **Services > Suricata > Interface Settings**
   - Check **Packets Dropped** column
   - Should be 0% or very low (<1%)

### Review Stats

```bash
tail -100 /var/log/suricata/suricata_*/stats.log
```

Look for:
- `capture.kernel_drops: 0` (should be zero or very low)
- `decoder.avg_pkt_size` (typical values: 300-1500 bytes)
- `flow.memuse` (should stay below Stream Memory Limit)

---

## Maintenance

### Rule Updates

**Automatic Updates (Recommended):**
1. Go to **Services > Suricata > Global Settings**
2. **Update Interval:** 12 hours (default)
3. ✅ Check "Remove Blocked Hosts After Deinstall"
4. ✅ Check "Enable Live Rule Swaps"

**Manual Updates:**
1. Go to **Services > Suricata > Updates**
2. Click **Update Rules**
3. Wait for completion
4. Rules automatically reload

### Weekly Maintenance

**Every Week:**
1. Review alerts in Grafana dashboard
2. Check for new false positives
3. Verify forwarder is running (if using OpenSearch)
4. Check disk space: `/var/log/suricata`

### Monthly Maintenance

**Every Month:**
1. Review CPU/memory usage trends
2. Update pfSense and Suricata package
3. Review and tune rules (disable noisy ones)
4. Check for new Suricata features
5. Verify automatic log rotation is working

### Troubleshooting Common Issues

**High CPU Usage:**
- Reduce number of enabled rules
- Disable interfaces with low threat value
- Check for packet drops (may need more resources)

**Logs Not Forwarding:**
- Check forwarder is running: `ps aux | grep forward-suricata`
- See [SURICATA_FORWARDER_MONITORING.md](./SURICATA_FORWARDER_MONITORING.md)
- Verify OpenSearch is reachable

**False Positives:**
- Review alert in Grafana
- Determine if traffic is legitimate
- Disable specific SID or create suppression rule
- Document in pass list

**Packet Drops:**
- Increase Stream/Reassembly memory limits
- Reduce number of interfaces
- Disable unnecessary rules
- Upgrade hardware

---

## Performance Benchmarks

### Our Homelab Example

**Hardware:**
- Netgate 6100 (Intel Atom C3558 @ 2.2 GHz, 8 cores)
- 16 GB RAM
- Intel ix (82599) 10 Gbps NICs

**Configuration:**
- 3 Suricata instances (ix0, ix1, lagg1.22)
- ~42 ET categories (~150-170 rule files)
- 46 Snort rules (with subscription)
- Inline mode with Netmap
- Log forwarding to OpenSearch

**Performance:**
- CPU: 25-40% per interface (75-120% total on 8-core system)
- RAM: ~2.5 GB total (all instances)
- Throughput: 1 Gbps sustained with <0.1% packet drops
- Alerts: 300-600 per day (WAN interface)
- False positives: <5 per week (after 1 month tuning)

**Log Volume:**
- eve.json: ~50-100 MB/day per interface
- Total logs: ~150-300 MB/day (3 interfaces)
- OpenSearch storage: ~1-2 GB/week (with 7-day retention)

---

## Quick Reference

### Recommended Starting Configuration

**New Users (Phase 1 - First Month):**
- Mode: IDS (Alert Only)
- Interfaces: WAN only
- Rules: ~42 ET categories (core security)
- Inline: Enabled
- Log retention: 7 days local
- CPU budget: 25-30%

**Experienced Users (Phase 2 - After Tuning):**
- Mode: IDS or IPS (selective blocking)
- Interfaces: WAN + critical segments
- Rules: ~42 ET + 46 Snort (if subscribed)
- Inline: Enabled with Netmap
- Log retention: 1-3 days local + forwarding to SIEM
- CPU budget: 40-50%

**Production (Small Business):**
- Mode: IPS (full blocking)
- Interfaces: All perimeter interfaces
- Rules: Full ET + Snort subscription + custom
- Inline: Enabled with Netmap
- Log retention: 1 day local + long-term SIEM
- CPU budget: 50-70%
- Redundancy: HA pair

---

## Additional Resources

- **[Forwarder Monitoring](./SURICATA_FORWARDER_MONITORING.md)** - Keep logs flowing
- **[Troubleshooting Guide](./TROUBLESHOOTING.md)** - Common issues
- **[GeoIP Setup](./GEOIP_SETUP.md)** - IP geolocation for alerts
- **[Grafana Dashboard](../README.md)** - Visualization
- **Suricata Documentation:** https://suricata.readthedocs.io/
- **pfSense Suricata Package:** https://docs.netgate.com/pfsense/en/latest/packages/suricata/

---

## Changelog

- **2025-11-26**: Initial comprehensive optimization guide
- Based on real-world deployment with 3 interfaces, 42 ET categories, 46 Snort rules
- Tested on Netgate 6100 with OpenSearch SIEM integration
