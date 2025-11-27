# Hardware Requirements & Recommendations

> **Last Updated**: November 27, 2025  
> **Status**: ✅ Production-tested specifications

This document provides detailed hardware requirements and recommendations based on real-world deployment experience.

---

## 🚨 Critical Warnings

### DO NOT Use SD Cards for Logging

**YOU WILL DESTROY SD CARDS IN WEEKS**

Logging and SIEM workloads involve constant, high-frequency writes:
- Suricata eve.json: 10-1000+ writes/second depending on traffic
- OpenSearch indices: Continuous indexing operations
- Logstash buffers: Frequent disk writes
- InfluxDB points: Time-series data writes

**SD cards are NOT designed for this workload.** They have limited write cycles and will fail catastrophically, resulting in:
- ❌ Data loss (no warning, sudden death)
- ❌ Constant system rebuilds
- ❌ Wasted time and frustration
- ❌ Incomplete security visibility during failures

**Minimum acceptable storage**: SATA SSD with USB 3.0 adapter  
**Recommended storage**: NVMe SSD in proper enclosure or native M.2 slot

---

## 🖥️ SIEM Server Requirements

### Minimum Specifications (Small Home Lab)

**Use Case**: Single pfSense firewall, 1-3 Suricata instances, light traffic (<100Mbps sustained), 7-day retention

| Component | Minimum Spec | Notes |
|-----------|-------------|-------|
| **CPU** | Dual-core Intel/AMD with SMT | Logstash requires decent single-thread performance |
| **RAM** | 16GB | Tight but workable with tuning |
| **Storage** | 100GB SSD | Plan for 10-15GB/day with light traffic |
| **Network** | 1 Gigabit NIC | Must handle log ingestion spikes |
| **OS** | Ubuntu Server 22.04+ | Tested on 24.04 LTS |

**Component Breakdown (Minimum)**:
- OpenSearch: 6GB heap (leaves little room for growth)
- Logstash: 2GB heap (may struggle with traffic spikes)
- InfluxDB: 2GB (optional but recommended)
- Grafana: 1GB
- System: 2-3GB

⚠️ **Warning**: This is the absolute minimum. Expect performance issues during traffic spikes or when running complex queries. Not suitable for production environments.

---

### Recommended Specifications (Production Home Lab)

**Use Case**: Single pfSense firewall, 5-15 Suricata instances, moderate traffic (<500Mbps sustained), 30-day retention

| Component | Recommended Spec | Notes |
|-----------|-----------------|-------|
| **CPU** | Quad-core Intel/AMD (i5/Ryzen 5+) | Better Logstash performance, room for growth |
| **RAM** | **32GB** | Comfortable headroom for all components |
| **Storage** | 500GB-1TB NVMe SSD | Fast writes, 30+ day retention |
| **Network** | 1 Gigabit NIC | 2.5GbE or better for high-traffic environments |
| **OS** | Ubuntu Server 24.04 LTS | Current stable, long-term support |

**Component Breakdown (Recommended)**:
- OpenSearch: 12-16GB heap (excellent performance)
- Logstash: 4GB heap (handles spikes well)
- InfluxDB: 4GB (smooth time-series operations)
- Grafana: 2GB (fast dashboard rendering)
- System: 4-6GB (caching, buffers)

✅ **This is the sweet spot** for home lab and small business deployments. Provides excellent performance with room to grow.

---

### Production Reference Configuration

**Real-world deployment** running this exact stack:

| Component | Specification |
|-----------|--------------|
| **System** | Purism Librem Mini |
| **CPU** | Intel Core i7-10510U (4C/8T, 1.8-4.9GHz) |
| **RAM** | 32GB DDR4 |
| **Storage** | 2TB NVMe SSD |
| **OS** | Ubuntu Server 24.04 LTS |
| **Workload** | 15 Suricata instances (2 WAN + 13 VLAN) |
| **Traffic** | Home lab, bursty traffic patterns |
| **Retention** | 30+ days OpenSearch, 90+ days InfluxDB |

**Performance Characteristics**:
- ✅ Significant headroom on all resources
- ✅ Handles traffic spikes without issues
- ✅ Complex dashboard queries remain responsive
- ✅ Room for additional services (ntopng, etc.)

**Cost**: ~$800-1200 depending on configuration (2024/2025 pricing)

---

## 🔥 pfSense Firewall Requirements

### PfBlockerNG Only (No IDS/IPS)

**Use Case**: Blocklist filtering, DNSBL, GeoIP blocking

| Component | Specification | Notes |
|-----------|--------------|-------|
| **CPU** | Dual-core | Light processing load |
| **RAM** | **4-8GB** | Even with many blocklists |
| **Storage** | 16GB+ SSD | Blocklist storage |
| **Network** | Depends on WAN speed | 1Gbps+ NICs for gigabit connections |

✅ **PfBlockerNG is very efficient** - even with hundreds of thousands of blocklist entries, RAM usage remains manageable.

---

### Suricata IDS/IPS Requirements

**Use Case**: Intrusion detection/prevention on multiple interfaces

#### Minimum (1-2 Interfaces, IDS Mode)

| Component | Specification | Notes |
|-----------|--------------|-------|
| **CPU** | Quad-core | IDS inspection is CPU-intensive |
| **RAM** | 8GB | Minimum for 1-2 instances |
| **Stream Memory** | 1GB per interface | **Critical - see below** |

#### Recommended (Multi-Interface, IDS + IPS)

| Component | Specification | Notes |
|-----------|--------------|-------|
| **CPU** | 6-8 cores minimum | More cores = more throughput |
| **RAM** | **12-16GB** | Comfortable for 10-15 instances |
| **Stream Memory** | 1GB per interface | **Must increase from default** |
| **Network** | Intel NICs preferred | Better driver support, offloading |

#### Production Reference Configuration

**Real-world deployment**:

| Component | Specification |
|-----------|--------------|
| **System** | Custom pfSense appliance |
| **CPU** | Intel Atom C3758 (8C, 2.2GHz) |
| **RAM** | 16GB |
| **Storage** | 128GB SSD |
| **NICs** | Intel i350 (4-port) + onboard |
| **Suricata Instances** | 15 total (2 WAN inline IPS, 13 VLAN IDS) |

**Performance Characteristics**:
- **Average CPU Load**: 25-35% during normal operations
- **Peak CPU Load**: **100% for 3-5 minutes during rule reloads**
  - This is **normal and expected**
  - Plan maintenance windows accordingly
  - Monitor for thermal throttling on underpowered systems
- **RAM Usage**: 12-14GB with 15 instances
- **Stream Memory**: 1GB per interface (critical for stability)

⚠️ **Important**: The CPU spike during rule reloads can cause temporary packet drops in inline IPS mode. For critical environments, consider:
- Using IDS mode instead of inline IPS (alerts only, no blocking)
- Scheduling rule updates during maintenance windows
- Using faster CPUs (more headroom during reloads)

---

## ⚙️ Critical Suricata Configuration

### Stream Memory Increase (REQUIRED for Multicore)

**Problem**: Default stream memory (256MB) causes Suricata to crash on startup with multicore CPUs and busy networks.

**Symptoms**:
```
Suricata failed to start
Could not allocate stream memory
Out of memory error
```

**Solution**: Increase stream memory to **1GB (1073741824 bytes)** per interface.

**Configuration Steps**:

1. Navigate to: **Services** → **Suricata** → **[Interface]** → **Stream** tab
2. Find: **Stream Memcap**
3. Change from: `268435456` (256MB)
4. Change to: `1073741824` (1GB)
5. Click **Save**
6. Repeat for **each Suricata interface**
7. Restart Suricata: **Services** → **Suricata** → **Restart**

**RAM Impact**: With 15 interfaces × 1GB = 15GB stream memory allocation (in addition to other Suricata memory usage). This is why 16GB RAM is recommended for multi-interface deployments.

---

## 🌐 Why Suricata Over Snort?

**TL;DR**: Better multithreaded performance for modern multicore systems.

### Suricata Advantages

✅ **True Multithreading**: Efficiently uses all CPU cores  
✅ **Better Performance**: Higher throughput on multicore systems  
✅ **Modern Architecture**: Built from ground up for parallel processing  
✅ **Snort Rule Compatibility**: Can use Snort rules (see below)  
✅ **Active Development**: Frequent updates, new features

### Snort Compatibility

**You can still use Snort rules with Suricata!**

Recommended rule sources:
1. **Emerging Threats Open** (free, excellent coverage)
2. **Snort Registered Rules** (free with account)
3. **Snort Subscriber Rules** ($30/year, faster updates, more rules)
   - ✅ **Highly recommended** for production use
   - Early access to new rules (24-48 hour lead time)
   - Additional coverage for latest threats

### Rule Source Configuration

**In pfSense Suricata**:
1. Go to: **Services** → **Suricata** → **Global Settings** → **Rule Updates**
2. Enable:
   - ✅ **Emerging Threats Open**
   - ✅ **Snort** (requires Oinkcode)
3. Add Snort Oinkcode: [Register at snort.org](https://www.snort.org/users/sign_up)
4. Enable additional sources:
   - ✅ **Feodo Tracker Botnet C2 IP** (abuse.ch)
   - ✅ **Abuse.ch SSL Blacklist** (malicious certificates)
5. Update Rules: Click **Update** button

**Update Schedule**: Recommended daily updates, scheduled during low-traffic hours (3-5 AM).

---

## 🌍 GeoIP Requirements

### MaxMind GeoLite2 Account (FREE)

**Required for**:
- Suricata alert GeoIP enrichment
- PfBlockerNG country blocking
- ntopng traffic analysis
- Grafana geomap visualizations

**Setup**:
1. Create free account: [MaxMind GeoLite2 Signup](https://www.maxmind.com/en/geolite2/signup)
2. Generate license key
3. Configure in pfSense:
   - **System** → **Updates** → **MaxMind GeoIP**
   - Enter license key
   - Enable automatic updates

**Databases Used**:
- **GeoLite2-Country** (required): Country-level GeoIP
- **GeoLite2-City** (optional): City-level GeoIP
  - Provides more detailed location data
  - Used in Suricata IDS/IPS Grafana dashboard
  - Adds ~50MB to database size
  - Highly recommended for threat intelligence

**Update Frequency**: Weekly automatic updates (MaxMind releases Tuesday/Wednesday)

---

## 💾 Storage Planning

### Calculation Formula

**Per-day storage** ≈ (Events/day × 2KB) + (Metrics/day × 0.5KB)

### Example Scenarios

#### Light Traffic (Home Lab)
- **Suricata events**: 10,000-50,000/day
- **OpenSearch storage**: 20-100MB/day
- **InfluxDB metrics**: 5-10MB/day
- **7-day retention**: 1-2GB total
- **30-day retention**: 4-8GB total

#### Moderate Traffic (Small Business)
- **Suricata events**: 100,000-500,000/day
- **OpenSearch storage**: 200MB-1GB/day
- **InfluxDB metrics**: 20-50MB/day
- **7-day retention**: 5-10GB total
- **30-day retention**: 20-40GB total

#### Heavy Traffic (Multi-site)
- **Suricata events**: 1M-5M/day
- **OpenSearch storage**: 2-10GB/day
- **InfluxDB metrics**: 100-500MB/day
- **7-day retention**: 20-100GB total
- **30-day retention**: 100-400GB total

**Recommendation**: Start with 30-day retention, monitor actual usage, adjust as needed.

---

## 📊 InfluxDB for Network Metrics

### Why InfluxDB Over OpenSearch for Metrics?

**InfluxDB is purpose-built for time-series data** and offers significant advantages for networking metrics:

✅ **Better Compression**: 10-20× more efficient storage for metrics  
✅ **Faster Queries**: Optimized for time-series aggregations  
✅ **Lower RAM Usage**: More efficient in-memory indexing  
✅ **Simpler Schema**: No complex index templates  
✅ **Built-in Downsampling**: Automatic data rollups

### When to Use InfluxDB

**Perfect for**:
- Interface throughput (packets/sec, bytes/sec)
- Connection rates
- Protocol distribution over time
- Long-term trending (90+ days)
- Grafana rate() and derivative() queries

**Stick with OpenSearch for**:
- Full event data (logs, alerts)
- Text search and filtering
- Complex aggregations
- Geomap visualizations

### Recommended Setup

**Use both**:
- **OpenSearch**: Suricata alerts, full eve.json events (30-day retention)
- **InfluxDB**: Interface metrics, connection rates (90+ day retention)

This provides the best balance of functionality, performance, and cost (storage).

---

## 🔧 Performance Tuning Tips

### pfSense Suricata

1. **Disable unnecessary protocols**: If you don't use certain protocols (FTP, IRC, etc.), disable detection
2. **Use disablesid.conf aggressively**: See [SID Management docs](../config/sid/README.md)
3. **Tune per-interface**: Heavy IPS on WAN, lighter IDS on trusted VLANs
4. **Monitor CPU during reloads**: Ensure adequate cooling

### OpenSearch

1. **Set heap to 50% of RAM**: But no more than 31GB
2. **Use ILM policies**: Auto-delete old indices
3. **Optimize replica count**: 0 replicas for single-node setups
4. **Monitor disk space**: Set watermark alerts

### Logstash

1. **Tune pipeline workers**: Match CPU cores
2. **Adjust batch size**: Larger batches = better throughput
3. **Use persistent queues**: Prevents data loss during restarts
4. **Monitor queue depth**: Indicator of backlog/bottleneck

---

## 🛒 Hardware Shopping List

### Budget SIEM Server (~$400-600)

- **Mini PC**: Intel N100 or similar (16GB RAM, 500GB SSD)
  - Examples: Beelink, GMKtec, Minisforum
- **Alternative**: Used Dell/HP/Lenovo SFF with i5/Ryzen 5
- **Upgrade path**: Add more RAM or larger SSD later

### Recommended SIEM Server (~$800-1200)

- **Mini PC**: Intel i5/i7 or Ryzen 5/7 (32GB RAM, 1TB NVMe)
  - Examples: Intel NUC, Minisforum, Purism Librem Mini
- **Alternative**: Build micro-ATX system with newer CPU
- **Longevity**: 5+ years with room for workload growth

### Budget pfSense Firewall (~$300-500)

- **Protectli Vault**: 4-port, quad-core, 8GB RAM
- **Alternative**: Dell/HP thin client with dual-NIC PCIe card
- **Good for**: 500Mbps+ with Suricata on 2-3 interfaces

### Recommended pfSense Firewall (~$600-1000)

- **Protectli VP4670**: 6-port, Intel CPU, 16GB RAM
- **Netgate 6100**: Official pfSense hardware, support included
- **Good for**: Gigabit with Suricata on 10+ interfaces

---

## ✅ Pre-Deployment Checklist

Before ordering hardware, verify:

- [ ] **SIEM server has NO SD card** (use SSD/NVMe only)
- [ ] **SIEM server meets minimum 16GB RAM** (32GB strongly preferred)
- [ ] **SIEM server has 100GB+ SSD** (500GB+ recommended)
- [ ] **pfSense firewall has quad-core CPU minimum** (for Suricata)
- [ ] **pfSense firewall has 8GB+ RAM** (16GB for 10+ Suricata instances)
- [ ] **Network has sufficient switch ports** (for VLANs if using trunk)
- [ ] **Cooling is adequate** (Suricata rule reloads stress CPUs)
- [ ] **UPS is in place** (prevents corruption during power loss)
- [ ] **Backup strategy exists** (configuration and logs)

---

## 📞 Questions?

- **General Hardware**: Open a [GitHub Discussion](https://github.com/ChiefGyk3D/pfsense_grafana/discussions)
- **Suricata Performance**: See [SURICATA_OPTIMIZATION_GUIDE.md](SURICATA_OPTIMIZATION_GUIDE.md)
- **Storage Sizing**: See [MULTI_INTERFACE_RETENTION.md](MULTI_INTERFACE_RETENTION.md)
- **Troubleshooting**: See [TROUBLESHOOTING_CHECKLIST.md](../TROUBLESHOOTING_CHECKLIST.md)

---

**Remember**: It's better to overprovision initially than to rebuild with inadequate hardware. The cost difference between 16GB and 32GB RAM is minimal compared to the time lost troubleshooting performance issues.
