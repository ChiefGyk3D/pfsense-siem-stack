# pfSense Suricata IDS/IPS Dashboard for Grafana

A complete monitoring solution for pfSense Suricata IDS/IPS using Grafana, OpenSearch, and Logstash. Features real-time alert visualization, GeoIP mapping, and comprehensive event analytics.

![WAN Dashboard Preview](media/Suricata%20IDS_IPS%20WAN%20Dashboard.png)

*Live WAN-side monitoring with attack sources, alert signatures, and geographic visualization*

## 🌟 Features

### WAN-Side Monitoring (Current)
- **Real-time IDS/IPS Monitoring**: Live alert feeds with detailed signature information
- **GeoIP Visualization**: Interactive world map showing attack sources with city-level accuracy
- **Multi-Interface Support**: Monitors all Suricata instances simultaneously
- **Event Analytics**: Comprehensive breakdowns by type, protocol, severity, and category
- **Attack Tracking**: Top signatures, source countries, HTTP hosts, and more
- **Clean Design**: Optimized pie charts and tables with minimal clutter

### LAN-Side Monitoring (Coming Soon)
- Internal network traffic analysis
- RFC1918 source/destination filtering
- Lateral movement detection
- Internal host activity tracking

## 📋 Prerequisites

### Required Software
- **pfSense**: 2.7+ (tested on 2.8.1)
- **Suricata**: IDS/IPS package installed on pfSense
- **SIEM Server** (Ubuntu/Debian recommended):
  - OpenSearch 2.x
  - Logstash 8.x
  - Grafana 12.x
  - Python 3.11+ (for pfSense forwarder)

### Network Requirements
- pfSense must be able to reach SIEM server on UDP port 5140 (Logstash)
- Grafana accessible on port 3000
- OpenSearch on port 9200

## 🚀 Quick Start

### 1. Install SIEM Stack (Ubuntu/Debian)

```bash
# Clone repository
git clone https://github.com/ChiefGyk3D/pfsense_grafana.git
cd pfsense_grafana

# Run automated SIEM installer (OpenSearch, Logstash, Grafana)
sudo ./install.sh
```

This installs the complete SIEM stack on your server.

### 2. Configure Your Environment

**Create your configuration file** (required):

```bash
# Copy the example config
cp config.env.example config.env

# Edit with your settings
nano config.env
```

**Minimum required settings:**
```bash
SIEM_HOST=192.168.210.10      # Your SIEM server IP
PFSENSE_HOST=192.168.1.1       # Your pfSense firewall IP
```

All other settings have sensible defaults but can be customized.

### 3. Run Automated Setup

**ONE COMMAND** to configure everything:

```bash
./setup.sh
```

This single script will:
- ✅ Load your configuration from `config.env`
- ✅ Configure OpenSearch with proper index templates and auto-create settings
- ✅ Deploy the forwarder to pfSense with your SIEM IP
- ✅ Install and configure the watchdog for automatic restarts
- ✅ Verify everything is working

**That's it!** No manual configuration needed.

### 4. Import Dashboard

1. Open Grafana: `http://<siem-server-ip>:3000`
2. Login (default: admin/admin)
3. Go to **Dashboards** → **New** → **Import**
4. Upload: `dashboards/Suricata IDS_IPS Dashboard.json`
5. **Select your OpenSearch datasource** when prompted
6. Click **Import**

### 5. Verify Installation

Check everything is working:

```bash
./scripts/status.sh
```

This will verify:
- ✅ OpenSearch is running and configured correctly
- ✅ Logstash is listening for events
- ✅ Forwarder is running on pfSense
- ✅ Data is flowing and recent
- ✅ Watchdog is installed
- ✅ Suricata is generating events

**Green checkmarks** = everything is working!  
**Red X's** = see the error messages and suggested fixes

## 📁 Project Structure

```
pfsense_grafana/
├── config.env.example          # Configuration template (copy to config.env)
├── setup.sh                    # 🌟 ONE-COMMAND automated setup
├── install.sh                  # SIEM stack installer (run first)
├── dashboards/                 # Grafana dashboard JSON files
│   └── Suricata IDS_IPS Dashboard.json    ← Import this
├── scripts/
│   ├── forward-suricata-eve-python.py     ← Multi-interface forwarder
│   ├── install-opensearch-config.sh       ← OpenSearch configuration
│   ├── status.sh                          ← 🔍 Comprehensive health check
│   ├── restart-services.sh                ← Restart SIEM services
│   └── configure-retention-policy.sh      ← Set data retention
├── config/                     # Configuration files
│   ├── README.md                          ← OpenSearch setup docs
│   ├── logstash-suricata.conf             ← Logstash pipeline
│   └── opensearch-index-template.json     ← Index with geo_point
├── docs/                       # Detailed documentation
│   ├── OPENSEARCH_AUTO_CREATE.md          ← Midnight UTC problem fix
│   ├── TROUBLESHOOTING.md                 ← Common issues
│   └── GEOIP_SETUP.md                     ← GeoIP configuration
├── plugins/                    # Optional Telegraf plugins
│   └── telegraf_*.php/sh                  ← System metrics collectors
└── media/                      # Screenshots
    └── Suricata IDS_IPS WAN Dashboard.png ← Dashboard preview
```

**Key files:**
- `config.env.example` → Copy to `config.env` and customize
- `setup.sh` → Run this after installing SIEM stack
- `scripts/status.sh` → Check if everything is working

## 📊 Dashboard Panels

### Current Dashboard: WAN-Side Monitoring

Focused on external threats and inbound attack analysis.

#### Statistics
- **Events & Alerts**: Combined counter with sparklines and color-coded thresholds
- **Event Type Distribution**: Pie chart showing alert, http, dns, tls, etc.
- **Protocol Distribution**: TCP, UDP, ICMP breakdown
- **Interface Distribution**: Traffic by WAN interface

#### Alerts
- **Top 10 Alert Signatures**: Most triggered IDS rules
- **IDS Alert Logs**: Detailed table with time, signature, IPs, ports, countries
- **Alert Severity Breakdown**: Critical, high, medium, low classification

#### Geographic Visualization
- **Inbound Attack Sources Map**: Interactive world map with geohash clusters
- **Top 10 Source Countries**: Donut chart of attack origins
- **Country Statistics Table**: Detailed breakdown with event counts

#### HTTP Traffic Analysis
- **Top 10 HTTP Hosts**: Most accessed domains
- **HTTP Methods**: GET, POST, etc. distribution

### Upcoming: LAN-Side Dashboard

A companion dashboard for internal network monitoring (in development):
- Internal host communication patterns
- East-West traffic analysis
- RFC1918 source/destination focus
- Potential lateral movement detection

## 🔧 Configuration

### Customize Logstash Input

Edit `/etc/logstash/conf.d/suricata.conf`:

```ruby
input {
  udp {
    port => 5140
    codec => json
  }
}
```

### Adjust Data Retention

```bash
# Configure index lifecycle policy
scripts/configure-retention-policy.sh
```

Default retention: 30 days

### GeoIP Updates

The forwarder uses MaxMind GeoLite2-City database. To update:

```bash
# On pfSense, if using ntopng, it auto-updates
# Manual update:
ssh root@pfsense
fetch -o /usr/local/share/ntopng/GeoLite2-City.mmdb \
  https://github.com/PrxyHunter/GeoLite2/raw/master/GeoLite2-City.mmdb
```

## 🔍 Troubleshooting

### Quick Diagnosis

**Run the status check first:**

```bash
./scripts/status.sh
```

This will identify most common problems automatically.

### Common Issues

**1. Dashboard shows "No Data"** ⚠️ MOST COMMON
- **Symptom**: Grafana panels show "No Data" even though Suricata is running
- **Causes**: 
  - Datasource variable not resolved (`${DS_OPENSEARCH}` instead of actual datasource UID)
  - Nested field structure vs flat field queries (dashboard expecting `event_type` but data has `suricata.eve.event_type`)
  - Logstash config changed from flat to nested structure
  - Dashboard looking at wrong time range (new flat data only exists in recent timeframe)
- **Fixes**:
  1. Check datasource configuration: Dashboard must use actual UID, not `${DS_OPENSEARCH}` variable
  2. Verify field structure: `curl -s "http://localhost:9200/suricata-*/_search?size=1" | jq '.hits.hits[0]._source | keys'`
  3. If fields are nested under `suricata.eve.*`, update Logstash config to flatten OR update dashboard queries
  4. Run `./scripts/status.sh` to diagnose data flow issues
  5. Adjust time range to match when data started flowing (check index creation timestamps)

**2. Alerts not showing but other events are**
- **Symptom**: DNS, TLS, HTTP events work, but alert panels empty
- **Cause**: Forwarder only tails from EOF (end of file), missing historical alerts
- **Fix**: Wait for NEW alerts to be generated after forwarder starts
- **Why**: The forwarder uses `f.seek(0, 2)` to start at end of file, so pre-existing alerts aren't forwarded
- **Solution**: Generate test alerts or wait for real attacks to trigger rules

**3. Data structure mismatch**
- **Symptom**: Old data works but new data doesn't (or vice versa)
- **Diagnosis**: 
  ```bash
  # Check if you have both nested and flat structures
  curl -s "http://localhost:9200/_search?size=0" -H 'Content-Type: application/json' \
    -d '{"aggs":{"nested":{"filter":{"exists":{"field":"suricata.eve.event_type"}}},"flat":{"filter":{"exists":{"field":"event_type"}}}}}'
  ```
- **Fix**: 
  1. Choose flat or nested structure (flat is simpler)
  2. Update Logstash config to match
  3. Update dashboard field references to match
  4. Optional: Reindex old data to match new structure

**4. Forwarder not running**
- Run `./scripts/status.sh` to check forwarder status
- Verify: `./setup.sh` was run successfully
- Check forwarder logs: `ssh root@<pfsense-ip> 'tail -f /var/log/system.log | grep suricata'`

**5. Data stops at midnight UTC**
- **Cause**: OpenSearch auto-create disabled
- **Fix**: Run `./setup.sh` (it configures this automatically)
- **Details**: See `docs/OPENSEARCH_AUTO_CREATE.md`

**6. Multiple forwarders running**
- Kill extras: `ssh root@<pfsense-ip> 'pkill -f forward-suricata'`
- Run `./setup.sh` to start single clean instance

**7. Wrong SIEM IP configured**
- Edit `config.env` with correct SIEM IP
- Run `./setup.sh` to redeploy with new config

### Detailed Troubleshooting

- **[Dashboard "No Data" Fix](docs/DASHBOARD_NO_DATA_FIX.md)**: 🔥 Complete guide for the most common issue - panels showing "No Data"
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)**: Comprehensive troubleshooting for all components

### Geomap Not Displaying

The geomap requires proper `geo_point` mapping. Check:

```bash
# Verify mapping
curl http://localhost:9200/suricata-*/_mapping | jq '.[] | .mappings.properties.suricata.properties.eve.properties.geoip_src.properties.location'

# Should show: {"type": "geo_point"}
```

If not, re-create the index template:

```bash
curl -X PUT "http://localhost:9200/_index_template/suricata-template" \
  -H 'Content-Type: application/json' \
  -d @config/opensearch-index-template.json
```

### Forwarder Not Monitoring All Interfaces

The forwarder should automatically detect all Suricata instances. If missing interfaces:

```bash
# Check available eve.json files
ssh root@pfsense 'ls -la /var/log/suricata/*/eve.json'

# Restart forwarder
pkill -f forward-suricata
nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &
```

See [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more solutions.

### pfBlocker Panels Show No Data

If the Telegraf dashboard's pfBlocker panels are empty, this is usually caused by pfSense's filterlog daemon not properly handling log rotation.

**Quick Fix:**
```bash
# Via SSH to pfSense
ssh root@pfsense
php -r 'require_once("/etc/inc/filter.inc"); filter_configure(); system_syslogd_start();'
php -r 'require_once("/usr/local/pkg/pfblockerng/pfblockerng.inc"); pfblockerng_sync_on_changes();'
```

**Prevention & Monitoring:**
See [pfSense Filterlog Rotation Fix](docs/PFSENSE_FILTERLOG_ROTATION_FIX.md) for:
- GUI configuration options
- Automated monitoring setup
- Preventive measures
- Integration with status.sh

## 📖 Documentation

### Setup Guides
- **[New User Checklist](docs/NEW_USER_CHECKLIST.md)**: 🎯 Complete step-by-step checklist for first-time setup
- **[Quick Start Guide](QUICK_START.md)**: Fast setup for experienced users
- **[SIEM Stack Installation](docs/INSTALL_SIEM_STACK.md)**: Detailed OpenSearch/Logstash/Grafana setup
- **[Forwarder Installation](docs/INSTALL_PFSENSE_FORWARDER.md)**: pfSense forwarder deployment
- **[Dashboard Import](docs/INSTALL_DASHBOARD.md)**: Dashboard configuration and customization

### Configuration
- **[Suricata Optimization Guide](docs/SURICATA_OPTIMIZATION_GUIDE.md)**: 🌟 Complete guide for new users - rule selection, performance tuning, IDS vs IPS
- **[GeoIP Setup](docs/GEOIP_SETUP.md)**: MaxMind database installation
- **[Configuration Guide](docs/CONFIGURATION.md)**: Advanced settings and tuning
- **[Telegraf Interface Fixes](docs/TELEGRAF_INTERFACE_FIXES.md)**: Universal interface detection
- **[Forwarder Monitoring](docs/SURICATA_FORWARDER_MONITORING.md)**: Automatic restart and monitoring strategies
- **[Telegraf pfBlocker Setup](docs/TELEGRAF_PFBLOCKER_SETUP.md)**: pfBlocker panel configuration

### Troubleshooting
- **[Dashboard "No Data" Fix](docs/DASHBOARD_NO_DATA_FIX.md)**: 🔥 **START HERE** - Fix the most common issue (panels showing "No Data")
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)**: Common issues and fixes for all components
- **[pfSense Filterlog Fix](docs/PFSENSE_FILTERLOG_ROTATION_FIX.md)**: Fix for pfBlocker data loss
- **[OpenSearch Auto-Create](docs/OPENSEARCH_AUTO_CREATE.md)**: Midnight UTC data stoppage fix

## 🔐 Security Considerations

- **Firewall Rules**: Restrict Logstash UDP 5140 to pfSense IP only
- **OpenSearch**: Bind to localhost or use authentication
- **Grafana**: Change default admin password immediately
- **GeoIP Data**: Contains location information - secure appropriately

## 🤝 Contributing

Contributions welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test changes thoroughly
4. Submit pull request with clear description

## 📜 License

This project is licensed under the MIT License - see [LICENSE](LICENSE) file.

## 🙏 Credits

- Original pfSense Telegraf dashboards by various contributors
- Suricata IDS/IPS by OISF
- OpenSearch by Amazon
- Grafana by Grafana Labs

## 💬 Support

- **Issues**: [GitHub Issues](https://github.com/ChiefGyk3D/pfsense_grafana/issues)
- **Discussions**: [GitHub Discussions](https://github.com/ChiefGyk3D/pfsense_grafana/discussions)
- **Documentation**: [Wiki](https://github.com/ChiefGyk3D/pfsense_grafana/wiki)

---

**Made with ❤️ for the pfSense community**
