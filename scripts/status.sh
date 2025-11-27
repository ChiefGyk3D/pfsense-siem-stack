#!/bin/bash
# Comprehensive Status Check for pfSense Suricata Dashboard
# Checks SIEM stack, forwarder, and data flow

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../config.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load config if it exists
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo -e "${YELLOW}Warning: config.env not found, using defaults${NC}"
    SIEM_HOST="${SIEM_HOST:-localhost}"
    PFSENSE_HOST="${PFSENSE_HOST:-}"
    OPENSEARCH_PORT="${OPENSEARCH_PORT:-9200}"
    LOGSTASH_UDP_PORT="${LOGSTASH_UDP_PORT:-5140}"
    INDEX_PREFIX="${INDEX_PREFIX:-suricata}"
    PFSENSE_USER="${PFSENSE_USER:-root}"
fi

ERRORS=0

print_status() {
    if [ "$1" -eq 0 ]; then
        echo -e "${GREEN}✓${NC} $2"
    else
        echo -e "${RED}✗${NC} $2"
        ((ERRORS++))
    fi
}

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

#
# SIEM Server Checks
#
print_header "SIEM Server Status ($SIEM_HOST)"

# OpenSearch
echo -n "Checking OpenSearch... "
if curl -s -f "http://${SIEM_HOST}:${OPENSEARCH_PORT}" > /dev/null 2>&1; then
    print_status 0 "OpenSearch is running"
    
    # Check cluster health
    HEALTH=$(curl -s "http://${SIEM_HOST}:${OPENSEARCH_PORT}/_cluster/health" | jq -r '.status // "unknown"')
    echo "  Cluster status: $HEALTH"
    
    # Check auto-create setting
    AUTO_CREATE=$(curl -s "http://${SIEM_HOST}:${OPENSEARCH_PORT}/_cluster/settings?filter_path=persistent.action.auto_create_index" | jq -r '.persistent.action.auto_create_index // "not set"')
    if [[ "$AUTO_CREATE" == *"${INDEX_PREFIX}"* ]]; then
        echo -e "  ${GREEN}✓${NC} Auto-create enabled for ${INDEX_PREFIX}-*"
    else
        echo -e "  ${RED}✗${NC} Auto-create NOT enabled (will cause midnight UTC failures!)"
        ((ERRORS++))
    fi
else
    print_status 1 "OpenSearch is NOT responding"
fi

# Logstash
echo -n "Checking Logstash port... "
if nc -z -w2 "$SIEM_HOST" "$LOGSTASH_UDP_PORT" 2>/dev/null; then
    print_status 0 "Logstash UDP port $LOGSTASH_UDP_PORT is listening"
else
    print_status 1 "Logstash UDP port $LOGSTASH_UDP_PORT is NOT accessible"
fi

# Check indices
echo ""
echo "Indices:"
curl -s "http://${SIEM_HOST}:${OPENSEARCH_PORT}/_cat/indices/${INDEX_PREFIX}-*?v&s=index&h=index,docs.count,store.size" 2>/dev/null || echo "  Could not retrieve indices"

# Check event count
EVENT_COUNT=$(curl -s "http://${SIEM_HOST}:${OPENSEARCH_PORT}/${INDEX_PREFIX}-*/_count" 2>/dev/null | jq -r '.count // 0')
echo ""
echo "Total events: $EVENT_COUNT"

if [ "$EVENT_COUNT" -gt 0 ]; then
    # Check latest event
    LATEST=$(curl -s "http://${SIEM_HOST}:${OPENSEARCH_PORT}/${INDEX_PREFIX}-*/_search" \
        -H 'Content-Type: application/json' \
        -d '{"size":1,"sort":[{"@timestamp":"desc"}],"_source":["@timestamp"]}' 2>/dev/null | \
        jq -r '.hits.hits[0]._source["@timestamp"] // "unknown"')
    echo "Latest event: $LATEST"
    
    # Check if recent (within last hour)
    if [ "$LATEST" != "unknown" ]; then
        LATEST_TS=$(date -d "$LATEST" +%s 2>/dev/null || echo "0")
        NOW_TS=$(date +%s)
        AGE=$((NOW_TS - LATEST_TS))
        
        if [ "$AGE" -lt 3600 ]; then
            echo -e "  ${GREEN}✓${NC} Data is recent (${AGE}s ago)"
        elif [ "$AGE" -lt 86400 ]; then
            echo -e "  ${YELLOW}⚠${NC} Data is $((AGE / 3600)) hours old"
            ((ERRORS++))
        else
            echo -e "  ${RED}✗${NC} Data is $((AGE / 86400)) days old!"
            ((ERRORS++))
        fi
    fi
fi

# Check pfBlocker data (if InfluxDB available)
if command -v influx > /dev/null 2>&1; then
    echo ""
    echo -e "${CYAN}=== pfBlocker Data (InfluxDB) ===${NC}"
    
    # Try to check pfBlocker data
    echo -n "pfBlocker IP blocks (last hour)... "
    PFBLOCKER_COUNT=$(influx -host "${SIEM_HOST}" -database pfsense -execute "SELECT COUNT(*) FROM tail_ip_block_log WHERE time > now() - 1h" -format csv 2>/dev/null | tail -1 | cut -d',' -f2)
    
    if [ -n "$PFBLOCKER_COUNT" ] && [ "$PFBLOCKER_COUNT" != "0" ]; then
        echo -e "${GREEN}✓${NC} ${PFBLOCKER_COUNT} events"
    elif [ "$PFBLOCKER_COUNT" = "0" ]; then
        echo -e "${YELLOW}⚠${NC} No events (might be no blocked traffic)"
    else
        echo -e "${YELLOW}⚠${NC} Could not check (InfluxDB might not be configured)"
    fi
    
    echo -n "pfBlocker DNSBL (last hour)... "
    DNSBL_COUNT=$(influx -host "${SIEM_HOST}" -database pfsense -execute "SELECT COUNT(*) FROM tail_dnsbl_log WHERE time > now() - 1h" -format csv 2>/dev/null | tail -1 | cut -d',' -f2)
    
    if [ -n "$DNSBL_COUNT" ] && [ "$DNSBL_COUNT" != "0" ]; then
        echo -e "${GREEN}✓${NC} ${DNSBL_COUNT} events"
    elif [ "$DNSBL_COUNT" = "0" ]; then
        echo -e "${YELLOW}⚠${NC} No events (might be no blocked DNS queries)"
    else
        echo -e "${YELLOW}⚠${NC} Could not check"
    fi
fi

#
# pfSense Forwarder Checks
#
if [ -n "$PFSENSE_HOST" ]; then
    print_header "pfSense Forwarder Status ($PFSENSE_HOST)"
    
    # SSH connectivity
    echo -n "Testing SSH... "
    if ssh -o ConnectTimeout=5 -o BatchMode=yes "${PFSENSE_USER}@${PFSENSE_HOST}" 'echo OK' > /dev/null 2>&1; then
        print_status 0 "SSH connection successful"
        
        # Check forwarder process
        echo -n "Checking forwarder process... "
        FORWARDER_RUNNING=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "ps aux | grep -c '[f]orward-suricata-eve.py'" 2>/dev/null || echo "0")
        
        if [ "$FORWARDER_RUNNING" -eq 1 ]; then
            print_status 0 "Forwarder is running"
            
            # Get PID and details
            FORWARDER_PID=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "ps aux | grep '[f]orward-suricata-eve.py' | awk '{print \$2}'" 2>/dev/null)
            echo "  PID: $FORWARDER_PID"
            
            # Check monitored interfaces
            echo "  Monitored interfaces:"
            ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "lsof -p ${FORWARDER_PID} 2>/dev/null | grep eve.json | awk '{print \$9}'" | while read -r iface; do
                echo "    • $iface"
            done
            
        elif [ "$FORWARDER_RUNNING" -gt 1 ]; then
            print_status 1 "Multiple forwarders running! ($FORWARDER_RUNNING instances)"
        else
            print_status 1 "Forwarder is NOT running"
        fi
        
        # Check watchdog cron
        echo -n "Checking watchdog cron... "
        WATCHDOG_CRON=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "crontab -l 2>/dev/null | grep -c watchdog" || echo "0")
        if [ "$WATCHDOG_CRON" -gt 0 ]; then
            print_status 0 "Watchdog cron is installed"
        else
            print_status 1 "Watchdog cron is NOT installed"
        fi
        
        # Check Suricata logs
        echo -n "Checking Suricata... "
        EVE_LOGS=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "find /var/log/suricata -name 'eve.json' 2>/dev/null | wc -l" || echo "0")
        if [ "$EVE_LOGS" -gt 0 ]; then
            print_status 0 "Found $EVE_LOGS Suricata interface(s)"
            
            # Check if logs are recent
            LATEST_SURICATA=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "find /var/log/suricata -name 'eve.json' -mmin -5 | wc -l" || echo "0")
            if [ "$LATEST_SURICATA" -gt 0 ]; then
                echo -e "  ${GREEN}✓${NC} Suricata is actively logging"
            else
                echo -e "  ${YELLOW}⚠${NC} Suricata logs not updated in last 5 minutes"
            fi
        else
            print_status 1 "No Suricata eve.json files found"
        fi
        
        # Check filter.log health (for pfBlocker)
        echo ""
        echo -e "${CYAN}=== pfSense Filterlog Health ===${NC}"
        
        # Check filter.log age
        echo -n "Filter.log freshness... "
        FILTER_LOG_STAT=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "stat -f %m /var/log/filter.log 2>/dev/null" || echo "")
        if [ -n "$FILTER_LOG_STAT" ]; then
            NOW=$(date +%s)
            AGE=$((NOW - FILTER_LOG_STAT))
            if [ $AGE -gt 600 ]; then
                print_status 1 "Stale (${AGE}s old, threshold 600s)"
                echo -e "  ${YELLOW}→ Fix: ssh root@${PFSENSE_HOST} 'php -r \"require_once(\\\"/etc/inc/filter.inc\\\"); filter_configure(); system_syslogd_start();\"'${NC}"
            else
                print_status 0 "Current (${AGE}s old)"
            fi
        else
            print_status 1 "Could not check"
        fi
        
        # Check filterlog has file open
        echo -n "Filterlog file handle... "
        HAS_HANDLE=$(ssh "${PFSENSE_USER}@${PFSENSE_HOST}" "lsof -p \$(pgrep filterlog 2>/dev/null) 2>/dev/null | grep -c filter.log" 2>/dev/null || echo "0")
        if [ "$HAS_HANDLE" -gt 0 ]; then
            print_status 0 "Open"
        else
            print_status 1 "No file handle - filterlog needs restart"
        fi
        
    else
        print_status 1 "Cannot connect via SSH"
        echo "  Please ensure SSH is enabled and keys are configured"
    fi
else
    echo -e "${YELLOW}Skipping pfSense checks (PFSENSE_HOST not configured)${NC}"
fi

#
# Summary
#
print_header "Summary"

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo "The Suricata dashboard should be working correctly."
    exit 0
else
    echo -e "${RED}✗ Found $ERRORS issue(s)${NC}"
    echo ""
    echo "Common fixes:"
    echo "  • No data / old data: Check forwarder is running on pfSense"
    echo "  • Auto-create disabled: Run ./setup.sh to configure OpenSearch"
    echo "  • Forwarder not running: Check SSH connectivity and watchdog"
    echo "  • Multiple forwarders: Kill extras: pkill -f forward-suricata-eve"
    echo ""
    echo "For detailed troubleshooting, see: docs/TROUBLESHOOTING.md"
    exit 1
fi
