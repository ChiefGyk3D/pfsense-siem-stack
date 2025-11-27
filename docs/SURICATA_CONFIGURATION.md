# Suricata Configuration Guide

> **Last Updated**: November 27, 2025  
> **Status**: ✅ Production-tested configuration

Comprehensive guide to configuring Suricata on pfSense for optimal performance and coverage.

---

## 📋 Table of Contents

- [Why Suricata Over Snort](#-why-suricata-over-snort)
- [Rule Sources](#-rule-sources)
- [Critical Configuration](#-critical-configuration-required)
- [Interface Configuration](#️-interface-configuration)
- [Performance Tuning](#-performance-tuning)
- [Common Issues](#-common-issues)

---

## 🔥 Why Suricata Over Snort?

### Multithreading Performance

**Suricata** was designed from the ground up for modern multicore processors:

✅ **True Multithreading**: Efficiently distributes packet processing across all CPU cores  
✅ **Higher Throughput**: 2-5× better performance on multicore systems  
✅ **Modern Architecture**: Built for parallel processing, not retrofitted  
✅ **Active Development**: Frequent releases with performance improvements  
✅ **Better Resource Utilization**: Uses available cores effectively

**Snort** (version 2.x) uses a single-threaded architecture:
- Only uses one CPU core per instance
- Requires running multiple instances for parallelism (complex)
- Lower throughput on modern hardware
- Snort 3 improves this, but Suricata remains ahead

### Real-World Performance

**Production deployment** (Intel Atom C3758, 8 cores):
- 15 Suricata instances (2 WAN + 13 VLAN)
- Average CPU: 25-35% (well-distributed across cores)
- Peak CPU: 100% during rule reloads (3-5 minutes, expected)
- Throughput: Handles gigabit bursts without packet loss

Same hardware with Snort would require complex multi-instance setup and likely struggle with throughput.

---

## 📚 Rule Sources

### Recommended Configuration

**Enable these rule sources** in pfSense:

1. **Emerging Threats Open** (Free, Essential)
   - Community-maintained ruleset
   - Broad threat coverage
   - Updated daily
   - ✅ **Always enable this**

2. **Snort Registered Rules** (Free with Account)
   - Requires registration at [snort.org](https://www.snort.org/users/sign_up)
   - Get your "Oinkcode" from account settings
   - Broader coverage than ET Open
   - ✅ **Recommended for all users**

3. **Snort Subscriber Rules** ($30/year, Highly Recommended)
   - Early access to new rules (24-48 hours ahead)
   - More comprehensive coverage
   - Professional-grade threat intelligence
   - ✅ **Highly recommended for production**
   - Register at [snort.org/products](https://www.snort.org/products)

4. **Feodo Tracker Botnet C2 IP** (Free, abuse.ch)
   - Known botnet command & control IPs
   - Updated frequently (hourly)
   - Low false positive rate
   - ✅ **Enable for botnet detection**

5. **Abuse.ch SSL Blacklist** (Free, abuse.ch)
   - Malicious SSL/TLS certificates
   - Known malware C2 infrastructure
   - Updated frequently
   - ✅ **Enable for SSL/TLS threat detection**

### Configuration Steps

**Navigate to**: Services → Suricata → Global Settings → Rule Updates

1. **Enable Rule Categories**:
   ```
   ☑ Emerging Threats Open
   ☑ Snort (requires Oinkcode)
   ☑ Feodo Tracker
   ☑ Abuse.ch SSL Blacklist
   ```

2. **Add Snort Oinkcode**:
   - Get code from [snort.org/users/[youraccount]](https://www.snort.org/)
   - Paste in "Oinkmaster Oinkcode" field
   - Save

3. **Configure Update Schedule**:
   - **Update Interval**: Daily (recommended)
   - **Update Start Time**: 03:00 (low-traffic hours)
   - **Remove Blocked Hosts Interval**: 1 hour
   - ☑ **Live Rule Swap on Update** (prevents drops)

4. **Update Rules Now**:
   - Click **Update** button
   - Wait 5-10 minutes for first download
   - Monitor `/var/log/suricata/suricata_[interface]/suricata.log` for errors

---

## 🔧 Critical Configuration (REQUIRED)

### Stream Memory Increase

**Problem**: Default stream memory (256MB) causes crashes on multicore systems with busy networks.

**Symptoms**:
```
[ERROR] Failed to allocate stream memory
[ERROR] Out of memory
Suricata failed to start
```

**Solution**: Increase stream memory to **1GB per interface**.

#### Configuration Steps

**For EACH Suricata interface**:

1. Navigate to: **Services** → **Suricata** → **[Interface Name]**
2. Click **Stream** tab
3. Find **Stream Memcap** setting
4. Change value:
   - **From**: `268435456` (256MB, default)
   - **To**: `1073741824` (1GB, recommended)
5. Click **Save**
6. **Repeat for every interface**
7. Restart Suricata: **Services** → **Suricata** → **Interfaces** → Click restart icon

#### RAM Implications

- **Per interface**: 1GB stream memory
- **Example**: 15 interfaces × 1GB = 15GB total
- **Additional memory**: Base Suricata process (~500MB-1GB per instance)
- **Total RAM needed**: 
  - 8GB minimum (1-2 interfaces)
  - 16GB recommended (10-15 interfaces)

**Note**: This is in ADDITION to pfSense base requirements. Plan accordingly.

---

## ⚙️ Interface Configuration

### Interface Types

**Inline IPS** (WAN Interfaces):
- **Mode**: Inline IPS
- **Action**: Block + Alert
- **Purpose**: Active threat prevention
- **Performance**: Higher CPU usage
- **Risk**: False positives can break legitimate traffic
- **Use on**: WAN interfaces only (ix0, ix1, em0, etc.)

**IDS Only** (Internal Interfaces):
- **Mode**: IDS
- **Action**: Alert only
- **Purpose**: Monitoring and detection
- **Performance**: Lower CPU usage
- **Risk**: No traffic disruption
- **Use on**: LAN, VLAN interfaces

### Recommended Setup

| Interface Type | Mode | Purpose |
|---------------|------|---------|
| WAN (Primary) | Inline IPS | Active blocking |
| WAN (Secondary) | Inline IPS | Active blocking |
| LAN | IDS | Monitoring only |
| VLAN (Trusted) | IDS | Light monitoring |
| VLAN (IoT) | IDS | Heavy monitoring |
| VLAN (Guest) | IDS | Heavy monitoring |

**Why IDS on internal?**
- Lower false positive risk (won't break internal apps)
- Still detects lateral movement, scanning, malware
- Can upgrade to IPS after tuning rules
- Better for troubleshooting (alerts don't block traffic)

---

## 🎯 Performance Tuning

### Per-Interface Settings

**Navigate to**: Services → Suricata → [Interface] → Settings

#### WAN Interfaces (Inline IPS)

```
Stream Settings:
  Stream Memcap: 1073741824 (1GB)
  Stream Reassembly Depth: 1048576 (1MB)
  
App Layer:
  HTTP Request/Response Body Limit: 100000 bytes (100KB)
  
Performance:
  Detect Engine Profile: high
  Max Pending Packets: 1024 (adjust based on CPU)
```

#### VLAN Interfaces (IDS)

```
Stream Settings:
  Stream Memcap: 1073741824 (1GB)
  Stream Reassembly Depth: 524288 (512KB, lighter)
  
App Layer:
  HTTP Request/Response Body Limit: 50000 bytes (50KB)
  
Performance:
  Detect Engine Profile: medium
  Max Pending Packets: 512
```

### CPU Optimization

**Adjust based on CPU cores**:

1. **Quad-core CPU**: 
   - Run 2-4 Suricata instances max
   - Use "medium" or "low" detect profile on VLANs
   
2. **6-8 core CPU**:
   - Run 5-10 instances comfortably
   - Use "high" on WAN, "medium" on VLANs
   
3. **8+ core CPU**:
   - Run 15+ instances
   - Use "high" on all interfaces if needed

**Monitor**: System → Activity → Top Processes
- Watch during rule reloads (expect 100% CPU for 3-5 min)
- If sustained >80% CPU, reduce detect profile or disable interfaces

---

## 🌍 GeoIP Configuration

### MaxMind GeoLite2 Setup

**Required for GeoIP features** in alerts and dashboards.

#### 1. Create Free MaxMind Account

1. Go to: [maxmind.com/en/geolite2/signup](https://www.maxmind.com/en/geolite2/signup)
2. Register (free)
3. Verify email

#### 2. Generate License Key

1. Log in to MaxMind account
2. Navigate to: **Account** → **Manage License Keys**
3. Click **Generate New License Key**
4. Name it (e.g., "pfSense")
5. Select: **No** for "Will this key be used for GeoIP Update?"
6. Copy the license key (shown once!)

#### 3. Configure in pfSense

1. Navigate to: **System** → **Updates**
2. Click **MaxMind GeoIP** tab
3. Paste license key in **License Key** field
4. ☑ **Enable automatic updates**
5. Click **Save**
6. Click **Update Now**

#### 4. Verify Installation

```bash
ssh root@pfsense.local
ls -lh /usr/local/share/GeoIP/
```

Expected files:
```
GeoLite2-Country.mmdb    (~6MB)
GeoLite2-City.mmdb       (~70MB, optional but recommended)
GeoLite2-ASN.mmdb        (~7MB)
```

#### 5. Configure Suricata

1. Navigate to: **Services** → **Suricata** → **Global Settings**
2. **GeoIP Settings**:
   - GeoIP DB: `/usr/local/share/GeoIP/GeoLite2-Country.mmdb`
   - City DB: `/usr/local/share/GeoIP/GeoLite2-City.mmdb` (optional)
3. Click **Save**
4. Restart Suricata instances

### GeoIP in Alerts

Once configured, Suricata alerts include:
- `geoip.country_code` (e.g., "US", "CN", "RU")
- `geoip.country_name` (e.g., "United States")
- `geoip.city_name` (if using City DB)
- `geoip.latitude` / `geoip.longitude` (for mapping)

**Note**: The forwarder script enriches logs further with additional GeoIP data before sending to Logstash.

---

## 🚨 Common Issues

### Issue 1: Suricata Won't Start After Install

**Symptom**: Interface shows "stopped" and won't start.

**Cause**: Stream memory too low for multicore CPU.

**Fix**:
1. Increase stream memory to 1GB (see [Critical Configuration](#-critical-configuration-required))
2. Check pfSense has enough total RAM
3. Restart Suricata

---

### Issue 2: High CPU During Rule Reloads

**Symptom**: CPU spikes to 100% for 3-5 minutes when updating rules.

**Cause**: This is **NORMAL** behavior. Suricata reloads all rules and signatures.

**Mitigation**:
- Schedule updates during low-traffic hours (3-5 AM)
- Ensure adequate cooling (check for thermal throttling)
- Use "Live Rule Swap" to minimize disruption
- Consider faster CPU if this is a persistent issue

**NOT a bug** - this is expected behavior.

---

### Issue 3: Packet Drops in Inline IPS Mode

**Symptom**: Packet loss, high latency during traffic spikes.

**Cause**: CPU can't keep up with inline inspection.

**Fix**:
1. Reduce **Max Pending Packets** (try 512 or 256)
2. Lower **Detect Engine Profile** to "medium" or "low"
3. Disable unnecessary rules (see SID management)
4. Upgrade to faster CPU
5. Consider switching to IDS mode (alerts only, no blocking)

---

### Issue 4: False Positives Breaking Traffic

**Symptom**: Legitimate applications fail, users complain of connectivity issues.

**Cause**: Aggressive rules blocking normal traffic.

**Fix**:
1. Check Suricata logs: **Services** → **Suricata** → **Alerts**
2. Identify problematic SID
3. Add to disablesid.conf or suppress.conf
   - See [SID Management Guide](../config/sid/README.md)
   - See [APPLYING_CHANGES.md](../config/sid/APPLYING_CHANGES.md)
4. Update rules and restart

**Prevention**: Start with IDS mode, tune rules, then switch to IPS.

---

### Issue 5: No Alerts in Dashboard

**Symptom**: Grafana shows "No Data".

**Cause**: Forwarder not running, Logstash misconfigured, or OpenSearch issue.

**Fix**:
1. Check forwarder: `ps aux | grep forward-suricata-eve.py`
2. Check logs: `tail -f /var/log/suricata_forwarder_debug.log`
3. Test OpenSearch: `curl http://opensearch:9200/suricata-*/_count`
4. See: [Dashboard Troubleshooting Guide](DASHBOARD_NO_DATA_FIX.md)

---

### Issue 6: Rule Updates Fail

**Symptom**: "Failed to download rules" error.

**Cause**: Invalid Oinkcode, network issue, or rule source down.

**Fix**:
1. Verify Oinkcode at [snort.org](https://www.snort.org/)
2. Check pfSense can reach internet: `ping -c 3 rules.emergingthreats.net`
3. Check DNS resolution: `host rules.emergingthreats.net`
4. Try manual update: **Services** → **Suricata** → **Updates** → **Update**
5. Check logs: `/var/log/suricata/suricata_49221.log` (different number for your system)

---

## 📊 Monitoring Performance

### Check CPU Usage

**During normal operation**:
```bash
ssh root@pfsense.local
top -H
```

Look for `Suricata` processes. Should be <50% average.

### Check Memory Usage

```bash
ssh root@pfsense.local
vmstat -h
```

Look for available RAM. Should have 2-4GB free minimum.

### Check Packet Drops

**Navigate to**: Services → Suricata → [Interface] → Interface Stats

Look for:
- **Capture → Kernel Drops**: Should be 0 or very low
- **Flow → Memcap**: Should not be increasing rapidly
- **TCP → Reassembly Errors**: Should be minimal

**If high drops**: Reduce load (lower detect profile, disable rules, upgrade hardware).

---

## 🔗 Related Documentation

- **[Hardware Requirements](HARDWARE_REQUIREMENTS.md)** - CPU, RAM, and storage sizing
- **[Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md)** - In-depth tuning
- **[SID Management](../config/sid/README.md)** - Rule tuning and false positive reduction
- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues and solutions

---

## ✅ Configuration Checklist

Before considering Suricata "production ready":

- [ ] **Stream memory increased to 1GB** per interface
- [ ] **Rule sources configured** (ET Open, Snort, Feodo, Abuse.ch)
- [ ] **GeoIP database installed** and updating
- [ ] **Update schedule configured** (daily, off-peak hours)
- [ ] **Interface modes chosen** (IPS on WAN, IDS on LAN/VLAN)
- [ ] **Performance tested** (CPU <80% average, no packet drops)
- [ ] **Forwarder deployed** and sending data
- [ ] **Dashboard importing data** successfully
- [ ] **False positives tuned** (SID management configured)
- [ ] **Monitoring in place** (watchdogs, alerts)

---

**Pro Tip**: Start with IDS mode on all interfaces, run for 1-2 weeks, tune out false positives, THEN enable IPS mode on WAN. This prevents breaking production traffic during initial tuning.
