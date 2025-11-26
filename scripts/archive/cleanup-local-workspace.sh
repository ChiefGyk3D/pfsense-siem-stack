#!/bin/bash

# Cleanup local workspace - remove old/unused scripts and files

echo "=== LOCAL WORKSPACE CLEANUP ==="
echo ""
echo "This will remove old scripts that are no longer needed:"
echo ""

# List files to remove
FILES_TO_REMOVE=(
    "scripts/install_graylog_opensearch.sh"
    "scripts/forward-suricata-eve-to-graylog.sh"
    "scripts/setup-pfsense-filterlog.sh"
    "scripts/install-geoip.sh"
    "scripts/setup-filterlog-parser.sh"
    "scripts/setup-filterlog-csv-extractors.sh"
    "scripts/create-filterlog-grok-extractor.sh"
    "scripts/setup-suricata-extractors-for-dashboard-14893.sh"
    "scripts/install-filebeat-suricata.sh"
    "scripts/fix-filebeat-opensearch.sh"
    "scripts/fix-filebeat-opensearch-compat.sh"
    "pfsense_suricata.json"
)

for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "/home/chiefgyk3d/src/Grafana_Dashboards/$file" ]; then
        echo "  - $file"
    fi
done

echo ""
read -p "Remove these files? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Remove files
cd /home/chiefgyk3d/src/Grafana_Dashboards
for file in "${FILES_TO_REMOVE[@]}"; do
    if [ -f "$file" ]; then
        rm -f "$file"
        echo "Removed: $file"
    fi
done

echo ""
echo "✅ Local cleanup complete!"
echo ""
echo "Remaining files:"
ls -lh scripts/*.sh 2>/dev/null | awk '{print "  - " $9}'
echo ""
echo "Current dashboards:"
ls -lh *.json 2>/dev/null | awk '{print "  - " $9}'
