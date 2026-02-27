# pfSense Suricata Dashboards for Grafana

Grafana dashboards for monitoring Suricata IDS/IPS on pfSense, powered by OpenSearch.

![Suricata IDS/IPS Dashboard](images/dashboard-preview.png)

## Architecture

```
┌──────────────┐     UDP      ┌──────────┐           ┌────────────┐     query     ┌─────────┐
│   pfSense    │────5140────▶ │ Logstash │──────────▶│ OpenSearch │◀────────────── │ Grafana │
│  (Suricata)  │              │          │           │            │               │         │
│  + Forwarder │              └──────────┘           └────────────┘               └─────────┘
│  + GeoIP     │                                    suricata-YYYY.MM.dd
└──────────────┘
```

**Forwarder** runs on pfSense, tails all Suricata EVE JSON logs, enriches with GeoIP, and sends via UDP.
**Logstash** receives, parses JSON, and indexes into OpenSearch with daily indices.
**Grafana** queries OpenSearch with pre-built dashboards for IDS/IPS alerts, traffic analysis, and geolocation.

## Quick Start

### Prerequisites

| Component | Where | Version |
|-----------|-------|---------|
| pfSense CE | Firewall | 2.7+ |
| Suricata | pfSense package | Any |
| Python 3 | pfSense (`pkg install python311`) | 3.11+ |
| OpenSearch | SIEM server | 2.x |
| Logstash | SIEM server | 8.x |
| Grafana | SIEM server | 10+ |
| OpenSearch plugin | Grafana | `grafana-opensearch-datasource` |

### Install (3 steps)

```bash
# 1. Clone and configure
git clone https://github.com/ChiefGyk3D/pfsense-siem-stack.git
cd pfsense-siem-stack
cp config.env.example config.env
nano config.env          # Set SIEM_HOST and PFSENSE_HOST (at minimum)

# 2. Set up SSH key access to pfSense (if not done already)
ssh-copy-id admin@<your-pfsense-ip>

# 3. Run the installer
./setup.sh
```

That's it. `setup.sh` handles everything:
- Applies OpenSearch index template and auto-create settings
- Deploys Logstash pipeline config (if SIEM server is SSH-accessible)
- Deploys the forwarder + watchdog cron to pfSense
- Imports both Grafana dashboards via API
- Verifies end-to-end data flow

### Configuration

Edit `config.env` — the only file you need to touch:

```bash
SIEM_HOST=192.168.1.10       # Your SIEM server IP
PFSENSE_HOST=192.168.1.1     # Your pfSense IP
PFSENSE_USER=admin           # SSH user for pfSense
SIEM_SSH_USER=chiefgyk3d     # SSH user for SIEM server (for Logstash deploy)
GRAFANA_ADMIN_USER=admin     # Grafana login
GRAFANA_ADMIN_PASS=admin     # Grafana password
```

See [config.env.example](config.env.example) for all options.

## Dashboards

### Suricata IDS/IPS Dashboard
Main dashboard with 14 panels:
- Events & alerts timeline
- Event type and protocol distribution
- Top source/destination IPs
- Top DNS queries, HTTP hosts, destination ports
- Alert signatures and severity
- GeoIP source country map
- IDS alert log table

### Suricata Per-Interface Dashboard
Interface-focused dashboard with row-repeat:
- Per-interface stats, alerts, top IPs
- Automatically creates sections for each Suricata interface

Both dashboards support an **interface filter** dropdown to focus on specific VLANs/interfaces.

## Troubleshooting

### No data in dashboards?

```bash
# 1. Check forwarder is running on pfSense
ssh admin@<pfsense> 'ps aux | grep forward-suricata'

# 2. Check Logstash is receiving data
ssh user@<siem> 'sudo journalctl -u logstash --since "5 min ago" | tail -20'

# 3. Check OpenSearch has events
curl http://<siem>:9200/suricata-*/_count

# 4. Run the diagnostic script
./scripts/diagnose-and-repair.sh
```

### Common issues

| Problem | Solution |
|---------|----------|
| Forwarder not running | Watchdog cron restarts it within 1 minute. Check: `crontab -l` on pfSense |
| No EVE logs on pfSense | Enable Suricata on interfaces: Services → Suricata |
| Logstash not receiving | Check UDP 5140 is open: `ss -ulnp \| grep 5140` on SIEM |
| Wrong field types in OpenSearch | Delete today's index, re-apply template: `./scripts/install-opensearch-config.sh` |
| GeoIP not working | Install ntopng on pfSense for GeoLite2-City.mmdb, or see [GeoIP docs](docs/GEOIP_ENRICHMENT.md) |

## Project Layout

```
config/
  logstash-suricata.conf          # Logstash pipeline config
  opensearch-index-template.json  # OpenSearch index template
dashboards/
  Suricata_IDS_IPS.json           # Main IDS/IPS dashboard
  Suricata_Per_Interface.json     # Per-interface dashboard
scripts/
  forward-suricata-eve.py         # Forwarder (deployed to pfSense)
  diagnose-and-repair.sh          # End-to-end diagnostic tool
  install-opensearch-config.sh    # OpenSearch template/settings installer
  status.sh                       # Check all component status
  configure-retention-policy.sh   # Set index retention/cleanup
docs/                             # Detailed documentation
config.env.example                # Configuration template
setup.sh                          # Main installer (start here)
```

## Advanced Topics

- [SIEM Stack Installation](docs/INSTALL_SIEM_STACK.md) — Installing OpenSearch, Logstash, Grafana from scratch
- [pfSense Forwarder Details](docs/INSTALL_PFSENSE_FORWARDER.md) — Manual forwarder setup
- [GeoIP Enrichment](docs/GEOIP_ENRICHMENT.md) — GeoIP database setup and map dashboards
- [Suricata SID Management](config/sid/) — Custom rule tuning
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) — Detailed problem resolution

## Contributing

PRs welcome. Please test with at least one pfSense + OpenSearch setup before submitting.

## License

MIT

## Support

If this project helps you, consider supporting development:

- [GitHub Sponsors](https://github.com/sponsors/ChiefGyk3D)
- [Ko-fi](https://ko-fi.com/chiefgyk3d)
- BTC: `bc1qtdwm3fhxjpdgvnfcmlu3m5enwkgas6ynyf3c0j`
