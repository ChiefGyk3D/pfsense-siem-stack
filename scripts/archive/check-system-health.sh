#!/bin/bash
# Check overall system health for pfSense Suricata monitoring stack
# Usage: ./check-system-health.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== pfSense Suricata SIEM Stack Health Check ===${NC}"
echo ""

# Function to check service
check_service() {
    local service=$1
    echo -n "Checking $service... "
    if systemctl is-active --quiet "$service"; then
        echo -e "${GREEN}✓ Running${NC}"
        return 0
    else
        echo -e "${RED}✗ Not running${NC}"
        return 1
    fi
}

# Function to check port
check_port() {
    local port=$1
    local protocol=$2
    local desc=$3
    echo -n "Checking $desc (port $port/$protocol)... "
    if sudo netstat -${protocol}lnp 2>/dev/null | grep -q ":$port "; then
        echo -e "${GREEN}✓ Listening${NC}"
        return 0
    else
        echo -e "${RED}✗ Not listening${NC}"
        return 1
    fi
}

ERRORS=0

# Check services
echo -e "${YELLOW}[1/5] Checking Services${NC}"
check_service opensearch || ((ERRORS++))
check_service logstash || ((ERRORS++))
check_service grafana-server || ((ERRORS++))
echo ""

# Check ports
echo -e "${YELLOW}[2/5] Checking Network Ports${NC}"
check_port 9200 t "OpenSearch HTTP" || ((ERRORS++))
check_port 5140 u "Logstash UDP" || ((ERRORS++))
check_port 3000 t "Grafana" || ((ERRORS++))
echo ""

# Check OpenSearch cluster health
echo -e "${YELLOW}[3/5] Checking OpenSearch Cluster${NC}"
echo -n "Cluster health... "
CLUSTER_STATUS=$(curl -s http://localhost:9200/_cluster/health | jq -r .status 2>/dev/null)
if [ "$CLUSTER_STATUS" == "green" ]; then
    echo -e "${GREEN}✓ Green${NC}"
elif [ "$CLUSTER_STATUS" == "yellow" ]; then
    echo -e "${YELLOW}⚠ Yellow (acceptable for single-node)${NC}"
elif [ "$CLUSTER_STATUS" == "red" ]; then
    echo -e "${RED}✗ Red (critical)${NC}"
    ((ERRORS++))
else
    echo -e "${RED}✗ Unable to check${NC}"
    ((ERRORS++))
fi

echo -n "OpenSearch version... "
OS_VERSION=$(curl -s http://localhost:9200 | jq -r .version.number 2>/dev/null)
if [ -n "$OS_VERSION" ]; then
    echo -e "${GREEN}$OS_VERSION${NC}"
else
    echo -e "${RED}✗ Unable to retrieve${NC}"
    ((ERRORS++))
fi
echo ""

# Check data flow
echo -e "${YELLOW}[4/5] Checking Data Flow${NC}"
echo -n "Event count in OpenSearch... "
EVENT_COUNT=$(curl -s "http://localhost:9200/suricata-*/_count" | jq -r .count 2>/dev/null)
if [ -n "$EVENT_COUNT" ] && [ "$EVENT_COUNT" -gt 0 ]; then
    echo -e "${GREEN}$EVENT_COUNT events${NC}"
else
    echo -e "${RED}✗ No events found${NC}"
    ((ERRORS++))
fi

echo -n "Latest event timestamp... "
LATEST_TS=$(curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq -r '.hits.hits[0]._source."@timestamp"' 2>/dev/null)
if [ -n "$LATEST_TS" ] && [ "$LATEST_TS" != "null" ]; then
    echo -e "${GREEN}$LATEST_TS${NC}"
    
    # Check if recent (within last 5 minutes)
    LATEST_EPOCH=$(date -d "$LATEST_TS" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE=$((NOW_EPOCH - LATEST_EPOCH))
    
    if [ $AGE -lt 300 ]; then
        echo -e "  ${GREEN}✓ Events are current (${AGE}s ago)${NC}"
    else
        echo -e "  ${YELLOW}⚠ Last event was ${AGE}s ago (>5 minutes)${NC}"
    fi
else
    echo -e "${RED}✗ Unable to retrieve${NC}"
    ((ERRORS++))
fi

echo -n "Event type distribution... "
EVENT_TYPES=$(curl -s "http://localhost:9200/suricata-*/_search?size=0" -H "Content-Type: application/json" -d '{"aggs":{"types":{"terms":{"field":"suricata.eve.event_type.keyword","size":5}}}}' | jq -r '.aggregations.types.buckets[] | "\(.key):\(.doc_count)"' 2>/dev/null | tr '\n' ' ')
if [ -n "$EVENT_TYPES" ]; then
    echo -e "${GREEN}$EVENT_TYPES${NC}"
else
    echo -e "${YELLOW}⚠ Unable to retrieve${NC}"
fi
echo ""

# Check resources
echo -e "${YELLOW}[5/5] Checking Resources${NC}"
echo -n "Disk space... "
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -lt 80 ]; then
    echo -e "${GREEN}${DISK_USAGE}% used${NC}"
elif [ "$DISK_USAGE" -lt 90 ]; then
    echo -e "${YELLOW}⚠ ${DISK_USAGE}% used (getting high)${NC}"
else
    echo -e "${RED}✗ ${DISK_USAGE}% used (critical)${NC}"
    ((ERRORS++))
fi

echo -n "Memory usage... "
MEM_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2*100}')
if [ "$MEM_USAGE" -lt 90 ]; then
    echo -e "${GREEN}${MEM_USAGE}%${NC}"
else
    echo -e "${YELLOW}⚠ ${MEM_USAGE}% (high)${NC}"
fi

echo -n "OpenSearch heap usage... "
HEAP_PERCENT=$(curl -s "http://localhost:9200/_cat/nodes?h=heap.percent" | tr -d ' ' 2>/dev/null)
if [ -n "$HEAP_PERCENT" ]; then
    if [ "$HEAP_PERCENT" -lt 75 ]; then
        echo -e "${GREEN}${HEAP_PERCENT}%${NC}"
    elif [ "$HEAP_PERCENT" -lt 90 ]; then
        echo -e "${YELLOW}⚠ ${HEAP_PERCENT}% (getting high)${NC}"
    else
        echo -e "${RED}✗ ${HEAP_PERCENT}% (critical)${NC}"
        ((ERRORS++))
    fi
else
    echo -e "${YELLOW}⚠ Unable to check${NC}"
fi
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! System is healthy.${NC}"
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS issue(s). Review output above.${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "  - Check service logs: sudo journalctl -u <service> -n 50"
    echo "  - Verify forwarder: ./check-forwarder-status.sh PFSENSE_IP"
    echo "  - See docs/TROUBLESHOOTING.md for detailed help"
    exit 1
fi
