#!/bin/bash
# Unified pfSense Suricata Dashboard Setup
# Configures OpenSearch and deploys forwarder in one go

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/config.env"
CONFIG_EXAMPLE="${SCRIPT_DIR}/config.env.example"

# Helper functions
print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check for config file
if [ ! -f "$CONFIG_FILE" ]; then
    print_error "Configuration file not found: $CONFIG_FILE"
    echo ""
    print_info "Creating config.env from example..."
    
    if [ ! -f "$CONFIG_EXAMPLE" ]; then
        print_error "Example config not found: $CONFIG_EXAMPLE"
        exit 1
    fi
    
    cp "$CONFIG_EXAMPLE" "$CONFIG_FILE"
    
    echo ""
    print_warning "Configuration file created: $CONFIG_FILE"
    print_warning "Please edit this file with your settings and run this script again"
    echo ""
    print_info "Required settings:"
    echo "  • SIEM_HOST - IP address of your SIEM server"
    echo "  • PFSENSE_HOST - IP address of your pfSense firewall"
    echo ""
    print_info "Example:"
    echo "  nano $CONFIG_FILE"
    echo ""
    exit 0
fi

# Load configuration
print_info "Loading configuration from: $CONFIG_FILE"
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# Validate required variables
REQUIRED_VARS=("SIEM_HOST" "PFSENSE_HOST")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    print_error "Missing required configuration variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  • $var"
    done
    echo ""
    print_info "Please edit $CONFIG_FILE and set these variables"
    exit 1
fi

# Display configuration
print_header "Configuration Summary"
echo "SIEM Server:"
echo "  • Host: $SIEM_HOST"
echo "  • OpenSearch: $SIEM_HOST:${OPENSEARCH_PORT:-9200}"
echo "  • Logstash: $SIEM_HOST:${LOGSTASH_UDP_PORT:-5140}"
echo "  • Grafana: $SIEM_HOST:${GRAFANA_PORT:-3000}"
echo ""
echo "pfSense Firewall:"
echo "  • Host: $PFSENSE_HOST"
echo "  • User: ${PFSENSE_USER:-root}"
echo ""
echo "Index Configuration:"
echo "  • Suricata prefix: ${INDEX_PREFIX:-suricata}"
echo "  • pfBlockerNG prefix: pfblockerng"
echo "  • Retention: ${RETENTION_DAYS:-30} days"
echo ""

# Prompt to continue
read -p "Continue with this configuration? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warning "Setup cancelled"
    exit 0
fi

#
# Step 1: Configure OpenSearch
#
print_header "Step 1: Configure OpenSearch"

print_info "Checking OpenSearch connectivity..."
if ! curl -s -f "http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}" > /dev/null; then
    print_error "Cannot connect to OpenSearch at http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}"
    print_error "Please ensure OpenSearch is installed and running"
    print_info "Run the SIEM installer first: sudo ./install.sh"
    exit 1
fi

print_info "Running OpenSearch configuration..."
OPENSEARCH_HOST="$SIEM_HOST" \
OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}" \
    "${SCRIPT_DIR}/scripts/install-opensearch-config.sh"

if [ $? -ne 0 ]; then
    print_error "OpenSearch configuration failed"
    exit 1
fi

#
# Step 2: Deploy forwarder to pfSense
#
print_header "Step 2: Deploy Forwarder to pfSense"

print_info "Testing SSH connectivity to pfSense..."
if ! ssh -o ConnectTimeout=5 "${PFSENSE_USER:-root}@${PFSENSE_HOST}" 'echo "SSH OK"' > /dev/null 2>&1; then
    print_error "Cannot connect to pfSense via SSH"
    print_error "Please ensure:"
    echo "  1. SSH is enabled in pfSense (System > Advanced > Secure Shell)"
    echo "  2. SSH key is configured or you have the password"
    exit 1
fi

print_info "Preparing forwarder with your configuration..."

# Create temporary forwarder with config
TEMP_FORWARDER=$(mktemp)
sed -e "s/GRAYLOG_SERVER = \".*\"/GRAYLOG_SERVER = \"${SIEM_HOST}\"/" \
    -e "s/GRAYLOG_PORT = .*/GRAYLOG_PORT = ${LOGSTASH_UDP_PORT:-5140}/" \
    -e "s/DEBUG_ENABLED = .*/DEBUG_ENABLED = ${DEBUG_ENABLED:-False}/" \
    "${SCRIPT_DIR}/scripts/forward-suricata-eve-python.py" > "$TEMP_FORWARDER"

print_info "Deploying forwarder to pfSense..."

# Stop existing forwarders
ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" 'pkill -f forward-suricata-eve || true'
sleep 2

# Deploy forwarder
scp "$TEMP_FORWARDER" "${PFSENSE_USER:-root}@${PFSENSE_HOST}:/usr/local/bin/forward-suricata-eve.py"
ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" 'chmod +x /usr/local/bin/forward-suricata-eve.py'
rm "$TEMP_FORWARDER"

print_info "Creating watchdog script..."
ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" 'cat > /usr/local/bin/suricata-forwarder-watchdog.sh' << 'WATCHDOG_EOF'
#!/bin/sh
# Auto-generated watchdog script for Suricata forwarder
FORWARDER_SCRIPT="/usr/local/bin/forward-suricata-eve.py"
LOG_TAG="suricata-forwarder-watchdog"

PYTHON_PID=$(ps aux | grep "[f]orward-suricata-eve.py" | awk '{print $2}' | head -1)

if [ -z "$PYTHON_PID" ]; then
    logger -t "$LOG_TAG" "Forwarder not running, starting..."
    nohup /usr/local/bin/python3.11 "$FORWARDER_SCRIPT" > /dev/null 2>&1 &
    sleep 2
    PYTHON_PID=$(ps aux | grep "[f]orward-suricata-eve.py" | awk '{print $2}' | head -1)
    if [ -n "$PYTHON_PID" ]; then
        logger -t "$LOG_TAG" "Forwarder started (PID: $PYTHON_PID)"
    else
        logger -t "$LOG_TAG" "ERROR: Failed to start forwarder"
    fi
else
    MINUTE=$(date +%M)
    if [ "$((MINUTE % 5))" -eq 0 ]; then
        CPU=$(ps aux | grep "[f]orward-suricata-eve.py" | awk '{print $3}' | head -1)
        logger -t "$LOG_TAG" "Forwarder running (PID: $PYTHON_PID, CPU: ${CPU}%)"
    fi
fi
WATCHDOG_EOF

ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" 'chmod +x /usr/local/bin/suricata-forwarder-watchdog.sh'

print_info "Installing watchdog cron job..."
CRON_LINE="* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh"
ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" "(crontab -l 2>/dev/null | grep -v watchdog; echo '${CRON_LINE}') | crontab -"

print_info "Installing rc.d service for boot auto-start..."
ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" 'cat > /usr/local/etc/rc.d/suricata_forwarder' << 'RCD_EOF'
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

ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" 'chmod 755 /usr/local/etc/rc.d/suricata_forwarder && sysrc suricata_forwarder_enable=YES'
print_info "✓ rc.d service installed and enabled for boot auto-start"

print_info "Starting forwarder via rc.d service..."
ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" 'pkill -f forward-suricata-eve 2>/dev/null; sleep 1; /usr/local/etc/rc.d/suricata_forwarder start'
sleep 3

# Verify
FORWARDER_PID=$(ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" "cat /var/run/suricata_forwarder.pid 2>/dev/null || ps aux | grep '[f]orward-suricata-eve' | awk '{print \$2}' | head -1" || echo "")
if [ -z "$FORWARDER_PID" ]; then
    print_error "Forwarder failed to start"
    print_info "Check logs: ssh ${PFSENSE_USER:-root}@${PFSENSE_HOST} 'tail -50 /var/log/system.log | grep suricata'"
    exit 1
fi

print_info "✓ Forwarder started (PID: $FORWARDER_PID)"

# Show monitored interfaces
print_info "Monitored interfaces:"
ssh "${PFSENSE_USER:-root}@${PFSENSE_HOST}" "lsof -p ${FORWARDER_PID} | grep eve.json | awk '{print \$9}'" | while read -r iface; do
    echo "  • $iface"
done

#
# Step 3: Configure Grafana Datasources
#
print_header "Step 3: Configure Grafana Datasources"

GRAFANA_URL="http://${SIEM_HOST}:${GRAFANA_PORT:-3000}"
GRAFANA_AUTH="${GRAFANA_ADMIN_USER:-admin}:${GRAFANA_ADMIN_PASS:-admin}"

# Check if Grafana is accessible
print_info "Checking Grafana connectivity..."
if ! curl -s -f -u "$GRAFANA_AUTH" "${GRAFANA_URL}/api/health" > /dev/null 2>&1; then
    print_warning "Cannot connect to Grafana — skipping datasource setup"
    print_info "You can manually create datasources in Grafana after it's running"
else
    # Install OpenSearch datasource plugin if not already installed
    print_info "Checking OpenSearch datasource plugin..."
    if ! curl -s -u "$GRAFANA_AUTH" "${GRAFANA_URL}/api/plugins/grafana-opensearch-datasource" | grep -q '"id"' 2>/dev/null; then
        print_info "Installing grafana-opensearch-datasource plugin..."
        if command -v grafana-cli > /dev/null 2>&1; then
            sudo grafana-cli plugins install grafana-opensearch-datasource 2>/dev/null || true
            sudo systemctl restart grafana-server 2>/dev/null || true
            sleep 5
        elif ssh -o BatchMode=yes "chiefgyk3d@${SIEM_HOST}" 'command -v grafana-cli' > /dev/null 2>&1; then
            ssh "chiefgyk3d@${SIEM_HOST}" 'sudo grafana-cli plugins install grafana-opensearch-datasource 2>/dev/null && sudo systemctl restart grafana-server' 2>/dev/null || true
            sleep 5
        else
            print_warning "Could not install grafana-opensearch-datasource plugin automatically"
            print_info "Install manually: grafana-cli plugins install grafana-opensearch-datasource"
        fi
    fi

    # Create OpenSearch-pfBlockerNG datasource if it doesn't exist
    print_info "Checking for OpenSearch-pfBlockerNG datasource..."
    EXISTING_DS=$(curl -s -u "$GRAFANA_AUTH" "${GRAFANA_URL}/api/datasources/name/OpenSearch-pfBlockerNG" 2>/dev/null)
    
    if echo "$EXISTING_DS" | grep -q '"id"' 2>/dev/null; then
        print_info "✓ OpenSearch-pfBlockerNG datasource already exists"
    else
        print_info "Creating OpenSearch-pfBlockerNG datasource..."
        DS_RESPONSE=$(curl -s -u "$GRAFANA_AUTH" -X POST "${GRAFANA_URL}/api/datasources" \
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
            print_info "✓ OpenSearch-pfBlockerNG datasource created"
        else
            print_warning "Could not create datasource automatically"
            print_info "Create manually in Grafana: Configuration → Data Sources → Add OpenSearch"
            echo "  URL: http://localhost:9200"
            echo "  Index: pfblockerng-*"
            echo "  Time field: @timestamp"
        fi
    fi
fi

#
# Step 4: Verify Installation
#
print_header "Step 4: Verify Installation"

print_info "Waiting 10 seconds for events to flow..."
sleep 10

EVENT_COUNT=$(curl -s "http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}/${INDEX_PREFIX:-suricata}-*/_count" | jq -r '.count // 0')

if [ "$EVENT_COUNT" -gt 0 ]; then
    print_info "✓ Suricata data is flowing! Event count: $EVENT_COUNT"
else
    print_warning "⚠ No Suricata events found yet. This is normal if Suricata is quiet."
    print_info "Check status with: curl http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}/${INDEX_PREFIX:-suricata}-*/_count"
fi

# Check pfBlockerNG data (via Telegraf → OpenSearch)
PFBLOCK_COUNT=$(curl -s "http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}/pfblockerng-*/_count" 2>/dev/null | jq -r '.count // 0')

if [ "$PFBLOCK_COUNT" -gt 0 ]; then
    print_info "✓ pfBlockerNG data is flowing! Event count: $PFBLOCK_COUNT"
elif [ "$PFBLOCK_COUNT" = "0" ]; then
    print_warning "⚠ No pfBlockerNG events yet. Requires Telegraf with opensearch output configured on pfSense."
    print_info "See docs/TELEGRAF_PFBLOCKER_SETUP.md for Telegraf configuration."
fi

#
# Summary
#
print_header "Setup Complete!"

echo "Configuration:"
echo "  • OpenSearch configured with auto-create enabled (suricata-*, pfblockerng-*)"
echo "  • Forwarder deployed to pfSense (PID: $FORWARDER_PID)"
echo "  • Watchdog installed and running"
echo ""
echo "Next Steps:"
echo "  1. Import dashboards in Grafana:"
echo "     • URL: http://${SIEM_HOST}:${GRAFANA_PORT:-3000}"
echo "     • Login: ${GRAFANA_ADMIN_USER:-admin} / ${GRAFANA_ADMIN_PASS:-admin}"
echo "     • Dashboard: dashboards/pfsense_pfblockerng_system.json (mixed InfluxDB + OpenSearch)"
echo "     • Dashboard: dashboards/Suricata IDS_IPS Dashboard.json (OpenSearch)"
echo "     • Dashboard: dashboards/Suricata_Per_Interface.json (OpenSearch)"
echo ""
echo "  2. For pfBlockerNG monitoring (optional):"
echo "     • Install Telegraf package on pfSense via Package Manager"
echo "     • Configure Telegraf with [[outputs.opensearch]] plugin"
echo "     • Add tail inputs for pfBlockerNG logs"
echo "     • See docs/TELEGRAF_PFBLOCKER_SETUP.md for details"
echo ""
echo "  3. Verify data flow:"
echo "     curl http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}/${INDEX_PREFIX:-suricata}-*/_count"
echo "     curl http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}/pfblockerng-*/_count"
echo ""
echo "  4. Check forwarder status:"
echo "     ssh ${PFSENSE_USER:-root}@${PFSENSE_HOST} 'ps aux | grep forward-suricata'"
echo ""
echo "Troubleshooting:"
echo "  • Forwarder logs: ssh ${PFSENSE_USER:-root}@${PFSENSE_HOST} 'tail -f /var/log/system.log | grep suricata'"
echo "  • OpenSearch indices: curl http://${SIEM_HOST}:${OPENSEARCH_PORT:-9200}/_cat/indices/${INDEX_PREFIX:-suricata}-*?v"
echo "  • Configuration: cat $CONFIG_FILE"
echo ""
print_info "Documentation: docs/"
echo ""
