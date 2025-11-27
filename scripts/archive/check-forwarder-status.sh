#!/bin/bash
# Check pfSense forwarder status
# Usage: ./check-forwarder-status.sh PFSENSE_IP

if [ $# -ne 1 ]; then
    echo "Usage: $0 PFSENSE_IP"
    echo "Example: $0 192.168.1.1"
    exit 1
fi

PFSENSE_IP="$1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== pfSense Forwarder Status Check ===${NC}"
echo "pfSense IP: $PFSENSE_IP"
echo ""

ERRORS=0

# Check connectivity
echo -n "Testing connectivity to pfSense... "
if ping -c 1 -W 2 "$PFSENSE_IP" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${RED}✗ Cannot ping pfSense${NC}"
    exit 1
fi

# Check SSH access
echo -n "Testing SSH access... "
if ssh -o BatchMode=yes -o ConnectTimeout=5 root@"$PFSENSE_IP" "echo test" > /dev/null 2>&1; then
    echo -e "${GREEN}✓${NC}"
else
    echo -e "${YELLOW}⚠ SSH requires password (will prompt below)${NC}"
fi
echo ""

# Check if forwarder is running
echo -e "${YELLOW}[1/4] Checking Forwarder Process${NC}"
FORWARDER_STATUS=$(ssh root@"$PFSENSE_IP" 'ps aux | grep "[f]orward-suricata-eve-python.py"' 2>/dev/null)
if [ -n "$FORWARDER_STATUS" ]; then
    echo -e "${GREEN}✓ Forwarder is running${NC}"
    echo "$FORWARDER_STATUS" | awk '{printf "  PID: %s, CPU: %s%%, MEM: %s%%\n", $2, $3, $4}'
else
    echo -e "${RED}✗ Forwarder is NOT running${NC}"
    ((ERRORS++))
fi
echo ""

# Check if Suricata is generating events
echo -e "${YELLOW}[2/4] Checking Suricata Events${NC}"
echo -n "Checking for EVE JSON file... "
EVE_LOG=$(ssh root@"$PFSENSE_IP" 'ls /var/log/suricata/*/eve.json 2>/dev/null | head -1')
if [ -n "$EVE_LOG" ]; then
    echo -e "${GREEN}✓ Found: $EVE_LOG${NC}"
else
    echo -e "${RED}✗ No EVE JSON file found${NC}"
    echo "  Ensure Suricata is running and EVE JSON output is enabled"
    ((ERRORS++))
fi

if [ -n "$EVE_LOG" ]; then
    echo -n "Checking recent events... "
    RECENT_EVENTS=$(ssh root@"$PFSENSE_IP" "tail -1 '$EVE_LOG' 2>/dev/null")
    if [ -n "$RECENT_EVENTS" ]; then
        echo -e "${GREEN}✓ Events are being generated${NC}"
        LATEST_TS=$(echo "$RECENT_EVENTS" | jq -r .timestamp 2>/dev/null)
        if [ -n "$LATEST_TS" ] && [ "$LATEST_TS" != "null" ]; then
            echo "  Latest event: $LATEST_TS"
        fi
    else
        echo -e "${YELLOW}⚠ No recent events found${NC}"
    fi
fi
echo ""

# Check watchdog
echo -e "${YELLOW}[3/4] Checking Watchdog${NC}"
echo -n "Checking watchdog cron job... "
WATCHDOG_CRON=$(ssh root@"$PFSENSE_IP" 'crontab -l 2>/dev/null | grep watchdog')
if [ -n "$WATCHDOG_CRON" ]; then
    echo -e "${GREEN}✓ Configured${NC}"
    echo "  $WATCHDOG_CRON"
else
    echo -e "${YELLOW}⚠ Not configured in cron${NC}"
    echo "  Add via pfSense Web UI: System → Cron"
fi

echo -n "Checking watchdog logs... "
WATCHDOG_LOGS=$(ssh root@"$PFSENSE_IP" 'grep suricata-forwarder-watchdog /var/log/system.log 2>/dev/null | tail -3')
if [ -n "$WATCHDOG_LOGS" ]; then
    echo -e "${GREEN}✓ Found recent activity${NC}"
    echo "$WATCHDOG_LOGS" | while read -r line; do
        echo "  $line"
    done
else
    echo -e "${YELLOW}⚠ No recent watchdog activity${NC}"
fi
echo ""

# Check forwarder logs
echo -e "${YELLOW}[4/4] Checking Forwarder Logs${NC}"
FORWARDER_LOGS=$(ssh root@"$PFSENSE_IP" 'grep suricata-forwarder /var/log/system.log 2>/dev/null | tail -5')
if [ -n "$FORWARDER_LOGS" ]; then
    echo -e "${GREEN}Recent forwarder log entries:${NC}"
    echo "$FORWARDER_LOGS" | while read -r line; do
        echo "  $line"
    done
else
    echo -e "${YELLOW}⚠ No forwarder log entries found${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Forwarder appears to be working correctly${NC}"
    echo ""
    echo "Next steps:"
    echo "  - Verify events reaching SIEM: ./verify-suricata-data.sh"
    echo "  - Check full system health: ./check-system-health.sh"
else
    echo -e "${RED}✗ Found $ERRORS issue(s)${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  - Restart forwarder: ssh root@$PFSENSE_IP 'pkill -f forward-suricata; nohup /usr/local/bin/forward-suricata-eve.sh > /dev/null 2>&1 &'"
    echo "  - Check Suricata status: ssh root@$PFSENSE_IP 'service suricata status'"
    echo "  - See docs/TROUBLESHOOTING.md for detailed help"
    exit 1
fi
