# Graylog Integration for pfSense

> **Status**: 📝 Planned - Coming Soon  
> **Priority**: High (community requested)  
> **Last Updated**: November 27, 2025

Graylog integration for pfSense Suricata log analysis and security monitoring.

---

## Why Graylog?

Graylog is an excellent alternative to OpenSearch for users who want:

✅ **Easier Setup** - Simpler installation and configuration  
✅ **Better Web UI** - Purpose-built log management interface  
✅ **Quick Deployment** - Content packs for rapid configuration  
✅ **Excellent Alerting** - Powerful alert management out of the box  
✅ **Stream Processing** - Real-time log routing and processing  

---

## Current Status

Graylog support is **planned but not yet implemented**. The existing OpenSearch implementation works excellently, but we recognize many users prefer Graylog's ease of use and superior web interface.

**Historical Context**: Early versions of this project (see `docs/archive/GRAYLOG_*.md`) included Graylog documentation, but those guides are outdated and need complete rewrite for current pfSense/Suricata versions.

---

## Planned Features

### Phase 1: Basic Integration
- [ ] Graylog 5.x/6.x installation guide (Ubuntu 24.04)
- [ ] Suricata input configuration (Syslog/UDP)
- [ ] Field extractors for eve.json parsing
- [ ] Basic dashboards (alerts, sources, signatures)
- [ ] Index retention and rotation policies

### Phase 2: Advanced Features
- [ ] Content pack for one-click deployment
- [ ] GeoIP lookup integration
- [ ] Advanced search queries and saved searches
- [ ] Alert rules for common threats
- [ ] Stream routing (WAN vs LAN interfaces)

### Phase 3: Migration & Integration
- [ ] Migration guide from OpenSearch to Graylog
- [ ] Dual-stack operation (OpenSearch + Graylog)
- [ ] Historical data import/export
- [ ] Grafana integration for metrics
- [ ] Comparison with OpenSearch implementation

---

## Architecture (Planned)

```
┌─────────────┐
│   pfSense   │
│  Suricata   │ Multiple interfaces (WAN, VLANs)
└──────┬──────┘
       │ eve.json logs
       │
       ▼ Syslog/UDP (enriched with GeoIP)
┌─────────────┐
│  Graylog    │
│  Server     │ Log ingestion, parsing, indexing
│             │ 
│ ┌─────────┐ │
│ │MongoDB  │ │ Configuration storage
│ └─────────┘ │
│             │
│ ┌─────────┐ │
│ │OpenSrch │ │ Index storage (or Elasticsearch)
│ └─────────┘ │
└──────┬──────┘
       │
       ▼ Web UI (port 9000)
   Dashboards, Search, Alerts
```

---

## Why Not Implemented Yet?

1. **OpenSearch Works Well** - Current implementation is stable and well-documented
2. **Resource Constraints** - Limited development time to maintain multiple SIEM backends
3. **Community Contributions** - Waiting for community members who prefer Graylog to contribute

**We need your help!** If you're a Graylog user, consider contributing to this integration.

---

## How You Can Help

### 1. Testing & Feedback
- Try OpenSearch implementation
- Provide feedback on what Graylog features you need
- Share your current Graylog setup for pfSense

### 2. Documentation Contribution
- Review archived Graylog docs (`docs/archive/GRAYLOG_*.md`)
- Test integration with current pfSense/Suricata versions
- Write updated guides

### 3. Content Pack Development
- Create Graylog content pack for Suricata
- Include extractors, streams, dashboards
- Share with community

### 4. Code Contribution
- Adapt forwarder script for Graylog (if needed)
- Create installation automation
- Write testing procedures

---

## Comparison with OpenSearch

See [SIEM Comparison Guide](../COMPARISON.md) for detailed feature comparison.

**Quick Summary**:

| Aspect | Graylog | OpenSearch (Current) |
|--------|---------|---------------------|
| Setup Difficulty | ⭐⭐☆☆☆ Easy | ⭐⭐⭐☆☆ Medium |
| Web UI Quality | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐☆☆ Basic |
| Grafana Integration | ⭐⭐⭐☆☆ Good | ⭐⭐⭐⭐⭐ Excellent |
| Query Power | ⭐⭐⭐☆☆ Good | ⭐⭐⭐⭐⭐ Excellent |
| Alerting | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐⭐☆☆ Good |
| Resource Usage | ⭐⭐⭐☆☆ Medium | ⭐⭐⭐⭐☆ High |

**Recommendation**: 
- Choose **Graylog** if you want easier setup and better web UI
- Choose **OpenSearch** if you need powerful analytics and Grafana dashboards

---

## Migration from OpenSearch

When Graylog integration is implemented, we'll provide guides for:

1. **Clean Migration** - Move from OpenSearch to Graylog
2. **Dual Operation** - Run both simultaneously (different purposes)
3. **Data Export** - Extract historical data from OpenSearch
4. **Dashboard Recreation** - Rebuild visualizations in Graylog

---

## Resources

### Official Documentation
- [Graylog Documentation](https://docs.graylog.org/)
- [Graylog Marketplace](https://marketplace.graylog.org/)
- [Graylog Community](https://community.graylog.org/)

### Related Projects
- [Graylog Content Packs](https://marketplace.graylog.org/addons?kind=content_pack)
- [Graylog Suricata Input](https://marketplace.graylog.org/addons?tag=suricata)

### Archived Documentation (Outdated)
- `docs/archive/GRAYLOG_INDEX.md` - Old Graylog setup guide
- `docs/archive/GRAYLOG_SURICATA_SETUP.md` - Old Suricata integration

**Note**: These archived docs are for reference only and may not work with current versions.

---

## Timeline & Roadmap

**No firm ETA** - depends on community contributions and available development time.

**Want to accelerate this?**
1. Open a GitHub Discussion expressing interest
2. Volunteer to test and provide feedback
3. Contribute documentation or code
4. Share your existing Graylog setup

See [ROADMAP.md](../../ROADMAP.md) for overall project priorities.

---

## Questions?

- **General Questions**: [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions)
- **Feature Requests**: [GitHub Issues](https://github.com/ChiefGyk3D/pfsense-siem-stack/issues)
- **Contribution**: [CONTRIBUTING.md](../../CONTRIBUTING.md)

---

**Stay tuned!** Star the repository and watch for updates when Graylog integration becomes available.
