#!/bin/bash
#
# Search Suricata alerts mentioning the Telegram app
# Greps recent Suricata eve.json logs on pfSense for alert signatures that
# mention the Telegram messaging app. This does NOT configure Telegram
# notifications of any kind.
#

# Host/user from config.env unless overridden: check-telegram-alerts.sh [PFSENSE_IP] [PFSENSE_USER]
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
[ -f "${SCRIPT_DIR}/config.env" ] && . "${SCRIPT_DIR}/config.env"
PFSENSE_IP="${1:-${PFSENSE_HOST:-}}"
PFSENSE_USER="${2:-${PFSENSE_USER:-admin}}"
if [ -z "$PFSENSE_IP" ]; then
    echo "Usage: $0 <PFSENSE_IP> [PFSENSE_USER]   (or set PFSENSE_HOST in config.env)" >&2
    exit 1
fi

echo "================================================"
echo "Searching Suricata alerts mentioning Telegram (app)..."
echo "================================================"
echo ""

# Check recent Telegram alerts in Suricata logs
echo "🔍 Recent Suricata alerts mentioning Telegram (last 1000 lines):"
echo "================================================"
ssh "${PFSENSE_USER}@${PFSENSE_IP}" "
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
ssh "${PFSENSE_USER}@${PFSENSE_IP}" "
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
ssh "${PFSENSE_USER}@${PFSENSE_IP}" "
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
