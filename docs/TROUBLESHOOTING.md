# Troubleshooting Guide

Common issues and solutions for the pfSense Suricata monitoring stack.

## Table of Contents
- [Quick Diagnostic Commands](#quick-diagnostic-commands)
- [No Data in Dashboard](#no-data-in-dashboard)
- [Forwarder Issues](#forwarder-issues)
- [OpenSearch Issues](#opensearch-issues)
- [Logstash Issues](#logstash-issues)
- [Grafana Issues](#grafana-issues)
- [Performance Issues](#performance-issues)
- [Network Issues](#network-issues)

## Quick Diagnostic Commands

Run these commands to quickly check system health:

```bash
# Check all services status
sudo systemctl status opensearch logstash grafana-server

# Check event count
curl -s http://localhost:9200/suricata-*/_count | jq .count

# Check latest event
curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source | {timestamp: ."@timestamp", event_type: .suricata.eve.event_type, src: .suricata.eve.src_ip}'

# Check forwarder on pfSense
ssh root@YOUR_PFSENSE_IP 'ps aux | grep forward-suricata-eve-python.py | grep -v grep'

# Check Logstash is listening
sudo netstat -ulnp | grep 5140
```

## No Data in Dashboard

### Symptom
Grafana dashboard shows "No data" for all panels.

### Diagnosis

**1. Verify events exist in OpenSearch:**
```bash
curl -s http://localhost:9200/suricata-*/_count | jq .count
```

If count is 0:
- Continue to [Forwarder Issues](#forwarder-issues)
- Check [Logstash Issues](#logstash-issues)

If count > 0 but dashboard shows no data:
- Continue to [Grafana Issues](#grafana-issues)

**2. Check time range:**
- Dashboard time range (top right) might be too narrow
- Try "Last 24 hours" or "Last 7 days"
- Check latest event timestamp:
```bash
curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq -r '.hits.hits[0]._source."@timestamp"'
```

**3. Check field structure:**
```bash
curl -s "http://localhost:9200/suricata-*/_search?size=1" | jq '.hits.hits[0]._source | keys'
```

Should include: `@timestamp`, `suricata`, `host`

**4. Check datasource configuration:**
- Grafana → Connections → Data sources → OpenSearch-Suricata
- Click "Save & test" - should show green checkmark
- Verify:
  - URL: `http://localhost:9200`
  - Index: `suricata-*`
  - Time field: `@timestamp`

### Solutions

**If events exist but panels show no data:**
```bash
# Check panel queries
# 1. Edit panel → Query inspector
# 2. Check for field name errors (missing .keyword suffix)
# 3. Verify query syntax (Lucene format)

# Re-import dashboard
# Dashboard settings → JSON Model → Copy
# Dashboards → New → Import → Paste JSON
```

**If no events exist:**
- See [Forwarder Issues](#forwarder-issues)
- See [Logstash Issues](#logstash-issues)

## Forwarder Issues

### Forwarder Not Running

**Symptom:** No process found when checking:
```bash
ssh admin@YOUR_PFSENSE_IP 'pgrep -fl forward-suricata'
```

**Diagnosis:**
```bash
# Check if script exists and is executable
ssh admin@YOUR_PFSENSE_IP 'ls -la /usr/local/bin/forward-suricata-eve-python.py'

# Try running manually to see errors
ssh admin@YOUR_PFSENSE_IP '/usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve-python.py'

# Check syslog for errors
ssh admin@YOUR_PFSENSE_IP 'grep suricata-forwarder /var/log/system.log | tail -20'

# Check if maxminddb is available (should be pre-installed)
ssh admin@YOUR_PFSENSE_IP 'python3.11 -c "import maxminddb; print(\"OK\")"'
```

**Solutions:**
```bash
# Start forwarder manually
ssh admin@YOUR_PFSENSE_IP 'nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve-python.py > /dev/null 2>&1 &'

# Verify watchdog is configured
ssh admin@YOUR_PFSENSE_IP 'grep watchdog /etc/crontab'
# Should show: * * * * * root /usr/local/bin/suricata-forwarder-watchdog.sh

# If missing, add cron entry
ssh admin@YOUR_PFSENSE_IP 'echo "* * * * * root /usr/local/bin/suricata-forwarder-watchdog.sh" >> /etc/crontab && service cron restart'
```

### Forwarder Running But No Events

**Symptom:** Process running but OpenSearch event count not increasing.

**Diagnosis:**
```bash
# 1. Check if Suricata is generating events
ssh admin@YOUR_PFSENSE_IP 'tail -5 /var/log/suricata/suricata_*/eve.json'
# Should show JSON events

# 2. Test UDP connectivity
echo '{"test":"event"}' | ssh admin@YOUR_PFSENSE_IP "nc -u -w1 YOUR_SIEM_IP 5140"

# 3. Check for network/firewall blocking
ssh admin@YOUR_PFSENSE_IP 'nc -vzu YOUR_SIEM_IP 5140'

# 4. Check SIEM firewall allows UDP 5140
sudo ufw status | grep 5140
```

**Solutions:**
```bash
# Restart forwarder
ssh admin@YOUR_PFSENSE_IP 'pkill -f forward-suricata-eve-python.py; sleep 1; nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve-python.py > /dev/null 2>&1 &'

# Check SIEM server IP in forwarder script (or use DEBUG_ENABLED)
ssh admin@YOUR_PFSENSE_IP 'grep SIEM_HOST /usr/local/bin/forward-suricata-eve-python.py | head -1'

# Allow UDP 5140 on SIEM
sudo ufw allow 5140/udp
```

### Events Have _jsonparsefailure Tag

**Symptom:** Events in OpenSearch but tagged with `_jsonparsefailure`.

**Diagnosis:**
```bash
# Check event structure
curl -s "http://localhost:9200/suricata-*/_search?q=tags:_jsonparsefailure&size=1" | jq '.hits.hits[0]._source'

# Check what's in event.original or message field
curl -s "http://localhost:9200/suricata-*/_search?q=tags:_jsonparsefailure&size=1" | jq -r '.hits.hits[0]._source.event.original'
```

**Solutions:**

If event.original contains valid JSON:
```bash
# Logstash config should parse from event.original
# Check /etc/logstash/conf.d/suricata.conf has:
# json {
#   source => "[event][original]"
#   ...
# }

# Restart Logstash
sudo systemctl restart logstash
```

If event.original is garbage ("X" or malformed):
```bash
# Forwarder is broken - redeploy Python version
# See docs/INSTALL_PFSENSE_FORWARDER.md
```

## OpenSearch Issues

### OpenSearch Not Starting

**Symptom:**
```bash
sudo systemctl status opensearch
# Shows: failed or inactive
```

**Diagnosis:**
```bash
# Check logs
sudo journalctl -u opensearch -n 100

# Common errors:
# - "OutOfMemoryError" → Increase heap or reduce heap size
# - "max virtual memory" → vm.max_map_count too low
# - "unable to lock JVM memory" → bootstrap.memory_lock issue
```

**Solutions:**

**Insufficient memory:**
```bash
# Reduce heap size (edit to 50% of available RAM)
sudo vi /etc/opensearch/jvm.options.d/heap.options
# Change to: -Xms4g and -Xmx4g

sudo systemctl restart opensearch
```

**vm.max_map_count too low:**
```bash
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo systemctl restart opensearch
```

**Port already in use:**
```bash
# Check what's using port 9200
sudo netstat -tlnp | grep 9200

# If another service, either stop it or change OpenSearch port
sudo vi /etc/opensearch/opensearch.yml
# Change: http.port: 9201
sudo systemctl restart opensearch
```

### OpenSearch Running Slow

**Symptom:** Queries take >5 seconds, dashboard slow to load.

**Diagnosis:**
```bash
# Check cluster health
curl -s http://localhost:9200/_cluster/health | jq

# Check heap usage
curl -s http://localhost:9200/_cat/nodes?v&h=heap.percent,heap.current,heap.max

# Check index sizes
curl -s http://localhost:9200/_cat/indices/suricata-*?v&s=store.size:desc
```

**Solutions:**

**Delete old indices:**
```bash
# Delete indices older than 30 days
curl -X DELETE "http://localhost:9200/suricata-2025.10.*"

# Or use Index Lifecycle Management
```

**Increase heap:**
```bash
sudo vi /etc/opensearch/jvm.options.d/heap.options
# Increase to 50% of RAM (max 31GB)
# -Xms8g
# -Xmx8g

sudo systemctl restart opensearch
```

**Optimize indices:**
```bash
# Force merge old indices
curl -X POST "http://localhost:9200/suricata-2025.11.*/_forcemerge?max_num_segments=1"
```

## Logstash Issues

### Logstash Not Starting

**Symptom:**
```bash
sudo systemctl status logstash
# Shows: failed or inactive
```

**Diagnosis:**
```bash
# Check logs
sudo tail -f /var/log/logstash/logstash-plain.log

# Common errors:
# - "Address already in use" → Port 5140 taken
# - "Plugin not found" → logstash-output-opensearch not installed
# - "Pipeline error" → Syntax error in config
```

**Solutions:**

**Port in use:**
```bash
# Check what's using UDP 5140
sudo netstat -ulnp | grep 5140

# Kill conflicting process or change Logstash port
sudo vi /etc/logstash/conf.d/suricata.conf
# Change: port => 5141
```

**Plugin missing:**
```bash
cd /usr/share/logstash
sudo bin/logstash-plugin install logstash-output-opensearch
sudo systemctl restart logstash
```

**Config syntax error:**
```bash
# Test config
sudo /usr/share/logstash/bin/logstash --config.test_and_exit -f /etc/logstash/conf.d/suricata.conf

# If errors, fix syntax in /etc/logstash/conf.d/suricata.conf
```

### Logstash Not Receiving Data

**Symptom:** Logstash running but event count not increasing in OpenSearch.

**Diagnosis:**
```bash
# Check if Logstash is listening
sudo netstat -ulnp | grep 5140

# Check Logstash logs for incoming data
sudo tail -f /var/log/logstash/logstash-plain.log

# Test sending data
echo '{"test":"data"}' | nc -u -w1 localhost 5140
```

**Solutions:**

**UDP buffer size too small:**
```bash
# Increase system UDP buffer
echo "net.core.rmem_max=33554432" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Verify Logstash config has:
# receive_buffer_bytes => 33554432

sudo systemctl restart logstash
```

**Firewall blocking:**
```bash
sudo ufw allow 5140/udp
sudo ufw status
```

## Grafana Issues

### Can't Login to Grafana

**Default credentials:**
- Username: `admin`
- Password: `admin`

**Reset admin password:**
```bash
sudo grafana-cli admin reset-admin-password newpassword
sudo systemctl restart grafana-server
```

### OpenSearch Datasource Fails Test

**Symptom:** "Data source is not working" error when saving datasource.

**Diagnosis:**
```bash
# Test OpenSearch from Grafana server
curl http://localhost:9200

# Check Grafana logs
sudo tail -f /var/log/grafana/grafana.log
```

**Solutions:**

**OpenSearch not accessible:**
```bash
# If OpenSearch is on different host, update URL
# Datasource URL should be: http://OPENSEARCH_IP:9200

# Check network connectivity
ping OPENSEARCH_IP
curl http://OPENSEARCH_IP:9200
```

**Plugin not installed:**
```bash
sudo grafana-cli plugins install grafana-opensearch-datasource
sudo systemctl restart grafana-server
```

### Panels Show "Unknown Visualization"

**Symptom:** Some panels show "Unknown visualization" or don't render.

**Solution:**
- Stat panels and pie charts don't work reliably with OpenSearch datasource
- Convert to **Table** or **Time series** visualizations
- Edit panel → Change visualization type → Apply

## Performance Issues

### High CPU Usage

**OpenSearch:**
```bash
# Check query performance
curl -s "http://localhost:9200/_nodes/stats/thread_pool" | jq

# Check active queries
curl -s "http://localhost:9200/_tasks" | jq

# Solution: Reduce query complexity or increase resources
```

**Logstash:**
```bash
# Check pipeline stats
curl -s "http://localhost:9600/_node/stats/pipelines" | jq

# Solution: Reduce filter complexity or add more workers
sudo vi /etc/logstash/logstash.yml
# Add: pipeline.workers: 4
```

### High Memory Usage

**OpenSearch using too much RAM:**
```bash
# Check current heap
curl -s http://localhost:9200/_cat/nodes?v&h=heap.percent,heap.max

# Reduce heap if >80% used
sudo vi /etc/opensearch/jvm.options.d/heap.options
```

### Disk Space Issues

**Symptom:** Disk full or nearly full.

**Solutions:**
```bash
# Check index sizes
curl -s http://localhost:9200/_cat/indices/suricata-*?v&s=store.size:desc | head -20

# Delete old indices (careful!)
curl -X DELETE "http://localhost:9200/suricata-2025.10.*"

# Set up index lifecycle policy for auto-deletion
# Or use curator to manage indices
```

## Network Issues

### Can't Access Grafana from Browser

**Diagnosis:**
```bash
# Check Grafana is running
sudo systemctl status grafana-server

# Check Grafana is listening
sudo netstat -tlnp | grep 3000

# Check firewall
sudo ufw status | grep 3000
```

**Solutions:**
```bash
# Allow port 3000
sudo ufw allow 3000/tcp

# If accessing from remote host, check router/firewall rules
```

### pfSense Can't Reach SIEM Server

**Diagnosis:**
```bash
# From pfSense, test connectivity
ssh root@YOUR_PFSENSE_IP 'ping -c 3 YOUR_SIEM_IP'
ssh root@YOUR_PFSENSE_IP 'nc -vzu YOUR_SIEM_IP 5140'
```

**Solutions:**
- Check SIEM server firewall: `sudo ufw allow from PFSENSE_IP to any port 5140 proto udp`
- Check pfSense firewall rules (Firewall → Rules)
- Verify routing between pfSense and SIEM server

## Common Error Messages

### "max file descriptors [4096] for opensearch process is too low"

```bash
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
# Reboot or restart OpenSearch
```

### "flood stage disk watermark [95%] exceeded"

```bash
# Delete old indices or add more disk space
curl -X DELETE "http://localhost:9200/suricata-OLD_DATE"
```

### "failed to obtain node locks"

```bash
# OpenSearch already running or crashed
sudo systemctl stop opensearch
sudo rm -rf /var/lib/opensearch/nodes/*/node.lock
sudo systemctl start opensearch
```

## Getting Help

If issues persist:

1. **Gather diagnostic info:**
```bash
# Save to file
sudo systemctl status opensearch logstash grafana-server > /tmp/status.txt
sudo journalctl -u opensearch -n 100 > /tmp/opensearch.log
sudo journalctl -u logstash -n 100 > /tmp/logstash.log
curl -s http://localhost:9200/_cluster/health > /tmp/cluster-health.json
curl -s http://localhost:9200/suricata-*/_count > /tmp/event-count.json
```

2. **Check documentation:**
   - OpenSearch: https://opensearch.org/docs/
   - Logstash: https://www.elastic.co/guide/en/logstash/current/index.html
   - Grafana: https://grafana.com/docs/

3. **Open GitHub issue** with diagnostic info

## Preventive Maintenance

### Regular Tasks

**Weekly:**
```bash
# Check disk space
df -h

# Check event count growth
curl -s http://localhost:9200/suricata-*/_count | jq .count

# Check service status
sudo systemctl status opensearch logstash grafana-server
```

**Monthly:**
```bash
# Delete old indices (>90 days)
curl -X DELETE "http://localhost:9200/suricata-2025.08.*"

# Check OpenSearch cluster health
curl -s http://localhost:9200/_cluster/health | jq

# Review Grafana dashboard performance
```

**After pfSense Updates:**
```bash
# Verify forwarder still running
ssh root@YOUR_PFSENSE_IP 'ps aux | grep forward-suricata-eve-python.py'

# Check cron job still exists (System → Cron in pfSense UI)

# Check syslog for forwarder messages
ssh root@YOUR_PFSENSE_IP 'grep suricata-forwarder /var/log/system.log | tail -10'
```
