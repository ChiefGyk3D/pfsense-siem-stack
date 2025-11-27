# Repository Rename Migration Checklist

> **Target Name**: `pfsense-siem-stack`  
> **Current Name**: `pfsense_grafana` / `Grafana_Dashboards`  
> **Date Started**: November 27, 2025  
> **Status**: 🚧 In Progress

---

## ✅ Phase 1: Cleanup & Preparation (COMPLETED)

### File Cleanup
- [x] Delete `docs/archive/old_readmes/README.md.old`
- [x] Delete `docs/archive/README.md.backup`
- [x] Verify no other backup files exist

### New Documentation Created
- [x] Create `docs/siem/COMPARISON.md` (OpenSearch vs Graylog vs Wazuh)
- [x] Create `docs/siem/graylog/README.md` (planned integration)
- [x] Create `docs/siem/wazuh/README.md` (planned integration)
- [x] Create `RENAME_CLEANUP_PLAN.md` (migration guide)
- [x] Create this checklist

### README Updates
- [x] Update title: "pfSense SIEM Stack"
- [x] Update subtitle with multi-SIEM support
- [x] Add multi-SIEM notice
- [x] Update overview section
- [x] Add link to SIEM comparison
- [x] Add Suricata badge

---

## 🔄 Phase 2: GitHub Repository Rename (TODO)

### Pre-Rename Verification
- [ ] Commit all current changes
- [ ] Push to GitHub
- [ ] Verify CI/CD passes (if applicable)
- [ ] Tag current state: `git tag -a pre-rename -m "Before rename to pfsense-siem-stack"`

### Rename on GitHub
- [ ] Go to: https://github.com/ChiefGyk3D/pfsense_grafana/settings
- [ ] Scroll to **Repository name**
- [ ] Change `pfsense_grafana` → `pfsense-siem-stack`
- [ ] Click **Rename** button
- [ ] Verify GitHub shows redirect notice

### Repository Settings
- [ ] Update **Description**: "Complete SIEM infrastructure for pfSense - OpenSearch, Graylog, Wazuh support with Suricata IDS/IPS monitoring"
- [ ] Update **Website**: (if you have documentation site)
- [ ] Update **Topics/Tags**:
  - [x] Core: `pfsense`, `suricata`, `siem`, `opensearch`, `security-monitoring`, `ids-ips`, `network-security`
  - [ ] Secondary: `grafana`, `logstash`, `graylog`, `wazuh`, `threat-detection`, `intrusion-detection`, `firewall-monitoring`

---

## 💻 Phase 3: Local Repository Update (TODO)

### Update Remote URL
```bash
cd /home/chiefgyk3d/src/Grafana_Dashboards

# Update remote URL
git remote set-url origin https://github.com/ChiefGyk3D/pfsense-siem-stack.git

# Verify
git remote -v

# Should show:
# origin  https://github.com/ChiefGyk3D/pfsense-siem-stack.git (fetch)
# origin  https://github.com/ChiefGyk3D/pfsense-siem-stack.git (push)
```
- [ ] Execute remote URL update
- [ ] Verify with `git remote -v`
- [ ] Test with `git fetch`

### Rename Local Directory (Optional)
```bash
cd /home/chiefgyk3d/src
mv Grafana_Dashboards pfsense-siem-stack
cd pfsense-siem-stack
```
- [ ] Rename local directory to match (optional but recommended)
- [ ] Update any shell aliases or bookmarks

---

## 📝 Phase 4: Documentation Updates (TODO)

### README.md
- [x] Title and subtitle updated
- [x] Multi-SIEM support notice added
- [x] Overview section updated
- [ ] Verify all internal links work
- [ ] Update any hardcoded repo URLs (if any)

### CONTRIBUTING.md
- [ ] Update clone command:
  ```bash
  git clone https://github.com/ChiefGyk3D/pfsense-siem-stack.git
  ```
- [ ] Update any references to old repo name
- [ ] Add note about multi-SIEM contributions

### ROADMAP.md
- [ ] Add Graylog integration milestone
- [ ] Add Wazuh integration milestone
- [ ] Update repo name references

### ORGANIZATION.md
- [ ] Update project name
- [ ] Add docs/siem/ structure
- [ ] Update file tree

### Documentation Index
- [ ] Add link to SIEM comparison
- [ ] Add Graylog placeholder docs
- [ ] Add Wazuh placeholder docs
- [ ] Update navigation

### Installation Scripts
- [ ] Check `install.sh` for repo name references
- [ ] Check `setup.sh` for repo name references
- [ ] Check any documentation links in scripts

---

## 📢 Phase 5: Announcement & Communication (TODO)

### Create Announcement
```markdown
# 📢 Repository Renamed: pfsense-siem-stack

We've renamed the repository to better reflect multi-SIEM support!

**Old**: pfsense_grafana / Grafana_Dashboards  
**New**: pfsense-siem-stack

✅ GitHub auto-redirects old URLs  
✅ Update your local clone: `git remote set-url origin https://github.com/ChiefGyk3D/pfsense-siem-stack.git`  
✅ Now supports: OpenSearch (current), Graylog (planned), Wazuh (planned)

See [SIEM Comparison](docs/siem/COMPARISON.md) for details!
```

Tasks:
- [ ] Create GitHub Discussion with announcement
- [ ] Pin announcement to repository
- [ ] Update LinkedIn post (if not yet published)
- [ ] Add temporary notice to README (remove after 30 days)

### Temporary README Notice (Add to top)
```markdown
> 📢 **Repository Renamed**: This project was renamed from `pfsense_grafana` to 
> `pfsense-siem-stack` to reflect multi-SIEM backend support. GitHub automatically 
> redirects old URLs. [Learn more](RENAME_CLEANUP_PLAN.md)
```
- [ ] Add temporary notice to README
- [ ] Set reminder to remove notice after 30 days

---

## 🔗 Phase 6: External References (TODO - If Applicable)

### Social Media
- [ ] Update Twitter/X posts (if any)
- [ ] Update LinkedIn references
- [ ] Update Reddit posts (if any)
- [ ] Update Discord/Slack references (if any)

### Documentation Sites
- [ ] Update external documentation (if hosted elsewhere)
- [ ] Update wiki references (if applicable)
- [ ] Update blog posts mentioning the project

### Package Managers
- [ ] Update Docker Hub references (if applicable)
- [ ] Update Ansible Galaxy (if applicable)
- [ ] Update any published packages

---

## 🧪 Phase 7: Testing & Verification (TODO)

### Functionality Tests
- [ ] Clone repository with new URL
- [ ] Run installation scripts
- [ ] Verify all documentation links work
- [ ] Test dashboard imports
- [ ] Verify forwarder deployment

### Documentation Tests
- [ ] Walk through Quick Start guide
- [ ] Verify all relative links work
- [ ] Check all images load correctly
- [ ] Test navigation between docs

### Search Engine Verification
- [ ] Verify GitHub search finds new name
- [ ] Check Google indexing (may take days/weeks)
- [ ] Update any SEO metadata

---

## 📊 Phase 8: Post-Migration Cleanup (TODO)

### Archive Old References
- [ ] Move RENAME_CLEANUP_PLAN.md to docs/archive/ (after 60 days)
- [ ] Remove temporary README notice (after 30 days)
- [ ] Archive this checklist (after completion)

### Monitor Issues
- [ ] Watch for user confusion about rename
- [ ] Update any GitHub issues mentioning old name
- [ ] Help users update their local clones

---

## 📋 Summary Status

| Phase | Status | Progress |
|-------|--------|----------|
| Phase 1: Cleanup & Preparation | ✅ Complete | 100% |
| Phase 2: GitHub Rename | ⏳ Pending | 0% |
| Phase 3: Local Update | ⏳ Pending | 0% |
| Phase 4: Documentation | 🚧 In Progress | 30% |
| Phase 5: Announcement | ⏳ Pending | 0% |
| Phase 6: External References | ⏳ Pending | 0% |
| Phase 7: Testing | ⏳ Pending | 0% |
| Phase 8: Post-Migration | ⏳ Pending | 0% |

**Overall Progress**: ~20%

---

## 🎯 Next Steps (Priority Order)

1. **Complete Phase 2**: Rename repository on GitHub ⚠️
2. **Complete Phase 3**: Update local clone
3. **Complete Phase 4**: Update all documentation
4. **Complete Phase 5**: Create announcement
5. **Complete Phase 7**: Test everything
6. **Start Phase 8**: Monitor and cleanup

---

## 💡 Notes & Lessons Learned

### What Went Well
- ✅ Cleanup of obsolete files completed quickly
- ✅ SIEM comparison docs provide clear value
- ✅ Placeholder docs set proper expectations
- ✅ README updates improve discoverability

### Challenges Encountered
- None yet (pre-rename phase)

### Future Improvements
- Consider automated link checking
- Add pre-commit hooks for repo name references
- Create migration guide for users

---

## 📞 Questions or Issues?

If you encounter problems during migration:
1. Check this checklist for missed steps
2. Review [RENAME_CLEANUP_PLAN.md](RENAME_CLEANUP_PLAN.md)
3. Open GitHub Discussion for help

---

**Last Updated**: November 27, 2025  
**Checklist Version**: 1.0  
**Maintained By**: ChiefGyk3D
