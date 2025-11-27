#!/bin/bash
# Deploy pfSense Suricata forwarder
# Usage: ./deploy-pfsense-forwarder.sh PFSENSE_IP SIEM_IP

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

if [ $# -ne 2 ]; then
    echo -e "${RED}Usage: $0 PFSENSE_IP SIEM_IP${NC}"
    echo "Example: $0 192.168.1.1 192.168.1.100"
    exit 1
fi

PFSENSE_IP="$1"
SIEM_IP="$2"

echo -e "${GREEN}=== pfSense Suricata Forwarder Deployment ===${NC}"
echo "pfSense IP: $PFSENSE_IP"
echo "SIEM Server IP: $SIEM_IP"
echo ""

# Check if we can reach pfSense
echo -e "${YELLOW}[1/6]${NC} Testing connectivity to pfSense..."
if ! ping -c 1 -W 2 "$PFSENSE_IP" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Cannot ping pfSense at $PFSENSE_IP${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} pfSense is reachable"

# Check if SSH is available
echo -e "${YELLOW}[2/6]${NC} Testing SSH access..."
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 root@"$PFSENSE_IP" "echo test" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Cannot SSH to pfSense. Please ensure:${NC}"
    echo "  1. SSH is enabled (System > Advanced > Secure Shell)"
    echo "  2. SSH key is configured or you'll be prompted for password"
    exit 1
fi
echo -e "${GREEN}✓${NC} SSH access confirmed"

# Create temporary directory for modified files
TEMP_DIR=$(mktemp -d)
echo -e "${YELLOW}[3/6]${NC} Preparing deployment files..."

# Copy files and update SIEM IP
cd "$(dirname "$0")/pfsense"

# Update Python script with SIEM IP
sed "s/GRAYLOG_SERVER = \".*\"/GRAYLOG_SERVER = \"$SIEM_IP\"/" forward-suricata-eve-python.py > "$TEMP_DIR/forward-suricata-eve-python.py"
cp forward-suricata-eve.sh "$TEMP_DIR/"
cp suricata-forwarder-watchdog.sh "$TEMP_DIR/"

echo -e "${GREEN}✓${NC} Files prepared with SIEM IP: $SIEM_IP"

# Deploy to pfSense
echo -e "${YELLOW}[4/6]${NC} Deploying files to pfSense..."
scp "$TEMP_DIR/forward-suricata-eve-python.py" root@"$PFSENSE_IP":/usr/local/bin/ || {
    echo -e "${RED}ERROR: Failed to copy Python forwarder${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
}
scp "$TEMP_DIR/forward-suricata-eve.sh" root@"$PFSENSE_IP":/usr/local/bin/ || {
    echo -e "${RED}ERROR: Failed to copy wrapper script${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
}
scp "$TEMP_DIR/suricata-forwarder-watchdog.sh" root@"$PFSENSE_IP":/usr/local/bin/ || {
    echo -e "${RED}ERROR: Failed to copy watchdog script${NC}"
    rm -rf "$TEMP_DIR"
    exit 1
}

# Make executable
ssh root@"$PFSENSE_IP" 'chmod +x /usr/local/bin/forward-suricata-eve-python.py /usr/local/bin/forward-suricata-eve.sh /usr/local/bin/suricata-forwarder-watchdog.sh'

echo -e "${GREEN}✓${NC} Files deployed and made executable"

# Clean up temp directory
rm -rf "$TEMP_DIR"

# Stop any existing forwarder
echo -e "${YELLOW}[5/6]${NC} Stopping existing forwarder (if any)..."
ssh root@"$PFSENSE_IP" 'pkill -f forward-suricata-eve-python.py 2>/dev/null || true'
sleep 2
echo -e "${GREEN}✓${NC} Cleanup complete"

# Install watchdog cron
echo -e "${YELLOW}[6/7]${NC} Installing watchdog cron job..."
CRON_LINE="* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh"
EXISTING_CRON=$(ssh root@"$PFSENSE_IP" "crontab -l 2>/dev/null | grep -F 'suricata-forwarder-watchdog.sh' || echo ''")

if [ -z "$EXISTING_CRON" ]; then
    ssh root@"$PFSENSE_IP" "(crontab -l 2>/dev/null; echo '${CRON_LINE}') | crontab -"
    echo -e "${GREEN}✓${NC} Watchdog cron job installed"
else
    echo -e "${GREEN}✓${NC} Watchdog cron job already exists"
fi

# Start forwarder
echo -e "${YELLOW}[7/7]${NC} Starting forwarder..."
ssh root@"$PFSENSE_IP" 'nohup /usr/local/bin/forward-suricata-eve.sh > /dev/null 2>&1 &'
sleep 3

# Verify it's running
if ssh root@"$PFSENSE_IP" 'ps aux | grep "[f]orward-suricata-eve-python.py"' > /dev/null; then
    echo -e "${GREEN}✓${NC} Forwarder started successfully"
    
    # Show process info
    echo ""
    echo -e "${GREEN}Forwarder Process:${NC}"
    ssh root@"$PFSENSE_IP" 'ps aux | grep "[f]orward-suricata-eve-python.py"'
    
    # Show syslog entry
    echo ""
    echo -e "${GREEN}Syslog Entry:${NC}"
    ssh root@"$PFSENSE_IP" 'grep suricata-forwarder /var/log/system.log | tail -1' || echo "No syslog entries yet"
    
    # Show watchdog cron
    echo ""
    echo -e "${GREEN}Watchdog Cron:${NC}"
    ssh root@"$PFSENSE_IP" "crontab -l | grep watchdog"
else
    echo -e "${RED}ERROR: Forwarder failed to start${NC}"
    echo "Check logs: ssh root@$PFSENSE_IP 'tail -20 /var/log/system.log'"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo "Forwarder Configuration:"
echo "  • Location: /usr/local/bin/forward-suricata-eve.py"
echo "  • Target SIEM: $SIEM_IP:5140"
echo "  • Watchdog: Enabled (runs every minute)"
echo ""
echo "Verify installation:"
echo "  1. Check event count in OpenSearch:"
echo "     curl -s http://$SIEM_IP:9200/suricata-*/_count | jq .count"
echo ""
echo "  2. Monitor forwarder logs:"
echo "     ssh root@$PFSENSE_IP 'tail -f /var/log/system.log | grep suricata-forwarder'"
echo ""
echo "  3. Check monitored interfaces:"
echo "     ssh root@$PFSENSE_IP 'lsof -c python3.11 | grep eve.json'"
echo ""
echo -e "${GREEN}✓${NC} Watchdog will automatically restart forwarder if it crashes"
echo -e "${GREEN}✓${NC} Cron job persists across reboots"
