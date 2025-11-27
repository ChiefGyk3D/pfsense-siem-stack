#!/bin/sh
#
# Suricata Log Forwarder Monitoring Setup
# 
# Interactive script to configure automatic monitoring and restart
# for the Suricata EVE JSON forwarder on pfSense
#
# Usage: ./setup_forwarder_monitoring.sh
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running on pfSense
if [ ! -f /etc/platform ]; then
    echo "${RED}Error: This script must be run on pfSense${NC}"
    exit 1
fi

echo "${BLUE}=================================================${NC}"
echo "${BLUE}Suricata Log Forwarder Monitoring Setup${NC}"
echo "${BLUE}=================================================${NC}"
echo ""
echo "This script will help you set up automatic monitoring"
echo "for the Suricata log forwarder to ensure continuous"
echo "log delivery to OpenSearch/Logstash."
echo ""

# Check if forwarder script exists
if [ ! -f /usr/local/bin/forward-suricata-eve.py ]; then
    echo "${RED}Error: Forward script not found at /usr/local/bin/forward-suricata-eve.py${NC}"
    echo "Please install the forwarder first."
    exit 1
fi

# Check if forwarder is currently running
if pgrep -f forward-suricata-eve.py > /dev/null; then
    echo "${GREEN}✓ Forwarder is currently running${NC}"
else
    echo "${YELLOW}⚠ Forwarder is not currently running${NC}"
    echo "Starting forwarder now..."
    /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
    sleep 2
    if pgrep -f forward-suricata-eve.py > /dev/null; then
        echo "${GREEN}✓ Forwarder started successfully${NC}"
    else
        echo "${RED}✗ Failed to start forwarder${NC}"
        exit 1
    fi
fi

echo ""
echo "${BLUE}=================================================${NC}"
echo "${BLUE}Choose Your Monitoring Strategy${NC}"
echo "${BLUE}=================================================${NC}"
echo ""
echo "1) ${GREEN}Hybrid (Recommended)${NC} - Crash recovery + Activity monitoring"
echo "   Best for: Home labs, small businesses, most users"
echo "   - Checks for crashes every 5 minutes"
echo "   - Monitors activity during active hours (9 AM - 11 PM)"
echo ""
echo "2) ${GREEN}Simple Keepalive${NC} - Crash recovery only"
echo "   Best for: Minimal maintenance, set-and-forget"
echo "   - Checks for crashes every 5 minutes"
echo "   - Manual restart needed after Suricata restarts"
echo ""
echo "3) ${GREEN}24/7 Active Monitoring${NC} - Full monitoring around the clock"
echo "   Best for: Data centers, always-on services"
echo "   - Checks for crashes every 5 minutes"
echo "   - Monitors activity 24/7 every 10 minutes"
echo ""
echo "4) ${GREEN}Business Hours${NC} - Monitoring during work hours only"
echo "   Best for: Small businesses (9-5 operation)"
echo "   - Checks for crashes every 5 minutes"
echo "   - Monitors activity Monday-Friday, 8 AM - 6 PM"
echo ""
echo "5) ${YELLOW}Custom${NC} - Manual configuration"
echo "   - I'll guide you through custom settings"
echo ""
echo "6) ${YELLOW}Remove Monitoring${NC} - Uninstall all monitoring"
echo ""
echo "0) ${RED}Exit without changes${NC}"
echo ""

# Get user choice
printf "Enter your choice [1-6, 0 to exit]: "
read CHOICE

case "$CHOICE" in
    1)
        OPTION_NAME="Hybrid (Recommended)"
        CRON_ENTRIES='# Suricata Log Forwarder Monitoring - Hybrid Approach
# Option 1: Simple keepalive - handles crashes
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
# Option 3: Activity monitor - handles stuck processes during active hours (9 AM - 11 PM)
*/15 9-23 * * * [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &'
        ;;
    2)
        OPTION_NAME="Simple Keepalive"
        CRON_ENTRIES='# Suricata Log Forwarder Monitoring - Simple Keepalive
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &'
        ;;
    3)
        OPTION_NAME="24/7 Active Monitoring"
        CRON_ENTRIES='# Suricata Log Forwarder Monitoring - 24/7 Active
# Option 1: Simple keepalive - handles crashes
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
# Option 3: Activity monitor - 24/7 monitoring
*/10 * * * * [ $(find /var/log/suricata/*/eve.json -mmin -10 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &'
        ;;
    4)
        OPTION_NAME="Business Hours"
        CRON_ENTRIES='# Suricata Log Forwarder Monitoring - Business Hours
# Option 1: Simple keepalive - handles crashes
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &
# Option 3: Activity monitor - Monday-Friday 8 AM - 6 PM
*/15 8-18 * * 1-5 [ $(find /var/log/suricata/*/eve.json -mmin -15 | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &'
        ;;
    5)
        echo ""
        echo "${BLUE}Custom Configuration${NC}"
        echo ""
        echo "Enable crash recovery (recommended)? [Y/n]: "
        read CRASH_RECOVERY
        if [ "$CRASH_RECOVERY" != "n" ] && [ "$CRASH_RECOVERY" != "N" ]; then
            CRON_ENTRIES='# Suricata Log Forwarder Monitoring - Custom
*/5 * * * * pgrep -f forward-suricata-eve.py > /dev/null || /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &'
        else
            CRON_ENTRIES='# Suricata Log Forwarder Monitoring - Custom'
        fi
        
        echo "Enable activity monitoring? [y/N]: "
        read ACTIVITY_MON
        if [ "$ACTIVITY_MON" = "y" ] || [ "$ACTIVITY_MON" = "Y" ]; then
            echo "Check interval in minutes [10]: "
            read INTERVAL
            INTERVAL=${INTERVAL:-10}
            
            echo "Activity threshold in minutes [${INTERVAL}]: "
            read THRESHOLD
            THRESHOLD=${THRESHOLD:-$INTERVAL}
            
            echo "Time restriction? (1=24/7, 2=Business hours, 3=Custom): "
            read TIME_RESTRICT
            case "$TIME_RESTRICT" in
                1)
                    TIME_SPEC="* * * *"
                    ;;
                2)
                    TIME_SPEC="8-18 * * 1-5"
                    ;;
                3)
                    echo "Enter cron time spec (e.g., '9-23 * * *'): "
                    read TIME_SPEC
                    ;;
                *)
                    TIME_SPEC="9-23 * * *"
                    ;;
            esac
            
            CRON_ENTRIES="${CRON_ENTRIES}
*/${INTERVAL} ${TIME_SPEC} [ \$(find /var/log/suricata/*/eve.json -mmin -${THRESHOLD} | wc -l) -eq 0 ] && killall python3.11 && sleep 2 && /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py &"
        fi
        OPTION_NAME="Custom"
        ;;
    6)
        echo ""
        echo "${YELLOW}Removing all Suricata forwarder monitoring...${NC}"
        # Remove existing cron entries
        crontab -l 2>/dev/null | grep -v "forward-suricata-eve.py" | crontab - 2>/dev/null || true
        echo "${GREEN}✓ Monitoring removed${NC}"
        echo ""
        echo "Note: The forwarder itself is still running."
        echo "To stop it: killall python3.11"
        exit 0
        ;;
    0)
        echo "Exiting without changes."
        exit 0
        ;;
    *)
        echo "${RED}Invalid choice${NC}"
        exit 1
        ;;
esac

echo ""
echo "${BLUE}=================================================${NC}"
echo "${BLUE}Configuration Summary${NC}"
echo "${BLUE}=================================================${NC}"
echo ""
echo "Selected option: ${GREEN}${OPTION_NAME}${NC}"
echo ""
echo "Cron entries to be added:"
echo "${YELLOW}${CRON_ENTRIES}${NC}"
echo ""
echo "Proceed with installation? [Y/n]: "
read CONFIRM

if [ "$CONFIRM" = "n" ] || [ "$CONFIRM" = "N" ]; then
    echo "Installation cancelled."
    exit 0
fi

# Backup existing crontab
echo ""
echo "Creating backup of existing crontab..."
crontab -l > /tmp/crontab.backup 2>/dev/null || true

# Remove any existing forwarder monitoring entries
echo "Removing old monitoring entries..."
crontab -l 2>/dev/null | grep -v "forward-suricata-eve.py" | grep -v "Suricata Log Forwarder Monitoring" > /tmp/crontab.new || true

# Add new entries
echo "${CRON_ENTRIES}" >> /tmp/crontab.new

# Install new crontab
echo "Installing new crontab..."
crontab /tmp/crontab.new

# Verify installation
if crontab -l | grep -q "forward-suricata-eve.py"; then
    echo ""
    echo "${GREEN}=================================================${NC}"
    echo "${GREEN}✓ Installation Successful!${NC}"
    echo "${GREEN}=================================================${NC}"
    echo ""
    echo "Monitoring has been configured with: ${GREEN}${OPTION_NAME}${NC}"
    echo ""
    echo "Active cron entries:"
    crontab -l | grep -A 3 "Suricata Log Forwarder Monitoring"
    echo ""
    echo "Next steps:"
    echo "1. Wait 5-15 minutes for monitoring to activate"
    echo "2. Test by killing the forwarder: ${YELLOW}killall python3.11${NC}"
    echo "3. Check it restarts: ${YELLOW}ps aux | grep forward-suricata-eve.py${NC}"
    echo ""
    echo "For more information, see: docs/SURICATA_FORWARDER_MONITORING.md"
else
    echo ""
    echo "${RED}✗ Installation failed${NC}"
    echo "Restoring backup..."
    crontab /tmp/crontab.backup 2>/dev/null || true
    exit 1
fi

# Cleanup
rm -f /tmp/crontab.new /tmp/crontab.backup

exit 0
