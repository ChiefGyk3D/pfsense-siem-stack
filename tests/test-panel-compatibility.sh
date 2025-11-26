#!/bin/bash
# Test Dashboard Panel Compatibility with OpenSearch Datasource
# This script helps identify which Grafana panel types work with grafana-opensearch-datasource

GRAFANA_URL="${GRAFANA_URL:-http://192.168.210.10:3000}"
GRAFANA_USER="${GRAFANA_USER:-admin}"
GRAFANA_PASS="${GRAFANA_PASS:-admin}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Grafana Panel Compatibility Test ===${NC}"
echo ""

# Check installed panel plugins
echo -e "${YELLOW}Checking installed panel plugins...${NC}"
curl -s "$GRAFANA_URL/api/plugins" -u "$GRAFANA_USER:$GRAFANA_PASS" | \
  jq -r 'if type == "array" then .[] | select(.type=="panel") | "  ✓ \(.id) - \(.name)" else "Error: \(.message // .)" end'

echo ""

# Check datasources
echo -e "${YELLOW}Checking configured datasources...${NC}"
curl -s "$GRAFANA_URL/api/datasources" -u "$GRAFANA_USER:$GRAFANA_PASS" | \
  jq -r '.[] | "  \(.type) - \(.name) (uid: \(.uid))"'

echo ""

# Get OpenSearch datasource UID
DATASOURCE_UID=$(curl -s "$GRAFANA_URL/api/datasources" -u "$GRAFANA_USER:$GRAFANA_PASS" | \
  jq -r '.[] | select(.type=="grafana-opensearch-datasource") | .uid' | head -1)

if [ -z "$DATASOURCE_UID" ]; then
    DATASOURCE_UID=$(curl -s "$GRAFANA_URL/api/datasources" -u "$GRAFANA_USER:$GRAFANA_PASS" | \
      jq -r '.[] | select(.type=="elasticsearch") | .uid' | head -1)
fi

echo -e "${YELLOW}Using datasource UID: ${DATASOURCE_UID}${NC}"
echo ""

# Test simple query
echo -e "${YELLOW}Testing basic query to OpenSearch...${NC}"
EVENT_COUNT=$(curl -s http://192.168.210.10:9200/suricata-*/_count | jq -r '.count')
echo -e "  Event count in OpenSearch: ${GREEN}${EVENT_COUNT}${NC}"

echo ""
echo -e "${BLUE}=== Panel Type Recommendations ===${NC}"
echo ""

cat <<EOF
Based on grafana-opensearch-datasource plugin v2.32.1 compatibility:

${GREEN}✓ WORKS WELL:${NC}
  • table - Event details, logs (confirmed working)
  • timeseries - Time-based graphs (confirmed working)
  • stat - Single value metrics (should work)
  • gauge - Single value with gauge display

${YELLOW}⚠ MAY WORK:${NC}
  • piechart - Depends on aggregation support
  • barchart - Basic bar charts
  • bargauge - Bar gauge visualization

${RED}✗ UNLIKELY TO WORK:${NC}
  • grafana-worldmap-panel - Legacy plugin, needs specific data format
  • grafana-piechart-panel - Legacy plugin, may need Elasticsearch datasource
  • graph (old) - Deprecated, use timeseries instead

${BLUE}ℹ RECOMMENDATION:${NC}
  1. Start with table and timeseries (proven to work)
  2. Test built-in stat panels for top values
  3. Try native piechart (not grafana-piechart-panel)
  4. If pie charts don't work, use horizontal bar charts
  5. Focus on practical visualizations over fancy ones

EOF

echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Back up current dashboard:"
echo "     ./scripts/export-dashboard.sh suricata-complete dashboards/suricata-complete-backup.json"
echo ""
echo "  2. Create test dashboard with new panel types"
echo "  3. Gradually add visualizations to see what works"
echo "  4. Document working combinations for future use"
