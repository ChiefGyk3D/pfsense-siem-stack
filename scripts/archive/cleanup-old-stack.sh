#!/bin/bash

# Cleanup script - Remove Graylog, Filebeat, and old indices
# Keep: MongoDB (might be useful), OpenSearch, Logstash

set -e

echo "=== CLEANUP SCRIPT ==="
echo ""
echo "This will remove:"
echo "  - Graylog server and all data"
echo "  - Filebeat"
echo "  - Old graylog_* indices from OpenSearch"
echo "  - Suricata receiver service"
echo ""
echo "This will keep:"
echo "  - OpenSearch (for Logstash data)"
echo "  - MongoDB (in case you want it later)"
echo "  - Logstash (currently being used)"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo "Stopping services..."
sudo systemctl stop graylog-server || true
sudo systemctl stop filebeat || true
sudo systemctl stop suricata-receiver || true

echo "Disabling services..."
sudo systemctl disable graylog-server || true
sudo systemctl disable filebeat || true
sudo systemctl disable suricata-receiver || true

echo "Removing packages..."
sudo apt-get remove -y graylog-server filebeat || true

echo "Removing Graylog data..."
sudo rm -rf /var/lib/graylog-server
sudo rm -rf /var/log/graylog-server
sudo rm -rf /etc/graylog/server

echo "Removing Filebeat data..."
sudo rm -rf /var/lib/filebeat
sudo rm -rf /var/log/filebeat

echo "Removing suricata-receiver service..."
sudo rm -f /etc/systemd/system/suricata-receiver.service
sudo rm -rf /var/log/suricata-remote
sudo systemctl daemon-reload

echo "Removing old OpenSearch indices..."
# Delete graylog indices
curl -X DELETE "http://localhost:9200/graylog_*" 2>/dev/null || true
# Delete filebeat indices if any exist
curl -X DELETE "http://localhost:9200/filebeat-*" 2>/dev/null || true

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Still running:"
echo "  - OpenSearch on port 9200"
echo "  - MongoDB on port 27017"
echo "  - Logstash on port 5140 (UDP input for Suricata)"
echo "  - Grafana on port 3000"
echo ""
echo "Active indices:"
curl -s "http://localhost:9200/_cat/indices?v" | grep -v "^health"
echo ""
echo "Services status:"
systemctl is-active opensearch mongodb logstash grafana-server | paste -d' ' <(echo -e "OpenSearch\nMongoDB\nLogstash\nGrafana") -
