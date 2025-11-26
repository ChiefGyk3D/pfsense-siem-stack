#!/bin/bash
# Restart all SIEM services
# Usage: sudo ./restart-services.sh

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Restarting SIEM Services ===${NC}"
echo ""

# Function to restart service
restart_service() {
    local service=$1
    echo -n "Restarting $service... "
    systemctl restart "$service"
    sleep 3
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed${NC}"
        return 1
    fi
}

ERRORS=0

# Restart in order: OpenSearch first, then Logstash, then Grafana
restart_service opensearch || ((ERRORS++))
restart_service logstash || ((ERRORS++))
restart_service grafana-server || ((ERRORS++))

echo ""
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All services restarted successfully${NC}"
    echo ""
    echo "Verify status:"
    echo "  systemctl status opensearch logstash grafana-server"
    echo "Or run:"
    echo "  ./check-system-health.sh"
else
    echo -e "${RED}✗ $ERRORS service(s) failed to restart${NC}"
    echo ""
    echo "Check logs:"
    echo "  sudo journalctl -u opensearch -n 50"
    echo "  sudo journalctl -u logstash -n 50"
    echo "  sudo journalctl -u grafana-server -n 50"
    exit 1
fi
