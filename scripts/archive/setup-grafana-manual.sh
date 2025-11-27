#!/bin/bash

# Setup Grafana datasource and dashboard for Suricata
# Run this on the logging-siem server

GRAFANA_HOST="localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="YOUR_GRAFANA_PASSWORD_HERE"  # Update this!

echo "=== Creating Elasticsearch Datasource for Suricata ==="
echo ""

# Create datasource
DATASOURCE_RESPONSE=$(curl -s -X POST "http://$GRAFANA_HOST/api/datasources" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Elasticsearch-Suricata",
    "type": "elasticsearch",
    "access": "proxy",
    "url": "http://localhost:9200",
    "database": "suricata-*",
    "jsonData": {
      "interval": "Daily",
      "timeField": "@timestamp",
      "esVersion": "7.10.0",
      "maxConcurrentShardRequests": 5
    }
  }')

echo "$DATASOURCE_RESPONSE" | jq .

# Get datasource UID
DATASOURCE_UID=$(echo "$DATASOURCE_RESPONSE" | jq -r '.datasource.uid // .uid // empty')

if [ -z "$DATASOURCE_UID" ]; then
    echo ""
    echo "Checking if datasource already exists..."
    EXISTING=$(curl -s "http://$GRAFANA_HOST/api/datasources/name/Elasticsearch-Suricata" -u "$GRAFANA_USER:$GRAFANA_PASS")
    DATASOURCE_UID=$(echo "$EXISTING" | jq -r '.uid')
    
    if [ "$DATASOURCE_UID" = "null" ] || [ -z "$DATASOURCE_UID" ]; then
        echo "❌ Failed to create datasource. Check your Grafana credentials."
        exit 1
    fi
    echo "✓ Using existing datasource: $DATASOURCE_UID"
else
    echo "✓ Datasource created: $DATASOURCE_UID"
fi

echo ""
echo "=== Downloading Dashboard 14893 ==="
curl -s "https://grafana.com/api/dashboards/14893/revisions/2/download" -o /tmp/dashboard-14893.json
echo "✓ Downloaded"

echo ""
echo "=== Importing Dashboard ==="

# Modify dashboard to use our datasource
DASHBOARD_JSON=$(cat /tmp/dashboard-14893.json | jq --arg uid "$DATASOURCE_UID" '
  .dashboard = . |
  .dashboard.panels |= map(
    if .datasource != null then
      .datasource = {"type": "elasticsearch", "uid": $uid}
    else . end
  ) |
  .dashboard.templating.list |= map(
    if .datasource != null then
      .datasource = {"type": "elasticsearch", "uid": $uid}
    else . end
  ) |
  {
    dashboard: .dashboard,
    overwrite: true,
    inputs: [],
    folderId: 0
  }
')

DASHBOARD_RESPONSE=$(curl -s -X POST "http://$GRAFANA_HOST/api/dashboards/db" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H "Content-Type: application/json" \
  -d "$DASHBOARD_JSON")

DASHBOARD_UID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.uid // empty')

if [ -n "$DASHBOARD_UID" ]; then
    echo "✅ Dashboard imported!"
    echo ""
    echo "🎉 Access your Suricata IDS dashboard at:"
    echo "   http://192.168.210.10:3000/d/$DASHBOARD_UID"
    echo ""
    echo "Note: Adjust the time range to see your data (last 24 hours recommended)"
else
    echo "❌ Import failed:"
    echo "$DASHBOARD_RESPONSE" | jq .
fi

echo ""
echo "=== Current Data Summary ==="
curl -s "http://localhost:9200/suricata-*/_count" | jq -r '"Total documents: " + (.count | tostring)'
echo ""
echo "Event types captured:"
curl -s "http://localhost:9200/suricata-*/_search?size=0" -H 'Content-Type: application/json' -d '{
  "aggs": {
    "types": {
      "terms": {"field": "suricata.eve.event_type.keyword", "size": 10}
    }
  }
}' | jq -r '.aggregations.types.buckets[] | "  - " + .key + ": " + (.doc_count | tostring)'
