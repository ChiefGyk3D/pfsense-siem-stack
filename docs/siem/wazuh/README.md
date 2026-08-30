# Wazuh Integration for pfSense

> **Status**: 📝 Planned - Long-term Roadmap  
> **Priority**: Medium (after Graylog)  
> **Last Updated**: November 27, 2025

Wazuh XDR/SIEM integration for pfSense with advanced EDR and compliance capabilities.

---

## Why Wazuh?

Wazuh is a comprehensive XDR (Extended Detection and Response) platform that goes beyond traditional SIEM:

✅ **Endpoint Detection & Response** - Monitor servers, workstations, AND network  
✅ **Compliance Reporting** - PCI-DSS, HIPAA, GDPR, NIST frameworks built-in  
✅ **Active Response** - Automated remediation actions  
✅ **File Integrity Monitoring** - Detect unauthorized file changes  
✅ **Vulnerability Detection** - Identify outdated software  
✅ **Configuration Assessment** - Security policy compliance checks  

---

## Current Status

Wazuh support is on the **long-term roadmap** but not yet prioritized. It offers capabilities beyond what OpenSearch or Graylog provide, making it ideal for environments with:

- Compliance requirements (PCI-DSS, HIPAA, etc.)
- Multi-system monitoring (firewall + servers + endpoints)
- Need for active response and remediation
- Security audit requirements

**Priority**: Lower than Graylog due to complexity and resource requirements.

---

## Planned Features

### Phase 1: Basic Integration
- [ ] Wazuh manager installation (Ubuntu 24.04)
- [ ] Wazuh indexer setup (OpenSearch backend)
- [ ] pfSense log forwarding to Wazuh
- [ ] Suricata alert integration
- [ ] Basic dashboards in Wazuh UI

### Phase 2: Advanced Features
- [ ] Wazuh agent on pfSense (if feasible)
- [ ] Custom rules and decoders for pfSense
- [ ] Suricata alert enrichment
- [ ] Integration with PfBlockerNG
- [ ] Active response scripts

### Phase 3: EDR Capabilities
- [ ] Multi-system correlation (pfSense + servers)
- [ ] File integrity monitoring
- [ ] Vulnerability scanning integration
- [ ] Compliance reporting templates
- [ ] Incident response playbooks

---

## Architecture (Planned)

```
┌─────────────────────────────────────────────────────────────┐
│                    Wazuh Manager                            │
│  (Central processing, rule engine, active response)         │
└───────────────┬─────────────────────────────┬───────────────┘
                │                             │
        ┌───────▼────────┐          ┌────────▼────────┐
        │ Wazuh Indexer  │          │  Wazuh Agent    │
        │  (OpenSearch)  │          │  (Optional)     │
        └───────┬────────┘          └────────┬────────┘
                │                            │
        ┌───────▼────────┐          ┌────────▼────────┐
        │ Wazuh Dashboard│          │    pfSense      │
        │   (Web UI)     │          │   Suricata      │
        └────────────────┘          └─────────────────┘
                                             │
                                    ┌────────▼────────┐
                                    │  Other Agents   │
                                    │ (Servers, etc.) │
                                    └─────────────────┘
```

---

## Use Cases

### Compliance Monitoring

**PCI-DSS Requirements**:
- Log all access to network resources
- Monitor file integrity on critical systems
- Regular vulnerability assessments
- Automated alerting on policy violations

**Wazuh provides**:
- Pre-built PCI-DSS compliance dashboards
- Automated compliance scoring
- Evidence collection for audits

### Multi-System Correlation

**Scenario**: Detect attack chains across infrastructure

1. Suricata alerts on network scan (pfSense)
2. Server logs show authentication attempts (Wazuh agent)
3. Workstation shows malware execution (Wazuh agent)
4. **Wazuh correlates** all events → high-priority incident

### Active Response

**Example**: Automated IP blocking

1. Suricata detects brute-force SSH attack
2. Wazuh processes alert
3. Active response script adds IP to PfBlockerNG
4. Threat automatically blocked

---

## Why Not Implemented Yet?

1. **Complexity** - Wazuh is significantly more complex than OpenSearch/Graylog
2. **Resource Requirements** - Requires 32GB+ RAM for manager + agents
3. **Use Case** - Most users need SIEM, not full XDR
4. **Priority** - Graylog integration is higher priority (easier, more requested)

**When to implement**: After Graylog support is complete and stable.

---

## Comparison with Other SIEMs

See [SIEM Comparison Guide](../COMPARISON.md) for detailed feature comparison.

**Quick Summary**:

| Aspect | Wazuh | OpenSearch | Graylog |
|--------|-------|-----------|---------|
| Complexity | ⭐⭐⭐⭐⭐ Very Hard | ⭐⭐⭐☆☆ Medium | ⭐⭐☆☆☆ Easy |
| EDR Features | ⭐⭐⭐⭐⭐ Excellent | ⭐☆☆☆☆ None | ⭐☆☆☆☆ None |
| Compliance | ⭐⭐⭐⭐⭐ Excellent | ⭐⭐☆☆☆ Manual | ⭐⭐⭐☆☆ Good |
| Active Response | ⭐⭐⭐⭐⭐ Yes | ⭐☆☆☆☆ No | ⭐⭐☆☆☆ Limited |
| Resource Usage | ⭐⭐⭐⭐⭐ Very High | ⭐⭐⭐⭐☆ High | ⭐⭐⭐☆☆ Medium |
| Agent Required | ⭐⭐⭐⭐☆ Yes (optional) | ⭐☆☆☆☆ No | ⭐☆☆☆☆ No |

**Recommendation**: 
- Choose **Wazuh** only if you need EDR, compliance, or active response
- For network monitoring only, OpenSearch or Graylog are simpler choices

---

## Interest in Wazuh?

Help us prioritize this integration!

### Express Interest
1. Open a [GitHub Discussion](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions)
2. Explain your use case (compliance, EDR, etc.)
3. Share your environment details

### Contribute
1. Test Wazuh with current pfSense setup
2. Document integration steps
3. Create custom rules/decoders
4. Share configuration examples

---

## Resources

### Official Documentation
- [Wazuh Documentation](https://documentation.wazuh.com/)
- [Wazuh + pfSense Guide](https://wazuh.com/blog/monitoring-pfsense-firewalls-with-wazuh/)
- [Wazuh Community](https://github.com/wazuh/wazuh/discussions)

### Integration Examples
- [Wazuh Suricata Integration](https://documentation.wazuh.com/current/learning-wazuh/suricata.html)
- [Custom Rules](https://documentation.wazuh.com/current/user-manual/ruleset/custom.html)
- [Active Response](https://documentation.wazuh.com/current/user-manual/capabilities/active-response/)

### Compliance Resources
- [PCI-DSS Dashboard](https://documentation.wazuh.com/current/compliance/pci-dss/index.html)
- [HIPAA Compliance](https://documentation.wazuh.com/current/compliance/hipaa/index.html)
- [GDPR Compliance](https://documentation.wazuh.com/current/compliance/gdpr/index.html)

---

## Timeline & Roadmap

**ETA**: TBD - Long-term roadmap

**Dependencies**:
1. Graylog integration complete
2. Community interest validated
3. Development resources available

**Estimated Effort**: 3-6 months for full integration

See [ROADMAP.md](../../../ROADMAP.md) for overall project priorities.

---

## Alternative Approach: Hybrid Setup

**Instead of full Wazuh migration**, consider hybrid architecture:

1. **Keep OpenSearch/Graylog** for pfSense/Suricata logs
2. **Add Wazuh** for servers and endpoints only
3. **Correlate** via shared indexer or SIEM connector

This provides EDR benefits without migrating working pfSense integration.

---

## Questions?

- **General Questions**: [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions)
- **Feature Requests**: [GitHub Issues](https://github.com/ChiefGyk3D/pfsense-siem-stack/issues)
- **Contribution**: [CONTRIBUTING.md](../../../CONTRIBUTING.md)

---

**Want Wazuh sooner?** Contribute! Community-driven development can accelerate this integration significantly.
