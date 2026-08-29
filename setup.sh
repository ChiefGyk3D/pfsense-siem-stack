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

# Display configuration
echo ""
echo "  SIEM Server:   ${SIEM_HOST} (OpenSearch :${OPENSEARCH_PORT:-9200}, Logstash UDP :${LOGSTASH_UDP_PORT:-5140}, Grafana :${GRAFANA_PORT:-3000})"
echo "  pfSense:       ${PFSENSE_HOST} (User: ${PFSENSE_USER}, ${EVE_COUNT} Suricata interfaces)"
echo "  Indices:       ${INDEX_PREFIX:-suricata}-*, pfblockerng-*"
echo "  Retention:     ${RETENTION_DAYS:-30} days"
echo ""

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
    ERRORS=$((ERRORS+1))
fi

# Apply pfBlockerNG index template (keyword mappings for aggregation)
PFB_TEMPLATE_FILE="${SCRIPT_DIR}/config/opensearch-pfblockerng-template.json"
if [[ -f "$PFB_TEMPLATE_FILE" ]]; then
    HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' \
        -XPUT "${OPENSEARCH_URL}/_index_template/pfblockerng" \
        -H 'Content-Type: application/json' -d @"$PFB_TEMPLATE_FILE")
    if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
        info "pfBlockerNG index template applied for pfblockerng-*"
    else
        error "Failed to apply pfBlockerNG index template (HTTP $HTTP_CODE)"
        ERRORS=$((ERRORS+1))
    fi
else
    warn "pfBlockerNG template not found: $PFB_TEMPLATE_FILE (optional — needed for Telegraf pfBlockerNG integration)"
fi

# Enable auto-create
HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' \
    -XPUT "${OPENSEARCH_URL}/_cluster/settings" \
    -H 'Content-Type: application/json' -d '{
    "persistent": {
        "action.auto_create_index": "suricata-*,pfblockerng-*,.monitoring-*,.watches,.triggered_watches,.watcher-history-*,.ml-*"
    }
}')
if [[ "$HTTP_CODE" == "200" ]]; then
    info "Auto-create enabled for ${INDEX_PREFIX}-* and pfblockerng-* indices"
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

# Install rc.d service for boot auto-start
info "Installing rc.d service for boot persistence..."
ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'cat > /usr/local/etc/rc.d/suricata_forwarder' << 'RCD_EOF'
#!/bin/sh
# PROVIDE: suricata_forwarder
# REQUIRE: DAEMON
# KEYWORD: shutdown

. /etc/rc.subr

name="suricata_forwarder"
rcvar="suricata_forwarder_enable"
command="/usr/local/bin/forward-suricata-eve.py"
command_interpreter="/usr/local/bin/python3.11"
pidfile="/var/run/${name}.pid"
logfile="/var/log/suricata-forwarder.log"

start_cmd="${name}_start"
stop_cmd="${name}_stop"
status_cmd="${name}_status"

suricata_forwarder_start() {
    if [ -f "$pidfile" ] && kill -0 $(cat "$pidfile") 2>/dev/null; then
        echo "${name} already running (pid=$(cat $pidfile))"
        return 0
    fi
    echo "Starting ${name}..."
    /usr/sbin/daemon -f -p "$pidfile" -o "$logfile" -r "$command"
    echo "${name} started."
}

suricata_forwarder_stop() {
    if [ -f "$pidfile" ]; then
        kill $(cat "$pidfile") 2>/dev/null
        rm -f "$pidfile"
        echo "${name} stopped."
    else
        echo "${name} not running."
    fi
}

suricata_forwarder_status() {
    if [ -f "$pidfile" ] && kill -0 $(cat "$pidfile") 2>/dev/null; then
        echo "${name} is running (pid=$(cat $pidfile))"
    else
        echo "${name} is not running."
        return 1
    fi
}

load_rc_config $name
: ${suricata_forwarder_enable:="NO"}
run_rc_command "$1"
RCD_EOF

ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'chmod 755 /usr/local/etc/rc.d/suricata_forwarder && sysrc suricata_forwarder_enable=YES'
info "rc.d service installed and enabled for boot auto-start"

# Start forwarder via rc.d service
info "Starting forwarder via rc.d service..."
ssh "${PFSENSE_USER}@${PFSENSE_HOST}" 'pkill -f forward-suricata-eve 2>/dev/null; sleep 1; /usr/local/etc/rc.d/suricata_forwarder start'
sleep 3

FORWARDER_PID=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "cat /var/run/suricata_forwarder.pid 2>/dev/null || pgrep -f 'forward-suricata-eve' | head -1" || echo "")
if [[ -n "$FORWARDER_PID" ]]; then
    info "Forwarder running (PID: ${FORWARDER_PID}, ${EVE_COUNT} interfaces)"
else
    error "Forwarder failed to start"
    echo "  Check logs: ssh ${PFSENSE_USER}@${PFSENSE_HOST} 'tail -50 /var/log/system.log | grep suricata'"
    ERRORS=$((ERRORS+1))
fi

# =============================================================================
# STEP 5: Configure Grafana Datasources & Import Dashboards
# =============================================================================
header "Step 5/${TOTAL_STEPS}: Grafana Datasources & Dashboards"

if [[ "$GRAFANA_OK" == true ]]; then
    # Check/install OpenSearch datasource plugin
    if ! curl -s -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/plugins/grafana-opensearch-datasource" | grep -q '"id"' 2>/dev/null; then
        info "Installing grafana-opensearch-datasource plugin..."
        if ssh -o BatchMode=yes "${SIEM_SSH_USER:-$(whoami)}@${SIEM_HOST}" 'command -v grafana-cli' &>/dev/null; then
            ssh "${SIEM_SSH_USER:-$(whoami)}@${SIEM_HOST}" 'sudo grafana-cli plugins install grafana-opensearch-datasource 2>/dev/null && sudo systemctl restart grafana-server' 2>/dev/null || true
            sleep 5
        else
            warn "Could not install grafana-opensearch-datasource plugin automatically"
            echo "  Install manually: grafana-cli plugins install grafana-opensearch-datasource"
        fi
    fi

    # Create OpenSearch-pfBlockerNG datasource if it doesn't exist
    EXISTING_PFB_DS=$(curl -s -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/datasources/name/OpenSearch-pfBlockerNG" 2>/dev/null)
    if echo "$EXISTING_PFB_DS" | grep -q '"id"' 2>/dev/null; then
        info "OpenSearch-pfBlockerNG datasource already exists"
    else
        info "Creating OpenSearch-pfBlockerNG datasource..."
        DS_RESPONSE=$(curl -s -u "${GRAFANA_AUTH}" -X POST "${GRAFANA_URL}/api/datasources" \
            -H 'Content-Type: application/json' \
            -d "{
                \"name\": \"OpenSearch-pfBlockerNG\",
                \"type\": \"grafana-opensearch-datasource\",
                \"access\": \"proxy\",
                \"url\": \"http://localhost:9200\",
                \"database\": \"pfblockerng-*\",
                \"jsonData\": {
                    \"database\": \"pfblockerng-*\",
                    \"flavor\": \"opensearch\",
                    \"pplEnabled\": true,
                    \"version\": \"2.19.4\",
                    \"timeField\": \"@timestamp\",
                    \"logMessageField\": \"\",
                    \"logLevelField\": \"\"
                }
            }")
        if echo "$DS_RESPONSE" | grep -q '"datasource"' 2>/dev/null; then
            info "OpenSearch-pfBlockerNG datasource created"
        else
            warn "Could not create pfBlockerNG datasource automatically"
            echo "  Create manually: Grafana → Data Sources → Add OpenSearch (pfblockerng-*)"
        fi
    fi
fi

# Dashboard auto-import function
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
        }" &>/dev/null && info "Created OpenSearch-Suricata datasource" || true
    fi

    DS_NAME=$(curl -sf -u "${GRAFANA_AUTH}" "${GRAFANA_URL}/api/datasources/uid/${DS_UID}" 2>/dev/null | \
        jq -r '.name // "OpenSearch-Suricata"')

    local PAYLOAD
    PAYLOAD=$(python3 << PYEOF
import json, sys
with open("$json_file") as f:
    dash = json.load(f)

DS_UID = "$DS_UID"
DS_NAME = "$DS_NAME"
DS_TYPE = "grafana-opensearch-datasource"
DS_REF = {"type": DS_TYPE, "uid": DS_UID}

for key in ("__inputs", "__elements", "__requires", "id"):
    dash.pop(key, None)
dash["uid"] = "$dash_uid"
dash["title"] = "$dash_title"

for tvar in dash.get("templating", {}).get("list", []):
    if tvar.get("name") == "DS_OPENSEARCH":
        tvar["current"] = {"selected": True, "text": DS_NAME, "value": DS_UID}
        tvar["options"] = []
    if tvar.get("name") == "interface":
        tvar["datasource"] = DS_REF
        tvar["current"] = {"selected": True, "text": "All", "value": "\$__all"}
        tvar["refresh"] = 1

def fix_ds(obj):
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
        "Suricata IDS/IPS Dashboard" || ERRORS=$((ERRORS+1))

    import_dashboard \
        "${SCRIPT_DIR}/dashboards/Suricata_Per_Interface.json" \
        "suricata_per_interface" \
        "Suricata Per-Interface Dashboard" || ERRORS=$((ERRORS+1))

    echo ""
    echo "  Import pfSense system dashboard manually (requires InfluxDB datasource):"
    echo "    Grafana → Dashboards → Import → dashboards/pfsense_pfblockerng_system.json"
else
    echo "  Import dashboards manually:"
    echo "    1. Open ${GRAFANA_URL} → Dashboards → Import"
    echo "    2. Upload dashboards/pfsense_pfblockerng_system.json (InfluxDB + OpenSearch)"
    echo "    3. Upload dashboards/Suricata_IDS_IPS.json (OpenSearch)"
    echo "    4. Upload dashboards/Suricata_Per_Interface.json (OpenSearch)"
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
    info "Suricata data flowing! ${EVENT_COUNT} events in ${INDEX_PREFIX}-${TODAY}"

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
    warn "No Suricata events yet in today's index (may need a minute)"
    echo "    Check manually: curl ${OPENSEARCH_URL}/${INDEX_PREFIX}-*/_count"
fi

# Check pfBlockerNG data
PFBLOCK_COUNT=$(curl -s "${OPENSEARCH_URL}/pfblockerng-*/_count" 2>/dev/null | jq -r '.count // 0' 2>/dev/null || echo "0")
if [[ "$PFBLOCK_COUNT" -gt 0 ]]; then
    info "pfBlockerNG data flowing! ${PFBLOCK_COUNT} events"
else
    warn "No pfBlockerNG events yet (requires Telegraf with opensearch output on pfSense)"
    echo "    See docs/TELEGRAF_PFBLOCKER_SETUP.md"
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
echo "    ssh ${PFSENSE_USER}@${PFSENSE_HOST} 'service suricata_forwarder status'"
echo ""
