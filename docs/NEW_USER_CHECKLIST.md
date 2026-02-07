# New User Setup Checklist

Complete step-by-step checklist for deploying pfSense Suricata Dashboard from scratch.

## Pre-Installation Checklist

### Hardware Requirements

**SIEM Server (Ubuntu/Debian):**
- [ ] CPU: 4+ cores recommended (2 minimum)
- [ ] RAM: 8 GB minimum, 16 GB recommended
- [ ] Disk: 100+ GB for logs (depends on retention)
- [ ] Network: Static IP address configured

**pfSense Firewall:**
- [ ] pfSense 2.7+ installed (2.8.1 tested)
- [ ] Suricata package installed
- [ ] At least one interface configured for monitoring
- [ ] SSH enabled (System > Advanced > Admin Access)
- [ ] SSH key-based authentication configured (recommended)

### Network Requirements

- [ ] Firewall rule: Allow pfSense → SIEM Server UDP port 5140
- [ ] Firewall rule: Allow your workstation → SIEM Server TCP port 3000 (Grafana)
- [ ] DNS resolution working on both systems
- [ ] NTP configured on both systems (time sync critical!)

### Software Prerequisites

**On SIEM Server:**
- [ ] Ubuntu 20.04+ or Debian 11+ installed
- [ ] Root or sudo access
- [ ] Internet connectivity for package downloads
- [ ] Git installed: `sudo apt install git -y`

**On pfSense:**
- [ ] Suricata package installed and configured
- [ ] At least one interface enabled in Suricata
- [ ] Rules downloaded and enabled (see [Suricata Optimization Guide](./SURICATA_OPTIMIZATION_GUIDE.md))
- [ ] SSH enabled and accessible

---

## Installation Steps

### Phase 1: Initial Setup (30 minutes)

#### 1. Clone Repository
```bash
# On your SIEM server
cd ~
git clone https://github.com/ChiefGyk3D/pfsense_grafana.git
cd pfsense_grafana
```
- [ ] Repository cloned successfully
- [ ] Current directory is `pfsense_grafana/`

#### 2. Install SIEM Stack
```bash
# Run as root or with sudo
sudo ./install.sh
```

**This installs:**
- OpenSearch 2.x
- Logstash 8.x  
- Grafana 12.x

**Expected time:** 15-20 minutes

**Checkpoint:**
- [ ] OpenSearch running: `sudo systemctl status opensearch`
- [ ] Logstash running: `sudo systemctl status logstash`
- [ ] Grafana running: `sudo systemctl status grafana-server`
- [ ] No errors in installation output

#### 3. Configure Environment
```bash
# Copy example configuration
cp config.env.example config.env

# Edit with your settings
nano config.env
```

**Required changes:**
```bash
SIEM_HOST=192.168.210.10        # Your SIEM server IP
PFSENSE_HOST=192.168.1.1        # Your pfSense IP
```

**Optional but recommended:**
```bash
GRAFANA_ADMIN_PASS=YourStrongPassword  # Change default password
RETENTION_DAYS=30                      # Adjust retention
```

- [ ] `config.env` created from example
- [ ] SIEM_HOST configured with correct IP
- [ ] PFSENSE_HOST configured with correct IP
- [ ] GRAFANA_ADMIN_PASS changed from default

#### 4. Setup SSH Access to pfSense
```bash
# Test SSH connectivity
ssh root@<pfsense-ip>

# If prompted for password, setup key-based auth (recommended):
ssh-copy-id root@<pfsense-ip>
```

- [ ] SSH connection successful
- [ ] Key-based authentication working (recommended)
- [ ] Can execute commands without password prompt

#### 5. Run Automated Setup
```bash
# From pfsense_grafana directory
./setup.sh
```

**This configures:**
- OpenSearch index templates
- Deploys forwarder to pfSense
- Installs watchdog for auto-restart
- Verifies everything is working

**Expected time:** 5 minutes

**Checkpoint:**
- [ ] Script completed without errors
- [ ] Forwarder deployed to pfSense
- [ ] Watchdog cron installed
- [ ] Data flowing to OpenSearch

---

### Phase 2: Dashboard Setup (10 minutes)

#### 6. Access Grafana
```bash
# Open in browser
http://<siem-server-ip>:3000
```

**Login:**
- Username: `admin`
- Password: (from config.env, default `admin`)

- [ ] Grafana login successful
- [ ] Password changed on first login

#### 7. Configure OpenSearch Data Sources

**Navigate:** Configuration (⚙️) → Data Sources → Add data source → OpenSearch

**Datasource 1 — Suricata:**
```
Name: OpenSearch-Suricata
URL: http://localhost:9200
Index name: suricata-*
Time field: @timestamp
Version: 2.0+
```

- [ ] Suricata data source added
- [ ] Test successful (green checkmark)

**Datasource 2 — pfBlockerNG:**
```
Name: OpenSearch-pfBlockerNG
URL: http://localhost:9200
Index name: pfblockerng-*
Time field: @timestamp
Version: 2.0+
```

- [ ] pfBlockerNG data source added
- [ ] Test successful (green checkmark)

#### 8. Import Dashboards

**Navigate:** Dashboards (+) → Import → Upload JSON file

**Import all three dashboards:**

**Dashboard 1: pfSense System & pfBlockerNG**
- **File:** `dashboards/pfsense_pfblockerng_system.json`
- **Datasource:** Select your InfluxDB datasource (system metrics) AND OpenSearch-pfBlockerNG datasource (pfBlockerNG panels)
- [ ] Dashboard imported successfully
- [ ] Shows system metrics, network stats (InfluxDB)
- [ ] Shows pfBlockerNG IP blocks and DNSBL blocks (OpenSearch)

**Dashboard 2: Suricata WAN Monitoring**
- **File:** `dashboards/Suricata IDS_IPS Dashboard.json`
- **Datasource:** Select your OpenSearch datasource
- [ ] Dashboard imported successfully
- [ ] Shows WAN-side security events and alerts

**Dashboard 3: Suricata Per-Interface (LAN Monitoring)**
- **File:** `dashboards/Suricata_Per_Interface.json`
- **Datasource:** Select your OpenSearch datasource
- [ ] Dashboard imported successfully
- [ ] Shows per-VLAN/interface sections
- [ ] Interface dropdown populated with your interfaces

---

### Phase 3: Validation (15 minutes)

#### 9. Verify Data Flow

**Run status check:**
```bash
./scripts/status.sh
```

**Expected output:**
```
✓ OpenSearch is running
✓ Logstash is running  
✓ Grafana is running
✓ Forwarder is running on pfSense
✓ Watchdog cron is installed
✓ Recent data found (within last 5 minutes)
```

- [ ] All checks passing (green checkmarks)
- [ ] Recent data timestamp within last 5 minutes
- [ ] No error messages

#### 10. Check Dashboard Panels

**In Grafana dashboard:**
- [ ] "Events & Alerts" panel showing data
- [ ] "Event Type Distribution" pie chart populated
- [ ] "Protocol Distribution" showing TCP/UDP/ICMP
- [ ] "Top 10 Alert Signatures" table has entries
- [ ] GeoIP map showing attack sources (may take a few minutes)
- [ ] "IDS Alert Logs" table showing recent alerts

**If panels empty:**
- Wait 2-3 minutes for data to flow
- Generate test alert: `curl http://testmyids.com`
- Check forwarder: `ssh root@pfsense 'ps aux | grep forward-suricata'`

#### 11. Test Alert Generation

```bash
# From any machine that routes through pfSense
curl http://testmyids.com
```

**Within 30 seconds:**
- [ ] Alert appears in "IDS Alert Logs" panel
- [ ] Counter increments in "Events & Alerts"
- [ ] Signature shows "ET POLICY curl User-Agent Detected"

---

### Phase 4: Optimization (Optional, 1-2 hours)

#### 12. Optimize Suricata Rules

**Follow:** [Suricata Optimization Guide](./SURICATA_OPTIMIZATION_GUIDE.md)

**Recommended for new users:**
- [ ] Read "Phase 1: Starting Out" section
- [ ] Enable ~42 core ET rule categories
- [ ] Configure IDS mode (alert only) first
- [ ] Review log retention settings
- [ ] Configure automatic log management

**After 1-3 months:**
- [ ] Consider IPS mode (selective blocking)
- [ ] Add Snort subscription rules (optional)
- [ ] Fine-tune rules based on false positives

#### 13. Setup Forwarder Monitoring

**Follow:** [Forwarder Monitoring Guide](./SURICATA_FORWARDER_MONITORING.md)

**Recommended approach: Hybrid**
```bash
./scripts/setup_forwarder_monitoring.sh
# Select Option 1: Hybrid
```

- [ ] Monitoring installed via script
- [ ] Cron jobs verified: `ssh root@pfsense 'crontab -l'`
- [ ] Test restart: Kill forwarder and wait 5 minutes

#### 14. Configure Data Retention

```bash
# Adjust retention policy
./scripts/configure-retention-policy.sh
```

**Default:** 30 days

**Adjust based on:**
- Disk space available
- Compliance requirements
- Alert volume (check with `./scripts/status.sh`)

- [ ] Retention policy configured
- [ ] Disk space monitored: `df -h /var/lib/opensearch`

---

## Post-Installation Checklist

### Security Hardening

- [ ] Grafana admin password changed from default
- [ ] Grafana users configured (if multi-user)
- [ ] Firewall rules configured (only allow necessary access)
- [ ] OpenSearch bound to localhost (default in install.sh)
- [ ] SSH key-based auth enabled on pfSense
- [ ] Logstash UDP 5140 restricted to pfSense IP only

### Backup Configuration

**Critical files to backup:**
- [ ] `config.env` (contains your settings)
- [ ] Grafana dashboards (export JSON periodically)
- [ ] OpenSearch index templates
- [ ] Suricata rule configuration

```bash
# Backup config
cp config.env config.env.backup

# Export Grafana dashboard
# (Use Grafana UI: Dashboard settings → JSON Model → Copy)

# Backup OpenSearch template
curl http://localhost:9200/_index_template/suricata-template > suricata-template-backup.json
```

### Monitoring Setup

- [ ] Review dashboard daily for first week
- [ ] Set up Grafana alerts (optional)
- [ ] Monitor disk usage: `df -h /var/lib/opensearch`
- [ ] Check forwarder status weekly: `./scripts/status.sh`
- [ ] Review Suricata stats: Grafana "Performance" panels

### Documentation

- [ ] Read [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [ ] Bookmark [Suricata Optimization Guide](./SURICATA_OPTIMIZATION_GUIDE.md)
- [ ] Review [Forwarder Monitoring Guide](./SURICATA_FORWARDER_MONITORING.md)
- [ ] Keep notes on false positives for tuning

---

## Maintenance Schedule

### Daily (First Week)
- Check dashboard for unusual activity
- Review new alert signatures
- Verify data is flowing (`./scripts/status.sh`)

### Weekly
- Review CPU/memory usage on pfSense
- Check disk space: `df -h /var/lib/opensearch`
- Review false positives
- Update Suricata rules (automatic by default)

### Monthly
- Update pfSense and packages
- Update SIEM stack packages
- Review and tune Suricata rules
- Export dashboard backups
- Review retention policy vs disk usage
- Check for new Grafana dashboard updates

### Quarterly
- Review security posture based on alerts
- Update GeoIP database (if not using ntopng)
- Review and update documentation
- Test disaster recovery procedures

---

## Common Issues & Quick Fixes

### Dashboard Shows "No Data"
```bash
# Check everything
./scripts/status.sh

# Most common: forwarder not running
ssh root@pfsense 'ps aux | grep forward-suricata'

# Restart if needed
./setup.sh
```

### Data Stops at Midnight UTC
```bash
# OpenSearch auto-create disabled
./setup.sh  # Re-run to fix

# Or manually:
./scripts/install-opensearch-config.sh
```

### High CPU on pfSense
- Reduce Suricata rule count
- Disable low-value interfaces
- See [Suricata Optimization Guide](./SURICATA_OPTIMIZATION_GUIDE.md)

### Disk Space Running Out
```bash
# Reduce retention
./scripts/configure-retention-policy.sh

# Check index sizes
curl http://localhost:9200/_cat/indices/suricata-*?v&s=store.size:desc
```

### Too Many False Positives
- Review alerts in dashboard
- Disable noisy signatures
- Add suppression rules
- See [Suricata Optimization Guide](./SURICATA_OPTIMIZATION_GUIDE.md) → "Phase 2: After Tuning"

---

## Support Resources

### Documentation
- **Main README:** [../README.md](../README.md)
- **Troubleshooting:** [TROUBLESHOOTING.md](./TROUBLESHOOTING.md)
- **Suricata Optimization:** [SURICATA_OPTIMIZATION_GUIDE.md](./SURICATA_OPTIMIZATION_GUIDE.md)
- **Forwarder Monitoring:** [SURICATA_FORWARDER_MONITORING.md](./SURICATA_FORWARDER_MONITORING.md)
- **GeoIP Setup:** [GEOIP_SETUP.md](./GEOIP_SETUP.md)

### Community
- **GitHub Issues:** Report bugs or request features
- **GitHub Discussions:** Ask questions, share configurations
- **pfSense Forums:** General pfSense and Suricata help
- **Suricata Docs:** https://suricata.readthedocs.io/

### Emergency Commands

**Restart everything (SIEM):**
```bash
./scripts/restart-services.sh
```

**Restart forwarder (pfSense):**
```bash
ssh root@pfsense 'pkill -f forward-suricata && nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &'
```

**Check logs:**
```bash
# SIEM
sudo tail -f /var/log/logstash/logstash-plain.log
sudo journalctl -u opensearch -f

# pfSense
ssh root@pfsense 'tail -f /var/log/system.log | grep suricata'
```

---

## Next Steps

After successful installation:

1. **Learn Your Baseline** (Week 1)
   - Review alerts daily
   - Identify normal vs suspicious traffic
   - Document legitimate traffic patterns

2. **Tune Rules** (Weeks 2-4)
   - Disable noisy false positives
   - Focus on high/critical severity alerts
   - Customize for your environment

3. **Consider IPS Mode** (Month 2+)
   - After understanding traffic patterns
   - See [Suricata Optimization Guide](./SURICATA_OPTIMIZATION_GUIDE.md) → "IDS vs IPS Mode"
   - Start with one interface (Guest network recommended)

4. **Expand Monitoring** (Month 3+)
   - Add internal interfaces if needed
   - Setup alerting in Grafana
   - Integrate with other security tools

5. **Share Your Experience**
   - Submit improvements via GitHub
   - Help other users in Discussions
   - Share your dashboard customizations

---

## Completion Sign-Off

**Installation Complete:**
- [ ] All Phase 1 steps completed
- [ ] All Phase 2 steps completed
- [ ] All Phase 3 validation passed
- [ ] Documentation reviewed
- [ ] Maintenance schedule understood

**Installation Date:** _______________

**Installed By:** _______________

**pfSense Version:** _______________

**SIEM Server:** _______________

**Notes:**
```
(Add any environment-specific notes here)
```

---

🎉 **Congratulations!** Your pfSense Suricata Dashboard is fully operational. Happy monitoring!
