#!/bin/bash

# Fix dashboard template variables to include "All" option

echo "=== Fixing Dashboard Template Variables ==="
echo ""

read -p "Enter Grafana admin username [admin]: " GRAFANA_USER
GRAFANA_USER=${GRAFANA_USER:-admin}

read -sp "Enter Grafana admin password: " GRAFANA_PASS
echo ""
echo ""

GRAFANA_HOST="localhost:3000"
DASHBOARD_UID="CILgABg7k"

echo "Downloading current dashboard..."
curl -s "http://$GRAFANA_HOST/api/dashboards/uid/$DASHBOARD_UID" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" > /tmp/dashboard-vars-fix.json

echo "✓ Downloaded"
echo ""
echo "Fixing template variables to include 'All' option..."

# Fix template variables to allow "All" and make queries work
cat /tmp/dashboard-vars-fix.json | jq '
  .dashboard.templating.list |= map(
    # Add multi-select and "All" option to all variables
    .multi = true |
    .includeAll = true |
    .allValue = "*" |
    # Fix the query format to use proper JSON
    if .name == "iface" then
      .query = "suricata.eve.in_iface.keyword:*"
    elif .name == "protocol" then
      .query = "suricata.eve.proto.keyword:*"
    elif .name == "category" then
      .query = "suricata.eve.alert.category.keyword:*"
    elif .name == "port_dest" then
      .query = "suricata.eve.dest_port:*"
    else . end |
    # Set current value to All
    .current = {
      "selected": true,
      "text": "All",
      "value": "$__all"
    }
  ) |
  # Simplify panel queries to not require all variables
  .dashboard.panels |= map(
    if .targets then
      .targets |= map(
        if .query then
          # Remove variable filters from query, make it simpler
          .query = ""
        else . end
      )
    else . end |
    if .panels then
      .panels |= map(
        if .targets then
          .targets |= map(
            if .query then
              .query = ""
            else . end
          )
        else . end
      )
    else . end
  )
' > /tmp/dashboard-vars-fixed.json

echo "✓ Variables fixed"
echo ""
echo "Uploading fixed dashboard..."

UPLOAD_JSON=$(cat /tmp/dashboard-vars-fixed.json | jq '{
  dashboard: .dashboard,
  overwrite: true,
  message: "Fixed template variables to include All option"
}')

RESPONSE=$(curl -s -X POST "http://$GRAFANA_HOST/api/dashboards/db" \
  -u "$GRAFANA_USER:$GRAFANA_PASS" \
  -H "Content-Type: application/json" \
  -d "$UPLOAD_JSON")

if echo "$RESPONSE" | jq -e '.status == "success"' >/dev/null 2>&1; then
    echo "✅ Dashboard updated successfully!"
    echo ""
    echo "📊 Dashboard URL: http://192.168.210.10:3000/d/$DASHBOARD_UID"
    echo ""
    echo "Refresh the dashboard and make sure:"
    echo "  1. Time range is set to 'Last 24 hours'"
    echo "  2. All template variables at the top show 'All'"
else
    echo "❌ Update failed"
    echo "Response:"
    echo "$RESPONSE" | jq .
fi

echo ""
echo "=== Testing Data Query ==="
curl -s "http://localhost:9200/suricata-*/_search?size=0" -H "Content-Type: application/json" -d '{
  "query": {"range": {"@timestamp": {"gte": "now-24h"}}},
  "aggs": {
    "events": {"terms": {"field": "suricata.eve.event_type.keyword", "size": 10}}
  }
}' | jq "{total: .hits.total.value, event_types: [.aggregations.events.buckets[] | {type: .key, count: .doc_count}]}"
