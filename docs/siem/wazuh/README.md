# Wazuh Integration

> **Status**: ✅ Dashboards and deployment script ship in this repo and run in
> production. The Wazuh server itself (manager, indexer, syslog-ng front end) is
> provided by [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack).

## What this repo provides

| Asset | Purpose |
|-------|---------|
| [`dashboards/wazuh/wazuh_security_overview.json`](../../../dashboards/wazuh/wazuh_security_overview.json) | 20 panels: alert levels, MITRE ATT&CK, PCI DSS / NIST / HIPAA mapping, auth success/failure, hourly trend by agent, recent high-level alerts |
| [`dashboards/wazuh/wazuh_vulnerability_detection.json`](../../../dashboards/wazuh/wazuh_vulnerability_detection.json) | 11 panels: CVEs, severity distribution, vulnerable packages, severity by agent |
| [`dashboards/wazuh/wazuh_file_integrity_monitoring.json`](../../../dashboards/wazuh/wazuh_file_integrity_monitoring.json) | 11 panels: file added/modified/deleted, per-agent breakdown, detail table |
| [`scripts/deploy-wazuh-dashboards.py`](../../../scripts/deploy-wazuh-dashboards.py) | Creates the `OpenSearch-Wazuh` Grafana datasource, a folder, imports the three dashboards and verifies data with API queries. Credentials via `GRAFANA_PASS` / `WAZUH_INDEXER_PASS` environment variables; TLS verification on by default. |
| [`dashboards/wazuh/README.md`](../../../dashboards/wazuh/README.md) | Panel inventory, datasource settings, field reference for `wazuh-alerts-4.x-*` |

Deploy:

```bash
export GRAFANA_PASS='...' WAZUH_INDEXER_PASS='...'
python3 scripts/deploy-wazuh-dashboards.py --grafana-url http://<SIEM_IP>:3000 \
    --wazuh-url https://<WAZUH_INDEXER>:9200 --wazuh-user admin
python3 scripts/deploy-wazuh-dashboards.py --help   # all options
```

## What pfSense must do for Wazuh

Wazuh's built-in `pf` decoder only matches if the syslog line carries a hostname.
pfSense's default BSD (RFC 3164) format omits it, so Wazuh's pre-decoder misreads the
program name as the host and you get **zero firewall alerts despite data flowing**.

1. Status → System Logs → Settings → **Remote Logging Options**
2. Enable remote logging to your SIEM's syslog receiver (UDP 514 by default in
   siem-docker-stack), select the log categories you want (Firewall Events at minimum;
   add System, DNS Resolver, DHCP as needed)
3. **Log Message Format**: `RFC 5424 (syslog-protocol)`
4. **Timestamp Format**: `RFC 3339 with microsecond precision`

syslog-ng on the SIEM side converts RFC 5424 → the BSD form Wazuh expects; that
configuration lives in siem-docker-stack.

Optional: install the Wazuh agent on pfSense itself for FIM/inventory. It is not in the
pfSense package repo (FreeBSD builds exist upstream) and, like every unmanaged file, must
be reinstalled after a pfSense upgrade — see
[Upgrading pfSense](../../pfsense/PFSENSE_UPGRADE_GUIDE.md).

## How it fits with the OpenSearch stack

The Wazuh indexer *is* OpenSearch, so one Grafana queries `wazuh-alerts-4.x-*` and
`suricata-*` side by side. Keep Suricata events flowing through this repo's forwarder
(structured EVE JSON, GeoIP, flat fields) rather than through Wazuh's Suricata
integration; use Wazuh for pfSense syslog, endpoints, FIM, vulnerabilities and
compliance. Comparison and decision guide: [COMPARISON.md](../COMPARISON.md).

## Not done yet

- Alert rules that correlate Suricata alerts with Wazuh agent events (roadmap Phase B)
- A Wazuh custom decoder/rules pack for pfBlockerNG log lines
- pfSense-side Wazuh agent packaging

Contributions welcome — see [CONTRIBUTING.md](../../../CONTRIBUTING.md).
