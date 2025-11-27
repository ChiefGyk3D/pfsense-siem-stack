# Graylog + Suricata IDS Setup - Documentation Index

Complete documentation for integrating Graylog with Suricata IDS on pfSense and visualizing with Grafana.

## 📚 Documentation Structure

### Getting Started

1. **[GRAYLOG_SURICATA_SETUP.md](GRAYLOG_SURICATA_SETUP.md)** - Main Setup Guide
   - Complete step-by-step installation guide
   - Architecture overview
   - Detailed configuration for all components
   - Integration instructions
   - Troubleshooting section
   - **Start here** if you're new to the stack

2. **[QUICK_SETUP_COMMANDS.md](QUICK_SETUP_COMMANDS.md)** - Quick Reference
   - All essential commands in one place
   - Copy-paste ready
   - Minimal explanations
   - Perfect for experienced users
   - **Start here** if you know what you're doing

3. **[TROUBLESHOOTING_CHECKLIST.md](TROUBLESHOOTING_CHECKLIST.md)** - Diagnostic Guide
   - Comprehensive troubleshooting checklist
   - Common issues and solutions
   - Service management commands
   - Performance baselines
   - Emergency recovery procedures
   - **Start here** if something isn't working

### Scripts

4. **[scripts/forward-suricata-logs.sh](scripts/forward-suricata-logs.sh)** - Log Forwarder
   - Forwards Suricata EVE JSON logs to Graylog
   - Built-in testing and monitoring
   - Start/stop/restart management
   - See [scripts/README.md](scripts/README.md) for usage

5. **[scripts/README.md](scripts/README.md)** - Scripts Documentation
   - Installation instructions for scripts
   - Usage examples
   - Configuration details

### Main Project

6. **[README.md](README.md)** - Project Overview
   - Main pfSense Grafana dashboard documentation
   - InfluxDB + Telegraf monitoring
   - System metrics dashboard
   - Now includes link to IDS/IPS monitoring

## 🗺️ Setup Workflow

### Recommended Setup Order

```
┌─────────────────────────────────────────────────────┐
│ 1. Read GRAYLOG_SURICATA_SETUP.md (Architecture)   │
│    Understand the components and requirements       │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 2. Follow QUICK_SETUP_COMMANDS.md or detailed guide │
│    Install MongoDB → Data Node → Graylog → Grafana  │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 3. Configure pfSense                                │
│    Enable Suricata + Configure syslog forwarding    │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 4. Setup Log Forwarding                             │
│    Install and configure forward-suricata-logs.sh   │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 5. Configure Graylog                                │
│    Create inputs, extractors, and streams           │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 6. Setup Grafana                                    │
│    Add OpenSearch data source + Import dashboard    │
└─────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────┐
│ 7. Verify and Test                                  │
│    Use TROUBLESHOOTING_CHECKLIST.md if needed       │
└─────────────────────────────────────────────────────┘
```

## 📖 Quick Links by Task

### I want to...

#### Install the complete stack
- Start: [GRAYLOG_SURICATA_SETUP.md - Part 1](GRAYLOG_SURICATA_SETUP.md#part-1-install-graylog-with-opensearch)
- Quick version: [QUICK_SETUP_COMMANDS.md - Section 1-7](QUICK_SETUP_COMMANDS.md#1-install-graylog-stack-ubuntu-22042404)

#### Configure Suricata on pfSense
- Guide: [GRAYLOG_SURICATA_SETUP.md - Part 2](GRAYLOG_SURICATA_SETUP.md#part-2-configure-suricata-on-pfsense)

#### Forward logs from pfSense to Graylog
- Syslog: [GRAYLOG_SURICATA_SETUP.md - Step 2.3](GRAYLOG_SURICATA_SETUP.md#step-3-configure-syslog-forwarding-to-graylog)
- Suricata: [scripts/README.md - forward-suricata-logs.sh](scripts/README.md#forward-suricata-logssh)

#### Setup Graylog inputs and extractors
- Guide: [GRAYLOG_SURICATA_SETUP.md - Part 3](GRAYLOG_SURICATA_SETUP.md#part-3-configure-graylog-inputs)

#### Connect Grafana to OpenSearch
- Guide: [GRAYLOG_SURICATA_SETUP.md - Part 4](GRAYLOG_SURICATA_SETUP.md#part-4-configure-opensearch-data-source-in-grafana)

#### Import the IDS dashboard
- Guide: [GRAYLOG_SURICATA_SETUP.md - Part 5](GRAYLOG_SURICATA_SETUP.md#part-5-import-grafana-dashboard)
- Dashboard: https://grafana.com/grafana/dashboards/22780

#### Troubleshoot issues
- Checklist: [TROUBLESHOOTING_CHECKLIST.md](TROUBLESHOOTING_CHECKLIST.md)
- Common issues: [GRAYLOG_SURICATA_SETUP.md - Troubleshooting](GRAYLOG_SURICATA_SETUP.md#troubleshooting)

#### Monitor system metrics (InfluxDB/Telegraf)
- Original dashboard: [README.md](README.md)

## 🎯 Quick Command Reference

### Check Service Status
```bash
sudo systemctl status mongod graylog-datanode graylog-server grafana-server
```

### View Live Logs
```bash
sudo journalctl -u graylog-server -f
```

### Test Connectivity
```bash
# From pfSense to Graylog
echo "test" | nc -u graylog-ip 1514

# From anywhere to OpenSearch
curl http://graylog-ip:9200
```

### Restart All Services
```bash
sudo systemctl restart mongod
sleep 10
sudo systemctl restart graylog-datanode
sleep 30
sudo systemctl restart graylog-server
```

## 🔗 External Resources

### Official Documentation
- **Graylog**: https://go2docs.graylog.org/
- **Suricata**: https://suricata.readthedocs.io/
- **OpenSearch**: https://opensearch.org/docs/
- **Grafana**: https://grafana.com/docs/
- **pfSense**: https://docs.netgate.com/

### Community Forums
- **Graylog Community**: https://community.graylog.org/
- **pfSense Forum**: https://forum.netgate.com/
- **Grafana Community**: https://community.grafana.com/

### Dashboards
- **pfSense IDS Dashboard**: https://grafana.com/grafana/dashboards/22780
- **pfSense System Dashboard**: [pfSense-Grafana-Dashboard.json](pfSense-Grafana-Dashboard.json)

## 📊 What Gets Monitored

### With This IDS Stack
- ✅ Firewall logs (pfSense)
- ✅ IDS/IPS alerts (Suricata)
- ✅ Network traffic patterns
- ✅ Security events
- ✅ Blocked connections
- ✅ Attack signatures
- ✅ Protocol anomalies

### With Original Dashboard (InfluxDB/Telegraf)
- ✅ System metrics (CPU, RAM, Disk)
- ✅ Network throughput
- ✅ Gateway response times
- ✅ Interface statistics
- ✅ pfBlocker statistics
- ✅ DNS query metrics (optional)

## 🎓 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                         pfSense                              │
│                                                               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   Firewall   │    │   Suricata   │    │   Telegraf   │  │
│  │    Rules     │    │     IDS      │    │   (System    │  │
│  │              │    │              │    │   Metrics)   │  │
│  └──────┬───────┘    └──────┬───────┘    └──────┬───────┘  │
│         │                   │                    │          │
└─────────┼───────────────────┼────────────────────┼──────────┘
          │                   │                    │
          │ Syslog            │ JSON               │ Metrics
          │ UDP:1514          │ TCP:1515           │ HTTP:8086
          │                   │                    │
          ↓                   ↓                    ↓
┌─────────────────────┐  ┌────────────────┐  ┌──────────────┐
│      Graylog        │  │   InfluxDB     │  │              │
│  ┌────────────┐     │  │   (Time-series │  │              │
│  │  Data Node │     │  │    Database)   │  │              │
│  │ (OpenSearch)     │  │                │  │              │
│  └─────┬──────┘     │  └───────┬────────┘  │              │
│        │            │          │           │              │
│  ┌─────┴──────┐     │          │           │              │
│  │  MongoDB   │     │          │           │              │
│  │ (Metadata) │     │          │           │              │
│  └────────────┘     │          │           │              │
└─────────┬───────────┘          │           │              │
          │                      │           │              │
          │ OpenSearch API       │ InfluxQL  │              │
          │ HTTP:9200            │ HTTP:8086 │              │
          │                      │           │              │
          └──────────────────────┴───────────┴──────────────┤
                                                             │
                        ┌────────────────────────────────────┘
                        │
                        ↓
                ┌───────────────┐
                │    Grafana    │
                │               │
                │ ┌───────────┐ │
                │ │ OpenSearch│ │  → IDS/Firewall Dashboards
                │ │   Source  │ │
                │ └───────────┘ │
                │               │
                │ ┌───────────┐ │
                │ │  InfluxDB │ │  → System Metrics Dashboards
                │ │   Source  │ │
                │ └───────────┘ │
                └───────────────┘
```

## 💡 Pro Tips

1. **Start with test data**: Use `echo "test" | nc -u graylog-ip 1514` to verify connectivity before configuring complex setups

2. **Monitor resource usage**: Keep an eye on RAM and disk usage, especially for OpenSearch

3. **Use streams in Graylog**: Organize logs by creating streams for different log types

4. **Set up alerting**: Configure Graylog alerts for critical IDS events

5. **Regular maintenance**: 
   - Rotate logs
   - Clean up old indices
   - Update Suricata rules
   - Backup configurations

6. **Security first**:
   - Change default passwords
   - Enable HTTPS
   - Restrict network access
   - Keep software updated

## 🆘 Getting Help

If you run into issues:

1. **Check the troubleshooting checklist**: [TROUBLESHOOTING_CHECKLIST.md](TROUBLESHOOTING_CHECKLIST.md)
2. **Review logs**: Most issues show up in service logs
3. **Test connectivity**: Use netcat to verify network paths
4. **Search GitHub issues**: https://github.com/ChiefGyk3D/pfsense_grafana/issues
5. **Ask the community**: Links in each official documentation

## 📝 Contributing

Found an issue or want to improve the documentation?

1. Fork the repository
2. Make your changes
3. Submit a pull request
4. Or open an issue: https://github.com/ChiefGyk3D/pfsense_grafana/issues

## 📜 License

All documentation and scripts are licensed under **MPL 2.0**.

See [LICENSE](LICENSE) for details.

---

**Project**: https://github.com/ChiefGyk3D/pfsense_grafana  
**Created**: November 24, 2025  
**Author**: ChiefGyk3D  
**License**: Mozilla Public License 2.0
