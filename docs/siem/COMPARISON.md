# SIEM Backend Comparison

> **Status**: 🚧 Work in Progress  
> **Last Updated**: November 27, 2025

Comparison of different SIEM backends for pfSense integration.

---

## Supported Backends

### OpenSearch (Current - Production Ready ✅)

**Status**: Fully implemented and documented

**Characteristics**:
- Open-source fork of Elasticsearch (Apache 2.0 license)
- Excellent Grafana integration via data source
- Strong search and aggregation capabilities
- Index lifecycle management (ILM) for retention

**Resource Requirements**:
- RAM: 8-16GB heap (16GB total minimum)
- CPU: 4+ cores recommended
- Storage: Fast SSD (NVMe preferred)

**Pros**:
- ✅ Powerful search and analytics
- ✅ Excellent Grafana visualization
- ✅ Strong query language (DSL)
- ✅ Scalable to multi-node clusters

**Cons**:
- ❌ Steeper learning curve
- ❌ More resource-intensive
- ❌ Complex cluster management

**Best For**: Users who want powerful analytics, Grafana dashboards, and have adequate hardware

**Documentation**: See main docs (INSTALL_SIEM_STACK.md, etc.)

---

### Graylog (Planned 📝)

**Status**: Coming Soon

**Characteristics**:
- Purpose-built log management platform
- Excellent web UI out of the box
- Stream-based processing
- Strong alerting capabilities

**Resource Requirements** (estimated):
- RAM: 8-12GB minimum
- CPU: 4+ cores recommended
- Storage: SSD recommended
- Dependencies: MongoDB, OpenSearch/Elasticsearch

**Pros**:
- ✅ Easier initial setup
- ✅ Better out-of-box UI
- ✅ Excellent alerting
- ✅ Content packs for quick deployment
- ✅ Stream-based processing

**Cons**:
- ❌ Enterprise features require license
- ❌ Additional dependency (MongoDB)
- ❌ Less powerful than raw OpenSearch queries
- ❌ Grafana integration less native

**Best For**: Users who want ease of use, quick setup, and don't need deep Grafana integration

**ETA**: TBD - community contributions welcome!

---

### Wazuh (Planned 📝)

**Status**: Long-term roadmap

**Characteristics**:
- Open-source XDR/SIEM platform
- Endpoint detection and response (EDR)
- Compliance reporting (PCI-DSS, HIPAA, etc.)
- Active response and remediation
- File integrity monitoring (FIM)

**Resource Requirements** (estimated):
- RAM: 16-32GB (more for manager)
- CPU: 8+ cores recommended
- Storage: Fast SSD for indices
- Architecture: Manager + agents + indexer

**Pros**:
- ✅ EDR capabilities (beyond network)
- ✅ Compliance reporting built-in
- ✅ Active response mechanisms
- ✅ File integrity monitoring
- ✅ Vulnerability detection
- ✅ Multi-system correlation

**Cons**:
- ❌ More complex architecture
- ❌ Higher resource requirements
- ❌ Steeper learning curve
- ❌ Agent deployment overhead

**Best For**: Environments with compliance requirements, need for EDR, or multi-system correlation

**ETA**: TBD - lower priority than Graylog

---

## Feature Comparison Matrix

| Feature | OpenSearch | Graylog | Wazuh |
|---------|------------|---------|-------|
| **Status** | ✅ Production | 📝 Planned | 📝 Planned |
| **License** | Apache 2.0 | Server Side Public License | GPL v2 |
| **Ease of Setup** | Medium | Easy | Hard |
| **Web UI Quality** | Basic (Kibana fork) | Excellent | Good |
| **Grafana Integration** | Excellent | Good | Good |
| **Alert Management** | Good | Excellent | Excellent |
| **Compliance Reporting** | Manual | Good | Excellent |
| **Active Response** | No | Limited | Yes |
| **EDR Capabilities** | No | No | Yes |
| **Query Language** | DSL (powerful) | GUI + search syntax | DSL |
| **Scalability** | Excellent | Good | Excellent |
| **Resource Usage** | High | Medium | High |
| **Learning Curve** | Steep | Gentle | Steep |
| **Community Support** | Large | Medium | Large |

---

## Decision Guide

### Choose OpenSearch If You...

✅ Want powerful analytics and custom dashboards  
✅ Have adequate hardware (16GB+ RAM)  
✅ Prefer Grafana for visualization  
✅ Need scalability for growth  
✅ Are comfortable with command-line tools

### Choose Graylog If You...

✅ Want quick, easy setup  
✅ Prefer web UI over Grafana  
✅ Need excellent alerting out-of-box  
✅ Want content packs for rapid deployment  
✅ Have moderate hardware (12GB+ RAM)

### Choose Wazuh If You...

✅ Have compliance requirements (PCI-DSS, HIPAA)  
✅ Need EDR beyond network monitoring  
✅ Want active response capabilities  
✅ Monitor multiple systems (firewall + servers + workstations)  
✅ Have significant hardware (32GB+ RAM)

---

## Migration Paths

### OpenSearch → Graylog

**Coming Soon**: Guide to migrate from OpenSearch to Graylog while preserving historical data.

**Considerations**:
- Export OpenSearch indices
- Import into Graylog via content packs
- Map field names
- Recreate dashboards in Graylog UI

### OpenSearch → Wazuh

**Coming Soon**: Guide to integrate Wazuh alongside or replace OpenSearch.

**Considerations**:
- Wazuh uses OpenSearch/Elasticsearch as backend
- Can keep existing OpenSearch indices
- Wazuh adds manager layer on top
- Consider agent deployment strategy

### Graylog → OpenSearch

**Future**: Guide for users who start with Graylog but need more powerful analytics.

---

## Multi-Backend Support

**Can I run multiple SIEMs?**

Yes, but not recommended for the same data:
- Different SIEMs for different purposes (e.g., OpenSearch for pfSense, Wazuh for endpoints)
- Same SIEM for all systems (e.g., Wazuh for everything)

**Resource Impact**: Running multiple SIEMs requires significant hardware (32GB+ RAM).

---

## Contributing

Want to help add Graylog or Wazuh support?

1. Check archived Graylog docs: `docs/archive/GRAYLOG_*.md`
2. Review this comparison for technical details
3. See [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines
4. Open a GitHub Discussion to coordinate efforts

**Priority**: Graylog > Wazuh (based on community requests)

---

## Resources

### OpenSearch
- [OpenSearch Documentation](https://opensearch.org/docs/)
- [Grafana OpenSearch Data Source](https://grafana.com/docs/grafana/latest/datasources/opensearch/)

### Graylog
- [Graylog Documentation](https://docs.graylog.org/)
- [Graylog Marketplace](https://marketplace.graylog.org/)

### Wazuh
- [Wazuh Documentation](https://documentation.wazuh.com/)
- [Wazuh + pfSense Integration](https://wazuh.com/blog/monitoring-pfsense-firewalls-with-wazuh/)

---

**Questions?** Open a [GitHub Discussion](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions)
