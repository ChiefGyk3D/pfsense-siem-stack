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

None.

## Open, reduced to Medium: forged events on UDP 5140 (t_spoof)

Was High. `config/logstash-suricata.conf` now parses the sender's JSON into `[@metadata][eve]`,
validates it, and copies only allow-listed keys to the root, so the sender cannot overwrite
`@timestamp`, `tags`, `host` or add fields; invalid events go to `eve-quarantine-*`. Residual: a host that can reach the port (or spoof the pfSense
address on the same segment) can still send a well-formed fake alert, or flood noise to hide a real one.
It is Medium because nothing in this repo acts on events (no alert rules or automation found). Fix for the
residual is a network control: a dedicated VLAN or IPsec/WireGuard path to the SIEM
(`docs/reference/CONFIGURATION.md`, Sender integrity). The filter was tested under plain ruby, not in Logstash.

## Mitigated in the fix for #49

- Critical: OpenSearch bound to `0.0.0.0` with no authentication and 9200 open to all. Now loopback by
  default, no 9200 rule, remote exposure only by explicit settings (`render_opensearch_yml`,
  `firewall_plan` in `scripts/lib-install-safety.sh`). `INSECURE_OPEN_ACCESS=true` restores the old install.
- High: default Grafana `admin` password. Now set or generated, `admin` refused (`install.sh`, `setup.sh`);
  port 3000 limited to `GRAFANA_ALLOWED_SOURCES`.
- High: network metadata readable through the open API. Follows from the first item.

Residual: the OpenSearch security plugin is still disabled (no authentication or TLS), and existing installs
keep their old `opensearch.yml` and ufw rules until the operator changes them (the installer warns).

## UNVERIFIED items

- Rule and feed provider flow and the false-positive drop threat (inline IPS, `config/sid`).
- pfBlockerNG process and its log flow to Telegraf (docs only).
- Telegraf output to OpenSearch over HTTP (docs only; config lives in pfSense `config.xml`).
- Stored-XSS risk in dashboards from attacker-controlled fields (panels not inspected).
- CrowdSec `fetch | sh` install (exploratory doc, not integrated).

## Not reviewed

`wiki.yml` and `dependabot-auto-merge.yml` permissions beyond the header; the `.sh` Telegraf plugins
line by line; whether the retention policy covers `pfblockerng-*`.
