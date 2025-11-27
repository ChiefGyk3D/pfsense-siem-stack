# Graylog + OpenSearch Setup for pfSense Suricata Log Analysis

Complete guide for setting up Graylog with OpenSearch to collect and analyze Suricata IDS/IPS logs from pfSense, with Grafana visualization.

## Architecture Overview

```
pfSense (Suricata) → Graylog (Logs Processing) → OpenSearch (Storage) → Grafana (Visualization)
```

## Server Information

- **Server IP**: 192.168.210.10
- **OS**: Ubuntu 24.04 LTS
- **Resources**: 32GB RAM, 1.8TB Storage

## Prerequisites

- Ubuntu 24.04 LTS server
- At least 4GB RAM (8GB+ recommended)
- Sudo/root access
- pfSense with Suricata installed

## Installation Steps

### Step 1: Install Graylog Stack (MongoDB, OpenSearch, Graylog)

Copy the installation script to your server and run it:

```bash
# From your local machine, copy the script to the server
scp scripts/install_graylog_opensearch.sh chiefgyk3d@192.168.210.10:~/

# SSH into the server
ssh chiefgyk3d@192.168.210.10

# Make the script executable and run it
chmod +x install_graylog_opensearch.sh
sudo ./install_graylog_opensearch.sh
```

The script will install:
1. **MongoDB** - Stores Graylog configuration data
2. **OpenSearch** - Stores and indexes log data
3. **Graylog** - Log collection and processing

**Installation Time**: ~10-15 minutes

After installation completes, note the admin password displayed on screen (also saved in `/root/graylog_admin_password.txt`).

### Step 2: Access Graylog Web Interface

1. Open a browser and navigate to: `http://192.168.210.10:9000`
2. Login with:
   - **Username**: `admin`
   - **Password**: (from installation output or `/root/graylog_admin_password.txt`)

### Step 3: Configure Graylog Input for Suricata Logs

Suricata can send logs in multiple formats. We'll configure both Syslog and GELF inputs:

#### Option A: Syslog UDP Input (Simpler, recommended)

1. In Graylog web UI, go to **System → Inputs**
2. Select **Syslog UDP** from the dropdown
3. Click **Launch new input**
4. Configure:
   - **Title**: `pfSense Suricata Syslog`
   - **Bind address**: `0.0.0.0`
   - **Port**: `514`
   - **Store full message**: Check this box
5. Click **Save**

#### Option B: GELF UDP Input (More structured data)

1. In Graylog web UI, go to **System → Inputs**
2. Select **GELF UDP** from the dropdown
3. Click **Launch new input**
4. Configure:
   - **Title**: `pfSense Suricata GELF`
   - **Bind address**: `0.0.0.0`
   - **Port**: `12201`
5. Click **Save**

### Step 4: Configure pfSense to Forward Suricata Logs

#### Method 1: Using Syslog (via System Logs Settings)

1. In pfSense, go to **Status → System Logs → Settings**
2. Under **Remote Logging Options**:
   - **Enable Remote Logging**: Check
   - **Source Address**: (leave default or select WAN interface)
   - **IP Protocol**: IPv4
   - **Remote log servers**: `192.168.210.10:514`
   - **Remote Syslog Contents**: Check all desired log types including **System Events**
3. Click **Save**

4. Go to **Services → Suricata → [Interface] → Alerts**
5. Enable **Send Alerts to System Log** (this sends alerts to syslog which will forward to Graylog)

#### Method 2: Using EVE JSON Output (Advanced)

1. In pfSense, go to **Services → Suricata → [Interface]**
2. Enable EVE JSON log output
3. Use the provided script to forward logs:

```bash
# On pfSense, create the forwarding script
mkdir -p /usr/local/etc/telegraf.d
cat > /usr/local/etc/rc.d/suricata_forward.sh <<'EOF'
#!/bin/sh
# Forward Suricata EVE logs to Graylog
tail -F /var/log/suricata/*/eve.json | \
    while read line; do
        echo "$line" | nc -u 192.168.210.10 12201
    done &
EOF

chmod +x /usr/local/etc/rc.d/suricata_forward.sh
/usr/local/etc/rc.d/suricata_forward.sh
```

### Step 5: Verify Logs in Graylog

1. In Graylog, go to **Search**
2. You should start seeing logs appear
3. Search for Suricata-specific keywords: `suricata`, `alert`, `IDS`, etc.
4. Create **Streams** to filter Suricata logs:
   - Go to **Streams → Create Stream**
   - Name it "Suricata Alerts"
   - Add rules to match Suricata messages

### Step 6: Create Graylog Extractors (Optional but Recommended)

Extractors parse fields from your logs for better searching:

1. Go to **System → Inputs → [Your Input] → Manage Extractors**
2. Click **Actions → Import extractors**
3. Create extractors for common Suricata fields:
   - `src_ip`, `dest_ip`, `src_port`, `dest_port`
   - `signature`, `severity`, `category`
   - `protocol`, `action`

## Grafana Configuration

### Step 7: Install Grafana OpenSearch Data Source Plugin

On your Grafana server (may be same or different server):

```bash
# Install the OpenSearch plugin
sudo grafana-cli plugins install grafana-opensearch-datasource

# Restart Grafana
sudo systemctl restart grafana-server
```

### Step 8: Configure OpenSearch Data Source in Grafana

1. In Grafana, go to **Configuration → Data Sources → Add data source**
2. Search for and select **OpenSearch**
3. Configure:
   - **Name**: `Graylog OpenSearch`
   - **URL**: `http://192.168.210.10:9200`
   - **Index name**: `graylog_*` (Graylog creates indices with this pattern)
   - **Time field name**: `timestamp`
   - **Version**: `2.0+`
   - **Min time interval**: `10s`
4. Click **Save & Test**

### Step 9: Import Grafana Dashboard

1. Go to **Dashboards → Import**
2. Enter dashboard ID: `22780`
3. Or use URL: `https://grafana.com/grafana/dashboards/22780`
4. Click **Load**
5. Select your **Graylog OpenSearch** data source
6. Click **Import**

**Note**: Dashboard 22780 is designed for pfSense with Suricata. You may need to adjust panel queries to match your Graylog field names.

### Step 10: Customize Dashboard Queries

The dashboard may need adjustments based on how Graylog indexes your data:

1. **Edit a panel** → **Edit**
2. Update queries to match Graylog field names:
   - Graylog typically uses fields like: `message`, `source`, `facility`, `level`
   - Extracted fields: `src_ip`, `dest_ip`, `signature`, etc.
3. Test queries in Graylog first to understand field structure

Example query structure:
```
{
  "query": {
    "bool": {
      "filter": [
        {"range": {"timestamp": {"gte": "$__from", "lte": "$__to"}}},
        {"match": {"message": "suricata"}}
      ]
    }
  }
}
```

## Troubleshooting

### Check Service Status

```bash
# MongoDB
sudo systemctl status mongod

# OpenSearch
sudo systemctl status opensearch
curl http://localhost:9200

# Graylog
sudo systemctl status graylog-server
sudo tail -f /var/log/graylog-server/server.log
```

### Check if Logs are Being Received

```bash
# Monitor Graylog logs
sudo tail -f /var/log/graylog-server/server.log

# Check OpenSearch indices
curl http://localhost:9200/_cat/indices?v

# Test UDP port connectivity from pfSense
nc -zvu 192.168.210.10 514
```

### Common Issues

#### Graylog Not Starting
- Check Java version: `java -version` (needs Java 17)
- Check OpenSearch is running: `curl http://localhost:9200`
- Review logs: `sudo journalctl -u graylog-server -f`

#### No Logs Appearing in Graylog
- Verify input is running: System → Inputs (should show "running")
- Check firewall: `sudo ufw status`
- Test from pfSense: `echo "test message" | nc -u 192.168.210.10 514`
- Check pfSense firewall rules allow outbound to 192.168.210.10

#### OpenSearch Connection Issues
- Verify OpenSearch is listening: `netstat -tulpn | grep 9200`
- Check OpenSearch logs: `sudo tail -f /var/log/opensearch/graylog.log`
- Verify configuration: `cat /etc/opensearch/opensearch.yml`

#### Grafana Can't Connect to OpenSearch
- Test connectivity: `curl http://192.168.210.10:9200`
- Check OpenSearch security settings (should be disabled for local access)
- Verify index pattern exists: `curl http://192.168.210.10:9200/_cat/indices?v`

## Performance Tuning

### OpenSearch Optimization

Edit `/etc/opensearch/opensearch.yml`:

```yaml
# Increase search queue size
thread_pool.search.queue_size: 10000

# Increase bulk queue size
thread_pool.write.queue_size: 1000

# Adjust refresh interval for better performance
indices.refresh_interval: 30s
```

### Graylog Optimization

Edit `/etc/graylog/server/server.conf`:

```conf
# Increase processing buffer
processbuffer_processors = 5
outputbuffer_processors = 3

# Adjust message journal
message_journal_max_size = 5gb

# Input read batch size
inputbuffer_ring_size = 65536
```

Restart services after changes:
```bash
sudo systemctl restart opensearch
sudo systemctl restart graylog-server
```

## Maintenance

### Rotate Old Logs

Graylog automatically manages index rotation. Configure in:
**System → Indices → Default Index Set → Index Rotation & Retention**

Recommended settings:
- **Rotation Strategy**: Index Time
- **Rotation Period**: P1D (1 day)
- **Retention Strategy**: Delete Index
- **Max Number of Indices**: 30 (keep 30 days of logs)

### Backup Configuration

```bash
# Backup Graylog configuration
sudo cp -r /etc/graylog/server /backup/graylog-config-$(date +%Y%m%d)

# Backup OpenSearch configuration
sudo cp -r /etc/opensearch /backup/opensearch-config-$(date +%Y%m%d)

# MongoDB backup (Graylog metadata)
mongodump --out /backup/mongodb-$(date +%Y%m%d)
```

## Additional Resources

- [Graylog Documentation](https://go2docs.graylog.org/)
- [OpenSearch Documentation](https://opensearch.org/docs/)
- [Suricata Documentation](https://suricata.readthedocs.io/)
- [pfSense Suricata Package](https://docs.netgate.com/pfsense/en/latest/packages/suricata/index.html)
- [Grafana Dashboard 22780](https://grafana.com/grafana/dashboards/22780-pfsense-firewall-and-ids-dashboard-2025/)

## Support

For issues specific to this setup, refer to the troubleshooting section above or check:
- Graylog logs: `/var/log/graylog-server/server.log`
- OpenSearch logs: `/var/log/opensearch/graylog.log`
- System logs: `journalctl -xe`
