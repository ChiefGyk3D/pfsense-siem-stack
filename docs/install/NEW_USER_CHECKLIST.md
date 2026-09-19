# New User Setup Checklist

Step-by-step checklist for deploying the pfSense SIEM stack from scratch. It tells you
*what to verify at each stage*; the commands themselves live in
[QUICK_START.md](../../QUICK_START.md) and the install guides linked from each step.

## Pre-Installation Checklist

### Hardware Requirements

Full detail: [Hardware Requirements](HARDWARE_REQUIREMENTS.md).

**SIEM Server:**
- [ ] CPU: 4+ cores recommended (2 minimum)
- [ ] RAM: 16 GB minimum, 32 GB recommended
- [ ] Disk: 100 GB+ SSD (500 GB+ for 30-day retention on busy networks); **no SD cards**
- [ ] Network: static IP address configured

**pfSense Firewall:**
- [ ] pfSense 2.7.2+ installed (2.8.1 tested; 2.9.0 supported, see [pfSense Upgrade Guide](../pfsense/PFSENSE_UPGRADE_GUIDE.md))
- [ ] Suricata package installed, rules downloaded, enabled on at least one interface
- [ ] SSH enabled (System > Advanced > Secure Shell)
- [ ] Optional: ntopng or pfBlockerNG with a MaxMind key, for GeoIP ([GeoIP Setup](GEOIP_SETUP.md))

### Network Requirements

- [ ] pfSense → SIEM server: UDP 5140 allowed (Logstash input)
- [ ] Workstation → SIEM server: TCP 3000 (Grafana) and TCP 9200 (OpenSearch, used by `setup.sh`)
- [ ] Workstation → pfSense: TCP 22 (SSH)
- [ ] NTP configured on both systems (time sync matters for the dashboards)

### Software Prerequisites

**On SIEM Server:**
- [ ] Ubuntu 24.04 LTS installed (tested; 22.04 should work)
- [ ] Root or sudo access and Internet connectivity for package downloads
- [ ] `git` installed

**On the workstation you run the scripts from** (can be the SIEM server itself):
- [ ] `bash`, `ssh`, `scp`, `curl`, `jq`, `python3` available

---

## Installation Steps

### Phase 1: Initial Setup (30 minutes)

Follow [QUICK_START.md](../../QUICK_START.md) steps 1-3. Check off as you go:

#### 1. Clone and configure
- [ ] Repository cloned: `git clone https://github.com/ChiefGyk3D/pfsense-siem-stack.git`
- [ ] `config.env` created from `config.env.example`
- [ ] **Required** variables set: `SIEM_HOST`, `PFSENSE_HOST`, `PFSENSE_USER` (default `admin`)
- [ ] Recommended: `GRAFANA_ADMIN_PASS` changed from `admin`; `RETENTION_DAYS` reviewed (default 30)

#### 2. SSH access to pfSense
- [ ] `ssh-copy-id admin@<PFSENSE_IP>` done — the scripts never prompt for passwords
- [ ] `ssh admin@<PFSENSE_IP> 'echo ok'` works without a password prompt

#### 3. Preflight
- [ ] `./scripts/preflight.sh` passes (config.env, SSH to both hosts, Python on pfSense, OpenSearch reachability, GeoIP presence). Fix every ✗ before continuing; ⚠ for OpenSearch is expected before `install.sh` has run.

#### 4. Install the SIEM stack
- [ ] `sudo ./install.sh` completed on the SIEM server (OpenSearch 2.19.4 in `/opt/opensearch`, Logstash 8.19.7, Grafana 12.3.0) — manual alternative: [SIEM Stack Installation](INSTALL_SIEM_STACK.md)
- [ ] `systemctl status opensearch logstash grafana-server` all active
- [ ] `curl -s http://localhost:9200 | jq .version.number` returns `2.19.4`

#### 5. Run the automated setup
- [ ] `./setup.sh` completed without errors (it re-runs preflight, installs the OpenSearch index template, deploys the Logstash pipeline, deploys forwarder + rc.d service + watchdog to pfSense, imports the Suricata dashboards, verifies data flow)
- [ ] `ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'` reports running
- [ ] `ssh admin@<PFSENSE_IP> 'crontab -l | grep watchdog'` shows the every-minute entry
- [ ] Event count increasing: `curl -s http://localhost:9200/suricata-*/_count | jq .count`

---

### Phase 2: Dashboard Setup (10 minutes)

Detail: [Dashboard Installation](INSTALL_DASHBOARD.md).

#### 6. Access Grafana
- [ ] Login at `http://<SIEM_IP>:3000` works (`admin` / your `GRAFANA_ADMIN_PASS`)
- [ ] Password changed if still `admin`

#### 7. Data sources
- [ ] `OpenSearch-Suricata` (index `suricata-*`, time field `@timestamp`) exists and tests green
- [ ] `OpenSearch-pfBlockerNG` (index `pfblockerng-*`) exists — `setup.sh` creates it; tests green once Telegraf sends data
- [ ] *Optional:* InfluxDB datasource `pfsense` (database `pfsense`) — only for the pfSense system dashboard

#### 8. Dashboards
`setup.sh` imports the two Suricata dashboards through the Grafana API. Confirm, and import manually only if missing:

- [ ] **Suricata IDS/IPS** — `dashboards/Suricata_IDS_IPS.json` (UID `suricata_ids_ips`) at `http://<SIEM_IP>:3000/d/suricata_ids_ips`
- [ ] **Suricata Per-Interface** — `dashboards/Suricata_Per_Interface.json` (UID `suricata_per_interface`); interface dropdown lists your interfaces
- [ ] *Optional:* **pfSense System & pfBlockerNG** — `dashboards/pfsense_pfblockerng_system.json`, imported manually with the InfluxDB and OpenSearch-pfBlockerNG datasources ([Telegraf pfBlockerNG Setup](../pfsense/TELEGRAF_PFBLOCKER_SETUP.md))

---

### Phase 3: Validation (15 minutes)

#### 9. Verify data flow
- [ ] `./scripts/status.sh` — all checks green (OpenSearch, Logstash, Grafana, forwarder on pfSense, watchdog cron, recent data)
- [ ] Recent data timestamp within the last 5 minutes

#### 10. Check dashboard panels
- [ ] Events over time, event type and protocol distributions populated
- [ ] Top source/destination IPs populated
- [ ] GeoIP map shows external sources (needs a GeoLite2-City DB on pfSense — see [GeoIP Setup](GEOIP_SETUP.md); may take a few minutes)

If panels are empty: wait 2-3 minutes, check the time range, then run
`./scripts/diagnose-and-repair.sh`. See [Dashboard No Data Fix](../troubleshooting/DASHBOARD_NO_DATA_FIX.md).

#### 11. Test alert generation
- [ ] From a machine behind pfSense: `curl http://testmyids.com`
- [ ] Within ~30 seconds an alert (e.g. "ET POLICY curl User-Agent Detected") appears in the alerts table

---

### Phase 4: Optimization (Optional, 1-2 hours)

#### 12. Tune Suricata rules
Follow the [Suricata Optimization Guide](../pfsense/SURICATA_OPTIMIZATION_GUIDE.md):
- [ ] Read "Phase 1: Starting Out"; enable the core ET rule categories
- [ ] Stay in IDS mode (alert only) for the first weeks
- [ ] Review log retention/rotation on pfSense

#### 13. Forwarder monitoring
- [ ] Optional deeper monitoring per [Forwarder Monitoring Guide](../operations/SURICATA_FORWARDER_MONITORING.md) (`./scripts/setup_forwarder_monitoring.sh`)
- [ ] Test recovery: `ssh admin@<PFSENSE_IP> 'pkill -f forward-suricata-eve.py'` — the watchdog restarts it within a minute

#### 14. Data retention
- [ ] Retention policy applied: `setup.sh` applies `RETENTION_DAYS` from config.env (default 30). To change it later run `./scripts/configure-retention-policy.sh <DAYS>` — it takes the day count as an argument (default 90 when omitted) and does not prompt
- [ ] Disk usage checked: `df -h /opt/opensearch/data`

---

## Post-Installation Checklist

### Security Hardening

- [ ] Grafana admin password changed from default; additional users created if multi-user
- [ ] **OpenSearch is NOT bound to localhost and has NO authentication** by default — `install.sh` sets `network.host: 0.0.0.0`, `plugins.security.disabled: true` and opens ufw 9200/tcp. Restrict 9200 with ufw to trusted hosts (`sudo ufw delete allow 9200/tcp` then `sudo ufw allow from <WORKSTATION_IP> to any port 9200 proto tcp`) or enable the security plugin. Tracked in [ROADMAP.md, Phase A](../../ROADMAP.md).
- [ ] Logstash UDP 5140 restricted to the pfSense IP (`sudo ufw allow from <PFSENSE_IP> to any port 5140 proto udp`)
- [ ] Grafana 3000 restricted to your management network
- [ ] SSH key-based auth only on pfSense

### Backup Configuration

- [ ] `config.env` backed up (contains your settings and Grafana password)
- [ ] Grafana dashboards exported periodically (Dashboard settings → JSON Model, or the API)
- [ ] OpenSearch index template saved: `curl -s http://localhost:9200/_index_template/suricata-template > suricata-template-backup.json`
- [ ] pfSense configuration backed up (Diagnostics > Backup & Restore). Note: the forwarder files on pfSense are **not** in that backup — re-run `./setup.sh` after a restore

### Documentation

- [ ] Read [Troubleshooting Guide](../troubleshooting/TROUBLESHOOTING.md)
- [ ] Bookmark [Suricata Optimization Guide](../pfsense/SURICATA_OPTIMIZATION_GUIDE.md)
- [ ] Keep notes on false positives for tuning

---

## Maintenance Schedule

### Daily (First Week)
- Check dashboard for unusual activity and new alert signatures
- Verify data is flowing: `./scripts/status.sh`

### Weekly
- Review CPU/memory on pfSense; review false positives
- Check disk space: `df -h /opt/opensearch/data`
- Confirm Suricata rule updates are running

### Monthly
- Update SIEM stack packages (`apt`) and pfSense packages
- Export dashboard backups; review retention vs disk usage

### After upgrading pfSense
- Re-run `./setup.sh` and then `./scripts/status.sh`. The forwarder, rc.d service and root crontab entry are outside `config.xml` and can be removed by an upgrade or package reinstall. See [pfSense Upgrade Guide](../pfsense/PFSENSE_UPGRADE_GUIDE.md).

### Quarterly
- Review security posture based on alerts
- Confirm the GeoLite2 database on pfSense is still updating (ntopng/pfBlockerNG)
- Test disaster recovery (restore pfSense config, re-run `./setup.sh`)

---

## Common Issues & Quick Fixes

| Symptom | First thing to try | Detail |
|---------|--------------------|--------|
| Dashboard shows "No data" | `./scripts/status.sh`, then `./scripts/diagnose-and-repair.sh` | [Dashboard No Data Fix](../troubleshooting/DASHBOARD_NO_DATA_FIX.md) |
| Forwarder not running | `ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'` (or wait a minute for the watchdog) | [Forwarder Installation](INSTALL_PFSENSE_FORWARDER.md#troubleshooting) |
| Data stops at midnight UTC | `./scripts/install-opensearch-config.sh` (or re-run `./setup.sh`) | [OpenSearch Auto-Create](../troubleshooting/OPENSEARCH_AUTO_CREATE.md) |
| High CPU on pfSense | Reduce rule count, disable low-value interfaces | [Suricata Optimization Guide](../pfsense/SURICATA_OPTIMIZATION_GUIDE.md) |
| Disk filling up | `./scripts/configure-retention-policy.sh <DAYS>`; check `curl -s 'http://localhost:9200/_cat/indices/suricata-*?v&s=store.size:desc'` | [Multi-Interface Retention](../operations/MULTI_INTERFACE_RETENTION.md) |
| Too many false positives | Disable noisy SIDs, add suppressions | [Suricata Optimization Guide](../pfsense/SURICATA_OPTIMIZATION_GUIDE.md) |
| Everything on the SIEM needs a restart | `./scripts/restart-services.sh` | |

**Logs:** SIEM — `sudo journalctl -u logstash -f`, `sudo journalctl -u opensearch -f`;
pfSense — `ssh admin@<PFSENSE_IP> 'tail -f /var/log/system.log | grep suricata'`.

---

## Support Resources

- **Quick start:** [QUICK_START.md](../../QUICK_START.md)
- **Documentation hub:** [DOCUMENTATION_INDEX.md](../DOCUMENTATION_INDEX.md)
- **Troubleshooting:** [TROUBLESHOOTING.md](../troubleshooting/TROUBLESHOOTING.md)
- **GeoIP Setup:** [GEOIP_SETUP.md](GEOIP_SETUP.md)
- **Issues and discussions:** https://github.com/ChiefGyk3D/pfsense-siem-stack
- **Suricata Docs:** https://suricata.readthedocs.io/

---

## Next Steps

1. **Learn your baseline** (week 1) — review alerts daily, document legitimate traffic patterns
2. **Tune rules** (weeks 2-4) — disable noisy false positives, focus on high/critical severity
3. **Consider IPS mode** (month 2+) — one interface at a time; see the optimization guide's "IDS vs IPS Mode"
4. **Expand monitoring** (month 3+) — more interfaces, Grafana alerting, other integrations
5. **Share your experience** — improvements and dashboard customizations are welcome on GitHub

---

## Completion Sign-Off

- [ ] All Phase 1 steps completed
- [ ] All Phase 2 steps completed
- [ ] All Phase 3 validation passed
- [ ] Security hardening reviewed (especially OpenSearch exposure)
- [ ] Maintenance schedule understood

**Installation Date:** _______________

**Installed By:** _______________

**pfSense Version:** _______________

**SIEM Server:** _______________

**Notes:**
```
(Add any environment-specific notes here)
```
