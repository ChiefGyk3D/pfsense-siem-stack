#!/bin/bash

# Fix dashboard field references to use .keyword for text fields

echo "=== Fixing Suricata Dashboard Field Mappings ==="
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
  -u "$GRAFANA_USER:$GRAFANA_PASS" > /tmp/dashboard-to-fix.json

echo "✓ Downloaded"
echo ""
echo "Fixing field references..."

# Fix the dashboard JSON to use .keyword for text fields
cat /tmp/dashboard-to-fix.json | jq '
  # Function to fix field names in queries
  def fix_fields:
    gsub("suricata\\.eve\\.src_ip(?!\\.keyword)"; "suricata.eve.src_ip.keyword") |
    gsub("suricata\\.eve\\.dest_ip(?!\\.keyword)"; "suricata.eve.dest_ip.keyword") |
    gsub("suricata\\.eve\\.proto(?!\\.keyword)"; "suricata.eve.proto.keyword") |
    gsub("suricata\\.eve\\.in_iface(?!\\.keyword)"; "suricata.eve.in_iface.keyword") |
    gsub("suricata\\.eve\\.alert\\.category(?!\\.keyword)"; "suricata.eve.alert.category.keyword") |
    gsub("suricata\\.eve\\.alert\\.signature(?!\\.keyword)"; "suricata.eve.alert.signature.keyword") |
    gsub("suricata\\.eve\\.event_type(?!\\.keyword)"; "suricata.eve.event_type.keyword");
  
  # Fix all template variables
  .dashboard.templating.list |= map(
    if .query then
      .query |= fix_fields
    else . end
  ) |
  
  # Fix all panel queries
  .dashboard.panels |= map(
    if .panels then
      .panels |= map(
        if .targets then
          .targets |= map(
            if .query then .query |= fix_fields else . end |
            if .bucketAggs then
              .bucketAggs |= map(
                if .field then
                  .field |= (
                    if (. == "suricata.eve.src_ip" or 
                        . == "suricata.eve.dest_ip" or 
                        . == "suricata.eve.proto" or 
                        . == "suricata.eve.in_iface" or
                        . == "suricata.eve.alert.category" or
                        . == "suricata.eve.alert.signature" or
                        . == "suricata.eve.event_type") and (. | contains(".keyword") | not)
                    then . + ".keyword"
                    else .
                    end
                  )
                else . end
              )
            else . end
          )
        else . end
      )
    else . end |
    if .targets then
      .targets |= map(
        if .query then .query |= fix_fields else . end |
        if .bucketAggs then
          .bucketAggs |= map(
            if .field then
              .field |= (
                if (. == "suricata.eve.src_ip" or 
                    . == "suricata.eve.dest_ip" or 
                    . == "suricata.eve.proto" or 
                    . == "suricata.eve.in_iface" or
                    . == "suricata.eve.alert.category" or
                    . == "suricata.eve.alert.signature" or
                    . == "suricata.eve.event_type") and (. | contains(".keyword") | not)
                then . + ".keyword"
                else .
                end
              )
            else . end
          )
        else . end
      )
    else . end
  )
' > /tmp/dashboard-fixed.json

echo "✓ Fields fixed"
echo ""
echo "Uploading fixed dashboard..."

# Prepare for upload
UPLOAD_JSON=$(cat /tmp/dashboard-fixed.json | jq '{
  dashboard: .dashboard,
  overwrite: true,
  message: "Fixed field mappings to use .keyword for text fields"
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
    echo "Refresh the dashboard in your browser to see the changes."
else
    echo "Response:"
    echo "$RESPONSE" | jq .
fi
