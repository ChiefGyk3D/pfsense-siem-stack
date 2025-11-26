#!/bin/bash

# Configure Grafana datasource and import dashboard 14893 for Suricata

GRAFANA_HOST="localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

echo "=== Setting up Grafana for Suricata Dashboard 14893 ==="
echo ""

# Create Elasticsearch datasource for suricata-* index
echo "Creating Elasticsearch datasource for Suricata data..."

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
      "maxConcurrentShardRequests": 5,
      "logMessageField": "message",
      "logLevelField": ""
    }
  }')

echo "$DATASOURCE_RESPONSE" | jq .

DATASOURCE_UID=$(echo "$DATASOURCE_RESPONSE" | jq -r '.datasource.uid // .uid // empty')

if [ -z "$DATASOURCE_UID" ]; then
    echo ""
    echo "⚠️  Datasource creation may have failed or already exists."
    echo "Checking existing datasources..."
    EXISTING_UID=$(curl -s "http://$GRAFANA_HOST/api/datasources/name/Elasticsearch-Suricata" \
      -u "$GRAFANA_USER:$GRAFANA_PASS" | jq -r '.uid')
    
    if [ -n "$EXISTING_UID" ] && [ "$EXISTING_UID" != "null" ]; then
        DATASOURCE_UID="$EXISTING_UID"
        echo "✓ Using existing datasource with UID: $DATASOURCE_UID"
    else
        echo "❌ Failed to create or find datasource"
        exit 1
    fi
else
    echo ""
    echo "✓ Datasource created with UID: $DATASOURCE_UID"
fi

echo ""
echo "=== Importing Dashboard 14893 ==="

# Download dashboard JSON if not present
if [ ! -f "/tmp/dashboard-14893.json" ]; then
    echo "Downloading dashboard 14893..."
    curl -s "https://grafana.com/api/dashboards/14893/revisions/2/download" -o /tmp/dashboard-14893.json
fi

# Read and modify dashboard JSON to use our datasource
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

# Import dashboard
DASHBOARD_RESPONSE=$(curl -s -X POST "http://$GRAFANA_HOST/api/dashboards/db" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H "Content-Type: application/json" \
  -d "$DASHBOARD_JSON")

echo "$DASHBOARD_RESPONSE" | jq .

DASHBOARD_UID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.uid // empty')

if [ -n "$DASHBOARD_UID" ]; then
    echo ""
    echo "✅ Dashboard imported successfully!"
    echo ""
    echo "Dashboard URL: http://192.168.210.10:3000/d/$DASHBOARD_UID"
    echo ""
    echo "Note: You may need to adjust the time range to see recent data."
else
    echo ""
    echo "❌ Dashboard import failed"
    echo "Check the response above for errors"
    exit 1
fi

echo ""
echo "=== Data Verification ==="
echo "Documents in suricata-* indices:"
curl -s "http://localhost:9200/suricata-*/_count" | jq .
echo ""
echo "Sample event types:"
curl -s "http://localhost:9200/suricata-*/_search?size=0" -H 'Content-Type: application/json' -d '{
  "aggs": {
    "event_types": {
      "terms": {
        "field": "suricata.eve.event_type.keyword",
        "size": 10
      }
    }
  }
}' | jq '.aggregations.event_types.buckets[] | {type: .key, count: .doc_count}'
