# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **[New User Checklist](docs/NEW_USER_CHECKLIST.md)**: Complete step-by-step installation and validation checklist
- **[Suricata Optimization Guide](docs/SURICATA_OPTIMIZATION_GUIDE.md)**: Comprehensive guide for rule selection, IDS vs IPS configuration, performance tuning, and log management
- **[Documentation Index](docs/DOCUMENTATION_INDEX.md)**: Organized guide to all documentation with quick search functionality
- **[Forwarder Monitoring Guide](docs/SURICATA_FORWARDER_MONITORING.md)**: Three monitoring strategies with hybrid approach (crash recovery + activity monitoring)
- **[Forwarder Monitoring Quick Reference](docs/FORWARDER_MONITORING_QUICK_REF.md)**: One-liner commands for common monitoring tasks
- **[MAC Vendor Lookup Setup](docs/MAC_VENDOR_LOOKUP_SETUP.md)**: Custom Telegraf plugin for MAC vendor identification via ARP table
- **Automated forwarder monitoring setup script** (`scripts/setup_forwarder_monitoring.sh`)
- **Interactive monitoring installer** with 6 preset configurations

### Enhanced
- **README.md**: Added links to new optimization guide and user checklist
- **Forwarder monitoring**: Hybrid approach combining crash recovery (every 5 min) with activity monitoring (every 15 min during business hours)
- **Status script**: Now checks for watchdog/monitoring cron installation

### Fixed
- **Documented Telegraf restart procedure**: Proper method using `/usr/local/etc/rc.d/telegraf.sh` on pfSense
- **Forwarder restart after Suricata restart**: Documented need to restart forwarder when Suricata creates new log files
- **Permission issues**: Clarified that Telegraf runs as root by design on pfSense

### Documentation Updates
- Added Suricata ruleset recommendations (44 ET categories + 46 Snort rules)
- Documented inline mode vs legacy mode trade-offs
- Added IDS vs IPS configuration guidance
- Created comprehensive log retention strategies
- Documented QUIC protocol handling
- Added performance benchmarks from real deployment

## [1.2.0] - 2024-11-24

### Added
- **One-command setup**: `./setup.sh` automates entire configuration
- **Comprehensive status check**: `./scripts/status.sh` validates all components
- **Automated SIEM installer**: `./install.sh` installs OpenSearch, Logstash, Grafana
- **Multi-interface support**: Python forwarder automatically detects all Suricata instances
- **GeoIP enrichment**: City-level geolocation for attack sources
- **Interactive world map**: Geohash clustering of attack sources
- **WAN-side dashboard**: Focus on external threats and inbound attacks

### Changed
- Migrated from manual configuration to automated setup scripts
- Moved from shell forwarder to Python with better error handling
- Updated to OpenSearch 2.x (from Elasticsearch)
- Updated to Grafana 12.x
- Simplified installation to 4 steps from 12+

### Fixed
- **Midnight UTC data stoppage**: Automatic index creation configured
- **Multiple forwarder instances**: Setup script ensures single clean instance
- **Missing geo_point mapping**: Index template properly configures geolocation
- **Incomplete documentation**: Comprehensive guides for all features

## [1.1.0] - 2024-08

### Added
- OpenSearch compatibility (alternative to Elasticsearch)
- Logstash 8.x support
- Custom field mapping for Suricata events
- Retention policy configuration script

### Changed
- Updated Grafana dashboard for OpenSearch data source
- Improved panel queries for better performance
- Enhanced alert table with more details

### Fixed
- Field name conflicts between Logstash and OpenSearch
- GeoIP mapping issues
- Performance problems with large datasets

## [1.0.0] - 2024-06

### Added
- Initial release
- Suricata IDS/IPS dashboard for Grafana
- Basic log forwarding from pfSense to Elasticsearch
- GeoIP visualization
- Alert statistics and trending
- Top signatures panel
- HTTP traffic analysis

### Components
- Elasticsearch 7.x
- Logstash 7.x
- Grafana 9.x
- Shell-based log forwarder

---

## Version History Summary

| Version | Date       | Key Features |
|---------|------------|--------------|
| 1.2.0   | 2024-11-24 | Automated setup, multi-interface, Python forwarder, OpenSearch 2.x |
| 1.1.0   | 2024-08    | OpenSearch support, Logstash 8.x, improved mapping |
| 1.0.0   | 2024-06    | Initial release with basic Suricata dashboard |

---

## Upgrade Notes

### From 1.1.0 to 1.2.0

**Breaking Changes:**
- Forwarder moved from shell script to Python (automatic migration)
- Configuration now uses `config.env` instead of hardcoded values

**Migration Steps:**
1. Create `config.env` from `config.env.example`
2. Run `./setup.sh` to deploy new forwarder
3. Old forwarder will be automatically replaced
4. Verify with `./scripts/status.sh`

**Benefits:**
- Automatic multi-interface detection
- Better error handling
- Monitoring and auto-restart capabilities
- Simplified configuration management

### From 1.0.0 to 1.2.0

**Major Changes:**
- Elasticsearch → OpenSearch
- Grafana 9.x → 12.x
- Manual setup → Automated scripts

**Migration Steps:**
1. Backup existing Grafana dashboards
2. Install new SIEM stack: `sudo ./install.sh`
3. Create `config.env` with your settings
4. Run `./setup.sh` for automated configuration
5. Re-import dashboard from `dashboards/` directory
6. Verify all panels working with `./scripts/status.sh`

**Data Migration:**
- OpenSearch can coexist with Elasticsearch
- Historical data can remain in Elasticsearch
- New data flows to OpenSearch indices
- Update Grafana data source to point to OpenSearch

---

## Roadmap

### Planned Features

**v1.3.0 (Q1 2025)**
- [ ] LAN-side dashboard for internal traffic analysis
- [ ] RFC1918 filtering for internal monitoring
- [ ] Lateral movement detection
- [ ] Internal host activity tracking
- [ ] Alert severity customization
- [ ] Email alerting integration

**v1.4.0 (Q2 2025)**
- [ ] Machine learning anomaly detection
- [ ] Threat intelligence feed integration
- [ ] Custom rule management UI
- [ ] Performance optimization wizard
- [ ] HA/clustering support for SIEM stack
- [ ] Backup/restore automation

**v2.0.0 (Q3 2025)**
- [ ] pfSense plugin package
- [ ] Web-based configuration UI
- [ ] Multi-tenancy support
- [ ] Role-based access control
- [ ] API for programmatic access
- [ ] Mobile-responsive dashboard

### Community Requests

Vote for features on GitHub Discussions! Top requested:
- [ ] Telegram/Slack notification integration
- [ ] pfBlocker and Suricata correlation dashboard
- [ ] DNS query analysis (via Unbound logs)
- [ ] SSL/TLS certificate monitoring
- [ ] Automated report generation
- [ ] Docker deployment option

---

## Contributing

We welcome contributions! See key areas:

**Documentation:**
- Improve existing guides
- Add troubleshooting scenarios
- Translate to other languages
- Create video tutorials

**Features:**
- New dashboard panels
- Additional monitoring scripts
- Integration with other tools
- Performance optimizations

**Testing:**
- Test on different pfSense versions
- Validate with various hardware
- Report compatibility issues
- Provide feedback on usability

**Community:**
- Answer questions in Discussions
- Share your configurations
- Write blog posts
- Create case studies

---

## Acknowledgments

### Contributors
- **ChiefGyk3D**: Project maintainer and primary developer
- **Community Contributors**: Feature requests, bug reports, and testing
- **Early Adopters**: Feedback and real-world validation

### Technologies
- **Suricata**: OISF (Open Information Security Foundation)
- **pfSense**: Netgate and community
- **OpenSearch**: Amazon and OpenSearch Project
- **Grafana**: Grafana Labs
- **Python**: Python Software Foundation

### Inspiration
- Original pfSense Telegraf dashboards
- Unifi Poller project (data collection patterns)
- Security Onion (SIEM architecture ideas)
- Various community contributions on pfSense forums

---

## License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file.

---

## Support

- **Documentation**: [docs/DOCUMENTATION_INDEX.md](docs/DOCUMENTATION_INDEX.md)
- **Issues**: [GitHub Issues](https://github.com/ChiefGyk3D/pfsense_grafana/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense_grafana/discussions)
- **Email**: (Add if you want direct contact)

**Made with ❤️ for the pfSense community**
