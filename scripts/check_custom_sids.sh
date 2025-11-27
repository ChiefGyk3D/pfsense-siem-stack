#!/bin/bash
#
# check_custom_sids.sh - Investigate custom Suricata SIDs
#
# This script helps identify if custom SID numbers are actually being used
# Run this ON your pfSense box (copy via scp or paste into shell)
#

echo "=============================================="
echo "CUSTOM SID INVESTIGATION TOOL"
echo "=============================================="
echo ""

# List of custom SIDs to check
CUSTOM_SIDS="2100366 2100368 2100651 2101390 2101424 2102314 2103134 2103192 100000230"

echo "Checking for custom SIDs: $CUSTOM_SIDS"
echo ""

# Check if rules exist in Suricata rules directories
echo "1. Checking if rules are defined in rule files..."
echo "---"
for SID in $CUSTOM_SIDS; do
    echo -n "SID $SID: "
    FOUND=$(find /usr/local/etc/suricata -name "*.rules" 2>/dev/null | xargs grep -l "sid:$SID" 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        echo "FOUND in $FOUND"
        grep "sid:$SID" "$FOUND" 2>/dev/null | head -1
    else
        echo "NOT FOUND - rule doesn't exist, safe to remove from disablesid.conf"
    fi
done

echo ""
echo "2. Checking sid-msg.map files..."
echo "---"
for SID in $CUSTOM_SIDS; do
    echo -n "SID $SID: "
    FOUND=$(grep "^$SID " /usr/local/etc/suricata/*/sid-msg.map 2>/dev/null | head -1)
    if [ -n "$FOUND" ]; then
        echo "$FOUND"
    else
        echo "NOT in sid-msg.map - rule doesn't exist"
    fi
done

echo ""
echo "3. Checking if any are in your original suppress.conf..."
echo "---"
if [ -f /usr/local/etc/suricata/threshold.config ]; then
    for SID in $CUSTOM_SIDS; do
        if grep -q "sig_id $SID" /usr/local/etc/suricata/threshold.config 2>/dev/null; then
            echo "SID $SID found in threshold.config"
        fi
    done
else
    echo "No threshold.config found"
fi

echo ""
echo "=============================================="
echo "RECOMMENDATION:"
echo "=============================================="
echo "If a SID shows 'NOT FOUND' above, it's safe to remove"
echo "from your disablesid.conf - the rule doesn't exist."
echo ""
echo "These are likely from an old Reddit list that included"
echo "custom rules that don't exist in your environment."
