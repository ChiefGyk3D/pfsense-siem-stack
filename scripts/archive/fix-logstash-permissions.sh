#!/bin/bash

# Fix Logstash 8.x data directory permissions

echo "Fixing Logstash data directory permissions..."

sudo mkdir -p /usr/share/logstash/data
sudo chown -R logstash:logstash /usr/share/logstash/data
sudo chmod 755 /usr/share/logstash/data

echo ""
echo "✅ Permissions fixed!"
echo ""
echo "Restarting Logstash..."
sudo systemctl restart logstash

echo ""
echo "⏳ Waiting 15 seconds for startup..."
sleep 15

echo ""
echo "=== Logstash Status ==="
systemctl status logstash --no-pager -l | head -10

echo ""
echo "=== Port 5140 Status ==="
ss -ulnp | grep 5140 || echo "Port not listening yet"

echo ""
echo "=== Recent Logs ==="
journalctl -u logstash --since "30 seconds ago" --no-pager | tail -15
