#!/bin/bash
# Configure OpenSearch Index State Management (ISM) retention policy
# Automatically deletes indices older than specified days

set -e

# Configuration
OPENSEARCH_HOST="${OPENSEARCH_HOST:-192.168.210.10}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
RETENTION_DAYS="${1:-90}"
INDEX_PATTERN="${2:-suricata-*}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== OpenSearch Retention Policy Configuration ===${NC}"
echo ""
echo "Configuration:"
echo "  OpenSearch: ${OPENSEARCH_HOST}:${OPENSEARCH_PORT}"
echo "  Retention: ${RETENTION_DAYS} days"
echo "  Index Pattern: ${INDEX_PATTERN}"
echo ""

# Check if OpenSearch is reachable
if ! curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/" > /dev/null; then
    echo -e "${RED}ERROR: Cannot reach OpenSearch at ${OPENSEARCH_HOST}:${OPENSEARCH_PORT}${NC}"
    exit 1
fi

# Create ISM policy JSON
POLICY_NAME="delete-after-${RETENTION_DAYS}d"
POLICY_JSON=$(cat <<EOF
{
  "policy": {
    "description": "Delete indices older than ${RETENTION_DAYS} days",
    "default_state": "active",
    "states": [
      {
        "name": "active",
        "actions": [],
        "transitions": [
          {
            "state_name": "delete",
            "conditions": {
              "min_index_age": "${RETENTION_DAYS}d"
            }
          }
        ]
      },
      {
        "name": "delete",
        "actions": [
          {
            "delete": {}
          }
        ],
        "transitions": []
      }
    ],
    "ism_template": [
      {
        "index_patterns": ["${INDEX_PATTERN}"],
        "priority": 100
      }
    ]
  }
}
EOF
)

echo -e "${YELLOW}Creating ISM policy: ${POLICY_NAME}${NC}"
RESPONSE=$(curl -s -X PUT "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ism/policies/${POLICY_NAME}" \
  -H 'Content-Type: application/json' \
  -d "${POLICY_JSON}")

if echo "$RESPONSE" | grep -q '"_id"'; then
    echo -e "${GREEN}✓ Policy created successfully${NC}"
else
    echo -e "${YELLOW}Note: Policy may already exist${NC}"
    echo "Response: $RESPONSE"
fi

echo ""
echo -e "${YELLOW}Applying policy to existing indices matching: ${INDEX_PATTERN}${NC}"

# Get list of matching indices
INDICES=$(curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cat/indices/${INDEX_PATTERN}?h=index" | tr '\n' ' ')

if [ -z "$INDICES" ]; then
    echo -e "${YELLOW}No existing indices found matching ${INDEX_PATTERN}${NC}"
else
    echo "Found indices: $INDICES"
    
    # Apply policy to each index
    for INDEX in $INDICES; do
        echo -n "  Applying to $INDEX... "
        APPLY_RESPONSE=$(curl -s -X POST "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ism/add/${INDEX}" \
          -H 'Content-Type: application/json' \
          -d "{\"policy_id\": \"${POLICY_NAME}\"}")
        
        if echo "$APPLY_RESPONSE" | grep -q '"updated_indices":1'; then
            echo -e "${GREEN}✓${NC}"
        else
            echo -e "${YELLOW}Already applied or failed${NC}"
        fi
    done
fi

echo ""
echo -e "${BLUE}=== Verification ===${NC}"

# Show current policy
echo -e "${YELLOW}Policy Details:${NC}"
curl -s "http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ism/policies/${POLICY_NAME}" | \
  python3 -m json.tool 2>/dev/null || echo "Could not format policy"

echo ""
echo -e "${GREEN}=== Configuration Complete ===${NC}"
echo ""
echo "What happens now:"
echo "  1. New indices matching '${INDEX_PATTERN}' will automatically use this policy"
echo "  2. Indices older than ${RETENTION_DAYS} days will be automatically deleted"
echo "  3. OpenSearch checks index ages every few minutes"
echo ""
echo "To verify policy is working:"
echo "  curl -s http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_plugins/_ism/explain/${INDEX_PATTERN} | python3 -m json.tool"
echo ""
echo "To change retention period, re-run this script with different days:"
echo "  $0 30    # Change to 30 days"
echo "  $0 180   # Change to 180 days"
