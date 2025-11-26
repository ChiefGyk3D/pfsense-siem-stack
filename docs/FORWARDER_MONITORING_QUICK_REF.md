# Forwarder Monitoring Quick Reference

## 🎯 Quick Install (Recommended)

```bash
# SSH to pfSense
ssh root@192.168.1.1

# Download and run setup script
fetch -o /tmp/setup_forwarder_monitoring.sh https://raw.githubusercontent.com/ChiefGyk3D/pfsense_grafana/overhaul/scripts/setup_forwarder_monitoring.sh
chmod +x /tmp/setup_forwarder_monitoring.sh
/tmp/setup_forwarder_monitoring.sh

# Choose option 1 (Hybrid) when prompted
```

## 📋 Manual Install

### Hybrid (Recommended for Most Users)
```bash
crontab -e
# Add these lines:
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
*/15 9-23 * * * [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

### Simple (Minimal)
```bash
crontab -e
# Add this line:
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

### 24/7 Active
```bash
crontab -e
# Add these lines:
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
*/10 * * * * [ $(find /var/log/suricata/*/eve.json -mmin -10 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
```

## ✅ Verify Installation

```bash
# Check cron is configured
crontab -l | grep forward-suricata

# Kill forwarder and wait 5 minutes
killall python3.11
sleep 300
ps aux | grep forward-suricata-eve.py | grep -v grep
# Should be running again
```

## 🔧 Troubleshooting

### Logs Not Flowing
```bash
# Check forwarder status
ps aux | grep forward-suricata-eve.py | grep -v grep

# Manually restart
killall python3.11
/usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &

# Check logs are being written
ls -lh /var/log/suricata/*/eve.json

# Check recent events in OpenSearch
curl -s "http://192.168.210.10:9200/suricata-*/_search?size=1&sort=@timestamp:desc"
```

### Remove Monitoring
```bash
crontab -e
# Delete or comment out the forward-suricata-eve.py lines
```

## 📚 Full Documentation

See [SURICATA_FORWARDER_MONITORING.md](./SURICATA_FORWARDER_MONITORING.md) for:
- Detailed option comparisons
- Environment-specific recommendations
- Advanced configuration
- Complete troubleshooting guide
