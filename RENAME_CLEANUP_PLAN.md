# Project Rename & Cleanup Plan

> **Recommendation**: Rename to `pfsense-siem-stack`  
> **Status**: Ready for implementation  
> **Impact**: Minimal (GitHub auto-redirects)

---

## 📛 Recommended Name: pfsense-siem-stack

### Why This Name?

✅ **Accurate** - Describes pfSense + SIEM focus  
✅ **Technology Agnostic** - Works with OpenSearch, Graylog, Wazuh, Splunk  
✅ **SEO-Friendly** - "pfsense siem" is high-volume search term  
✅ **Professional** - Industry-standard naming convention  
✅ **Future-Proof** - Room for multiple SIEM backends without rename

### Alternative Options Considered

| Name | Pros | Cons | Score |
|------|------|------|-------|
| **pfsense-siem-stack** ⭐ | Clear focus, technology agnostic, great SEO | None | 10/10 |
| pfsense-security-stack | Broader scope, room for expansion | May dilute SIEM focus | 8/10 |
| pfsense-monitoring-stack | Observability angle, DevOps appeal | Less security-focused | 7/10 |
| pfsense-operations | Very broad | Too generic | 5/10 |

---

## 🗑️ Files to Delete (Immediate Cleanup)

### Obsolete Backup Files

```bash
# Delete old README backups
rm -f docs/archive/old_readmes/README.md.old
rm -f docs/archive/README.md.backup

# Verify no other backups exist
find . -type f \( -name "*.backup" -o -name "*.old" -o -name "*~" \) -not -path "./.git/*"
```

**Reason**: These are superseded by current documentation and provide no historical value.

---

## 📁 Directory Reorganization (Future)

### Current Structure
```
docs/
├── DOCUMENTATION_INDEX.md
├── HARDWARE_REQUIREMENTS.md
├── SURICATA_CONFIGURATION.md
├── INSTALL_SIEM_STACK.md
├── TROUBLESHOOTING.md
├── archive/
│   ├── GRAYLOG_INDEX.md
│   └── GRAYLOG_SURICATA_SETUP.md
└── ...
```

### Recommended Future Structure
```
docs/
├── DOCUMENTATION_INDEX.md
├── HARDWARE_REQUIREMENTS.md
├── SURICATA_CONFIGURATION.md
├── siem/
│   ├── COMPARISON.md              (NEW - compare all SIEM options)
│   ├── opensearch/                (MOVE current docs here)
│   │   ├── README.md
│   │   ├── INSTALL.md
│   │   ├── OPTIMIZATION.md
│   │   ├── TROUBLESHOOTING.md
│   │   └── RETENTION.md
│   ├── graylog/                   (NEW - placeholder for planned)
│   │   ├── README.md              (Coming Soon notice)
│   │   └── MIGRATION.md           (from OpenSearch)
│   └── wazuh/                     (NEW - placeholder for planned)
│       ├── README.md              (Coming Soon notice)
│       └── COMPARISON.md          (vs OpenSearch/Graylog)
└── integrations/
    ├── README.md                   (Overview of all integrations)
    ├── ntopng/
    ├── telegraf/
    └── pfblockerng/
```

**Note**: This reorganization is optional and can be done incrementally as Graylog/Wazuh support is added.

---

## 🔄 Migration Steps

### Step 1: Cleanup Obsolete Files (Now)

```bash
cd /home/chiefgyk3d/src/Grafana_Dashboards

# Delete backup files
rm -f docs/archive/old_readmes/README.md.old
rm -f docs/archive/README.md.backup

# Verify cleanup
git status
```

### Step 2: Create Placeholder Docs (Optional - Now or Later)

```bash
# Create SIEM comparison placeholder
mkdir -p docs/siem
cat > docs/siem/COMPARISON.md << 'EOF'
# SIEM Backend Comparison

> **Status**: 🚧 Work in Progress

Comparison of different SIEM backends for pfSense integration.

## Supported Backends

### OpenSearch (Current - Production Ready)
- **Status**: ✅ Fully implemented and documented
- **Documentation**: See main docs
- **Recommended For**: Most users, open-source preference

### Graylog (Planned)
- **Status**: 📝 Coming Soon
- **ETA**: TBD
- **Recommended For**: Graylog fans, existing Graylog infrastructure

### Wazuh (Planned)
- **Status**: 📝 Coming Soon
- **ETA**: TBD
- **Recommended For**: EDR integration, compliance requirements

## Feature Matrix

| Feature | OpenSearch | Graylog | Wazuh |
|---------|------------|---------|-------|
| Status | ✅ Production | 📝 Planned | 📝 Planned |
| Free/Open Source | ✅ | ✅ | ✅ |
| Resource Usage | Medium | Medium | Medium-High |
| Ease of Setup | Medium | Easy | Hard |
| Grafana Integration | Excellent | Good | Good |
| Alert Management | Good | Excellent | Excellent |

---

**Want to contribute?** Help us add Graylog or Wazuh support! See [CONTRIBUTING.md](../../CONTRIBUTING.md)
EOF

# Create Graylog placeholder
mkdir -p docs/siem/graylog
cat > docs/siem/graylog/README.md << 'EOF'
# Graylog Integration

> **Status**: 📝 Planned - Coming Soon

Graylog integration for pfSense Suricata log analysis.

## Why Graylog?

- Easier initial setup than OpenSearch
- Excellent web UI out of the box
- Strong alerting capabilities
- Good community support

## Planned Features

- [ ] Graylog installation guide
- [ ] Suricata input configuration
- [ ] Content packs for pfSense/Suricata
- [ ] Dashboard examples
- [ ] Migration guide from OpenSearch

## Current Status

Graylog support is planned but not yet implemented. The existing OpenSearch 
implementation works well, but we recognize many users prefer Graylog's 
ease of use.

**Want to help?** Check our archived Graylog docs in `docs/archive/` or 
contribute new content! See [CONTRIBUTING.md](../../CONTRIBUTING.md)

## Migration from OpenSearch

Coming soon: Step-by-step guide to migrate from OpenSearch to Graylog while 
preserving historical data.
EOF

# Create Wazuh placeholder
mkdir -p docs/siem/wazuh
cat > docs/siem/wazuh/README.md << 'EOF'
# Wazuh Integration

> **Status**: 📝 Planned - Long-term Roadmap

Wazuh EDR/XDR integration for pfSense with Suricata log analysis.

## Why Wazuh?

- Endpoint detection and response (EDR) capabilities
- Compliance reporting (PCI-DSS, HIPAA, etc.)
- Active response and remediation
- Open-source XDR platform

## Planned Features

- [ ] Wazuh installation guide
- [ ] pfSense agent deployment (if applicable)
- [ ] Suricata log integration
- [ ] Custom rules and decoders
- [ ] Dashboard examples
- [ ] Compliance reporting templates

## Current Status

Wazuh support is on the long-term roadmap. It offers advanced EDR capabilities 
beyond what OpenSearch provides, making it ideal for environments with compliance 
requirements.

**Interest in Wazuh?** Let us know in [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions) 
to help prioritize this integration!

## Use Cases

- **Compliance**: PCI-DSS, HIPAA, GDPR reporting
- **EDR**: Endpoint threat detection beyond network monitoring
- **Active Response**: Automated remediation actions
- **Multi-System**: Correlate pfSense + servers + workstations
EOF

echo "✅ Placeholder docs created!"
```

### Step 3: Rename Repository (GitHub Web UI)

1. Go to: https://github.com/ChiefGyk3D/pfsense_grafana/settings
2. Scroll to **Repository name**
3. Change `pfsense_grafana` → `pfsense-siem-stack`
4. Click **Rename**

**GitHub automatically redirects** old URLs, so no broken links!

### Step 4: Update Local Repository

```bash
cd /home/chiefgyk3d/src/Grafana_Dashboards

# Update remote URL
git remote set-url origin https://github.com/ChiefGyk3D/pfsense-siem-stack.git

# Verify
git remote -v

# Optional: Rename local directory to match
cd ..
mv Grafana_Dashboards pfsense-siem-stack
cd pfsense-siem-stack
```

### Step 5: Update Documentation

Update references in these files:

**README.md**:
```bash
# Change title
"pfSense Knowledge Base & Infrastructure" 
→ 
"pfSense SIEM Stack"

# Update subtitle
"Comprehensive pfSense deployment, monitoring, and security knowledge base"
→
"Complete SIEM infrastructure for pfSense firewalls — Multi-backend support for OpenSearch, Graylog, and Wazuh"

# Add multi-SIEM notice
> 🎯 **Multi-SIEM Support**: Choose your SIEM backend — OpenSearch (current), 
> Graylog (planned), Wazuh (planned) — with unified pfSense integration.
```

**CONTRIBUTING.md**:
- Update repo URL references
- Update clone commands

**ROADMAP.md**:
- Add Graylog integration milestone
- Add Wazuh integration milestone

### Step 6: Update GitHub Repository Settings

1. **Description**: "Complete SIEM infrastructure for pfSense - OpenSearch, Graylog, Wazuh support with Suricata IDS/IPS monitoring"

2. **Topics/Tags**:
   - pfsense
   - suricata
   - siem
   - opensearch
   - security-monitoring
   - ids-ips
   - network-security
   - grafana
   - logstash
   - graylog
   - wazuh
   - threat-detection

3. **About Section Links**:
   - Documentation: Link to docs/DOCUMENTATION_INDEX.md
   - Hardware Guide: Link to docs/HARDWARE_REQUIREMENTS.md

### Step 7: Create Announcement

```markdown
# 📢 Repository Renamed: pfsense-siem-stack

We've renamed the repository from `pfsense_grafana` to **`pfsense-siem-stack`** 
to better reflect the project's evolution and multi-SIEM support.

## What Changed?

✅ **Repository Name**: `pfsense_grafana` → `pfsense-siem-stack`  
✅ **Project Scope**: Grafana-focused → Multi-SIEM knowledge base  
✅ **Future Support**: OpenSearch (current), Graylog (planned), Wazuh (planned)

## Impact on You

- **GitHub automatically redirects** old URLs - no broken links!
- **Existing clones**: Update remote URL (see below)
- **Forks**: Continue working normally

## Update Your Local Clone

```bash
git remote set-url origin https://github.com/ChiefGyk3D/pfsense-siem-stack.git
```

## Why the Rename?

This project started as Grafana dashboard tweaks but evolved into a comprehensive 
SIEM knowledge base. The new name:
- Reflects multi-SIEM backend support
- Improves discoverability (SEO)
- Clarifies project scope
- Allows for Graylog and Wazuh integration

## What's Next?

- 📝 Graylog integration guides (planned)
- 📝 Wazuh EDR integration (planned)
- 🎯 Continued OpenSearch optimization
- 📚 Expanded documentation

Thank you for being part of this journey! 🚀
```

---

## 📊 Impact Assessment

### Breaking Changes
❌ **None** - GitHub auto-redirects prevent broken links

### User Impact
- **Existing users**: Minimal (optional URL update)
- **New users**: Better discoverability
- **Contributors**: Updated contribution guidelines

### Benefits
✅ Better SEO and discoverability  
✅ Clearer project scope  
✅ Room for multi-SIEM support  
✅ Professional naming  
✅ Accurate project description

---

## ✅ Cleanup Checklist

### Immediate (Do Now)
- [ ] Delete `docs/archive/old_readmes/README.md.old`
- [ ] Delete `docs/archive/README.md.backup`
- [ ] Create `docs/siem/COMPARISON.md` (optional)
- [ ] Create `docs/siem/graylog/README.md` (optional)
- [ ] Create `docs/siem/wazuh/README.md` (optional)

### Repository Rename (When Ready)
- [ ] Rename repository on GitHub
- [ ] Update local remote URL
- [ ] Update README.md title and description
- [ ] Update CONTRIBUTING.md references
- [ ] Update GitHub repo description
- [ ] Update GitHub topics/tags
- [ ] Create announcement post

### Documentation Improvements (Later)
- [ ] Move OpenSearch docs to `docs/siem/opensearch/`
- [ ] Create comparison matrix (OpenSearch vs Graylog vs Wazuh)
- [ ] Add .github/ISSUE_TEMPLATE/
- [ ] Add .github/PULL_REQUEST_TEMPLATE.md
- [ ] Create docs/integrations/ structure

---

## 🎯 Recommended Action Order

1. **Delete obsolete files** (5 minutes)
2. **Create placeholder docs** (15 minutes, optional)
3. **Rename repository** (2 minutes)
4. **Update local clone** (2 minutes)
5. **Update documentation** (30 minutes)
6. **Announce rename** (10 minutes)

**Total time**: ~1 hour for complete migration

---

## 💡 Questions?

- Is `pfsense-siem-stack` the right name? (Other options available)
- Should we create placeholder docs now or wait until implementing?
- Any other cleanup needed?

**Ready to proceed?** Let me know and I can execute any of these steps!
