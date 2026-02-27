#!/bin/bash
# diagnose-and-repair.sh - Comprehensive diagnostic and repair for Suricata dashboards
# Checks every link in the chain: pfSense forwarder → Logstash → OpenSearch → Grafana
# Run from the Grafana_Dashboards project directory

set -u

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PROJECT_DIR}/config.env"

ERRORS=0
WARNINGS=0
FIXES_APPLIED=0

# Load config
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo -e "${RED}ERROR: config.env not found at $CONFIG_FILE${NC}"
    echo "Run: cp config.env.example config.env && nano config.env"
    exit 1
fi

# Defaults
SIEM_HOST="${SIEM_HOST:-192.0.2.10}"
PFSENSE_HOST="${PFSENSE_HOST:-192.0.2.1}"
PFSENSE_USER="${PFSENSE_USER:-admin}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
LOGSTASH_UDP_PORT="${LOGSTASH_UDP_PORT:-5140}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASS="${GRAFANA_ADMIN_PASS:-admin}"
INDEX_PREFIX="${INDEX_PREFIX:-suricata}"

OS_URL="http://${SIEM_HOST}:${OPENSEARCH_PORT}"
GF_URL="http://${SIEM_HOST}:${GRAFANA_PORT}"

header() {
    echo ""
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════${NC}"
}

ok() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; ((ERRORS++)); }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; ((WARNINGS++)); }
info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
fix() { echo -e "  ${GREEN}🔧${NC} $1"; ((FIXES_APPLIED++)); }

# ============================================================================
# STEP 1: Network Connectivity
# ============================================================================
header "Step 1: Network Connectivity"

echo -e "  Testing connectivity to SIEM (${SIEM_HOST})..."
if ping -c 1 -W 2 "$SIEM_HOST" > /dev/null 2>&1; then
    ok "SIEM server reachable"
else
    fail "Cannot ping SIEM server at $SIEM_HOST"
fi

echo -e "  Testing SSH to pfSense (${PFSENSE_HOST})..."
if ssh -o ConnectTimeout=5 -o BatchMode=yes "${PFSENSE_USER}@${PFSENSE_HOST}" 'echo OK' > /dev/null 2>&1; then
    ok "SSH to pfSense working"
    PFSENSE_SSH=true
else
    warn "SSH to pfSense failed (may need password or key)"
    info "Try: ssh-copy-id ${PFSENSE_USER}@${PFSENSE_HOST}"
    PFSENSE_SSH=false
fi

# ============================================================================
# STEP 2: OpenSearch Health
# ============================================================================
header "Step 2: OpenSearch Health"

echo -e "  Checking OpenSearch..."
OS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${OS_URL}/" 2>/dev/null)
if [ "$OS_STATUS" = "200" ]; then
    ok "OpenSearch is running"

    # Cluster health
    HEALTH=$(curl -s "${OS_URL}/_cluster/health" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null)
    if [ "$HEALTH" = "green" ] || [ "$HEALTH" = "yellow" ]; then
        ok "Cluster health: $HEALTH"
    else
        fail "Cluster health: $HEALTH"
    fi

    # Auto-create index
    AUTO_CREATE=$(curl -s "${OS_URL}/_cluster/settings?flat_settings=true" | python3 -c "
import sys,json
d = json.load(sys.stdin)
v = d.get('persistent',{}).get('action.auto_create_index','not set')
print(v)
" 2>/dev/null)
    if echo "$AUTO_CREATE" | grep -qi "${INDEX_PREFIX}"; then
        ok "Auto-create enabled for ${INDEX_PREFIX}-* indices"
    else
        fail "Auto-create NOT enabled (causes midnight UTC data loss!)"
        info "Current setting: $AUTO_CREATE"
        echo ""
        echo -e "  ${YELLOW}FIXING: Enabling auto-create for ${INDEX_PREFIX}-*...${NC}"
        RESULT=$(curl -s -XPUT "${OS_URL}/_cluster/settings" \
            -H 'Content-Type: application/json' \
            -d "{\"persistent\":{\"action.auto_create_index\":\"${INDEX_PREFIX}-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*\"}}" 2>/dev/null)
        if echo "$RESULT" | grep -q '"acknowledged":true'; then
            fix "Auto-create enabled"
        else
            fail "Failed to enable auto-create: $RESULT"
        fi
    fi

    # Check index template
    TEMPLATE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${OS_URL}/_index_template/${INDEX_PREFIX}" 2>/dev/null)
    if [ "$TEMPLATE_STATUS" = "200" ]; then
        ok "Index template '${INDEX_PREFIX}' exists"

        # Check if template uses flat or nested structure
        TEMPLATE_FIELDS=$(curl -s "${OS_URL}/_index_template/${INDEX_PREFIX}" | python3 -c "
import sys,json
d = json.load(sys.stdin)
templates = d.get('index_templates',[])
if templates:
    props = templates[0].get('index_template',{}).get('template',{}).get('mappings',{}).get('properties',{})
    if 'event_type' in props:
        print('flat')
    elif 'suricata' in props:
        print('nested')
    else:
        print('unknown')
else:
    print('empty')
" 2>/dev/null)
        if [ "$TEMPLATE_FIELDS" = "flat" ]; then
            ok "Index template uses FLAT structure (correct)"
        elif [ "$TEMPLATE_FIELDS" = "nested" ]; then
            warn "Index template uses NESTED structure (needs update)"
            echo ""
            echo -e "  ${YELLOW}FIXING: Applying flat index template...${NC}"
            RESULT=$(curl -s -XPUT "${OS_URL}/_index_template/${INDEX_PREFIX}" \
                -H 'Content-Type: application/json' \
                -d @"${PROJECT_DIR}/config/opensearch-index-template.json" 2>/dev/null)
            if echo "$RESULT" | grep -q '"acknowledged":true'; then
                fix "Flat index template applied"
            else
                fail "Failed to apply template: $RESULT"
            fi
        else
            warn "Index template structure: $TEMPLATE_FIELDS"
        fi
    else
        warn "Index template '${INDEX_PREFIX}' not found"
        echo ""
        echo -e "  ${YELLOW}FIXING: Creating index template...${NC}"
        RESULT=$(curl -s -XPUT "${OS_URL}/_index_template/${INDEX_PREFIX}" \
            -H 'Content-Type: application/json' \
            -d @"${PROJECT_DIR}/config/opensearch-index-template.json" 2>/dev/null)
        if echo "$RESULT" | grep -q '"acknowledged":true'; then
            fix "Index template created"
        else
            fail "Failed to create template: $RESULT"
        fi
    fi

    # Check indices
    echo ""
    echo -e "  Checking ${INDEX_PREFIX}-* indices..."
    INDEX_COUNT=$(curl -s "${OS_URL}/_cat/indices/${INDEX_PREFIX}-*?h=index" 2>/dev/null | wc -l)
    if [ "$INDEX_COUNT" -gt 0 ]; then
        ok "$INDEX_COUNT index(es) found"
        # Show recent indices
        curl -s "${OS_URL}/_cat/indices/${INDEX_PREFIX}-*?h=index,docs.count,store.size&s=index:desc" 2>/dev/null | head -5 | while read -r line; do
            info "$line"
        done
    else
        warn "No ${INDEX_PREFIX}-* indices found"
    fi

    # Check today's index
    TODAY=$(date -u +%Y.%m.%d)
    TODAY_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${OS_URL}/${INDEX_PREFIX}-${TODAY}" 2>/dev/null)
    if [ "$TODAY_STATUS" = "200" ]; then
        TODAY_COUNT=$(curl -s "${OS_URL}/${INDEX_PREFIX}-${TODAY}/_count" | python3 -c "import sys,json; print(json.load(sys.stdin).get('count',0))" 2>/dev/null)
        ok "Today's index (${INDEX_PREFIX}-${TODAY}): $TODAY_COUNT events"
    else
        warn "Today's index (${INDEX_PREFIX}-${TODAY}) does not exist yet"
    fi

    # Check latest event timestamp
    LATEST_TS=$(curl -s "${OS_URL}/${INDEX_PREFIX}-*/_search?size=1&sort=@timestamp:desc" 2>/dev/null | python3 -c "
import sys,json
d = json.load(sys.stdin)
hits = d.get('hits',{}).get('hits',[])
if hits:
    print(hits[0].get('_source',{}).get('@timestamp','unknown'))
else:
    print('none')
" 2>/dev/null)
    if [ "$LATEST_TS" != "none" ] && [ -n "$LATEST_TS" ]; then
        info "Latest event: $LATEST_TS"
    else
        warn "No events found in any index"
    fi

    # Check field structure (flat vs nested)
    echo ""
    echo -e "  Checking field structure in latest event..."
    FIELD_STRUCTURE=$(curl -s "${OS_URL}/${INDEX_PREFIX}-*/_search?size=1&sort=@timestamp:desc" 2>/dev/null | python3 -c "
import sys,json
d = json.load(sys.stdin)
hits = d.get('hits',{}).get('hits',[])
if hits:
    src = hits[0].get('_source',{})
    if 'event_type' in src:
        print('flat')
    elif 'suricata' in src:
        print('nested')
    else:
        keys = list(src.keys())[:10]
        print(f'unknown: {keys}')
else:
    print('no_events')
" 2>/dev/null)
    case "$FIELD_STRUCTURE" in
        flat)
            ok "Events use FLAT field structure (correct)"
            ;;
        nested)
            fail "Events use NESTED structure (suricata.eve.*)"
            info "Deploy updated Logstash config and restart:"
            info "  sudo cp config/logstash-suricata.conf /etc/logstash/conf.d/suricata.conf"
            info "  sudo systemctl restart logstash"
            info "New events will use flat structure. Old indices keep nested data."
            ;;
        no_events)
            warn "No events to check structure"
            ;;
        *)
            warn "Field structure: $FIELD_STRUCTURE"
            ;;
    esac
else
    fail "OpenSearch is NOT responding (HTTP $OS_STATUS)"
    info "Check: sudo systemctl status opensearch"
fi

# ============================================================================
# STEP 3: Logstash
# ============================================================================
header "Step 3: Logstash Status"

# Check if logstash is running (remote or local)
echo -e "  Checking Logstash on SIEM server..."
LS_API=$(curl -s -o /dev/null -w "%{http_code}" "http://${SIEM_HOST}:9600/" 2>/dev/null)
if [ "$LS_API" = "200" ]; then
    ok "Logstash API reachable"
    
    # Check pipeline stats
    PIPELINE_EVENTS=$(curl -s "http://${SIEM_HOST}:9600/_node/stats/pipelines" 2>/dev/null | python3 -c "
import sys,json
d = json.load(sys.stdin)
pipelines = d.get('pipelines',{})
for name, p in pipelines.items():
    events_in = p.get('events',{}).get('in',0)
    events_out = p.get('events',{}).get('out',0)
    events_filtered = p.get('events',{}).get('filtered',0)
    print(f'{name}: in={events_in} out={events_out} filtered={events_filtered}')
" 2>/dev/null)
    if [ -n "$PIPELINE_EVENTS" ]; then
        info "Pipeline stats:"
        echo "$PIPELINE_EVENTS" | while read -r line; do
            info "  $line"
        done
    fi
else
    warn "Logstash API not reachable (port 9600)"
    info "Logstash may still be running without API enabled"
fi

# Check UDP port
echo -e "  Checking Logstash UDP port ${LOGSTASH_UDP_PORT}..."
if nc -z -u -w2 "$SIEM_HOST" "$LOGSTASH_UDP_PORT" 2>/dev/null; then
    ok "UDP port $LOGSTASH_UDP_PORT appears open"
else
    warn "Cannot verify UDP port $LOGSTASH_UDP_PORT (nc may not support UDP probe)"
    info "Send test event to verify:"
    info "  echo '{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%S.000000%z)\",\"event_type\":\"test\",\"src_ip\":\"1.2.3.4\"}' | nc -u -w1 ${SIEM_HOST} ${LOGSTASH_UDP_PORT}"
fi

# Check Logstash config on SIEM
echo -e "  Checking deployed Logstash config..."
if ssh -o ConnectTimeout=3 -o BatchMode=yes "${GRAFANA_ADMIN_USER}@${SIEM_HOST}" 'test -f /etc/logstash/conf.d/suricata.conf' 2>/dev/null; then
    # Check if config uses flat or nested
    CONFIG_TYPE=$(ssh -o ConnectTimeout=3 -o BatchMode=yes "${GRAFANA_ADMIN_USER}@${SIEM_HOST}" 'grep -c "suricata.*eve" /etc/logstash/conf.d/suricata.conf' 2>/dev/null)
    if [ "${CONFIG_TYPE:-0}" -gt 0 ]; then
        fail "Deployed Logstash config uses NESTED structure"
        info "Update with: scp config/logstash-suricata.conf ${GRAFANA_ADMIN_USER}@${SIEM_HOST}:/tmp/"
        info "Then on SIEM: sudo cp /tmp/logstash-suricata.conf /etc/logstash/conf.d/suricata.conf && sudo systemctl restart logstash"
    else
        ok "Deployed Logstash config uses flat structure"
    fi
else
    info "Cannot SSH to SIEM to check Logstash config (check manually)"
fi

# ============================================================================
# STEP 4: pfSense Forwarder
# ============================================================================
header "Step 4: pfSense Forwarder"

if [ "$PFSENSE_SSH" = true ]; then
    # Check forwarder process
    echo -e "  Checking forwarder process..."
    FORWARDER_PID=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'pgrep -f forward-suricata-eve' 2>/dev/null)
    if [ -n "$FORWARDER_PID" ]; then
        ok "Forwarder running (PID: $FORWARDER_PID)"
        
        # Check CPU usage
        FORWARDER_CPU=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "ps aux | grep '[f]orward-suricata-eve' | awk '{print \$3}'" 2>/dev/null)
        info "Forwarder CPU: ${FORWARDER_CPU}%"
    else
        fail "Forwarder NOT running"
        echo ""
        echo -e "  ${YELLOW}FIXING: Starting forwarder...${NC}"
        ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &' 2>/dev/null
        sleep 3
        FORWARDER_PID=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'pgrep -f forward-suricata-eve' 2>/dev/null)
        if [ -n "$FORWARDER_PID" ]; then
            fix "Forwarder started (PID: $FORWARDER_PID)"
        else
            fail "Failed to start forwarder"
            info "Check manually: ssh ${PFSENSE_USER}@${PFSENSE_HOST} '/usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py'"
        fi
    fi

    # Check forwarder target IP
    echo -e "  Checking forwarder configuration..."
    FORWARDER_TARGET=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'grep -E "GRAYLOG_SERVER|SIEM_HOST" /usr/local/bin/forward-suricata-eve.py 2>/dev/null | head -1' 2>/dev/null)
    if echo "$FORWARDER_TARGET" | grep -q "$SIEM_HOST"; then
        ok "Forwarder target: $SIEM_HOST"
    else
        warn "Forwarder target may not point to $SIEM_HOST"
        info "Current config: $FORWARDER_TARGET"
        info "Re-deploy forwarder with: ./setup.sh"
    fi

    # Check Suricata
    echo -e "  Checking Suricata on pfSense..."
    SURICATA_PID=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'pgrep suricata' 2>/dev/null)
    if [ -n "$SURICATA_PID" ]; then
        ok "Suricata running"
    else
        fail "Suricata NOT running on pfSense"
        info "Enable Suricata in pfSense web UI: Services > Suricata"
    fi

    # Check EVE JSON files
    echo -e "  Checking EVE JSON log files..."
    EVE_FILES=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'ls -la /var/log/suricata/*/eve.json 2>/dev/null | wc -l' 2>/dev/null)
    if [ "${EVE_FILES:-0}" -gt 0 ]; then
        ok "$EVE_FILES EVE JSON file(s) found"
        # Check recent activity
        RECENT_EVE=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'find /var/log/suricata/*/eve.json -mmin -5 2>/dev/null | wc -l' 2>/dev/null)
        if [ "${RECENT_EVE:-0}" -gt 0 ]; then
            ok "$RECENT_EVE file(s) updated in last 5 minutes"
        else
            warn "No EVE files updated in last 5 minutes (low traffic?)"
        fi
    else
        fail "No EVE JSON files found"
        info "Suricata may not have any interfaces configured"
    fi

    # Check watchdog cron
    echo -e "  Checking watchdog cron..."
    WATCHDOG=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'crontab -l 2>/dev/null | grep watchdog' 2>/dev/null)
    if [ -n "$WATCHDOG" ]; then
        ok "Watchdog cron installed"
    else
        warn "Watchdog cron NOT installed"
        info "Install with: ssh ${PFSENSE_USER}@${PFSENSE_HOST} '(crontab -l 2>/dev/null; echo \"* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh\") | crontab -'"
    fi

    # Check Python + maxminddb
    echo -e "  Checking Python environment..."
    PYTHON_OK=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'python3.11 -c "import maxminddb; print(\"ok\")" 2>/dev/null' 2>/dev/null)
    if [ "$PYTHON_OK" = "ok" ]; then
        ok "Python 3.11 + maxminddb available"
    else
        warn "maxminddb module may not be available"
        info "Forwarder will run without GeoIP enrichment"
    fi

    # Check GeoIP database
    echo -e "  Checking GeoIP database..."
    GEOIP_OK=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'ls -la /usr/local/share/ntopng/GeoLite2-City.mmdb /usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb /usr/local/share/GeoIP/GeoLite2-City.mmdb 2>/dev/null | head -1' 2>/dev/null)
    if [ -n "$GEOIP_OK" ]; then
        ok "GeoIP database found: $GEOIP_OK"
    else
        warn "No GeoIP City database found (geomap panel won't work)"
        info "Install ntopng package in pfSense for GeoIP data"
    fi
else
    warn "Skipping pfSense checks (SSH not available)"
    info "Connect manually: ssh ${PFSENSE_USER}@${PFSENSE_HOST}"
fi

# ============================================================================
# STEP 5: Grafana
# ============================================================================
header "Step 5: Grafana"

echo -e "  Checking Grafana..."
GF_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${GF_URL}/api/health" 2>/dev/null)
if [ "$GF_STATUS" = "200" ]; then
    ok "Grafana is running"

    # Check OpenSearch datasource
    echo -e "  Checking OpenSearch datasource..."
    DS_INFO=$(curl -s -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS}" "${GF_URL}/api/datasources" 2>/dev/null | python3 -c "
import sys,json
try:
    ds_list = json.load(sys.stdin)
    for ds in ds_list:
        if ds.get('type') == 'grafana-opensearch-datasource':
            print(f\"uid={ds.get('uid','?')} name={ds.get('name','?')} url={ds.get('url','?')}\")
            break
    else:
        print('none')
except:
    print('error')
" 2>/dev/null)
    if [ "$DS_INFO" != "none" ] && [ "$DS_INFO" != "error" ]; then
        ok "OpenSearch datasource: $DS_INFO"
    else
        fail "No OpenSearch datasource configured in Grafana"
        info "Add datasource: ${GF_URL}/connections/datasources/new"
        info "  Type: grafana-opensearch-datasource"
        info "  URL: http://localhost:9200"
        info "  Index: ${INDEX_PREFIX}-*"
        info "  Time field: @timestamp"
    fi

    # Check dashboards
    echo -e "  Checking Suricata dashboards..."
    DASHBOARDS=$(curl -s -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS}" "${GF_URL}/api/search?query=suricata" 2>/dev/null | python3 -c "
import sys,json
try:
    d = json.load(sys.stdin)
    for item in d:
        print(f\"  {item.get('title','?')} (uid={item.get('uid','?')})\")
except:
    pass
" 2>/dev/null)
    if [ -n "$DASHBOARDS" ]; then
        ok "Suricata dashboard(s) found:"
        echo "$DASHBOARDS"
    else
        warn "No Suricata dashboards found"
        info "Import dashboards from: dashboards/*.json"
    fi
else
    fail "Grafana is NOT responding (HTTP $GF_STATUS)"
    info "Check: sudo systemctl status grafana-server"
fi

# ============================================================================
# STEP 6: End-to-End Data Flow Test
# ============================================================================
header "Step 6: End-to-End Data Flow Test"

echo -e "  Sending test event to Logstash..."
TEST_TS=$(date -u +%Y-%m-%dT%H:%M:%S.000000+0000)
TEST_EVENT="{\"timestamp\":\"${TEST_TS}\",\"event_type\":\"test_diagnostic\",\"src_ip\":\"198.51.100.1\",\"dest_ip\":\"203.0.113.1\",\"proto\":\"TCP\",\"in_iface\":\"diagnostic_test\"}"

echo "$TEST_EVENT" | nc -u -w1 "$SIEM_HOST" "$LOGSTASH_UDP_PORT" 2>/dev/null
info "Test event sent: $TEST_EVENT"

echo -e "  Waiting 10 seconds for processing..."
sleep 10

# Check if test event arrived
TEST_RESULT=$(curl -s "${OS_URL}/${INDEX_PREFIX}-*/_search" \
    -H 'Content-Type: application/json' \
    -d '{"query":{"match":{"event_type":"test_diagnostic"}},"size":1,"sort":[{"@timestamp":"desc"}]}' 2>/dev/null | python3 -c "
import sys,json
d = json.load(sys.stdin)
hits = d.get('hits',{}).get('total',{})
count = hits.get('value',0) if isinstance(hits,dict) else hits
if count > 0:
    src = d['hits']['hits'][0].get('_source',{})
    if 'event_type' in src:
        print(f'flat:{count}')
    elif 'suricata' in src:
        print(f'nested:{count}')
    else:
        print(f'unknown:{count}')
else:
    print('none')
" 2>/dev/null)

case "$TEST_RESULT" in
    flat:*)
        ok "Test event received with FLAT structure! Pipeline is working."
        ;;
    nested:*)
        warn "Test event received but with NESTED structure"
        fail "Logstash config still uses nested structure - update it!"
        info "Deploy updated config:"
        info "  scp config/logstash-suricata.conf user@${SIEM_HOST}:/tmp/"
        info "  ssh user@${SIEM_HOST} 'sudo cp /tmp/logstash-suricata.conf /etc/logstash/conf.d/suricata.conf && sudo systemctl restart logstash'"
        ;;
    none)
        fail "Test event NOT received after 10 seconds"
        info "Possible causes:"
        info "  1. Logstash not running: ssh user@${SIEM_HOST} 'sudo systemctl status logstash'"
        info "  2. Firewall blocking UDP ${LOGSTASH_UDP_PORT}: ssh user@${SIEM_HOST} 'sudo ufw allow ${LOGSTASH_UDP_PORT}/udp'"
        info "  3. Logstash config error: ssh user@${SIEM_HOST} 'sudo journalctl -u logstash --since \"5 min ago\"'"
        ;;
    *)
        warn "Unexpected test result: $TEST_RESULT"
        ;;
esac

# ============================================================================
# Summary
# ============================================================================
header "Diagnostic Summary"

echo -e "  Errors:   ${RED}${ERRORS}${NC}"
echo -e "  Warnings: ${YELLOW}${WARNINGS}${NC}"
echo -e "  Fixes:    ${GREEN}${FIXES_APPLIED}${NC}"
echo ""

if [ "$ERRORS" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}  All checks passed! Pipeline is healthy.${NC}"
elif [ "$ERRORS" -eq 0 ]; then
    echo -e "${YELLOW}  No critical errors. Review warnings above.${NC}"
else
    echo -e "${RED}  Critical issues found. Follow the fix instructions above.${NC}"
    echo ""
    echo -e "${BLUE}  Quick fix commands:${NC}"
    echo ""
    echo "  # 1. Deploy updated Logstash config (on SIEM server):"
    echo "  scp config/logstash-suricata.conf ${GRAFANA_ADMIN_USER}@${SIEM_HOST}:/tmp/"
    echo "  ssh ${GRAFANA_ADMIN_USER}@${SIEM_HOST} 'sudo cp /tmp/logstash-suricata.conf /etc/logstash/conf.d/suricata.conf && sudo systemctl restart logstash'"
    echo ""
    echo "  # 2. Apply index template:"
    echo "  curl -XPUT '${OS_URL}/_index_template/${INDEX_PREFIX}' -H 'Content-Type: application/json' -d @config/opensearch-index-template.json"
    echo ""
    echo "  # 3. Enable auto-create:"
    echo "  curl -XPUT '${OS_URL}/_cluster/settings' -H 'Content-Type: application/json' -d '{\"persistent\":{\"action.auto_create_index\":\"${INDEX_PREFIX}-*\"}}'"
    echo ""
    echo "  # 4. Re-deploy forwarder to pfSense:"
    echo "  ./setup.sh"
    echo ""
    echo "  # 5. Re-import dashboards in Grafana:"
    echo "  # Go to ${GF_URL} → Dashboards → Import → Upload JSON"
    echo "  # Use: dashboards/Suricata_IDS_IPS.json"
    echo ""
    echo "  # 6. Delete old nested-structure indices (optional, frees space):"
    echo "  # curl -XDELETE '${OS_URL}/${INDEX_PREFIX}-*'"
fi

echo ""
exit $ERRORS
