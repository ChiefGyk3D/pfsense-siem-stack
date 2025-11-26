#!/bin/bash
# OpenSearch Configuration Installer for Suricata IDS/IPS Dashboard
# This script configures OpenSearch with proper index templates and cluster settings
# for automatic daily index creation with geo_point mappings

set -e

# Configuration
OPENSEARCH_HOST="${OPENSEARCH_HOST:-localhost}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
OPENSEARCH_URL="http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if OpenSearch is accessible
check_opensearch() {
    print_info "Checking OpenSearch connectivity at ${OPENSEARCH_URL}..."
    if ! curl -s -f "${OPENSEARCH_URL}" > /dev/null; then
        print_error "Cannot connect to OpenSearch at ${OPENSEARCH_URL}"
        print_error "Please ensure OpenSearch is running and accessible"
        exit 1
    fi
    print_info "OpenSearch is accessible"
}

# Function to apply index template
apply_index_template() {
    print_info "Applying Suricata index template..."
    
    if [ ! -f "${CONFIG_DIR}/opensearch-index-template.json" ]; then
        print_error "Index template file not found: ${CONFIG_DIR}/opensearch-index-template.json"
        exit 1
    fi
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -XPUT "${OPENSEARCH_URL}/_index_template/suricata-template" \
        -H 'Content-Type: application/json' \
        -d @"${CONFIG_DIR}/opensearch-index-template.json")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
        print_info "Index template applied successfully"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    else
        print_error "Failed to apply index template (HTTP $HTTP_CODE)"
        echo "$BODY"
        exit 1
    fi
}

# Function to configure auto-create index setting
configure_auto_create() {
    print_info "Configuring auto-create index setting..."
    
    # This is CRITICAL for automatic daily index creation
    # Without this, OpenSearch will NOT create new indices at midnight UTC
    # and Logstash will silently drop all events
    RESPONSE=$(curl -s -w "\n%{http_code}" -XPUT "${OPENSEARCH_URL}/_cluster/settings" \
        -H 'Content-Type: application/json' \
        -d '{
            "persistent": {
                "action.auto_create_index": "suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
            }
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" -eq 200 ]; then
        print_info "Auto-create index setting configured successfully"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
    else
        print_error "Failed to configure auto-create setting (HTTP $HTTP_CODE)"
        echo "$BODY"
        exit 1
    fi
}

# Function to verify configuration
verify_configuration() {
    print_info "Verifying configuration..."
    
    # Check index template
    print_info "Checking index template..."
    TEMPLATE=$(curl -s "${OPENSEARCH_URL}/_index_template/suricata-template")
    if echo "$TEMPLATE" | jq -e '.index_templates[0].name' > /dev/null 2>&1; then
        print_info "✓ Index template exists"
        PATTERNS=$(echo "$TEMPLATE" | jq -r '.index_templates[0].index_template.index_patterns[]')
        print_info "  Patterns: $PATTERNS"
    else
        print_error "✗ Index template not found"
        return 1
    fi
    
    # Check auto-create setting
    print_info "Checking auto-create index setting..."
    SETTING=$(curl -s "${OPENSEARCH_URL}/_cluster/settings?filter_path=persistent.action.auto_create_index")
    AUTO_CREATE=$(echo "$SETTING" | jq -r '.persistent.action.auto_create_index // "not set"')
    
    if [[ "$AUTO_CREATE" == *"suricata-"* ]]; then
        print_info "✓ Auto-create enabled for suricata-* indices"
        print_info "  Value: $AUTO_CREATE"
    else
        print_error "✗ Auto-create not properly configured"
        print_error "  Current value: $AUTO_CREATE"
        return 1
    fi
    
    # Create a test index to verify template application
    print_info "Testing index creation with template..."
    TEST_INDEX="suricata-test-$(date +%s)"
    
    CREATE_RESPONSE=$(curl -s -XPUT "${OPENSEARCH_URL}/${TEST_INDEX}" \
        -H 'Content-Type: application/json' \
        -d '{"settings":{"number_of_shards":1,"number_of_replicas":0}}')
    
    if echo "$CREATE_RESPONSE" | jq -e '.acknowledged' > /dev/null 2>&1; then
        print_info "✓ Test index created successfully"
        
        # Check if geo_point mapping was applied from template
        MAPPING=$(curl -s "${OPENSEARCH_URL}/${TEST_INDEX}/_mapping")
        GEOIP_TYPE=$(echo "$MAPPING" | jq -r ".\"${TEST_INDEX}\".mappings.properties.suricata.properties.eve.properties.geoip_src.properties.location.type // \"not found\"")
        
        if [ "$GEOIP_TYPE" = "geo_point" ]; then
            print_info "✓ Template applied: geo_point mapping confirmed"
        else
            print_warning "⚠ Template may not have applied correctly (geo_point type: $GEOIP_TYPE)"
        fi
        
        # Clean up test index
        curl -s -XDELETE "${OPENSEARCH_URL}/${TEST_INDEX}" > /dev/null
        print_info "  Test index cleaned up"
    else
        print_error "✗ Failed to create test index"
        echo "$CREATE_RESPONSE"
        return 1
    fi
}

# Function to create initial index
create_initial_index() {
    print_info "Creating initial index for today..."
    
    TODAY=$(date -u +%Y.%m.%d)
    INDEX_NAME="suricata-${TODAY}"
    
    # Check if index already exists
    if curl -s -f "${OPENSEARCH_URL}/${INDEX_NAME}" > /dev/null 2>&1; then
        print_info "Index ${INDEX_NAME} already exists, skipping creation"
        return 0
    fi
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -XPUT "${OPENSEARCH_URL}/${INDEX_NAME}" \
        -H 'Content-Type: application/json' \
        -d '{
            "settings": {
                "number_of_shards": 1,
                "number_of_replicas": 0
            }
        }')
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | sed '$d')
    
    if [ "$HTTP_CODE" -eq 200 ] || [ "$HTTP_CODE" -eq 201 ]; then
        print_info "Initial index ${INDEX_NAME} created successfully"
    else
        print_warning "Could not create initial index (HTTP $HTTP_CODE)"
        echo "$BODY"
    fi
}

# Main installation process
main() {
    echo "========================================"
    echo "OpenSearch Configuration Installer"
    echo "Suricata IDS/IPS Dashboard"
    echo "========================================"
    echo ""
    
    print_info "Target OpenSearch: ${OPENSEARCH_URL}"
    echo ""
    
    check_opensearch
    echo ""
    
    apply_index_template
    echo ""
    
    configure_auto_create
    echo ""
    
    verify_configuration
    echo ""
    
    create_initial_index
    echo ""
    
    echo "========================================"
    print_info "Installation completed successfully!"
    echo "========================================"
    echo ""
    print_info "Next steps:"
    echo "  1. Ensure Logstash is configured with config/logstash-suricata.conf"
    echo "  2. Deploy the forwarder to pfSense: scripts/forward-suricata-eve-python.py"
    echo "  3. Import the dashboard: dashboards/Suricata IDS_IPS Dashboard.json"
    echo ""
    print_warning "IMPORTANT: Daily indices will now be automatically created at midnight UTC"
    print_warning "Monitor Logstash logs for any index_not_found_exception errors"
    echo ""
}

# Run main function
main "$@"
