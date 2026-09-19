# SIEM Backend Comparison

> Which backend this project uses, which it supports, and which it tried and shelved —
> so you don't spend effort on a dead path.

## Where things stand (September 2026)

| Backend | Status in this repo | Server provided by |
|---------|--------------------|--------------------|
| **OpenSearch + Logstash + Grafana** | ✅ Production. The forwarder, index templates, retention and Suricata/pfBlockerNG dashboards target it. | `install.sh` here (bare metal) or [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack) (Docker, hot/warm, the recommended direction) |
| **Wazuh** | ✅ Three Grafana dashboards + `scripts/deploy-wazuh-dashboards.py` ship here and are used in production. pfSense feeds Wazuh via RFC 5424 syslog. | [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack) (Wazuh manager + indexer + syslog-ng) |
| **Graylog** | ⏸️ Explored in 2025 and shelved. Old guides are in git history. | — |

The strategic decision recorded in [ROADMAP.md](../../ROADMAP.md): **siem-docker-stack is
the canonical backend**; this repo owns the pfSense side (forwarder, Telegraf plugins,
Suricata tuning, dashboards) and keeps `install.sh` as a documented standalone
alternative.

---

## OpenSearch (the primary path)

**Why it was chosen**: Apache-2.0 fork of Elasticsearch, excellent Grafana datasource,
powerful aggregations for the dashboards this project is built around, ISM (Index State
Management) for retention, scales to a cluster when needed.

**What it costs**: 16 GB RAM minimum for the SIEM server (8 GB heap), fast SSD, a
steeper learning curve than an all-in-one product, and — as installed by `install.sh`
today — no authentication or TLS until you enable the security plugin (roadmap Phase A).

**Best for**: anyone who wants Grafana as the front end and is comfortable with curl and
the OpenSearch DSL. Everything in [docs/install/](../install/) assumes this backend.

## Wazuh (XDR alongside the network view)

**What it adds**: agents on servers and workstations (FIM, vulnerability detection,
compliance mapping to PCI DSS/NIST/HIPAA, MITRE ATT&CK tagging), active response, and a
rule engine that also understands pfSense syslog (`pf` decoder).

**How it fits here**: the Wazuh indexer is itself OpenSearch, so the same Grafana can
query `wazuh-alerts-4.x-*` next to `suricata-*`. The three dashboards in
[`dashboards/wazuh/`](../../dashboards/wazuh/README.md) (security overview, vulnerability
detection, file integrity monitoring) plus the deploy script are what this repo
contributes. pfSense-side requirements are in [wazuh/README.md](wazuh/README.md).

**What it costs**: another 16–32 GB of RAM for manager + indexer, agent rollout, and a
second place where rules live. Worth it when you have compliance requirements or
endpoints to watch; overkill for a firewall-only view.

## Graylog (shelved)

Graylog was evaluated because of its easier UI and strong alerting. It was shelved
because it duplicates what OpenSearch + Grafana already do here, adds a MongoDB
dependency, and its enterprise features (archiving, some alerting) sit behind a
licence. The old `GRAYLOG_INDEX.md` / `GRAYLOG_SURICATA_SETUP.md` guides live in git
history ([ARCHIVE.md](../ARCHIVE.md)). What a revival would need is listed in
[graylog/README.md](graylog/README.md). Nobody is working on it.

---

## Feature matrix

| Feature | OpenSearch + Grafana | Wazuh | Graylog |
|---------|---------------------|-------|---------|
| Status here | ✅ Production | ✅ Dashboards + deploy script | ⏸️ Shelved |
| Licence | Apache 2.0 | GPL v2 (server); indexer Apache 2.0 | SSPL / enterprise |
| Setup effort | Medium (`install.sh` automates it) | High (manager, indexer, agents) | Medium (MongoDB + OpenSearch) |
| Grafana integration | Native datasource | Via the indexer (same datasource) | Plugin/API |
| Alerting | Grafana alerting (rules as code planned) | Built-in, mature | Built-in, mature |
| Compliance reporting | Manual | Built-in | Partial |
| Endpoint/EDR | No | Yes | No |
| Active response | No | Yes | Limited |
| Query language | OpenSearch DSL / Lucene | OpenSearch DSL / Wazuh rules | Graylog search |
| Resource use | High | High | Medium |

## Decision guide

- **Just want to see what your firewall is doing, in Grafana** → OpenSearch. Follow the
  [Quick Start](../../QUICK_START.md).
- **Also have servers/workstations, or compliance requirements** → OpenSearch for the
  network view *plus* Wazuh via siem-docker-stack. Use the Wazuh dashboards here.
- **Prefer a single product with its own UI and no Grafana** → this project is not a
  good fit; Wazuh's own dashboard or Graylog are closer, but you will be on your own for
  the pfSense-specific tuning content (which still applies — see
  [docs/pfsense/](../DOCUMENTATION_INDEX.md#-pfsense-knowledge-base-no-siem-required)).

## Running more than one

Yes, and it is what the maintainer does: OpenSearch for Suricata/pfBlockerNG,
Wazuh for endpoints and pfSense syslog, one Grafana in front of both. Budget 32 GB+ RAM
for the server(s) and keep the data separated by index (`suricata-*`, `pfblockerng-*`,
`wazuh-alerts-*`) rather than shipping the same events twice.

## Resources

- [OpenSearch documentation](https://opensearch.org/docs/) ·
  [Grafana OpenSearch datasource](https://grafana.com/docs/grafana/latest/datasources/opensearch/)
- [Wazuh documentation](https://documentation.wazuh.com/) ·
  [Monitoring pfSense with Wazuh](https://wazuh.com/blog/monitoring-pfsense-firewalls-with-wazuh/)
- [Graylog documentation](https://docs.graylog.org/)

Questions or a case for reviving Graylog: open a
[GitHub Discussion](https://github.com/ChiefGyk3D/pfsense-siem-stack/discussions).
