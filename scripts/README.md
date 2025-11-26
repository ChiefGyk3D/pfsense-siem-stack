# Scripts Directory

Essential scripts for pfSense Suricata Dashboard. **Most users only need `../setup.sh` and `status.sh`**.

## 🌟 Main Scripts

### Setup (../setup.sh)
**ONE-COMMAND installer** - Configures everything automatically

```bash
./setup.sh  # Run from project root
```

- Loads config from `config.env`
- Configures OpenSearch
- Deploys forwarder to pfSense  
- Installs watchdog
- Verifies installation

### status.sh
**Health check** - Diagnose problems

```bash
./scripts/status.sh
```

Checks OpenSearch, Logstash, forwarder, data flow, and Suricata.

## 📦 Component Scripts

- **install-opensearch-config.sh** - OpenSearch configuration (called by setup.sh)
- **forward-suricata-eve-python.py** - Forwarder deployed to pfSense
- **setup_forwarder_monitoring.sh** - Interactive monitoring setup (NEW)
- **restart-services.sh** - Restart SIEM services
- **configure-retention-policy.sh** - Set data retention

### Forwarder Monitoring Setup

**Interactive configuration** for automatic forwarder monitoring:

```bash
./scripts/setup_forwarder_monitoring.sh
```

Choose from preset monitoring strategies:
- **Hybrid** (recommended): Crash recovery + activity monitoring
- **Simple**: Crash recovery only
- **24/7**: Full monitoring around the clock
- **Business Hours**: Weekday monitoring only
- **Custom**: Configure your own settings

See [Forwarder Monitoring Documentation](../docs/SURICATA_FORWARDER_MONITORING.md) for details.

## 📁 Archive

Old scripts superseded by `setup.sh` and `status.sh`. Kept for reference.

## 🚀 Quick Start

```bash
sudo ./install.sh                 # Install SIEM stack
cp config.env.example config.env  # Configure
nano config.env                   # Edit IPs
./setup.sh                        # Setup everything
./scripts/status.sh               # Verify
```

See `../README.md` for full documentation.
