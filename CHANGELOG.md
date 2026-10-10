# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Forwarder hardening (2026-10)

- **Fixed: the forwarder could stay dead for months.** After a pfSense upgrade the Python path baked into the rc.d unit can vanish, and the watchdog lived in root's crontab, which does not survive. The rc.d unit now falls back to the newest installed `python3.N` and warns if `maxminddb` is not importable.
- **Changed: watchdog is scheduled through the pfSense Cron package** (`scripts/pfsense-add-watchdog-cron.php`, entry kept in `config.xml`), not root's crontab. `status.sh` checks `/etc/crontab` accordingly.
- **Fixed: orphaned supervisors.** `stop` and `status` now find the forwarder by process, not only by pidfile, so a lost pidfile can no longer leave a `daemon` supervisor respawning an unmanaged forwarder that `status` reports as stopped.
- **New: `./setup.sh --forwarder-only`** redeploys just the forwarder, rc.d unit and watchdog, and verifies delivery from the pfSense side. It needs no access to OpenSearch, Logstash or Grafana from the workstation. Use it after a pfSense upgrade.

### SIEM freshness check (2026-10)

- **New: `scripts/check-siem-freshness.sh`** — exits non-zero when the newest Suricata event in OpenSearch is older than a threshold (default 15 min; `--via-pfsense` queries from the firewall when the workstation cannot reach OpenSearch). A dead forwarder, Logstash or OpenSearch went unnoticed for 2.5 months; this makes it a cron-able alarm. Exit codes: 0 fresh, 1 stale, 2 cannot query.

### Measured tuning results (2026-10)

- **New: [October 2026 Tuning Results](docs/pfsense/TUNING_RESULTS_2026-10.md)** — one table of before/after measurements from a real 1 Gbit/s cable migration (shaping, latency under load, Suricata CPU, rule volume, DNSBL, forwarder, feed health), plus what was applied but not isolated and what was not measured.
- **New in [Suricata Optimization Guide](docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md)**: measured inline-IPS capacity (UDP sweep to 950 Mbit/s), what cut CPU (parent BPF filter, `balanced` policy, removing duplicated IP-reputation rules), the TLS/stream bypass experiment (about a third less CPU for many short HTTPS connections, none for bulk downloads, reverted), the pfSense package's `encrypt-handling` versus Suricata's `encryption-handling` key mismatch, and scripting gotchas (`$rebuild_rules`, pass-throughs replace whole sections, stats need two flags).
- **New in [pfBlockerNG Optimization](docs/pfsense/PFBLOCKERNG_OPTIMIZATION.md)**: "Are the feeds themselves alive?" — placeholder-only tables, feeds that parse to 1 to 3 entries, repeated download failures, read-only commands to audit your own box, how to force a re-download after a URL change, and the measured Suricata/pfBlockerNG overlap.
- **Updated in [pfBlockerNG Feed Reference](docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md)**: abuse.ch SSLBL marked retired (last update 2025-01-02), ISC Shadowserver/Shodan URLs corrected to the `?text` form.
- **New in [Upgrading pfSense](docs/pfsense/PFSENSE_UPGRADE_GUIDE.md)**: a tuned-box checklist of what to capture before and compare after 2.9.0 (limiters, flow control, DNSBL VIP, feeds, Suricata instances and drops, forwarder, watchdog, Kea, gateways).


### pfSense shaping notes (2026-10)

- **New: [Shaping Optimization Notes](docs/pfsense/SHAPING_OPTIMIZATION_NOTES.md)** — measured lessons from moving to a 1 Gbit/s down, 500 Mbit/s up cable line: the upload limiter capping download, 50-slot child queues, the CoDel slot-limit trap, inverted per-host masks, failover-link shaping, dead ALTQ/wizard rules, resolver tuning, and the real-time/RTMP/default/bulk class design.
- **Corrected: [Traffic Shaping Guide](docs/pfsense/TRAFFIC_SHAPING_GUIDE.md)** — per-host mask direction was inverted (upload pipes key on source, download pipes on destination); added a corrections banner and the note that LAN-rule limiters do not see inbound port-forward traffic.
- **New in [pfBlockerNG Optimization](docs/pfsense/PFBLOCKERNG_OPTIMIZATION.md)**: how to measure the overlap between Suricata IP-reputation rules and pfBlockerNG lists, a three-command check that DNSBL is actually enforcing, and a troubleshooting entry for DNSBL silently stopping after a package upgrade (v3.2.14 stores the VIP as an ID in `pfb_dnsvip4`; the migration dropped it).
- **New in [Suricata Optimization Guide](docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md)**: how a legacy-mode instance on a VLAN trunk's parent interface duplicates inspection of every VLAN (measured +64% of a core versus +23% for the VLAN's own instance), and a BPF capture filter via the pass-through box that removed about 45 percent of total Suricata CPU with no inspection lost.
- **Corrected: [Upgrading pfSense](docs/pfsense/PFSENSE_UPGRADE_GUIDE.md)** — pfSense CE has no Boot Environments page in the GUI (Plus only); use `bectl create pre-2.9.0` from the shell. Added Part 3: what the official release notes confirm for 2.9.0, what is only reported, and what to re-test if you run limiters.

### Documentation overhaul (2026-09)

The docs tree was audited end to end against the code and reorganised into two tracks:
a **pfSense knowledge base** (`docs/pfsense/`, usable without the SIEM stack) and the
**SIEM stack** docs (install / operations / troubleshooting / reference). Highlights:

- **New: [Upgrading pfSense](docs/pfsense/PFSENSE_UPGRADE_GUIDE.md)** — general checklist plus 2.8.1 → 2.9.0 specifics (FreeBSD 16-CURRENT, PHP 8.5, sshd algorithm removals, TLS certificate enforcement, the Telegraf package `ssl_ca`/`fielddrop` breakage and workaround, `pkg bootstrap -f`), a table of every file this stack places on pfSense and whether it survives, and the post-upgrade `preflight.sh → setup.sh → status.sh` procedure
- **New: [Telegraf on pfSense](docs/pfsense/TELEGRAF_ON_PFSENSE.md)** — from-scratch guide that replaces `TELEGRAF_RESTART_PROCEDURE.md`, `PF_INFORMATION_PANEL_ISSUE.md` and the Telegraf half of `SETUP_FILTERLOG_MONITORING_CRON.md`; resolves the contradictory "should Telegraf run as root" advice (yes, by design)
- **New: [Field Reference](docs/reference/FIELD_REFERENCE.md)** — the authoritative flat schema for `suricata-*` and `pfblockerng-*`; ~120 stale `suricata.eve.*` references were corrected across the docs
- **New: [dashboards/README.md](dashboards/README.md)** — inventory of all 11 dashboard files, their UIDs, datasources and import method (notes that `suricata_ids_ips_active.json` shares a UID with `Suricata_IDS_IPS.json`)
- **README** cut from ~1000 to ~270 lines; duplicated directory tree, troubleshooting and documentation lists removed; status table now says Wazuh dashboards ship and Graylog is shelved (they were still marked "planned")
- **Merged/removed duplicates**: `FORWARDER_MONITORING_QUICK_REF.md` → `SURICATA_FORWARDER_MONITORING.md` (rewritten around the rc.d service); `SETUP_FILTERLOG_MONITORING_CRON.md` → `PFSENSE_FILTERLOG_ROTATION_FIX.md`; `docs/reference/SCRIPTS_REFERENCE.md` → `scripts/README.md` (now covers all 20 scripts and marks legacy ones); `config/sid/APPLYING_CHANGES.md` → `config/sid/README.md`; `TELEGRAF_INTERFACE_FIXES.md` → a section of `INSTALL_DASHBOARD.md`; `config/pfblockerng_optimization.md` moved to `docs/pfsense/PFBLOCKERNG_FEED_REFERENCE.md`
- **Corrected**: repo URL (`pfsense_siem_stack` → `pfsense-siem-stack`), `CONTRIBUTING.md` (PRs target `main`, CI documented, `/bin/sh` for pfSense scripts), OpenSearch install paths (`/opt/opensearch`), the false "OpenSearch bound to localhost" security claim, the management console's non-existent "Telegram alerts" feature, ILM → ISM, retention defaults, watchdog interval, SID counts (218 disabled / 2 suppressed), stream memcap and hardware examples that contradicted each other, personal IPs/hostnames/interface names replaced with placeholders, all "Last Updated: 2025" stamps
- Architecture diagram regenerated (no longer shows nested `suricata.eve.*` or a Logstash → InfluxDB path)

### Changed
- **Releases are now tagged.** `scripts/release.sh X.Y.Z` rolls the changelog, bumps `VERSION`, tags `vX.Y.Z`; pushing the tag publishes a GitHub Release with a source tarball and `SHA256SUMS` (`.github/workflows/release.yml`). This overhaul ships as **2.0.0** because the forwarder service was renamed.
- **`install.sh` is now the manual/bare-metal path, not the flagship.** The recommended server side is [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack) or any existing OpenSearch + Grafana; `setup.sh` only needs their addresses. README, Quick Start and the docs index present it that way.
- **BREAKING: forwarder service renamed** `suricata_forwarder` → `suricata_forwarder.sh` (`service suricata_forwarder.sh …`). `setup.sh` migrates a deployed box automatically; update any of your own scripts or cron jobs that referenced the old name.

### Fixed
- **setup.sh: rc.d service was never started at boot.** pfSense only runs `/usr/local/etc/rc.d/*.sh` at boot (rc.start_packages); the unit was installed as `suricata_forwarder` without the suffix, so boot persistence silently relied on the cron watchdog. Now installs `suricata_forwarder.sh`, removes the old file, and enables itself by default instead of depending on `/etc/rc.conf` (which pfSense does not manage). Service commands are now `service suricata_forwarder.sh start|stop|restart|status`.
- **setup.sh: rc.d hardcoded `python3.11`** as `command_interpreter` even though the interpreter was detected; now uses the detected path and refuses to start with a clear message if it disappears (e.g. after a pfSense upgrade). Detection prefers the version-neutral `/usr/local/bin/python3` and probes 3.13/3.12/3.11.
- **setup.sh: `service … stop` did not stop the forwarder** — `daemon -r` respawned the child. Now tracks supervisor and child PID files and stops both.
- **setup.sh: watchdog restarted with `nohup`** bypassing the service; now restarts through the rc.d script. The shipped `scripts/suricata-forwarder-watchdog.sh` is now identical to the generated one and no longer uses `killall python3.11`.
- `scripts/check-telegram-alerts.sh` reads `PFSENSE_HOST`/`PFSENSE_USER` from `config.env` instead of `ssh root@192.168.1.1`.
- `pfsense-siem` health check no longer requires exactly `python3.11`.

### Added
- **GitHub wiki, generated from the docs.** `scripts/build-wiki.py` turns every Markdown file in the repository into a wiki page (links rewritten, images copied, source file named on each page) and `.github/workflows/wiki.yml` publishes the result to the project wiki on every push to `main`. Hand-written landing pages in `wiki/`: Home, sidebar, footer, **[New to pfSense? Start Here](wiki/New-to-pfSense-Start-Here.md)** (the pieces, a reading order, the things that bite newcomers), a **[Glossary](wiki/Glossary.md)** and an **[FAQ](wiki/FAQ.md)**. CI runs the build so a doc without a page mapping or with a broken link fails the pull request.
- **Wazuh Security Overview dashboard** (`dashboards/wazuh/wazuh_security_overview.json`) — 20 panels: alert stats, MITRE ATT&CK, compliance (PCI DSS, NIST, HIPAA), auth success/failure tracking, hourly alert trend by agent, recent high-level alerts
- **Wazuh Vulnerability Detection dashboard** (`dashboards/wazuh/wazuh_vulnerability_detection.json`) — 11 panels: CVE tracking, severity distribution, vulnerable packages, severity by agent cross-reference
- **Wazuh File Integrity Monitoring dashboard** (`dashboards/wazuh/wazuh_file_integrity_monitoring.json`) — 11 panels: file change tracking (added/modified/deleted), per-agent breakdown, multi-terms detail view
- **Prometheus Stats dashboard** (`dashboards/prometheus_stats.json`) — 17 panels: TSDB internals, scrape target health, rule evaluation, WAL, memory — rebuilt for Prometheus 2.x metrics
- **Docker Container Monitoring dashboard** (`dashboards/docker_container_monitoring.json`) — 15 panels: container CPU, memory, network I/O, filesystem via cAdvisor + Prometheus
- **Suricata IDS/IPS Active dashboard** (`dashboards/suricata_ids_ips_active.json`) — 14 panels: current production Suricata dashboard export
- **Datasource reference** (`dashboards/datasources_reference.json`) — All 8 Grafana datasource configurations with UIDs for reproducibility
- **Wazuh dashboard deployment script** (`scripts/deploy-wazuh-dashboards.py`) — Standalone Python script that configures the OpenSearch-Wazuh datasource, creates folders, deploys all 3 Wazuh dashboards, and verifies data flow via API queries
- **Wazuh dashboard README** (`dashboards/wazuh/README.md`) — Panel inventory, datasource configuration, import instructions, field reference
- **[New User Checklist](docs/install/NEW_USER_CHECKLIST.md)**: Complete step-by-step installation and validation checklist
- **[Suricata Optimization Guide](docs/pfsense/SURICATA_OPTIMIZATION_GUIDE.md)**: Comprehensive guide for rule selection, IDS vs IPS configuration, performance tuning, and log management
- **[Documentation Index](docs/DOCUMENTATION_INDEX.md)**: Organized guide to all documentation with quick search functionality
- **[Forwarder Monitoring Guide](docs/operations/SURICATA_FORWARDER_MONITORING.md)**: Three monitoring strategies with hybrid approach (crash recovery + activity monitoring)
- **Forwarder Monitoring Quick Reference (since merged into `docs/operations/SURICATA_FORWARDER_MONITORING.md`)**: One-liner commands for common monitoring tasks
- **[MAC Vendor Lookup Setup](docs/pfsense/MAC_VENDOR_LOOKUP_SETUP.md)**: Custom Telegraf plugin for MAC vendor identification via ARP table
- **Automated forwarder monitoring setup script** (`scripts/setup_forwarder_monitoring.sh`)
- **Interactive monitoring installer** with 6 preset configurations

### Enhanced
- **README.md**: Added links to new optimization guide and user checklist
- **Forwarder monitoring**: Hybrid approach combining crash recovery (every 5 min) with activity monitoring (every 15 min during business hours)
- **Status script**: Now checks for watchdog/monitoring cron installation

### Fixed
- **setup.sh: Missing pfBlockerNG index template application** — `setup.sh` Step 2 only applied the Suricata index template, not the pfBlockerNG template. Without the pfBlockerNG template, `tag.*` fields (e.g., `tag.src_ip`, `tag.tld`, `tag.feed_name`) are mapped as `text` instead of `keyword`, causing Grafana aggregation errors: "Text fields are not optimised for operations that require per-document field data like aggregations and sorting". Now applies both templates during setup.
- **setup.sh: auto-create index missing pfblockerng-*** — The `action.auto_create_index` cluster setting didn't include `pfblockerng-*`, potentially preventing Telegraf from creating daily pfBlockerNG indices. Now includes `pfblockerng-*` in the auto-create whitelist.
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

### From 1.2.0 to 2.0.0

**Breaking change:** the pfSense rc.d service is now `/usr/local/etc/rc.d/suricata_forwarder.sh`
(`service suricata_forwarder.sh start|stop|restart|status`). The old extension-less unit was
never started by pfSense at boot.

**Migration:** `git pull` (or unpack the 2.0.0 tarball), then `./setup.sh`. It redeploys the
forwarder with the detected Python interpreter, installs the new rc.d script, removes the old
one, reinstalls the watchdog and re-applies index templates. Nothing changes on the SIEM
server side unless you also upgraded OpenSearch/Logstash/Grafana. Docs moved: see
[docs/DOCUMENTATION_INDEX.md](docs/DOCUMENTATION_INDEX.md); superseded pages are listed in the
2.0.0 changelog entry above.

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

Future plans live in [ROADMAP.md](ROADMAP.md) — the version-numbered roadmap that used to live here was merged into it (2026-08-29) so the project has a single plan.

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

This project is licensed under the Mozilla Public License 2.0 - see [LICENSE](LICENSE) file.

---

## Support

- **Documentation**: [docs/DOCUMENTATION_INDEX.md](docs/DOCUMENTATION_INDEX.md)
- **Issues**: [GitHub Issues](https://github.com/ChiefGyk3D/pfsense-siem-stack/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions)

**Made with ❤️ for the pfSense community**
