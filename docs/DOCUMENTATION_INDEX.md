# Documentation Index

Complete guide to all documentation in this repository.

## 🚀 Getting Started

**New to this project? Start here:**

1. **[New User Checklist](NEW_USER_CHECKLIST.md)** ⭐ RECOMMENDED
   - Step-by-step installation checklist
   - Validation procedures
   - Troubleshooting quick fixes
   - Post-installation security hardening
   - Maintenance schedule

2. **[Main README](../README.md)**
   - Project overview
   - Quick start commands
   - Architecture overview
   - Dashboard screenshots

3. **[Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md)** ⭐ ESSENTIAL
   - Rule selection strategies
   - Performance tuning
   - IDS vs IPS mode configuration
   - Log management
   - Testing and validation

---

## 📦 Installation

### Initial Setup
- **[SIEM Stack Installation](INSTALL_SIEM_STACK.md)**
  - OpenSearch installation
  - Logstash configuration
  - Grafana setup
  - System requirements

- **[pfSense Forwarder Installation](INSTALL_PFSENSE_FORWARDER.md)**
  - Python forwarder deployment
  - GeoIP database setup
  - Multi-interface support
  - Configuration options

- **[Dashboard Import](INSTALL_DASHBOARD.md)**
  - Grafana dashboard import
  - Data source configuration
  - Panel customization
  - Variable setup

### Automated Setup
- **Main README → Quick Start**
  - ONE command: `./setup.sh`
  - Automated everything
  - No manual configuration

---

## ⚙️ Configuration

### Core Configuration
- **[Configuration Guide](CONFIGURATION.md)**
  - config.env settings
  - Advanced options
  - Performance tuning
  - Custom fields

- **[GeoIP Setup](GEOIP_SETUP.md)**
  - MaxMind database installation
  - Auto-update configuration
  - ntopng integration
  - Manual updates

### OpenSearch & Logstash
- **[OpenSearch Auto-Create](OPENSEARCH_AUTO_CREATE.md)**
  - Fixes midnight UTC data stoppage
  - Index template configuration
  - Action.auto_create_index settings
  - Index lifecycle policies

- **[OpenSearch Configuration](../config/README.md)**
  - Index templates
  - Field mappings
  - geo_point configuration
  - Pipeline setup

### Suricata-Specific
- **[Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md)** ⭐
  - Rule selection (homelab vs business)
  - IDS vs IPS mode
  - Performance settings
  - Log retention

- **[Multi-Interface Retention](MULTI_INTERFACE_RETENTION.md)**
  - Per-interface log settings
  - Log rotation strategies
  - Disk space management
  - Forwarder considerations

---

## 🔧 Maintenance & Monitoring

### Forwarder Management
- **[Forwarder Monitoring Guide](SURICATA_FORWARDER_MONITORING.md)** ⭐
  - 3 monitoring strategies
  - Hybrid approach (recommended)
  - Crash recovery
  - Activity monitoring
  - Installation scripts

- **[Forwarder Monitoring Quick Reference](FORWARDER_MONITORING_QUICK_REF.md)**
  - One-liner commands
  - Quick diagnostics
  - Common tasks
  - Troubleshooting shortcuts

### Telegraf (Network Metrics)
- **[Telegraf Restart Procedure](TELEGRAF_RESTART_PROCEDURE.md)**
  - Correct restart method for pfSense
  - Why sudo doesn't work
  - Permission management
  - Integration with monitoring

- **[Telegraf Interface Fixes](TELEGRAF_INTERFACE_FIXES.md)**
  - Universal interface detection
  - Handle renamed interfaces
  - Dynamic configuration
  - VLAN support

- **[Telegraf pfBlocker Setup](TELEGRAF_PFBLOCKER_SETUP.md)**
  - pfBlocker metric collection
  - Dashboard integration
  - Common issues
  - Alternative approaches

### Log Management
- **[pfSense Filterlog Rotation Fix](PFSENSE_FILTERLOG_ROTATION_FIX.md)**
  - Fixes missing pfBlocker data
  - Daemon restart procedures
  - Automated monitoring
  - Prevention strategies

---

## 🐛 Troubleshooting

### General Issues
- **[Troubleshooting Guide](TROUBLESHOOTING.md)**
  - Common problems
  - Diagnostic commands
  - Log locations
  - Service restarts

- **[Troubleshooting Checklist](../TROUBLESHOOTING_CHECKLIST.md)**
  - Systematic diagnosis
  - Quick checks
  - Status validation
  - Resolution workflows

### Specific Issues
- **[PF Information Panel Issue](PF_INFORMATION_PANEL_ISSUE.md)**
  - Telegraf permission problems
  - Service restart issues
  - Resolution procedure
  - Lessons learned

---

## 🌐 Advanced Features

### MAC Vendor Lookup
- **[MAC Vendor Lookup Setup](MAC_VENDOR_LOOKUP_SETUP.md)**
  - Custom Telegraf plugin
  - nmap OUI database
  - Dashboard integration
  - Similar to Unifi dashboards

### Graylog Integration (Optional)
- **[Graylog Index Setup](../GRAYLOG_INDEX.md)**
  - Alternative to OpenSearch
  - Index configuration
  - Stream setup
  - Extractor configuration

- **[Graylog Suricata Setup](../GRAYLOG_SURICATA_SETUP.md)**
  - Complete Graylog integration
  - Input configuration
  - Pipeline rules
  - Dashboard creation

---

## 📊 Architecture & Design

### Data Flow
```
Suricata → eve.json → Python Forwarder → UDP:5140 → Logstash → OpenSearch → Grafana
  (pfSense)                                              (SIEM Server)

Telegraf → InfluxDB → Grafana
(pfSense)   (SIEM)     (SIEM)
```

### Components
- **pfSense**: Firewall + Suricata IDS/IPS + Telegraf metrics
- **Python Forwarder**: Multi-interface log forwarding with GeoIP
- **OpenSearch**: Log storage and indexing
- **InfluxDB**: Time-series metrics
- **Logstash**: Log parsing and enrichment
- **Grafana**: Unified dashboard visualization

---

## 🛠️ Scripts Reference

### Main Scripts (Project Root)
- **`install.sh`**: Install OpenSearch, Logstash, Grafana
- **`setup.sh`**: Configure everything (one command)
- **`install_plugins.sh`**: Optional Telegraf plugins

### Helper Scripts (scripts/)
- **`status.sh`**: Comprehensive health check
- **`restart-services.sh`**: Restart SIEM services
- **`configure-retention-policy.sh`**: Set data retention
- **`install-opensearch-config.sh`**: OpenSearch configuration
- **`setup_forwarder_monitoring.sh`**: Interactive monitoring setup

### Detailed Documentation
- **[Scripts README](../scripts/README.md)**
  - Script purposes
  - Usage examples
  - Dependencies
  - Archived scripts

---

## 📝 Additional Resources

### Configuration Files
- **config.env.example**: Environment variables template
- **config/logstash-suricata.conf**: Logstash pipeline
- **config/opensearch-index-template.json**: Index mapping
- **config/additional_config.conf**: Advanced Telegraf config

### Archived Documentation
Located in `docs/archive/`:
- Old setup procedures
- Legacy configuration methods
- Migration guides
- Historical references

**Note:** Archived docs superseded by `setup.sh` automation

---

## 📚 External Documentation

### Official Documentation
- **Suricata**: https://suricata.readthedocs.io/
- **pfSense**: https://docs.netgate.com/
- **OpenSearch**: https://opensearch.org/docs/
- **Grafana**: https://grafana.com/docs/
- **Telegraf**: https://docs.influxdata.com/telegraf/

### Community Resources
- **pfSense Forums**: https://forum.netgate.com/
- **Suricata Mailing List**: https://lists.openinfosecfoundation.org/
- **OISF (Suricata Foundation)**: https://suricata.io/

---

## 🔍 Quick Search

**Looking for specific information?**

### "How do I..."
- **...install everything?** → [New User Checklist](NEW_USER_CHECKLIST.md)
- **...optimize Suricata rules?** → [Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md)
- **...keep forwarder running?** → [Forwarder Monitoring Guide](SURICATA_FORWARDER_MONITORING.md)
- **...fix missing data?** → [Troubleshooting Guide](TROUBLESHOOTING.md)
- **...configure IPS blocking?** → [Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md) → "IDS vs IPS Mode"
- **...add MAC vendor lookup?** → [MAC Vendor Lookup Setup](MAC_VENDOR_LOOKUP_SETUP.md)
- **...reduce CPU usage?** → [Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md) → "Performance Tuning"

### "What if..."
- **...dashboard shows no data?** → [Troubleshooting Guide](TROUBLESHOOTING.md)
- **...data stops at midnight?** → [OpenSearch Auto-Create](OPENSEARCH_AUTO_CREATE.md)
- **...forwarder keeps crashing?** → [Forwarder Monitoring Guide](SURICATA_FORWARDER_MONITORING.md)
- **...disk space runs out?** → [Multi-Interface Retention](MULTI_INTERFACE_RETENTION.md)
- **...Telegraf won't start?** → [Telegraf Restart Procedure](TELEGRAF_RESTART_PROCEDURE.md)
- **...pfBlocker panels empty?** → [pfSense Filterlog Fix](PFSENSE_FILTERLOG_ROTATION_FIX.md)

### "Where is..."
- **...the config file?** → `config.env` (create from `config.env.example`)
- **...the dashboard JSON?** → `dashboards/Suricata IDS_IPS Dashboard.json`
- **...the forwarder script?** → `scripts/forward-suricata-eve-python.py`
- **...the Logstash config?** → `config/logstash-suricata.conf`
- **...the setup script?** → `./setup.sh` (project root)
- **...the status check?** → `./scripts/status.sh`

---

## 🔄 Documentation Updates

This documentation set is actively maintained. Last major update: **2025-11-26**

### Recent Additions
- **NEW**: [New User Checklist](NEW_USER_CHECKLIST.md) - Complete setup workflow
- **NEW**: [Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md) - Comprehensive rule tuning
- **UPDATED**: [Forwarder Monitoring Guide](SURICATA_FORWARDER_MONITORING.md) - 3 strategies with hybrid approach
- **UPDATED**: Main README - Added optimization guide link

### Contributing to Documentation
- Found an error? Submit a GitHub issue
- Have a better explanation? Submit a pull request
- Want to add a guide? Open a discussion first
- Improved a procedure? Share your findings

---

## 📞 Getting Help

1. **Check Documentation**: Use search above to find relevant guides
2. **Run Status Check**: `./scripts/status.sh` for automated diagnosis
3. **Review Troubleshooting**: [Troubleshooting Guide](TROUBLESHOOTING.md)
4. **Search GitHub Issues**: Someone may have had same problem
5. **Ask Community**: GitHub Discussions for questions
6. **Report Bugs**: GitHub Issues for confirmed bugs

**Pro Tip:** When asking for help, always include:
- Output of `./scripts/status.sh`
- pfSense version
- Suricata version
- Error messages (exact text)
- What you've already tried

---

## ✅ Documentation Checklist for Maintainers

When adding new features:
- [ ] Update this index
- [ ] Create detailed guide if complex
- [ ] Add to main README
- [ ] Update setup scripts if needed
- [ ] Test all commands in guide
- [ ] Add troubleshooting section
- [ ] Include in NEW_USER_CHECKLIST.md if essential
- [ ] Update CHANGELOG or git commit message

---

**Need something not listed here?** Open a GitHub Discussion and we'll help!
