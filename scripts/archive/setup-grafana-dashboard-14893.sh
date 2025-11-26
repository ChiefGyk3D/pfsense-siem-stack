#!/bin/bash

# Configure Grafana datasource and import dashboard 14893 for Suricata

GRAFANA_HOST="localhost:3000"
GRAFANA_USER="admin"
GRAFANA_PASS="admin"

echo "=== Setting up Grafana for Suricata Dashboard 14893 ==="
echo ""

# Check if OpenSearch datasource plugin is installed
echo "Checking for Elasticsearch/OpenSearch datasource plugin..."
PLUGIN_CHECK=$(curl -s "http://$GRAFANA_HOST/api/plugins/elasticsearch" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" | jq -r '.id' 2>/dev/null)

if [ "$PLUGIN_CHECK" != "elasticsearch" ]; then
    echo "ERROR: Elasticsearch datasource plugin not found!"
    echo "Install it with: grafana-cli plugins install grafana-opensearch-datasource"
    exit 1
fi

echo "✓ Elasticsearch datasource plugin found"
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

DATASOURCE_ID=$(echo "$DATASOURCE_RESPONSE" | jq -r '.datasource.id // .id // empty')

if [ -z "$DATASOURCE_ID" ]; then
    echo "WARNING: Datasource might already exist. Checking..."
    EXISTING_DS=$(curl -s "http://$GRAFANA_HOST/api/datasources/name/Elasticsearch-Suricata" \
      -u "$GRAFANA_USER:$GRAFANA_PASS" | jq -r '.id // empty')
    
    if [ -n "$EXISTING_DS" ]; then
        echo "✓ Using existing datasource (ID: $EXISTING_DS)"
        DATASOURCE_ID=$EXISTING_DS
    else
        echo "ERROR creating datasource:"
        echo "$DATASOURCE_RESPONSE" | jq
        exit 1
    fi
else
    echo "✓ Datasource created (ID: $DATASOURCE_ID)"
fi

echo ""
echo "Importing dashboard 14893..."

# Check if dashboard file exists
if [ ! -f "/home/chiefgyk3d/src/Grafana_Dashboards/dashboard-14893.json" ]; then
    echo "ERROR: dashboard-14893.json not found!"
    echo "Download it first with:"
    echo "  curl -o dashboard-14893.json https://grafana.com/api/dashboards/14893/revisions/1/download"
    exit 1
fi

# Import dashboard
DASHBOARD_JSON=$(cat /home/chiefgyk3d/src/Grafana_Dashboards/dashboard-14893.json | jq --arg ds_id "$DATASOURCE_ID" '
  # Update datasource references
  .dashboard = . |
  del(.id) |
  .dashboard.__inputs[0].pluginId = "elasticsearch" |
  .dashboard.__inputs[0].value = $ds_id |
  # Replace datasource variable with actual ID
  walk(
    if type == "object" and has("datasource") and (.datasource | type == "string") and (.datasource | startswith("${DS_")) then
      .datasource = $ds_id
    else
      .
    end
  ) |
  {
    dashboard: .dashboard,
    overwrite: true,
    inputs: [
      {
        name: "DS_ELASTICSEARCH",
        type: "datasource",
        pluginId: "elasticsearch",
        value: $ds_id
      }
    ]
  }
')

IMPORT_RESPONSE=$(echo "$DASHBOARD_JSON" | curl -s -X POST "http://$GRAFANA_HOST/api/dashboards/import" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H "Content-Type: application/json" \
  -d @-)

DASHBOARD_UID=$(echo "$IMPORT_RESPONSE" | jq -r '.uid // empty')

if [ -z "$DASHBOARD_UID" ]; then
    echo "ERROR importing dashboard:"
    echo "$IMPORT_RESPONSE" | jq
    exit 1
fi

echo "✓ Dashboard imported successfully!"
echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Dashboard URL: http://192.168.210.10:3000/d/$DASHBOARD_UID"
echo ""
echo "Next steps:"
echo "  1. Verify data is flowing: curl 'http://localhost:9200/suricata-*/_count'"
echo "  2. Open Grafana at http://192.168.210.10:3000"
echo "  3. Navigate to the dashboard"
echo "  4. Check that panels are showing data"
echo ""
echo "If no data appears:"
echo "  - Check Logstash is running: systemctl status logstash"
echo "  - Check data in OpenSearch: curl 'http://localhost:9200/suricata-*/_search?size=1'"
echo "  - Verify field structure: curl 'http://localhost:9200/suricata-*/_search?size=1' | jq '.hits.hits[0]._source.suricata.eve'"
