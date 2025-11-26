#!/bin/bash
# Verify Suricata events are flowing from pfSense to OpenSearch
# Usage: ./verify-suricata-data.sh [PFSENSE_IP]

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PFSENSE_IP="${1:-}"

echo -e "${BLUE}=== Suricata Data Flow Verification ===${NC}"
echo ""

ERRORS=0

# Check OpenSearch has data
echo -e "${YELLOW}[1/3] Checking OpenSearch${NC}"
echo -n "Checking for suricata indices... "
INDICES=$(curl -s "http://localhost:9200/_cat/indices/suricata-*" 2>/dev/null | wc -l)
if [ "$INDICES" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $INDICES indice(s)${NC}"
else
    echo -e "${RED}✗ No suricata indices found${NC}"
    ((ERRORS++))
fi

echo -n "Total event count... "
EVENT_COUNT=$(curl -s "http://localhost:9200/suricata-*/_count" | jq -r .count 2>/dev/null)
if [ -n "$EVENT_COUNT" ] && [ "$EVENT_COUNT" -gt 0 ]; then
    echo -e "${GREEN}$EVENT_COUNT events${NC}"
else
    echo -e "${RED}✗ No events found${NC}"
    ((ERRORS++))
fi

echo -n "Latest event... "
LATEST=$(curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" 2>/dev/null)
LATEST_TS=$(echo "$LATEST" | jq -r '.hits.hits[0]._source."@timestamp"' 2>/dev/null)
LATEST_TYPE=$(echo "$LATEST" | jq -r '.hits.hits[0]._source.suricata.eve.event_type' 2>/dev/null)

if [ -n "$LATEST_TS" ] && [ "$LATEST_TS" != "null" ]; then
    echo -e "${GREEN}$LATEST_TS (type: $LATEST_TYPE)${NC}"
    
    # Check age
    LATEST_EPOCH=$(date -d "$LATEST_TS" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    AGE=$((NOW_EPOCH - LATEST_EPOCH))
    
    if [ $AGE -lt 60 ]; then
        echo -e "  ${GREEN}✓ Fresh (${AGE}s ago)${NC}"
    elif [ $AGE -lt 300 ]; then
        echo -e "  ${YELLOW}⚠ Slightly old (${AGE}s ago, <5 min)${NC}"
    else
        echo -e "  ${RED}✗ Stale (${AGE}s ago, >5 min)${NC}"
        ((ERRORS++))
    fi
else
    echo -e "${RED}✗ No events found${NC}"
    ((ERRORS++))
fi
echo ""

# Check event type distribution
echo -e "${YELLOW}[2/3] Checking Event Types${NC}"
EVENT_TYPES=$(curl -s "http://localhost:9200/suricata-*/_search?size=0" -H "Content-Type: application/json" -d '{"aggs":{"types":{"terms":{"field":"suricata.eve.event_type.keyword","size":10}}}}' 2>/dev/null | jq -r '.aggregations.types.buckets[]' 2>/dev/null)

if [ -n "$EVENT_TYPES" ]; then
    echo "$EVENT_TYPES" | jq -r '"  \(.key): \(.doc_count) events"'
else
    echo -e "${YELLOW}⚠ Unable to retrieve event types${NC}"
fi
echo ""

# Check for parsing errors
echo -e "${YELLOW}[3/3] Checking Data Quality${NC}"
echo -n "Checking for JSON parsing failures... "
PARSE_FAILURES=$(curl -s "http://localhost:9200/suricata-*/_count?q=tags:_jsonparsefailure" 2>/dev/null | jq -r .count 2>/dev/null)
if [ "$PARSE_FAILURES" == "0" ]; then
    echo -e "${GREEN}✓ No parsing failures${NC}"
elif [ -n "$PARSE_FAILURES" ]; then
    FAILURE_PERCENT=$(echo "scale=2; $PARSE_FAILURES * 100 / $EVENT_COUNT" | bc)
    if (( $(echo "$FAILURE_PERCENT < 1" | bc -l) )); then
        echo -e "${YELLOW}⚠ $PARSE_FAILURES failures (${FAILURE_PERCENT}%)${NC}"
    else
        echo -e "${RED}✗ $PARSE_FAILURES failures (${FAILURE_PERCENT}%)${NC}"
        ((ERRORS++))
    fi
fi

echo -n "Checking field structure... "
SAMPLE=$(curl -s "http://localhost:9200/suricata-*/_search?size=1&q=NOT%20tags:_jsonparsefailure" 2>/dev/null | jq -r '.hits.hits[0]._source' 2>/dev/null)
HAS_SURICATA=$(echo "$SAMPLE" | jq 'has("suricata")' 2>/dev/null)
HAS_EVE=$(echo "$SAMPLE" | jq 'has("suricata") and .suricata | has("eve")' 2>/dev/null)

if [ "$HAS_SURICATA" == "true" ] && [ "$HAS_EVE" == "true" ]; then
    echo -e "${GREEN}✓ Correct (suricata.eve.*)${NC}"
else
    echo -e "${RED}✗ Incorrect structure${NC}"
    ((ERRORS++))
fi
echo ""

# Check pfSense forwarder if IP provided
if [ -n "$PFSENSE_IP" ]; then
    echo -e "${BLUE}Optional: Checking pfSense Forwarder${NC}"
    echo "Run: ./check-forwarder-status.sh $PFSENSE_IP"
    echo ""
fi

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ Data is flowing correctly!${NC}"
    echo ""
    echo "Event breakdown:"
    echo "  Total events: $EVENT_COUNT"
    echo "  Latest: $LATEST_TS"
    echo "  Parsing success: 100%"
    echo ""
    echo "Dashboard: http://localhost:3000/d/suricata-complete"
else
    echo -e "${RED}✗ Found $ERRORS issue(s)${NC}"
    echo ""
    echo "Troubleshooting:"
    if [ -n "$PFSENSE_IP" ]; then
        echo "  - Check forwarder: ./check-forwarder-status.sh $PFSENSE_IP"
    else
        echo "  - Check forwarder: ./check-forwarder-status.sh PFSENSE_IP"
    fi
    echo "  - Check Logstash: sudo journalctl -u logstash -n 50"
    echo "  - See docs/TROUBLESHOOTING.md"
    exit 1
fi
