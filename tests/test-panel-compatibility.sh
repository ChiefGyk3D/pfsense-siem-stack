#!/bin/bash
# Test Dashboard Panel Compatibility with OpenSearch Datasource
# This script helps identify which Grafana panel types work with grafana-opensearch-datasource

# Load config.env if present (repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

if [ -z "${SIEM_HOST:-}" ]; then
    echo "ERROR: SIEM_HOST not set."
    echo "Set SIEM_HOST in config.env (cp config.env.example config.env) or export SIEM_HOST."
    exit 1
fi

GRAFANA_URL="${GRAFANA_URL:-http://${SIEM_HOST}:${GRAFANA_PORT:-3000}}"
GRAFANA_USER="${GRAFANA_USER:-${GRAFANA_ADMIN_USER:-admin}}"
GRAFANA_PASS="${GRAFANA_PASS:-${GRAFANA_ADMIN_PASS:-admin}}"
OPENSEARCH_URL="${OPENSEARCH_URL:-http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}}"

FAILURES=0

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
if PLUGINS_JSON=$(curl -sf "$GRAFANA_URL/api/plugins" -u "$GRAFANA_USER:$GRAFANA_PASS"); then
    echo "$PLUGINS_JSON" | \
      jq -r 'if type == "array" then .[] | select(.type=="panel") | "  ✓ \(.id) - \(.name)" else "Error: \(.message // .)" end'
else
    echo -e "  ${RED}✗ Cannot query Grafana plugins at $GRAFANA_URL${NC}"
    FAILURES=$((FAILURES+1))
fi

echo ""

# Check datasources
echo -e "${YELLOW}Checking configured datasources...${NC}"
if DS_JSON=$(curl -sf "$GRAFANA_URL/api/datasources" -u "$GRAFANA_USER:$GRAFANA_PASS"); then
    echo "$DS_JSON" | jq -r '.[] | "  \(.type) - \(.name) (uid: \(.uid))"'
else
    echo -e "  ${RED}✗ Cannot query Grafana datasources${NC}"
    FAILURES=$((FAILURES+1))
fi

echo ""

# Get OpenSearch datasource UID
DATASOURCE_UID=$(curl -s "$GRAFANA_URL/api/datasources" -u "$GRAFANA_USER:$GRAFANA_PASS" | \
  jq -r '.[] | select(.type=="grafana-opensearch-datasource") | .uid' | head -1)

if [ -z "$DATASOURCE_UID" ]; then
    DATASOURCE_UID=$(curl -s "$GRAFANA_URL/api/datasources" -u "$GRAFANA_USER:$GRAFANA_PASS" | \
      jq -r '.[] | select(.type=="elasticsearch") | .uid' | head -1)
fi

if [ -z "$DATASOURCE_UID" ]; then
    echo -e "  ${RED}✗ No OpenSearch/Elasticsearch datasource found in Grafana${NC}"
    FAILURES=$((FAILURES+1))
else
    echo -e "${YELLOW}Using datasource UID: ${DATASOURCE_UID}${NC}"
fi
echo ""

# Test simple query
echo -e "${YELLOW}Testing basic query to OpenSearch...${NC}"
EVENT_COUNT=$(curl -sf "${OPENSEARCH_URL}/suricata-*/_count" | jq -r '.count')
if [ -z "$EVENT_COUNT" ] || [ "$EVENT_COUNT" = "null" ]; then
    echo -e "  ${RED}✗ Cannot query OpenSearch at ${OPENSEARCH_URL}${NC}"
    FAILURES=$((FAILURES+1))
else
    echo -e "  Event count in OpenSearch: ${GREEN}${EVENT_COUNT}${NC}"
fi

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
echo "  1. Back up current dashboard via the Grafana API:"
echo "     curl -s -u \"\$GRAFANA_USER:\$GRAFANA_PASS\" \"$GRAFANA_URL/api/dashboards/uid/suricata_ids_ips\" | jq '.dashboard' > dashboards/suricata-backup.json"
echo ""
echo "  2. Create test dashboard with new panel types"
echo "  3. Gradually add visualizations to see what works"
echo "  4. Document working combinations for future use"

if [ "$FAILURES" -gt 0 ]; then
    echo ""
    echo -e "${RED}RESULT: $FAILURES check(s) failed${NC}"
    exit 1
fi
echo ""
echo -e "${GREEN}RESULT: all checks passed${NC}"
exit 0
