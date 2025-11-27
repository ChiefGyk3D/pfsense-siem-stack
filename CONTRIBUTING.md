# Contributing to pfSense Knowledge Base

> **Help build the pfSense community knowledge repository**

Thank you for considering contributing! This project has evolved from a simple dashboard into a comprehensive pfSense knowledge base. Whether you're sharing configuration tips, automation scripts, troubleshooting solutions, or documentation improvements, your contributions are valued.

---

## 📚 What We're Building

This is not just a monitoring stack—it's a **knowledge repository** covering:

- **SIEM & Logging**: OpenSearch, Logstash, Grafana, log forwarding
- **Security**: IDS/IPS tuning, signature management, threat intelligence
- **Network Monitoring**: Multi-WAN, VLAN segmentation, traffic analysis
- **Automation**: Scripts, watchdogs, recovery procedures, deployment tools
- **Operations**: Configuration management, troubleshooting, best practices
- **Hardware & Performance**: Tuning guides, benchmarks, optimization strategies

---

## 🎯 Ways to Contribute

### 🔥 High Priority

#### 1. Documentation & Knowledge Sharing
- **Troubleshooting scenarios** you've encountered and solved
- **Configuration examples** from your production deployments
- **Performance tuning** lessons learned
- **Hardware recommendations** based on your experience
- **Video tutorials** or screen recordings
- **Architecture diagrams** for different use cases
- **Comparison guides** (e.g., Suricata vs Snort, inline vs passive)

#### 2. SIEM & Logging (🚧 Active Development)
- **LAN monitoring dashboard** - East-west traffic visualization
- **Additional log parsers** - pfSense filterlog, HAProxy, Unbound, DHCP
- **Alert rules** - Pre-configured detection rules with documentation
- **Index optimization** - Performance tuning for large deployments
- **Retention strategies** - Cost-effective storage management

#### 3. Security Enhancements
- **Signature tuning guides** - SID management strategies
- **Threat intelligence integration** - MISP, abuse.ch, OTX feeds
- **Blocklist optimization** - pfBlockerNG configuration best practices
- **False positive documentation** - Known FPs and suppression strategies

#### 4. Automation & Orchestration
- **Ansible playbooks** - Automated deployment and configuration
- **Monitoring scripts** - Health checks, alerting, recovery procedures
- **Configuration management** - Version control for pfSense configs
- **Backup/restore procedures** - Disaster recovery documentation

### Medium Priority
- **Deployment Options**
  - Docker/Docker Compose setup
  - Ansible playbooks
  - Kubernetes manifests
  - All-in-one installer scripts

- **Additional Integrations**
  - Zeek (formerly Bro) IDS
  - Snort3 native support
  - pfSense DHCP logs
  - VPN logs (OpenVPN, Wireguard, IPsec)

- **Testing & Validation**
  - Automated test suites
  - CI/CD pipelines
  - Performance benchmarks
  - Security hardening tests

### Low Priority
- **Aesthetic Improvements**
  - Grafana theme customizations
  - Logo and branding
  - Dashboard layout refinements

---

## 🚀 Getting Started

### 1. Fork and Clone

```bash
# Fork this repository on GitHub, then:
git clone https://github.com/<your-username>/pfsense_grafana.git
cd pfsense_grafana
git remote add upstream https://github.com/ChiefGyk3D/pfsense_grafana.git
```

### 2. Set Up Development Environment

**SIEM Server** (for testing):
```bash
# Install SIEM stack
sudo ./install.sh

# Configure for testing
cp config.env.example config.env
nano config.env  # Set your test pfSense IP
```

**pfSense Test Instance** (recommended):
- Use a spare pfSense box or VM
- Install Suricata package
- Configure SSH access
- Run in a lab/test network (not production!)

### 3. Create a Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/issue-description
```

---

## 📝 Contribution Guidelines

### Code Style

**Python (forwarders, scripts):**
- Follow PEP 8
- Use descriptive variable names
- Add docstrings to functions
- Include inline comments for complex logic

**Bash (watchdogs, helpers):**
- Use `#!/usr/bin/env bash` shebang
- Include error handling (`set -euo pipefail` where appropriate)
- Add help text for user-facing scripts
- Quote variables to prevent word splitting

**Grafana Dashboards (JSON):**
- Indent with 2 spaces
- Use descriptive panel titles
- Add panel descriptions explaining queries
- Test on Grafana 12.x

**Documentation (Markdown):**
- Use headers for structure
- Include code examples with syntax highlighting
- Add screenshots where helpful
- Keep line length reasonable (80-120 chars)

### Commit Messages

**Format:**
```
<type>(<scope>): <short description>

<longer description if needed>

Fixes #<issue-number>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring
- `perf`: Performance improvements
- `test`: Adding tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(dashboard): Add pfBlockerNG statistics panel

Added new panel showing top blocked domains and IPs from pfBlockerNG logs.
Includes pie chart for block reasons and time series for block rate.

Fixes #42
```

```
fix(forwarder): Handle log rotation on FreeBSD 14+

FreeBSD 14 changed inode behavior during log rotation. Updated forwarder
to check file modification time in addition to inode number.

Fixes #87
```

### Pull Request Process

1. **Test your changes**
   - Verify forwarder works on pfSense
   - Test dashboard loads in Grafana
   - Run `./scripts/status.sh` to validate
   - Check for broken links in docs

2. **Update documentation**
   - Add/update README if adding features
   - Update relevant docs in `docs/`
   - Add inline comments to code
   - Update CHANGELOG.md

3. **Submit PR**
   - Push to your fork
   - Open PR against `overhaul` branch (not `main`)
   - Fill out PR template
   - Link related issues

4. **Code review**
   - Address reviewer feedback
   - Keep PR scope focused (one feature/fix per PR)
   - Be patient — reviews may take a few days

---

## 🧪 Testing

### Manual Testing Checklist

**For Forwarder Changes:**
- [ ] Deploy to test pfSense: `scp scripts/forward-suricata-eve.py root@<pfsense>:/usr/local/bin/`
- [ ] Restart forwarder: `ssh root@<pfsense> "pkill -f forward-suricata-eve.py && nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &"`
- [ ] Check debug log: `ssh root@<pfsense> "tail -f /var/log/suricata_forwarder_debug.log"`
- [ ] Verify data in OpenSearch: `curl -s http://localhost:9200/suricata-*/_count`
- [ ] Test log rotation: Manually rotate logs and verify forwarder reopens files

**For Dashboard Changes:**
- [ ] Import into Grafana (don't overwrite production!)
- [ ] Test all panels load without errors
- [ ] Verify queries return data
- [ ] Test time range selector
- [ ] Check variable dropdowns work
- [ ] Export and validate JSON format

**For Documentation Changes:**
- [ ] Check Markdown rendering (use GitHub preview)
- [ ] Verify all links work
- [ ] Test code examples in a shell
- [ ] Proofread for typos/grammar

---

## 📚 Documentation Standards

### New Feature Documentation

When adding a feature, include:

1. **Overview** - What it does, why it's useful
2. **Prerequisites** - Requirements, dependencies
3. **Installation** - Step-by-step deployment
4. **Configuration** - Options, examples
5. **Usage** - How to use the feature
6. **Troubleshooting** - Common issues, fixes
7. **Examples** - Real-world use cases

### File Organization

- **docs/**: Detailed guides (installation, config, troubleshooting)
- **scripts/README.md**: Script usage and examples
- **README.md**: Project overview and quick start
- **QUICK_START.md**: 15-minute getting started guide

---

## 🐛 Reporting Bugs

### Before Submitting

1. Check [existing issues](https://github.com/ChiefGyk3D/pfsense_grafana/issues)
2. Run `./scripts/status.sh` and include output
3. Check logs:
   - OpenSearch: `/var/log/opensearch/opensearch.log`
   - Logstash: `/var/log/logstash/logstash-plain.log`
   - Forwarder: `/var/log/suricata_forwarder_debug.log` (on pfSense)

### Bug Report Template

```markdown
**Describe the bug**
Clear description of the issue.

**To Reproduce**
Steps to reproduce:
1. Go to '...'
2. Click on '...'
3. See error

**Expected behavior**
What you expected to happen.

**Environment:**
- pfSense version: [e.g., 2.8.1]
- Suricata version: [e.g., 7.0.7]
- SIEM server OS: [e.g., Ubuntu 24.04]
- OpenSearch version: [e.g., 2.18.0]
- Grafana version: [e.g., 12.3.0]

**Logs**
Paste relevant log snippets (use code blocks).

**Screenshots**
If applicable, add screenshots.
```

---

## 💡 Feature Requests

### Submitting Ideas

Use [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense_grafana/discussions) for:
- Feature ideas
- Architecture discussions
- Use case questions

Use [GitHub Issues](https://github.com/ChiefGyk3D/pfsense_grafana/issues) for:
- Concrete feature requests with implementation plan
- Bugs and fixes

### Feature Request Template

```markdown
**Is your feature related to a problem?**
Clear description of the problem or use case.

**Describe the solution**
What you'd like to happen.

**Describe alternatives**
Other approaches you've considered.

**Implementation notes**
How might this be implemented? (optional)

**Additional context**
Screenshots, diagrams, links to similar projects.
```

---

## 🤝 Community

- **GitHub Discussions**: Ask questions, share setups
- **GitHub Issues**: Report bugs, request features
- **Pull Requests**: Contribute code, docs, dashboards

---

## 📜 License

By contributing, you agree that your contributions will be licensed under the MPL 2.0 License.

---

## 🙏 Thank You!

Every contribution helps make this project better for the pfSense and open-source security community. Whether it's code, docs, bug reports, or feature ideas — thank you for your time and effort!

**Happy hacking! 🚀**
