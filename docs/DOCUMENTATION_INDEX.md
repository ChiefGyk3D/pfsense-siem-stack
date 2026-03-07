# pfSense Knowledge Base - Documentation Index

> **Complete navigation guide** — Find any documentation quickly

This is the central index for the pfSense Knowledge Base, covering SIEM infrastructure, security hardening, network monitoring, automation, and operational procedures.

---

## 🎯 Find What You Need

| I want to... | Go to... | Status |
|--------------|----------|--------|
| **Use the management console** | [Management Console Guide](MANAGEMENT_CONSOLE.md) ⭐ | ✅ Stable |
| **Learn about all helper scripts** | [Scripts Reference Guide](SCRIPTS_REFERENCE.md) | ✅ Stable |
| **Get started from scratch** | [Main README](../README.md) → [Quick Start](../QUICK_START.md) | ✅ Stable |
| **See what's complete vs WIP** | [Project Status](../README.md#-project-status) | ✅ Updated |
| **Install the SIEM stack** | [SIEM Stack Installation](INSTALL_SIEM_STACK.md) | ✅ Stable |
| **Deploy forwarder to pfSense** | [pfSense Forwarder Setup](INSTALL_PFSENSE_FORWARDER.md) | ✅ Stable |
| **Optimize Suricata** | [Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md) ⭐ | ✅ Stable |
| **Manage Suricata signatures** | [SID Management](../config/sid/README.md) | 🚧 Testing |
| **Fix "No Data" in dashboard** | [Dashboard Troubleshooting](DASHBOARD_NO_DATA_FIX.md) | ✅ Stable |
| **Monitor internal traffic** | [LAN Monitoring Guide](LAN_MONITORING.md) | ✅ Dashboard Ready |
| **Configure blocklists** | [PfBlockerNG Optimization](PFBLOCKERNG_OPTIMIZATION.md) | ✅ Stable |
| **Fix log rotation issues** | [Log Rotation Fix](LOG_ROTATION_FIX.md) | ✅ Solved |
| **Troubleshoot issues** | [Troubleshooting Guide](TROUBLESHOOTING.md) | ✅ Stable |
| **Understand architecture** | [Architecture Diagram](architecture.png) | ✅ Complete |

**Legend**: ✅ Stable & Production-Ready | 🚧 Work in Progress | 📝 Planned

---

## � Knowledge Base Scope

This repository documents:
- **✅ SIEM & Logging**: OpenSearch, Logstash, Grafana monitoring (stable, docs improving)
- **✅ IDS/IPS Security**: Suricata optimization, SID management, PfBlockerNG (stable, SID testing)
- **✅ Network Monitoring**: Multi-WAN, VLAN segmentation, interface tracking (stable)
- **✅ Automation**: Log forwarding, watchdogs, automated recovery (stable)
- **✅ LAN Monitoring**: Per-interface dashboard with dynamic VLAN sections (production ready)
- **🚧 Advanced Analytics**: Anomaly detection, machine learning (planned)
- **🚧 Multi-Firewall**: Central management of multiple pfSense instances (planned)

---

## �📖 Documentation Structure

### 1. Getting Started

**Start here if you're new:**

- **[Main README](../README.md)** - Project overview, features, architecture, status
- **[Quick Start Guide](../QUICK_START.md)** - 15-minute deployment walkthrough
- **[New User Checklist](NEW_USER_CHECKLIST.md)** ⭐ - Step-by-step validation
- **[Architecture Diagram](architecture.png)** - Visual overview of components
- **[Project Organization](../ORGANIZATION.md)** - File structure and navigation

**Read first:** [Main README](../README.md) → [Quick Start](../QUICK_START.md) → [New User Checklist](NEW_USER_CHECKLIST.md)

---

### 2. Installation & Deployment

**Before you start:**

- **[Hardware Requirements](HARDWARE_REQUIREMENTS.md)** ⭐ **READ THIS FIRST**
  - 🚨 Critical warnings (NO SD CARDS for logging!)
  - SIEM server specs (16GB RAM minimum, 32GB recommended)
  - pfSense requirements (Suricata needs quad-core, 8-16GB RAM)
  - Storage planning and sizing
  - Production reference configurations
  - Why Suricata over Snort (multithreading)
  - GeoIP setup requirements

**Installing the SIEM stack:**

- **[SIEM Stack Installation](INSTALL_SIEM_STACK.md)** - OpenSearch, Logstash, Grafana
  - System requirements (see Hardware Requirements first)
  - Ubuntu/Debian installation
  - Service configuration
  - Security hardening

**Deploying to pfSense:**

- **[pfSense Forwarder Setup](INSTALL_PFSENSE_FORWARDER.md)** - Python forwarder deployment
  - Automated via `setup.sh` (recommended)
  - Manual installation
  - GeoIP database configuration
  - Multi-interface support

**Dashboard setup:**

- **[Dashboard Import](INSTALL_DASHBOARD.md)** - Import Grafana dashboards
  - Datasource configuration
  - Panel customization
  - Variable setup

**Automated deployment:**

- **[README → Quick Start](../README.md#-quick-start)** - ONE command setup
  - `./install.sh` - Install SIEM stack
  - `./setup.sh` - Configure everything
  - `./scripts/status.sh` - Verify installation

---

### 3. Configuration

**Core configuration:**

- **[Configuration Guide](CONFIGURATION.md)** - All `config.env` settings
  - Required settings
  - Advanced options
  - Performance tuning
  - Custom fields

- **[GeoIP Setup](GEOIP_SETUP.md)** - MaxMind GeoIP database
  - Installation methods
  - Auto-update configuration
  - ntopng integration
  - Manual updates

**OpenSearch & Logstash:**

- **[OpenSearch Auto-Create](OPENSEARCH_AUTO_CREATE.md)** - Fix midnight UTC data stoppage
  - Index template configuration
  - `action.auto_create_index` settings
  - Index lifecycle policies

- **[Retention Policies](MULTI_INTERFACE_RETENTION.md)** - Data lifecycle management
  - Index rollover
  - Automatic deletion
  - Per-interface retention

**Telegraf (optional):**

- **[Telegraf pfBlockerNG Setup](TELEGRAF_PFBLOCKER_SETUP.md)** - pfBlockerNG → OpenSearch pipeline
- **[Telegraf Restart Procedure](TELEGRAF_RESTART_PROCEDURE.md)** - Troubleshooting

---

### 4. Optimization & Tuning

**Essential reading:**

- **[Suricata Configuration Guide](SURICATA_CONFIGURATION.md)** ⭐ **START HERE**
  - Why Suricata over Snort (multithreading)
  - Rule sources (ET, Snort, Feodo, Abuse.ch)
  - **Critical**: Stream memory increase (REQUIRED)
  - Interface configuration (IPS vs IDS)
  - GeoIP setup with MaxMind
  - Performance monitoring
  - Common issues and solutions

- **[Suricata Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md)** ⭐ **MUST READ**
  - Rule selection strategies
  - Performance tuning (inline IPS vs IDS)
  - Multi-interface configuration
  - Testing and validation
  - IDS vs IPS mode decision tree

**Threat intelligence:**

- **[PfBlockerNG Optimization](PFBLOCKERNG_OPTIMIZATION.md)** - Upstream blocklisting
  - Recommended feeds
  - Configuration best practices
  - Integration with Suricata
  - Performance tips

**Advanced monitoring:**

- **[LAN Monitoring & East-West Detection](LAN_MONITORING.md)** - Internal traffic monitoring
  - Suricata on VLANs
  - Lateral movement detection
  - Per-VLAN policies
  - Use cases and examples

---

### 5. Troubleshooting

**General issues:**

- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common problems and solutions
  - No data in dashboard
  - Forwarder not running
  - OpenSearch connection issues
  - Logstash pipeline errors

**Specific issues:**

- **[Dashboard "No Data" Fix](DASHBOARD_NO_DATA_FIX.md)** - Comprehensive dashboard troubleshooting
  - Datasource issues
  - Field mapping problems
  - EOF behavior
  - Time range issues

- **[Log Rotation Fix](LOG_ROTATION_FIX.md)** - Forwarder stuck on old files
  - How rotation works
  - Inode monitoring solution
  - Verification steps
  - Prevention

- **[pfSense Filterlog Rotation](PFSENSE_FILTERLOG_ROTATION_FIX.md)** - Filterlog specific issues

- **[Telegraf Interface Fixes](TELEGRAF_INTERFACE_FIXES.md)** - Telegraf interface stats issues

**Monitoring forwarder health:**

- **[Forwarder Monitoring Quick Reference](FORWARDER_MONITORING_QUICK_REF.md)** - Health checks
- **[Suricata Forwarder Monitoring](SURICATA_FORWARDER_MONITORING.md)** - Detailed monitoring setup

---

### 6. Advanced Topics

**Scripts and automation:**

- **[Scripts README](../scripts/README.md)** - All helper scripts explained
  - Forwarders
  - Watchdogs
  - Configuration tools
  - Utilities

**Specific guides:**

- **[MAC Vendor Lookup Setup](MAC_VENDOR_LOOKUP_SETUP.md)** - Enrich with OUI data
- **[pfSense Information Panel Issue](PF_INFORMATION_PANEL_ISSUE.md)** - Specific panel fix
- **[Filterlog Monitoring Cron](SETUP_FILTERLOG_MONITORING_CRON.md)** - Automated monitoring

---

### 7. Reference

**Project documentation:**

- **[CHANGELOG](../CHANGELOG.md)** - Version history and changes
- **[LICENSE](../LICENSE)** - Mozilla Public License 2.0
- **[CONTRIBUTING](../CONTRIBUTING.md)** - How to contribute
- **[Organization](../ORGANIZATION.md)** - Project structure

**Session notes:**

- **[Session Summary](SESSION_SUMMARY.md)** - Development session notes (historical)

---

## 📚 Recommended Reading Order

### For New Users

1. **[Main README](../README.md)** - Understand what this project does
2. **[Architecture Diagram](architecture.png)** - Visualize components
3. **[Quick Start](../QUICK_START.md)** - Deploy in 15 minutes
4. **[New User Checklist](NEW_USER_CHECKLIST.md)** - Validate installation
5. **[Suricata Optimization](SURICATA_OPTIMIZATION_GUIDE.md)** - Tune for your environment

### For Advanced Users

1. **[Configuration Guide](CONFIGURATION.md)** - Understand all options
2. **[PfBlockerNG Optimization](PFBLOCKERNG_OPTIMIZATION.md)** - Add upstream filtering
3. **[LAN Monitoring](LAN_MONITORING.md)** - Monitor internal traffic
4. **[Forwarder Monitoring](FORWARDER_MONITORING_QUICK_REF.md)** - Ensure reliability
5. **[Scripts README](../scripts/README.md)** - Automate operations

### For Troubleshooters

1. **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Start here
2. **[Dashboard "No Data" Fix](DASHBOARD_NO_DATA_FIX.md)** - Dashboard issues
3. **[Log Rotation Fix](LOG_ROTATION_FIX.md)** - Forwarder issues
4. **`./scripts/status.sh`** - Automated diagnostics

---

## 🔍 Finding Specific Information

### By Component

| Component | Documentation |
|-----------|---------------|
| **Suricata** | [Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md), [LAN Monitoring](LAN_MONITORING.md) |
| **Forwarder** | [Installation](INSTALL_PFSENSE_FORWARDER.md), [Monitoring](FORWARDER_MONITORING_QUICK_REF.md), [Rotation Fix](LOG_ROTATION_FIX.md) |
| **OpenSearch** | [Auto-Create](OPENSEARCH_AUTO_CREATE.md), [Retention](MULTI_INTERFACE_RETENTION.md) |
| **Logstash** | [SIEM Installation](INSTALL_SIEM_STACK.md), [Configuration](CONFIGURATION.md) |
| **Grafana** | [Dashboard Import](INSTALL_DASHBOARD.md), [No Data Fix](DASHBOARD_NO_DATA_FIX.md) |
| **PfBlockerNG** | [Optimization Guide](PFBLOCKERNG_OPTIMIZATION.md) |
| **Telegraf** | [Setup](TELEGRAF_PFBLOCKER_SETUP.md), [Restart](TELEGRAF_RESTART_PROCEDURE.md) |

### By Task

| Task | Documentation |
|------|---------------|
| **Install everything** | [Quick Start](../QUICK_START.md) |
| **Deploy forwarder** | [Forwarder Installation](INSTALL_PFSENSE_FORWARDER.md) |
| **Optimize Suricata** | [Optimization Guide](SURICATA_OPTIMIZATION_GUIDE.md) |
| **Monitor internal traffic** | [LAN Monitoring](LAN_MONITORING.md) |
| **Fix no data** | [Dashboard Fix](DASHBOARD_NO_DATA_FIX.md) |
| **Configure GeoIP** | [GeoIP Setup](GEOIP_SETUP.md) |
| **Set retention** | [Retention Policies](MULTI_INTERFACE_RETENTION.md) |

---

## 📁 Documentation Files

**Active documentation** (current and maintained):

```
docs/
├── DOCUMENTATION_INDEX.md          ← You are here
├── architecture.mmd / .png         ← Architecture diagram
│
├── Getting Started
│   ├── NEW_USER_CHECKLIST.md
│   └── ../QUICK_START.md
│
├── Installation
│   ├── INSTALL_SIEM_STACK.md
│   ├── INSTALL_PFSENSE_FORWARDER.md
│   └── INSTALL_DASHBOARD.md
│
├── Configuration
│   ├── CONFIGURATION.md
│   ├── GEOIP_SETUP.md
│   ├── OPENSEARCH_AUTO_CREATE.md
│   └── MULTI_INTERFACE_RETENTION.md
│
├── Optimization
│   ├── SURICATA_OPTIMIZATION_GUIDE.md  ⭐
│   ├── PFBLOCKERNG_OPTIMIZATION.md
│   └── LAN_MONITORING.md
│
├── Troubleshooting
│   ├── TROUBLESHOOTING.md
│   ├── DASHBOARD_NO_DATA_FIX.md
│   ├── LOG_ROTATION_FIX.md
│   ├── FORWARDER_MONITORING_QUICK_REF.md
│   └── SURICATA_FORWARDER_MONITORING.md
│
└── archive/                         ← Historical docs
```

**Archive** (`docs/archive/`): Old documentation kept for reference

---

## 🆘 Getting Help

1. **Check documentation** - Use this index to find relevant guides
2. **Run diagnostics** - `./scripts/status.sh` for automated checks
3. **Search issues** - [GitHub Issues](https://github.com/ChiefGyk3D/pfsense_siem_stack/issues)
4. **Ask questions** - [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense_siem_stack/discussions)
5. **Report bugs** - [New Issue](https://github.com/ChiefGyk3D/pfsense_siem_stack/issues/new)

---

**Last updated:** 2025-11-27 (Project overhaul)

**Maintained by:** [@ChiefGyk3D](https://github.com/ChiefGyk3D)

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
- **...the forwarder script?** → `scripts/forward-suricata-eve.py`
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
