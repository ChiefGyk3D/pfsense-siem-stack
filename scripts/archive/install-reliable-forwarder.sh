#!/bin/bash
# Install Suricata forwarder with automatic restart capability

echo "=== Installing Suricata Forwarder with Monitoring ==="
echo ""

# Copy files to pfSense
echo "Copying forwarder scripts to pfSense..."
scp /home/chiefgyk3d/src/Grafana_Dashboards/scripts/forward-suricata-eve-v2.sh root@192.168.210.1:/usr/local/bin/forward-suricata-eve.sh
scp /home/chiefgyk3d/src/Grafana_Dashboards/scripts/suricata-forwarder-watchdog.sh root@192.168.210.1:/usr/local/bin/

echo ""
echo "Setting permissions..."
ssh root@192.168.210.1 'chmod +x /usr/local/bin/forward-suricata-eve.sh /usr/local/bin/suricata-forwarder-watchdog.sh'

echo ""
echo "Stopping any existing forwarder processes..."
ssh root@192.168.210.1 'pkill -9 -f forward-suricata; pkill -9 -f "tail.*eve.json"; pkill -9 -f "nc.*5140"'

sleep 2

echo ""
echo "Starting new forwarder..."
ssh root@192.168.210.1 'nohup /usr/local/bin/forward-suricata-eve.sh > /dev/null 2>&1 &'

sleep 3

echo ""
echo "Checking if forwarder is running..."
ssh root@192.168.210.1 'ps aux | grep -v grep | grep -E "(forward-suricata|tail.*eve.json)" | wc -l | xargs echo "Forwarder processes:"'

echo ""
echo "Setting up cron job for watchdog (runs every 5 minutes)..."
ssh root@192.168.210.1 << 'CRONEOF'
# Check if cron entry already exists
if ! crontab -l 2>/dev/null | grep -q "suricata-forwarder-watchdog"; then
    # Add to crontab
    (crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/suricata-forwarder-watchdog.sh") | crontab -
    echo "✅ Watchdog cron job added"
else
    echo "✅ Watchdog cron job already exists"
fi
CRONEOF

echo ""
echo "Checking recent Suricata events..."
ssh root@192.168.210.1 'tail -1 /var/log/suricata/suricata_*/eve.json | jq -r ".timestamp // .flow_id"'

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "The forwarder will now:"
echo "  1. Automatically forward Suricata events to Logstash"
echo "  2. Be monitored by watchdog every 5 minutes"
echo "  3. Auto-restart if it stops or gets stuck"
echo ""
echo "Monitor with: ssh root@192.168.210.1 'tail -f /var/log/system.log | grep suricata'"
echo ""
echo "Wait 10 seconds and verify data is flowing to OpenSearch:"
echo "  ssh chiefgyk3d@192.168.210.10 'curl -s \"http://localhost:9200/suricata-*/_count?q=@timestamp:>now-1m\" | jq .count'"
