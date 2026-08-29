#!/bin/sh
#
# Apply Suricata drop.conf rules using suricata-update
# 
# This script works around pfSense GUI's non-functional SID Management
# by manually running suricata-update with the drop.conf file to convert
# high-confidence alert rules to drop/block rules.
#
# Usage: Run after updating Suricata rules in pfSense GUI
#        Or add to cron to run automatically after rule updates
#

set -e

# Suricata instance directories
INSTANCES="suricata_55721_ix0 suricata_50186_ix1"
BASE_DIR="/usr/local/etc/suricata"
OUTPUT_DIR="/var/lib/suricata/rules"

echo "=== Suricata Drop Rules Application ==="
echo "Started: $(date)"

for instance in $INSTANCES; do
    INSTANCE_DIR="${BASE_DIR}/${instance}"
    DROP_CONF="${INSTANCE_DIR}/drop.conf"
    
    if [ ! -f "${DROP_CONF}" ]; then
        echo "⚠️  Warning: ${DROP_CONF} not found, skipping ${instance}"
        continue
    fi
    
    echo ""
    echo "Processing ${instance}..."
    
    # Run suricata-update with drop.conf
    cd "${INSTANCE_DIR}"
    
    if suricata-update \
        --suricata-conf suricata.yaml \
        --drop-conf drop.conf \
        --no-reload \
        --no-test 2>&1 | grep -E '(Dropped|rules|Done)'; then
        
        # Copy generated rules to pfSense location
        if [ -f "${OUTPUT_DIR}/suricata.rules" ]; then
            cp "${OUTPUT_DIR}/suricata.rules" "${INSTANCE_DIR}/rules/suricata.rules"
            
            # Count drop rules
            DROP_COUNT=$(grep -c '^drop' "${INSTANCE_DIR}/rules/suricata.rules" || echo 0)
            ALERT_COUNT=$(grep -c '^alert' "${INSTANCE_DIR}/rules/suricata.rules" || echo 0)
            
            echo "✓ Applied to ${instance}: ${DROP_COUNT} drop rules, ${ALERT_COUNT} alert rules"
        else
            echo "✗ Error: Generated rules not found at ${OUTPUT_DIR}/suricata.rules"
        fi
    else
        echo "✗ Error: suricata-update failed for ${instance}"
    fi
done

echo ""
echo "=== Summary ==="
echo "Completed: $(date)"
echo ""
echo "Next steps:"
echo "1. Restart Suricata instances to activate blocking"
echo "2. Monitor for blocked events in Grafana (action:\"blocked\")"
echo "3. Check /var/log/suricata/*/eve.json for drop events"
