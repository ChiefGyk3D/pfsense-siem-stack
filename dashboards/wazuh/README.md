# Wazuh Dashboards for Grafana

Custom Grafana dashboards for Wazuh EDR/SIEM data stored in OpenSearch (Wazuh Indexer).

## Dashboards

### Wazuh Security Overview (`wazuh_security_overview.json`)
**20 panels** — Central security operations view.

| Row | Panels |
|-----|--------|
| Stats | Total Alerts, Level 12+ (High), Authentication, Vulnerability, FIM Events, Active Response |
| Timeline | Alert Timeline by Level (timeseries), Alert Level Distribution (table) |
| Rules | Top 15 Alert Rules (table), Alerts by Agent (table) |
| MITRE | ATT&CK Tactics (table), ATT&CK Techniques (table) |
| Compliance | PCI DSS (table), NIST 800-53 (table), HIPAA (table) |
| Auth | Auth Successes (stat), Auth Failures (stat, red threshold), Top Rule Groups (table), Hourly Alert Trend by Agent (stacked bars) |
| Recent | Recent High-Level Alerts Level 7+ (raw logs table) |

### Wazuh Vulnerability Detection (`wazuh_vulnerability_detection.json`)
**11 panels** — CVE and vulnerability tracking across agents.

| Row | Panels |
|-----|--------|
| Stats | Total Vulnerabilities, Critical/High, Unique CVEs (cardinality), Affected Agents (cardinality) |
| Overview | Severity Distribution (table), Vulnerability Timeline by Severity (timeseries) |
| Detail | Top 20 CVEs (table), Vulnerable Packages (table) |
| Agent | Vulnerabilities by Agent (table), Severity by Agent (multi-terms table) |
| Recent | Recent Critical/High Vulnerabilities (raw logs table) |

### Wazuh File Integrity Monitoring (`wazuh_file_integrity_monitoring.json`)
**11 panels** — File change tracking across endpoints.

| Row | Panels |
|-----|--------|
| Stats | Total FIM Events, Added, Modified, Deleted |
| Timeline | FIM Timeline by Event Type (timeseries), Event Types (table) |
| Files | Top Modified Files (table), FIM by Agent (table) |
| Detail | FIM Activity by Rule (table), FIM Detail: Agent / Event / Path (multi-terms table) |
| Recent | Recent FIM Events (raw logs table) |

## Prerequisites

### Datasource: OpenSearch-Wazuh

| Setting | Value |
|---------|-------|
| Type | `grafana-opensearch-datasource` |
| UID | `dff8stu43lr7kc` |
| URL | `https://wazuh-indexer:9200` |
| Index | `wazuh-alerts-4.x-*` |
| Time field | `timestamp` |
| Auth | Basic (admin/SecretPassword) |
| TLS | Skip verify = true |
| Version | 2.19.0 |
| PPL | Enabled |

### Wazuh Agents

These dashboards show data from Wazuh agents. The production deployment has 5 agents:

| Agent | OS | Hostname |
|-------|-----|----------|
| pi-node-01 | Linux ARM64 | Raspberry Pi |
| siem-server | Ubuntu 24.04 | SIEM Server |
| workstation-01 | Windows | Workstation |
| workstation-02 | Pop!_OS 22.04 | Workstation |
| gpu-server | Linux x86_64 | LLM Server |

## Import

### Via Grafana UI
1. Dashboards → New → Import → Upload JSON
2. Select the `.json` file
3. Place in "SIEM Alerts" folder

### Via API
```bash
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Authorization: Basic $(echo -n admin:changeme | base64)" \
  -H "Content-Type: application/json" \
  -d "{\"dashboard\": $(cat wazuh_security_overview.json), \"overwrite\": true, \"folderUid\": \"eff8gvnuqvbwgb\"}"
```

### Via automated script
```bash
cd siem-server
./scripts/deploy-grafana-dashboards.sh
```
