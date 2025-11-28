#!/bin/bash
#
# Check Telegram Alerts on pfSense
# This script analyzes recent Suricata logs to find Telegram-related alerts
#

PFSENSE_IP="${1:-192.168.1.1}"

echo "================================================"
echo "Checking Telegram Alerts on pfSense..."
echo "================================================"
echo ""

# Check recent Telegram alerts in Suricata logs
echo "🔍 Recent Telegram Alerts (last 1000 lines):"
echo "================================================"
ssh root@${PFSENSE_IP} "
    for log in /var/log/suricata/suricata_*/eve.json; do
        if [ -f \"\$log\" ]; then
            echo \"Checking: \$log\"
            tail -1000 \"\$log\" | jq -r 'select(.alert.signature | contains(\"Telegram\")) | \"[\(.timestamp)] SRC: \(.src_ip):\(.src_port) -> DST: \(.dest_ip):\(.dest_port) | \(.alert.signature) (SID:\(.alert.signature_id))\"' 2>/dev/null | tail -20
        fi
    done
" 2>/dev/null

echo ""
echo "================================================"
echo "🔍 Source IP Summary (Top 10):"
echo "================================================"
ssh root@${PFSENSE_IP} "
    for log in /var/log/suricata/suricata_*/eve.json; do
        if [ -f \"\$log\" ]; then
            tail -5000 \"\$log\" | jq -r 'select(.alert.signature | contains(\"Telegram\")) | .src_ip' 2>/dev/null
        fi
    done | sort | uniq -c | sort -rn | head -10
" 2>/dev/null

echo ""
echo "================================================"
echo "🔍 Alert Frequency by Hour (last 24h):"
echo "================================================"
ssh root@${PFSENSE_IP} "
    for log in /var/log/suricata/suricata_*/eve.json; do
        if [ -f \"\$log\" ]; then
            tail -10000 \"\$log\" | jq -r 'select(.alert.signature | contains(\"Telegram\")) | .timestamp[:13]' 2>/dev/null
        fi
    done | sort | uniq -c
" 2>/dev/null

echo ""
echo "================================================"
echo "Done!"
echo "================================================"
