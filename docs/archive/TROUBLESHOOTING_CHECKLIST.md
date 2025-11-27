# Graylog + Suricata Troubleshooting Checklist

Quick reference checklist for diagnosing common issues with the Graylog, Suricata, OpenSearch, and Grafana stack.

## Pre-Installation Checklist

- [ ] Ubuntu 22.04 or 24.04 server ready
- [ ] At least 8GB RAM available (16GB recommended)
- [ ] At least 50GB disk space (100GB+ recommended)
- [ ] pfSense 2.7+ installed and accessible
- [ ] Network connectivity between all systems verified
- [ ] Required ports documented and ready to open

## Installation Verification

### MongoDB
- [ ] MongoDB service is running: `sudo systemctl status mongod`
- [ ] MongoDB is listening on port 27017: `sudo netstat -tulpn | grep 27017`
- [ ] MongoDB config updated with bindIp/bindIpAll
- [ ] Can connect to MongoDB: `mongosh --host localhost`

### Graylog Data Node (OpenSearch)
- [ ] Data Node service is running: `sudo systemctl status graylog-datanode`
- [ ] vm.max_map_count is set to 262144: `cat /proc/sys/vm/max_map_count`
- [ ] password_secret configured in datanode.conf
- [ ] opensearch_heap configured appropriately
- [ ] mongodb_uri configured correctly
- [ ] OpenSearch is listening on port 9200: `curl http://localhost:9200`
- [ ] Can query OpenSearch: `curl http://localhost:9200/_cluster/health?pretty`

### Graylog Server
- [ ] Graylog service is running: `sudo systemctl status graylog-server`
- [ ] Graylog web interface accessible: `http://server-ip:9000`
- [ ] root_password_sha2 configured
- [ ] password_secret matches Data Node
- [ ] Preflight login completed
- [ ] Can login with admin credentials
- [ ] System overview shows green status

### Grafana
- [ ] Grafana service is running: `sudo systemctl status grafana-server`
- [ ] Grafana accessible: `http://server-ip:3000`
- [ ] Admin password changed from default
- [ ] Can login successfully

## Network Connectivity

### From pfSense to Graylog
```bash
# SSH into pfSense
ssh admin@pfsense-ip

# Test UDP syslog port
echo "test" | nc -u graylog-ip 1514

# Test TCP JSON port
echo "test" | nc -w1 graylog-ip 1515

# Test connectivity
ping -c 3 graylog-ip
```

- [ ] pfSense can reach Graylog server
- [ ] UDP port 1514 accessible
- [ ] TCP port 1515 accessible
- [ ] No firewall blocking between pfSense and Graylog

### From Grafana to Graylog OpenSearch
```bash
# On Grafana server
curl http://graylog-ip:9200
curl http://graylog-ip:9200/_cat/indices?v
```

- [ ] Grafana server can reach Graylog OpenSearch port
- [ ] Port 9200 accessible
- [ ] Can query OpenSearch indices

## Graylog Configuration

### Inputs
- [ ] Syslog UDP input created (port 1514)
- [ ] Syslog UDP input shows "Running" status
- [ ] Raw/Plaintext TCP input created for JSON (port 1515)
- [ ] JSON extractor added to Suricata input
- [ ] Inputs show received message counts

### Streams (Optional)
- [ ] pfSense Firewall stream created and started
- [ ] Suricata IDS stream created and started
- [ ] Stream rules configured correctly

### Data Reception
```bash
# Check Graylog logs for errors
sudo journalctl -u graylog-server | grep -i error

# Check message processing
# In Graylog UI: System > Nodes > Show metrics
```

- [ ] Messages appearing in Search
- [ ] Message rate shows in inputs
- [ ] No errors in Graylog server logs
- [ ] Disk journal not full

## pfSense Configuration

### System Logging
- [ ] Remote logging enabled
- [ ] Graylog server IP:port configured
- [ ] Firewall events enabled
- [ ] System events enabled
- [ ] Test message sent successfully

### Suricata
- [ ] Suricata package installed
- [ ] Suricata enabled on interface (usually WAN)
- [ ] EVE JSON logging enabled
- [ ] Rule sources configured and updated
- [ ] Suricata is running: `ps aux | grep suricata`
- [ ] EVE log file exists: `ls -la /var/log/suricata/*/eve.json`
- [ ] EVE log has recent entries: `tail /var/log/suricata/*/eve.json`

### Log Forwarding
- [ ] Log forwarding script installed
- [ ] Script configuration updated (GRAYLOG_IP, PORT)
- [ ] Script is executable
- [ ] Script passes connectivity test: `./forward-suricata-logs.sh test`
- [ ] Script is running: `./forward-suricata-logs.sh status`
- [ ] Script configured to start at boot

## Grafana Data Source

### OpenSearch Configuration
- [ ] OpenSearch/Elasticsearch data source added
- [ ] URL configured: `http://graylog-ip:9200`
- [ ] Index pattern configured: `graylog_*`
- [ ] Time field set to `timestamp`
- [ ] Data source saves successfully
- [ ] "Save & Test" shows success
- [ ] Can query data in Explore

### Dashboard
- [ ] Dashboard 22780 imported
- [ ] Data source selected during import
- [ ] Dashboard loads without errors
- [ ] Time range set appropriately (last 24h for testing)
- [ ] Variables work correctly

## Common Issues Checklist

### "No data in Graylog"
- [ ] Inputs are running (not stopped)
- [ ] Firewall allows traffic to input ports
- [ ] pfSense remote logging configured correctly
- [ ] Can send test message from pfSense: `echo "test" | nc -u graylog-ip 1514`
- [ ] Check Graylog input metrics in UI
- [ ] Check Graylog server logs: `sudo journalctl -u graylog-server -f`

### "Cannot access Graylog web interface"
- [ ] Graylog server service is running
- [ ] Port 9000 is listening: `sudo netstat -tulpn | grep 9000`
- [ ] Firewall allows port 9000: `sudo ufw allow 9000/tcp`
- [ ] http_bind_address configured in server.conf
- [ ] Browser can reach server IP
- [ ] Check for errors: `sudo journalctl -u graylog-server | tail -50`

### "Data Node won't start"
- [ ] vm.max_map_count is set correctly
- [ ] Enough disk space: `df -h`
- [ ] opensearch_heap not too large (max 31g)
- [ ] MongoDB is running and accessible
- [ ] password_secret is configured
- [ ] Check logs: `sudo journalctl -u graylog-datanode -f`

### "Suricata logs not appearing in Graylog"
- [ ] Suricata is generating logs: `tail -f /var/log/suricata/*/eve.json`
- [ ] Log forwarding script is running
- [ ] Script can connect to Graylog: `./forward-suricata-logs.sh test`
- [ ] JSON input is running in Graylog
- [ ] JSON extractor is configured
- [ ] Check script logs: `tail -f /var/log/forward-suricata-logs.log`

### "Grafana cannot connect to OpenSearch"
- [ ] OpenSearch is accessible: `curl http://graylog-ip:9200`
- [ ] Port 9200 allowed in firewall: `sudo ufw allow 9200/tcp`
- [ ] Data Node is running: `sudo systemctl status graylog-datanode`
- [ ] URL in Grafana data source is correct
- [ ] Test data source in Grafana settings

### "Dashboard shows no data"
- [ ] Data exists in Graylog/OpenSearch
- [ ] Correct data source selected in dashboard
- [ ] Time range includes data (try "Last 24 hours")
- [ ] Index pattern correct: `graylog_*`
- [ ] Field names match (check in Explore)
- [ ] Verify data: `curl http://graylog-ip:9200/graylog_*/_search?pretty`

### "High resource usage"
- [ ] Heap sizes appropriate (not too high)
- [ ] Disk I/O not saturated: `iostat -x 1 5`
- [ ] Enough RAM available: `free -h`
- [ ] Journal size not too large
- [ ] Old indices cleaned up/rotated
- [ ] MongoDB cache size optimized

### "Messages delayed or dropped"
- [ ] Journal not full: Check in Graylog UI
- [ ] Increase journal size in server.conf
- [ ] Enough processing power (CPU)
- [ ] Network not saturated
- [ ] Check message processing rate vs. input rate
- [ ] Consider adding more Data Nodes

## Performance Baselines

### Healthy System Metrics
- [ ] Graylog web interface loads in < 5 seconds
- [ ] Search queries return in < 2 seconds
- [ ] CPU usage < 80% average
- [ ] Memory usage < 90%
- [ ] Disk usage < 80%
- [ ] Network latency < 10ms to pfSense
- [ ] Message processing lag < 1 minute

### Resource Usage Guidelines
```
MongoDB:
- RAM: 2-4GB
- Disk I/O: Low-moderate
- CPU: Low (5-15%)

Data Node (OpenSearch):
- RAM: 8-16GB (heap + OS)
- Disk I/O: High
- CPU: Moderate-High (20-60%)

Graylog Server:
- RAM: 4-8GB (heap + OS)
- Disk I/O: Moderate
- CPU: Low-Moderate (10-30%)

Grafana:
- RAM: 1-2GB
- Disk I/O: Low
- CPU: Low (5-10%)
```

## Service Management Commands

### Check All Services
```bash
sudo systemctl status mongod
sudo systemctl status graylog-datanode
sudo systemctl status graylog-server
sudo systemctl status grafana-server
```

### Restart Services (in order)
```bash
# 1. MongoDB (if needed)
sudo systemctl restart mongod
sleep 10

# 2. Data Node
sudo systemctl restart graylog-datanode
sleep 30

# 3. Graylog Server
sudo systemctl restart graylog-server
sleep 20

# 4. Grafana (independent)
sudo systemctl restart grafana-server
```

### View Logs
```bash
# Real-time logs
sudo journalctl -u mongod -f
sudo journalctl -u graylog-datanode -f
sudo journalctl -u graylog-server -f
sudo journalctl -u grafana-server -f

# Last 100 lines
sudo journalctl -u graylog-server -n 100

# Errors only
sudo journalctl -u graylog-server | grep -i error
```

## Support Resources

- [ ] Checked Graylog documentation: https://go2docs.graylog.org/
- [ ] Checked Graylog community forum: https://community.graylog.org/
- [ ] Checked pfSense documentation: https://docs.netgate.com/
- [ ] Checked Suricata documentation: https://suricata.readthedocs.io/
- [ ] Checked Grafana documentation: https://grafana.com/docs/
- [ ] Checked project GitHub issues: https://github.com/ChiefGyk3D/pfsense_grafana/issues

## Emergency Recovery

If system is completely broken:

1. **Stop all services:**
```bash
sudo systemctl stop graylog-server
sudo systemctl stop graylog-datanode
sudo systemctl stop mongod
```

2. **Check logs for errors:**
```bash
sudo journalctl -u graylog-server | tail -100
sudo journalctl -u graylog-datanode | tail -100
```

3. **Verify disk space:**
```bash
df -h
```

4. **Check configuration files:**
```bash
sudo cat /etc/graylog/server/server.conf | grep -v "^#" | grep -v "^$"
sudo cat /etc/graylog/datanode/datanode.conf | grep -v "^#" | grep -v "^$"
```

5. **Start services one by one:**
```bash
sudo systemctl start mongod
# Wait and verify
sudo systemctl start graylog-datanode
# Wait 30 seconds and verify
sudo systemctl start graylog-server
# Wait 30 seconds and verify
```

6. **If still broken, check:**
   - [ ] password_secret matches in both configs
   - [ ] Heap sizes are reasonable
   - [ ] MongoDB is accessible
   - [ ] No port conflicts
   - [ ] Sufficient disk space

---

**Last Updated:** November 24, 2025
**Related Docs:** [GRAYLOG_SURICATA_SETUP.md](GRAYLOG_SURICATA_SETUP.md) | [QUICK_SETUP_COMMANDS.md](QUICK_SETUP_COMMANDS.md)
