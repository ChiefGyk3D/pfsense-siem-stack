# Dashboards

Every Grafana dashboard shipped in this repo, what it needs, and how it gets
imported. Import via **Dashboards → New → Import → Upload JSON** and pick your
datasources when prompted; the two Suricata dashboards are also imported
automatically by `./setup.sh` (step 5).

| File | Title / UID | Panels | Datasource(s) | Import |
|------|-------------|--------|---------------|--------|
| `Suricata_IDS_IPS.json` | Suricata IDS/IPS Dashboard · `suricata_ids_ips` | 14 | OpenSearch (`suricata-*`) | `setup.sh` or manual |
| `Suricata_Per_Interface.json` | Suricata Per-Interface Dashboard · `suricata_per_interface` | 6 (repeated per selected interface) | OpenSearch (`suricata-*`) | `setup.sh` or manual |
| `pfsense_pfblockerng_system.json` | pfSense System Dashboard · `GflT1CsMz_v2` | 41 | InfluxDB (`pfsense` database, Telegraf) **and** OpenSearch-pfBlockerNG (`pfblockerng-*`) | manual |
| `windows_exporter.json` | Windows Exporter Dashboard | 22 | Prometheus (windows_exporter) | manual, optional |
| `prometheus_stats.json` | Prometheus Stats | 17 | Prometheus (self-scrape) | manual, optional |
| `docker_container_monitoring.json` | Docker Container Monitoring | 15 | Prometheus (cAdvisor) | manual, optional |
| `wazuh/wazuh_security_overview.json` | Wazuh Security Overview · `wazuh-security-overview` | 20 | OpenSearch-Wazuh (`wazuh-alerts-4.x-*`) | `scripts/deploy-wazuh-dashboards.py` |
| `wazuh/wazuh_vulnerability_detection.json` | Wazuh Vulnerability Detection · `wazuh-vulnerabilities` | 11 | OpenSearch-Wazuh | `scripts/deploy-wazuh-dashboards.py` |
| `wazuh/wazuh_file_integrity_monitoring.json` | Wazuh File Integrity Monitoring · `wazuh-fim` | 11 | OpenSearch-Wazuh | `scripts/deploy-wazuh-dashboards.py` |
| `suricata_ids_ips_active.json` | Suricata IDS/IPS Dashboard · `suricata_ids_ips` | 14 | OpenSearch | **Do not import alongside `Suricata_IDS_IPS.json`** — same UID; this is a raw export of the maintainer's live copy kept for diffing |
| `datasources_reference.json` | — | — | — | Not a dashboard: the maintainer's Grafana datasource list (names, types, UIDs) for reproducing the same wiring |

## Datasources the dashboards expect

| Grafana datasource name | Type | Points at | Time field | Created by |
|-------------------------|------|-----------|------------|------------|
| `OpenSearch` | grafana-opensearch-datasource | `http://<SIEM_IP>:9200`, index `suricata-*` | `@timestamp` | `setup.sh` |
| `OpenSearch-pfBlockerNG` | grafana-opensearch-datasource | same host, index `pfblockerng-*` | `@timestamp` | `setup.sh` |
| `InfluxDB-pfSense` | influxdb | `http://<SIEM_IP>:8086`, database `pfsense` | — | you (see [Telegraf on pfSense](../docs/pfsense/TELEGRAF_ON_PFSENSE.md)) |
| `Prometheus` | prometheus | your Prometheus | — | you, optional |
| `OpenSearch-Wazuh` | grafana-opensearch-datasource | Wazuh indexer, index `wazuh-alerts-4.x-*` | `timestamp` | `deploy-wazuh-dashboards.py` |

The Suricata dashboards use a `DS_OPENSEARCH` datasource variable, so any
OpenSearch datasource can be selected at the top of the dashboard. The pfSense
System dashboard has two datasource dropdowns (`dataSource` for InfluxDB,
`osDataSource` for OpenSearch-pfBlockerNG) plus `WAN` and `LAN_Interfaces`
variables that discover your interface names from Telegraf data — nothing is
hardcoded to a specific NIC. Details:
[Dashboard Installation](../docs/install/INSTALL_DASHBOARD.md).

## What each Suricata dashboard shows

**Suricata IDS/IPS (WAN focus)** — events/alerts counters with sparklines, event
type and protocol distribution, top alert signatures, alert severity, the IDS alert
log table, attack-source world map (geohash on `geoip_src.location`), top source
countries, top HTTP hosts and methods. Filter by interface with the `interface`
variable (`in_iface`).

**Suricata Per-Interface (LAN/VLAN focus)** — a repeating row per selected
interface: events & alerts, top signatures, alert timeline, top source and
destination IPs, alert log. Select several interfaces to compare VLANs side by
side. Use case and configuration:
[LAN Monitoring](../docs/pfsense/LAN_MONITORING.md).

**pfSense System** — CPU, memory, disk, temperature, uptime; gateway RTT/loss;
per-interface throughput (InfluxDB via Telegraf); and the pfBlockerNG section
(IP blocks in/out, DNSBL blocks, top blocked sources/destinations, blocked
traffic by country, feed statistics, protocol/port distribution) from
OpenSearch. pfBlockerNG lives in OpenSearch rather than InfluxDB to avoid
InfluxDB series-cardinality blow-up on IP addresses.

## Field names

All Suricata panels query flat root-level fields (`event_type`, `src_ip`,
`alert.signature.keyword`, `in_iface`, `geoip_src.location`). See the
[Field Reference](../docs/reference/FIELD_REFERENCE.md) before editing a panel.

## Contributing a dashboard

Export with **Share → Export → "Export for sharing externally"** so datasources
become `${DS_...}` variables, keep 2-space JSON indentation, give panels
descriptions, test on Grafana 12.x, and add a row to the table above. CI validates
every JSON file under `dashboards/`.
