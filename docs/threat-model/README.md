# Threat model

`pfsense-siem-stack.threat-dragon.json` is an OWASP Threat Dragon v2 model of the stack this repo builds:
Suricata and pfBlockerNG on pfSense, the EVE forwarder (`scripts/forward-suricata-eve.py`), the UDP
transport to Logstash, OpenSearch, Grafana, the operator tooling (`setup.sh`, `install.sh`,
`pfsense-siem`) and the CI that ships it. There is no LLM, SOAR or alerting component in this repo
(`scripts/check-telegram-alerts.sh` only greps logs), so none is modeled.

Open it with OWASP Threat Dragon (desktop or web app): File > Open, pick the JSON file.

## Trust boundaries

- Untrusted network: WAN and monitored LAN hosts; all traffic and any packet to the SIEM ports.
- pfSense firewall host: Suricata, pfBlockerNG, Telegraf, the forwarder; runs as root.
- SIEM server: Logstash, OpenSearch, Grafana, installed by `install.sh`.
- Operator workstation: `config.env`, SSH keys, the setup tooling.
- Upstream and CI: package repositories, rule/feed providers, GitHub Actions.

## Evidence rule

Claims cite a file in the repo. Items known only from prose docs are marked `UNVERIFIED`.
The model was read from code, not run; nothing was scanned or executed.

## Open High and Critical threats

- Critical: OpenSearch has no authentication or TLS, listens on `0.0.0.0` and the installer opens
  9200 to all sources (`install.sh`). Documented as a known gap in `docs/reference/CONFIGURATION.md`.
- High: Logstash UDP 5140 accepts unauthenticated, plaintext, spoofable events from any source.
- High: default Grafana admin password (`admin`) in the installer and example config.
- High: sensitive network metadata in indices readable through the open API.

## UNVERIFIED items

- Rule and feed provider flow and the false-positive drop threat (inline IPS, `config/sid`).
- pfBlockerNG process and its log flow to Telegraf (docs only).
- Telegraf output to OpenSearch over HTTP (docs only; config lives in pfSense `config.xml`).
- Stored-XSS risk in dashboards from attacker-controlled fields (panels not inspected).
- CrowdSec `fetch | sh` install (exploratory doc, not integrated).

## Not reviewed

`wiki.yml` and `dependabot-auto-merge.yml` permissions beyond the header; the `.sh` Telegraf plugins
line by line; whether the retention policy covers `pfblockerng-*`.
