# Project Roadmap

> **From Dashboard Tweak to pfSense Knowledge Base**

This document tracks the evolution of the project and outlines future development plans.

---

## 🎯 Project Vision

Transform from a Grafana dashboard fix into a comprehensive, community-driven pfSense knowledge base covering security, monitoring, automation, and operations—providing battle-tested configurations and troubleshooting strategies for production deployments.

---

## 📅 Project Evolution

### Phase 1: Dashboard Fix (Origin)
**Status**: ✅ Complete

Started as a simple Grafana panel fix, evolved into realizing the monitoring infrastructure needed a complete overhaul.

**Achievements**:
- Fixed broken Grafana panels
- Identified infrastructure limitations
- Recognized need for comprehensive solution

---

### Phase 2: SIEM Infrastructure (Current Focus)
**Status**: 🚧 Active Development (Functional, Documentation Evolving)

#### Completed ✅
- **Multi-Interface Monitoring**: 15 Suricata instances (2 WAN inline IPS + 13 VLAN IDS)
- **Log Forwarder**: Inode-aware rotation handling, GeoIP enrichment, multi-threaded
- **OpenSearch/Logstash Pipeline**: Nested format, index templates, retention policies
- **WAN Security Dashboard**: Attack visualization, signature tracking, geographic mapping
- **Automated Installation**: One-command SIEM stack deployment
- **Watchdog Monitoring**: Auto-restart on failure, health checks
- **PfBlockerNG Integration**: Upstream threat filtering, DNSBL optimization
- **Architecture Documentation**: Mermaid diagrams, data flow visualization

#### In Progress 🚧
- **Documentation**: Comprehensive guides, troubleshooting scenarios (continuously improving)
- **SID Management**: 219 optimized signatures, 2 conditional suppressions (testing in production)
- **Log Rotation Handling**: Inode-aware forwarder (tested, documenting edge cases)
- **Performance Optimization**: Query tuning, index optimization, resource management

#### Pending 📝
- **LAN Monitoring Dashboard**: East-west traffic visualization, lateral movement detection
- **Alert Rule Library**: Pre-configured detection rules with documentation
- **Multi-Instance Deployment**: Monitoring multiple pfSense firewalls centrally

---

### Phase 3: Knowledge Base Expansion (Next Focus)
**Status**: 📝 Planned

Transform from SIEM-focused to comprehensive pfSense knowledge repository.

#### Planned Features

**Security & IDS/IPS**:
- [ ] Snort integration (currently Suricata-focused)
- [ ] Threat intelligence feeds (MISP, abuse.ch, OTX)
- [ ] Advanced signature tuning strategies
- [ ] IPS performance benchmarking guide
- [ ] False positive database (community-contributed)

**Monitoring & Logging**:
- [ ] pfSense filterlog dashboard (firewall rule analysis)
- [ ] HAProxy monitoring (reverse proxy stats)
- [ ] Unbound DNS analytics (query patterns, blocking stats)
- [ ] DHCP lease tracking dashboard
- [ ] VPN monitoring (OpenVPN, WireGuard, IPsec)
- [ ] Telegraf metrics dashboard (system health, interface stats)

**Automation & Configuration**:
- [ ] Ansible playbooks for deployment
- [ ] Docker/Docker Compose setup
- [ ] Configuration backup/restore procedures
- [ ] Multi-firewall orchestration
- [ ] Automated certificate renewal monitoring

**Operations & Troubleshooting**:
- [ ] Hardware sizing calculator
- [ ] Performance tuning database (CPU, RAM, disk I/O)
- [ ] Common failure scenarios and recovery procedures
- [ ] Upgrade procedures and compatibility matrix
- [ ] Disaster recovery playbook

---

### Phase 4: Community Platform (Long-term Vision)
**Status**: 📝 Conceptual

Build community-driven platform for pfSense knowledge sharing.

#### Vision
- **Configuration Marketplace**: Share and discover pfSense configurations
- **Troubleshooting Database**: Searchable problem/solution repository
- **Benchmark Database**: Community-contributed performance data
- **Tutorial Hub**: Video guides, written tutorials, interactive labs
- **Hardware Registry**: Tested hardware configurations and compatibility
- **Integration Library**: Pre-built integrations with other tools

---

## 🚧 Current Development Status

### ✅ Production Ready
| Component | Status | Notes |
|-----------|--------|-------|
| Suricata Multi-Interface | ✅ Stable | 15 instances tested (2 WAN + 13 VLAN) |
| Log Forwarder | ✅ Stable | Inode-aware, GeoIP, watchdog |
| OpenSearch/Logstash | ✅ Stable | Nested format, templates, retention |
| WAN Dashboard | ✅ Stable | Attack visualization, geo-mapping |
| PfBlockerNG Integration | ✅ Stable | Blocklists, DNSBL whitelist |
| Automated Installation | ✅ Stable | One-command deployment |

### 🚧 Active Development
| Component | Status | ETA | Notes |
|-----------|--------|-----|-------|
| Documentation | 🚧 Ongoing | Continuous | Adding troubleshooting, scenarios |
| SID Management | 🚧 Testing | Q1 2025 | 219 rules optimized, production testing |
| LAN Dashboard | 🚧 Design | Q1 2025 | East-west traffic visualization |
| Alert Rules | 🚧 Planning | Q2 2025 | Pre-configured detection library |

### 📝 Planned (Not Started)
| Feature | Priority | Target | Notes |
|---------|----------|--------|-------|
| Snort Integration | High | Q2 2025 | Currently Suricata only |
| Multi-Firewall | High | Q2 2025 | Central monitoring |
| Filterlog Dashboard | Medium | Q2 2025 | Firewall rule analysis |
| Ansible Playbooks | Medium | Q3 2025 | Automated deployment |
| Threat Intel Feeds | Low | Q3 2025 | MISP, abuse.ch |
| Configuration UI | Low | Q4 2025 | Web-based setup |

---

## 🤝 How to Contribute

This roadmap is community-driven. We welcome:

- **Documentation**: Share your deployment experiences, troubleshooting wins
- **Code**: Scripts, automation, integrations
- **Dashboards**: New visualizations, panel improvements
- **Testing**: Validate features, report issues, suggest improvements
- **Ideas**: Propose new features, vote on priorities

See [CONTRIBUTING.md](CONTRIBUTING.md) for detailed guidelines.

---

## 📊 Project Metrics

### Documentation Coverage
- ✅ **30+ guides** covering installation, configuration, troubleshooting
- ✅ **Architecture diagrams** (Mermaid + PNG)
- ✅ **Comprehensive index** for easy navigation
- 🚧 **Video tutorials** (planned)
- 🚧 **Interactive labs** (planned)

### Code & Automation
- ✅ **One-command installation** (`install.sh`)
- ✅ **Automated deployment** (`setup.sh`)
- ✅ **15+ operational scripts** (monitoring, recovery, validation)
- ✅ **SID management tools** (verification, optimization)
- 🚧 **Ansible playbooks** (planned)

### Community Engagement
- **GitHub Stars**: Track on [pfsense_grafana](https://github.com/ChiefGyk3D/pfsense_grafana)
- **Issues Resolved**: Tracking production deployment feedback
- **Contributors**: Open to community contributions

---

## 📝 Version History

### v2.0.0 (In Progress) - "Knowledge Base"
- Rebranded from "Grafana Dashboard" to "pfSense Knowledge Base"
- Added project status tracking (Complete, WIP, Planned)
- Comprehensive documentation overhaul
- SID management optimization (219 rules)
- Log rotation fix (inode-aware forwarder)
- Architecture diagram and visualization

### v1.2.0 - "SIEM Stack"
- Multi-interface Suricata monitoring
- GeoIP enrichment
- WAN security dashboard
- Automated SIEM installer
- Watchdog monitoring

### v1.0.0 - "Dashboard Fix"
- Initial Grafana dashboard
- Basic Suricata integration
- Single-interface monitoring

---

## 🔮 Future Considerations

Long-term ideas (no timeline, community-driven):
- Machine learning anomaly detection
- Mobile app for monitoring
- Multi-vendor firewall support (OPNsense, VyOS)
- Cloud deployment (AWS, Azure, GCP)
- Managed service offering

---

**Last Updated**: November 27, 2025  
**Maintainer**: [ChiefGyk3D](https://github.com/ChiefGyk3D)  
**License**: MPL 2.0
