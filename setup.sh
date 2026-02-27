#!/bin/bash
# =============================================================================
# pfSense Suricata → OpenSearch → Grafana Dashboard Setup
# =============================================================================
#
# One-command installer for the complete Suricata IDS/IPS monitoring stack.
#
# What this script does (in order):
#   1. Validates prerequisites (SSH, OpenSearch, Logstash, Grafana)
#   2. Applies OpenSearch index template + auto-create settings
#   3. Deploys Logstash pipeline config (if SIEM server is accessible via SSH)
#   4. Deploys the forwarder + watchdog to pfSense via SSH
#   5. Imports Grafana dashboards via API
#   6. Verifies end-to-end data flow
#
# Usage:
#   1. Copy config.env.example to config.env and edit with your IPs
#   2. Run: ./setup.sh
#
# Requirements:
#   - SSH key access to pfSense (ssh-copy-id admin@<pfsense-ip>)
#   - OpenSearch, Logstash, and Grafana running on the SIEM server
#   - Suricata running on pfSense with at least one interface
#   - curl and jq installed on the machine running this script
# =============================================================================

set -euo pipefail

# ── Colors & helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"

info()    { echo -e "  ${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "  ${YELLOW}[!]${NC} $1"; }
error()   { echo -e "  ${RED}[✗]${NC} $1"; }
header()  { echo ""; echo -e "${BLUE}${BOLD}── $1 ──${NC}"; echo ""; }

TOTAL_STEPS=6
ERRORS=0

# ── Load configuration ────────────────────────────────────────────────────────
if [[ ! -f "$CONFIG_FILE" ]]; then
    if [[ -f "${SCRIPT_DIR}/config.env.example" ]]; then
        cp "${SCRIPT_DIR}/config.env.example" "$CONFIG_FILE"
        echo ""
        echo -e "${YELLOW}Created config.env from the example template.${NC}"
    else
        echo -e "${RED}No config.env or config.env.example found.${NC}"
        exit 1
    fi
    echo ""
    echo "  Edit config.env with your network settings, then re-run:"
    echo ""
    echo "    nano ${CONFIG_FILE}"
    echo "    ./setup.sh"
    echo ""
    exit 0
fi

# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Defaults (with validation for required vars)
SIEM_HOST="${SIEM_HOST:?ERROR: Set SIEM_HOST in config.env}"
PFSENSE_HOST="${PFSENSE_HOST:?ERROR: Set PFSENSE_HOST in config.env}"
PFSENSE_USER="${PFSENSE_USER:-admin}"
SIEM_SSH_USER="${SIEM_SSH_USER:-$(whoami)}"
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
LOGSTASH_UDP_PORT="${LOGSTASH_UDP_PORT:-5140}"
GRAFANA_PORT="${GRAFANA_PORT:-3000}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASS="${GRAFANA_ADMIN_PASS:-admin}"
INDEX_PREFIX="${INDEX_PREFIX:-suricata}"
DEBUG_ENABLED="${DEBUG_ENABLED:-false}"

OPENSEARCH_URL="http://${SIEM_HOST}:${OPENSEARCH_PORT}"
GRAFANA_URL="http://${SIEM_HOST}:${GRAFANA_PORT}"
GRAFANA_AUTH="${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASS}"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}${BOLD}"
echo "  ╔═══════════════════════════════════════════════════════════╗"
echo "  ║   pfSense Suricata → OpenSearch → Grafana Setup          ║"
echo "  ╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  SIEM Server:   ${SIEM_HOST} (OpenSearch :${OPENSEARCH_PORT}, Logstash UDP :${LOGSTASH_UDP_PORT}, Grafana :${GRAFANA_PORT})"
echo "  pfSense:       ${PFSENSE_HOST} (SSH user: ${PFSENSE_USER})"
echo "  SIEM SSH user: ${SIEM_SSH_USER}"
echo "  Index pattern: ${INDEX_PREFIX}-YYYY.MM.dd"
echo ""

read -rp "  Continue with this configuration? [Y/n] " REPLY
[[ "${REPLY:-y}" =~ ^[Nn]$ ]] && { warn "Aborted."; exit 0; }

# =============================================================================
# STEP 1: Preflight checks
# =============================================================================
header "Step 1/${TOTAL_STEPS}: Preflight Checks"

# Check local tools
MISSING_TOOLS=()
for cmd in curl jq ssh scp python3; do
    command -v "$cmd" &>/dev/null || MISSING_TOOLS+=("$cmd")
done
if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
    error "Missing required tools: ${MISSING_TOOLS[*]}"
    echo "  Install: sudo apt install ${MISSING_TOOLS[*]}"
    exit 1
fi
info "Local tools OK (curl, jq, ssh, scp, python3)"

# Check OpenSearch
if curl -sf "${OPENSEARCH_URL}" &>/dev/null; then
    OS_VERSION=$(curl -sf "${OPENSEARCH_URL}" | jq -r '.version.number // "unknown"')
    info "OpenSearch ${OS_VERSION} at ${OPENSEARCH_URL}"
else
    error "Cannot reach OpenSearch at ${OPENSEARCH_URL}"
    echo "  Is OpenSearch installed and running on ${SIEM_HOST}?"
    exit 1
fi

# Check Grafana
GRAFANA_OK=false
if curl -sf "${GRAFANA_URL}/api/health" &>/dev/null; then
    info "Grafana reachable at ${GRAFANA_URL}"
    GRAFANA_OK=true
else
    warn "Cannot reach Grafana at ${GRAFANA_URL} — dashboards will need manual import"
fi

# Check pfSense SSH
if ssh -o ConnectTimeout=5 -o BatchMode=yes "${PFSENSE_USER}@${PFSENSE_HOST}" 'echo ok' &>/dev/null; then
    info "SSH to pfSense OK (${PFSENSE_USER}@${PFSENSE_HOST})"
else
    error "Cannot SSH to ${PFSENSE_USER}@${PFSENSE_HOST} (key-based auth required)"
    echo ""
    echo "  Set up SSH keys first:"
    echo "    ssh-copy-id ${PFSENSE_USER}@${PFSENSE_HOST}"
    echo ""
    exit 1
fi

# Check Suricata EVE logs on pfSense
EVE_COUNT=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'ls /var/log/suricata/*/eve.json 2>/dev/null | wc -l' | tr -d ' ')
if [[ "$EVE_COUNT" -gt 0 ]]; then
    info "Suricata active on pfSense (${EVE_COUNT} interface(s) with EVE logs)"
else
    error "No Suricata EVE logs found on pfSense"
    echo "  Enable Suricata: pfSense → Services → Suricata → Enable on at least one interface"
    exit 1
fi

# Detect Python on pfSense (try common paths)
PFSENSE_PYTHON=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" \
    'for p in /usr/local/bin/python3.11 /usr/local/bin/python3 /usr/bin/python3; do [ -x "$p" ] && echo "$p" && break; done')
if [[ -z "$PFSENSE_PYTHON" ]]; then
    error "Python 3 not found on pfSense"
    echo "  Install: ssh ${PFSENSE_USER}@${PFSENSE_HOST} 'pkg install python311'"
    exit 1
fi
info "Python on pfSense: ${PFSENSE_PYTHON}"

# =============================================================================
# STEP 2: Configure OpenSearch
# =============================================================================
header "Step 2/${TOTAL_STEPS}: Configure OpenSearch"

# Apply index template
TEMPLATE_FILE="${SCRIPT_DIR}/config/opensearch-index-template.json"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    error "Index template not found: $TEMPLATE_FILE"
    exit 1
fi

HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' \
    -XPUT "${OPENSEARCH_URL}/_index_template/suricata-template" \
    -H 'Content-Type: application/json' -d @"$TEMPLATE_FILE")
if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
    info "Index template applied for ${INDEX_PREFIX}-*"
else
    error "Failed to apply index template (HTTP $HTTP_CODE)"
    ((ERRORS++))
fi

# Enable auto-create
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' \
    -XPUT "${OPENSEARCH_URL}/_cluster/settings" \
    -H 'Content-Type: application/json' -d '{
    "persistent": {
        "action.auto_create_index": "suricata-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
}')
if [[ "$HTTP_CODE" == "200" ]]; then
    info "Auto-create enabled for ${INDEX_PREFIX}-* indices"
else
    warn "Could not set auto-create (HTTP $HTTP_CODE) — may already be configured"
fi

# =============================================================================
# STEP 3: Deploy Logstash pipeline config
# =============================================================================
header "Step 3/${TOTAL_STEPS}: Deploy Logstash Pipeline"

LOGSTASH_CONF="${SCRIPT_DIR}/config/logstash-suricata.conf"
LOGSTASH_DEPLOYED=false

if ssh -o ConnectTimeout=5 -o BatchMode=yes "${SIEM_SSH_USER}@${SIEM_HOST}" 'echo ok' &>/dev/null; then
    if ssh "${SIEM_SSH_USER}@${SIEM_HOST}" 'test -d /etc/logstash/conf.d' 2>/dev/null; then
        # Substitute OpenSearch host into config
        TEMP_CONF=$(mktemp)
        sed "s|hosts => \[\"http://localhost:9200\"\]|hosts => [\"http://${SIEM_HOST}:${OPENSEARCH_PORT}\"]|" \
            "$LOGSTASH_CONF" > "$TEMP_CONF"

        # Backup existing config, deploy new one
        ssh "${SIEM_SSH_USER}@${SIEM_HOST}" \
            "sudo cp /etc/logstash/conf.d/suricata.conf /etc/logstash/conf.d/suricata.conf.bak 2>/dev/null || true"
        scp -q "$TEMP_CONF" "${SIEM_SSH_USER}@${SIEM_HOST}:/tmp/suricata-logstash.conf"
        ssh "${SIEM_SSH_USER}@${SIEM_HOST}" \
            "sudo mv /tmp/suricata-logstash.conf /etc/logstash/conf.d/suricata.conf && sudo systemctl restart logstash" 2>/dev/null
        rm -f "$TEMP_CONF"
        info "Logstash config deployed and restarted on ${SIEM_HOST}"
        LOGSTASH_DEPLOYED=true
    else
        warn "Logstash config dir not found on ${SIEM_HOST}"
    fi
else
    warn "Cannot SSH to SIEM server as ${SIEM_SSH_USER}@${SIEM_HOST}"
fi

if [[ "$LOGSTASH_DEPLOYED" == false ]]; then
    echo ""
    echo "  Deploy Logstash config manually:"
    echo "    scp config/logstash-suricata.conf your-user@${SIEM_HOST}:/etc/logstash/conf.d/suricata.conf"
    echo "    # Edit 'hosts' line to point to your OpenSearch URL"
    echo "    sudo systemctl restart logstash"
    echo ""
fi

# =============================================================================
# STEP 4: Deploy forwarder to pfSense
# =============================================================================
header "Step 4/${TOTAL_STEPS}: Deploy Forwarder to pfSense"

FORWARDER_SRC="${SCRIPT_DIR}/scripts/forward-suricata-eve.py"
if [[ ! -f "$FORWARDER_SRC" ]]; then
    error "Forwarder not found: $FORWARDER_SRC"
    exit 1
fi

# Prepare forwarder with user's config baked in
TEMP_FORWARDER=$(mktemp)
sed -e "s|SIEM_HOST = os.getenv(\"SIEM_HOST\", \"[^\"]*\")|SIEM_HOST = os.getenv(\"SIEM_HOST\", \"${SIEM_HOST}\")|" \
    -e "s|LOGSTASH_PORT = int(os.getenv(\"LOGSTASH_UDP_PORT\", \"[^\"]*\"))|LOGSTASH_PORT = int(os.getenv(\"LOGSTASH_UDP_PORT\", \"${LOGSTASH_UDP_PORT}\"))|" \
    -e "s|DEBUG_ENABLED = os.getenv(\"DEBUG_ENABLED\", \"[^\"]*\")|DEBUG_ENABLED = os.getenv(\"DEBUG_ENABLED\", \"${DEBUG_ENABLED}\")|" \
    "$FORWARDER_SRC" > "$TEMP_FORWARDER"

# Fix shebang to match detected Python
sed -i "1s|^#!.*|#!${PFSENSE_PYTHON}|" "$TEMP_FORWARDER"

# Stop existing forwarder
info "Stopping existing forwarder (if any)..."
ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'pkill -f forward-suricata-eve || true' 2>/dev/null
sleep 2

# Deploy
info "Deploying forwarder..."
scp -q "$TEMP_FORWARDER" "${PFSENSE_USER}@${PFSENSE_HOST}:/usr/local/bin/forward-suricata-eve.py"
ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'chmod +x /usr/local/bin/forward-suricata-eve.py'
rm -f "$TEMP_FORWARDER"

# Deploy watchdog
info "Installing watchdog + cron job..."
ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "cat > /usr/local/bin/suricata-forwarder-watchdog.sh" << WATCHDOG_SCRIPT
#!/bin/sh
# Auto-generated watchdog — restarts forwarder if not running
PYTHON="${PFSENSE_PYTHON}"
FORWARDER="/usr/local/bin/forward-suricata-eve.py"
TAG="suricata-watchdog"

PID=\$(pgrep -f "forward-suricata-eve.py" | head -1)
if [ -z "\$PID" ]; then
    logger -t "\$TAG" "Forwarder not running — restarting"
    nohup \$PYTHON \$FORWARDER >/dev/null 2>&1 &
    sleep 2
    PID=\$(pgrep -f "forward-suricata-eve.py" | head -1)
    [ -n "\$PID" ] && logger -t "\$TAG" "Started (PID: \$PID)" || logger -t "\$TAG" "FAILED to start"
fi
WATCHDOG_SCRIPT
ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'chmod +x /usr/local/bin/suricata-forwarder-watchdog.sh'

# Install cron (idempotent — removes old entry first)
ssh "${PFSENSE_USER}@${PFSENSE_HOST}" '
    CRON="* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh"
    (crontab -l 2>/dev/null | grep -v "suricata-forwarder-watchdog" ; echo "$CRON") | crontab -
'

# Start forwarder
info "Starting forwarder..."
ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "nohup ${PFSENSE_PYTHON} /usr/local/bin/forward-suricata-eve.py >/dev/null 2>&1 &"
sleep 3

FORWARDER_PID=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'pgrep -f "forward-suricata-eve.py" | head -1' || echo "")
if [[ -n "$FORWARDER_PID" ]]; then
    info "Forwarder running (PID: ${FORWARDER_PID}, ${EVE_COUNT} interfaces)"
else
    error "Forwarder failed to start"
    echo "  Debug manually: ssh ${PFSENSE_USER}@${PFSENSE_HOST} '${PFSENSE_PYTHON} /usr/local/bin/forward-suricata-eve.py'"
    ((ERRORS++))
fi

# =============================================================================
# STEP 5: Import Grafana dashboards
# =============================================================================
header "Step 5/${TOTAL_STEPS}: Import Grafana Dashboards"

import_dashboard() {
    local json_file="$1"
    local dash_uid="$2"
    local dash_title="$3"

    if [[ ! -f "$json_file" ]]; then
        warn "Dashboard file not found: $json_file"
        return 1
    fi

    # Find existing OpenSearch datasource, or create one
    local DS_UID DS_NAME
    DS_UID=$(curl -sf -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/datasources" 2>/dev/null | \
        jq -r '[.[] | select(.type == "grafana-opensearch-datasource")][0].uid // empty')

    if [[ -z "$DS_UID" ]]; then
        # Create a datasource
        DS_UID="opensearch-suricata"
        curl -sf -u "${GRAFANA_AUTH}" -X POST "${GRAFANA_URL}/api/datasources" \
            -H 'Content-Type: application/json' -d "{
            \"name\": \"OpenSearch-Suricata\",
            \"type\": \"grafana-opensearch-datasource\",
            \"uid\": \"${DS_UID}\",
            \"url\": \"${OPENSEARCH_URL}\",
            \"access\": \"proxy\",
            \"jsonData\": {
                \"database\": \"${INDEX_PREFIX}-*\",
                \"flavor\": \"opensearch\",
                \"pplEnabled\": true,
                \"timeField\": \"@timestamp\",
                \"maxConcurrentShardRequests\": 5
            }
        }" &>/dev/null && info "Created OpenSearch datasource in Grafana" || true
    fi

    DS_NAME=$(curl -sf -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/datasources/uid/${DS_UID}" 2>/dev/null | \
        jq -r '.name // "OpenSearch-Suricata"')

    # Use Python to build the import payload — handles JSON manipulation properly
    local PAYLOAD
    PAYLOAD=$(python3 << PYEOF
import json, sys
with open("$json_file") as f:
    dash = json.load(f)

DS_UID = "$DS_UID"
DS_NAME = "$DS_NAME"
DS_TYPE = "grafana-opensearch-datasource"
DS_REF = {"type": DS_TYPE, "uid": DS_UID}

# Remove export-only fields
for key in ("__inputs", "__elements", "__requires", "id"):
    dash.pop(key, None)
dash["uid"] = "$dash_uid"
dash["title"] = "$dash_title"

# Fix template variables
for tvar in dash.get("templating", {}).get("list", []):
    if tvar.get("name") == "DS_OPENSEARCH":
        tvar["current"] = {"selected": True, "text": DS_NAME, "value": DS_UID}
        tvar["options"] = []
    if tvar.get("name") == "interface":
        tvar["datasource"] = DS_REF
        tvar["current"] = {"selected": True, "text": "All", "value": "\$__all"}
        tvar["refresh"] = 1

def fix_ds(obj):
    """Recursively fix all datasource references."""
    if isinstance(obj, dict):
        ds = obj.get("datasource")
        if isinstance(ds, dict):
            uid = ds.get("uid", "")
            if not uid or "DS_OPENSEARCH" in str(uid):
                obj["datasource"] = DS_REF.copy()
        elif isinstance(ds, str) and "DS_OPENSEARCH" in ds:
            obj["datasource"] = DS_REF.copy()
        for v in obj.values():
            fix_ds(v)
    elif isinstance(obj, list):
        for item in obj:
            fix_ds(item)

fix_ds(dash)
print(json.dumps({"dashboard": dash, "overwrite": True, "message": "Imported by setup.sh"}))
PYEOF
)

    local RESULT STATUS
    RESULT=$(echo "$PAYLOAD" | curl -sf -u "${GRAFANA_AUTH}" -X POST \
        "${GRAFANA_URL}/api/dashboards/db" \
        -H 'Content-Type: application/json' -d @- 2>/dev/null || echo '{"status":"error","message":"curl failed"}')
    STATUS=$(echo "$RESULT" | jq -r '.status // "error"')

    if [[ "$STATUS" == "success" ]]; then
        local URL
        URL=$(echo "$RESULT" | jq -r '.url // ""')
        info "Imported: ${dash_title} → ${GRAFANA_URL}${URL}"
        return 0
    else
        error "Failed to import ${dash_title}: $(echo "$RESULT" | jq -r '.message // "unknown"')"
        return 1
    fi
}

if [[ "$GRAFANA_OK" == true ]]; then
    import_dashboard \
        "${SCRIPT_DIR}/dashboards/Suricata_IDS_IPS.json" \
        "suricata_ids_ips" \
        "Suricata IDS/IPS Dashboard" || ((ERRORS++))

    import_dashboard \
        "${SCRIPT_DIR}/dashboards/Suricata_Per_Interface.json" \
        "suricata_per_interface" \
        "Suricata Per-Interface Dashboard" || ((ERRORS++))
else
    echo "  Import dashboards manually:"
    echo "    1. Open ${GRAFANA_URL} → Dashboards → Import"
    echo "    2. Upload dashboards/Suricata_IDS_IPS.json"
    echo "    3. Upload dashboards/Suricata_Per_Interface.json"
    echo "    4. Select your OpenSearch datasource when prompted"
fi

# =============================================================================
# STEP 6: Verify data flow
# =============================================================================
header "Step 6/${TOTAL_STEPS}: Verify Data Flow"

info "Waiting 15 seconds for events to flow..."
sleep 15

TODAY=$(date -u +%Y.%m.%d)
EVENT_COUNT=$(curl -sf "${OPENSEARCH_URL}/${INDEX_PREFIX}-${TODAY}/_count" 2>/dev/null | jq -r '.count // 0' 2>/dev/null || echo "0")

if [[ "$EVENT_COUNT" -gt 0 ]]; then
    info "Data flowing! ${EVENT_COUNT} events in ${INDEX_PREFIX}-${TODAY}"

    # Quick data breakdown
    curl -sf "${OPENSEARCH_URL}/${INDEX_PREFIX}-${TODAY}/_search" \
        -H 'Content-Type: application/json' -d '{
        "size": 0,
        "aggs": {
            "types": {"terms": {"field": "event_type", "size": 5}},
            "ifaces": {"terms": {"field": "in_iface", "size": 5}}
        }
    }' 2>/dev/null | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin).get('aggregations', {})
    types = ', '.join(f'{b[\"key\"]}({b[\"doc_count\"]})' for b in d.get('types',{}).get('buckets',[]))
    ifaces = ', '.join(b['key'] for b in d.get('ifaces',{}).get('buckets',[]))
    if types: print(f'    Event types: {types}')
    if ifaces: print(f'    Interfaces:  {ifaces}')
except: pass
" 2>/dev/null || true
else
    warn "No events yet in today's index (may need a minute, or network is quiet)"
    echo "    Check manually: curl ${OPENSEARCH_URL}/${INDEX_PREFIX}-*/_count"
fi

# =============================================================================
# Summary
# =============================================================================
header "Setup Complete"

if [[ "$ERRORS" -gt 0 ]]; then
    warn "${ERRORS} issue(s) encountered — review the messages above"
else
    info "All components deployed successfully!"
fi

echo ""
echo "  Grafana:    ${GRAFANA_URL}"
echo "  Dashboard:  ${GRAFANA_URL}/d/suricata_ids_ips"
echo "  OpenSearch: curl ${OPENSEARCH_URL}/_cat/indices/${INDEX_PREFIX}-*?v"
echo ""
echo "  Useful commands:"
echo "    ./scripts/status.sh              # Check all component status"
echo "    ./scripts/diagnose-and-repair.sh # Auto-diagnose problems"
echo "    ssh ${PFSENSE_USER}@${PFSENSE_HOST} 'ps aux | grep forward-suricata'"
echo ""
