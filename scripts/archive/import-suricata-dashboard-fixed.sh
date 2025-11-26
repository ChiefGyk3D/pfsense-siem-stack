#!/bin/bash

# Setup Grafana dashboard for Suricata IDS
# Interactive script that prompts for Grafana credentials

echo "=== Grafana Dashboard Setup for Suricata IDS ==="
echo ""

# Prompt for credentials
read -p "Enter Grafana admin username [admin]: " GRAFANA_USER
GRAFANA_USER=${GRAFANA_USER:-admin}

read -sp "Enter Grafana admin password: " GRAFANA_PASS
echo ""
echo ""

GRAFANA_HOST="localhost:3000"

# Test credentials
echo "Testing Grafana credentials..."
AUTH_TEST=$(curl -s -o /dev/null -w "%{http_code}" "http://$GRAFANA_HOST/api/datasources" -u "$GRAFANA_USER:$GRAFANA_PASS")

if [ "$AUTH_TEST" != "200" ]; then
    echo "❌ Authentication failed (HTTP $AUTH_TEST)"
    echo "Please check your username and password"
    exit 1
fi

echo "✓ Authentication successful"
echo ""

# Get Elasticsearch datasource UID
echo "Looking for Elasticsearch datasource..."
DATASOURCE_UID=$(curl -s "http://$GRAFANA_HOST/api/datasources" -u "$GRAFANA_USER:$GRAFANA_PASS" | \
    jq -r '.[] | select(.type == "elasticsearch") | .uid' | head -1)

if [ -z "$DATASOURCE_UID" ]; then
    echo "❌ No Elasticsearch datasource found!"
    echo ""
    echo "Please create an Elasticsearch datasource in Grafana with:"
    echo "  - URL: http://localhost:9200"
    echo "  - Index: suricata-*"
    echo "  - Time field: @timestamp"
    echo "  - Version: 7.10+"
    exit 1
fi

echo "✓ Found Elasticsearch datasource with UID: $DATASOURCE_UID"
echo ""

# Download dashboard - try latest revision
echo "Downloading dashboard 14893..."
curl -s "https://grafana.com/api/dashboards/14893" -o /tmp/dashboard-14893-info.json

# Get the latest revision number
LATEST_REVISION=$(cat /tmp/dashboard-14893-info.json | jq -r '.revision // 1')
echo "Latest revision: $LATEST_REVISION"

# Download the dashboard JSON
curl -s "https://grafana.com/api/dashboards/14893/revisions/$LATEST_REVISION/download" -o /tmp/dashboard-14893.json

# Check if download was successful
if ! cat /tmp/dashboard-14893.json | jq empty 2>/dev/null; then
    echo "❌ Failed to download dashboard. Trying without revision..."
    # Fallback: try downloading without specific revision
    curl -s "https://grafana.com/api/dashboards/14893/revisions/latest/download" -o /tmp/dashboard-14893.json
fi

# Verify we have valid JSON
if ! cat /tmp/dashboard-14893.json | jq -e . >/dev/null 2>&1; then
    echo "❌ Downloaded file is not valid JSON"
    echo "Content:"
    cat /tmp/dashboard-14893.json
    exit 1
fi

echo "✓ Dashboard downloaded"
echo ""

# Prepare dashboard JSON with datasource mapping
echo "Preparing dashboard import..."

# Check if the JSON already has a dashboard wrapper
HAS_DASHBOARD=$(cat /tmp/dashboard-14893.json | jq -e '.dashboard' >/dev/null 2>&1 && echo "yes" || echo "no")

if [ "$HAS_DASHBOARD" = "yes" ]; then
    # Already wrapped, just update datasources
    DASHBOARD_JSON=$(cat /tmp/dashboard-14893.json | jq --arg uid "$DATASOURCE_UID" '
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
      .overwrite = true
    ')
else
    # Needs to be wrapped
    DASHBOARD_JSON=$(cat /tmp/dashboard-14893.json | jq --arg uid "$DATASOURCE_UID" '
      {
        dashboard: (. | 
          .panels |= map(
            if .datasource != null then
              .datasource = {"type": "elasticsearch", "uid": $uid}
            else . end
          ) |
          .templating.list |= map(
            if .datasource != null then
              .datasource = {"type": "elasticsearch", "uid": $uid}
            else . end
          )
        ),
        overwrite: true,
        inputs: [],
        folderId: 0
      }
    ')
fi

# Import dashboard
echo "Importing dashboard to Grafana..."
DASHBOARD_RESPONSE=$(curl -s -X POST "http://$GRAFANA_HOST/api/dashboards/db" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H "Content-Type: application/json" \
  -d "$DASHBOARD_JSON")

DASHBOARD_UID=$(echo "$DASHBOARD_RESPONSE" | jq -r '.uid // empty')

if [ -n "$DASHBOARD_UID" ]; then
    echo ""
    echo "✅ Dashboard imported successfully!"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🎉 Suricata IDS Dashboard is ready!"
    echo ""
    echo "📊 Dashboard URL:"
    echo "   http://192.168.210.10:3000/d/$DASHBOARD_UID"
    echo ""
    echo "💡 Tips:"
    echo "   - Set time range to 'Last 24 hours' to see data"
    echo "   - The dashboard shows DNS, TLS, HTTP, and alert events"
    echo "   - Current data includes: $(curl -s http://localhost:9200/suricata-*/_count | jq -r .count) documents"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo ""
    echo "❌ Dashboard import failed"
    echo ""
    echo "Response:"
    echo "$DASHBOARD_RESPONSE" | jq .
    exit 1
fi

echo ""
echo "=== Current Suricata Data Summary ==="
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
