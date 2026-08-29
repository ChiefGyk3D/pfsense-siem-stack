#!/bin/bash
# Test multi-interface Suricata forwarder
# Simulates multiple interfaces for testing

# Load config.env if present (repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$(dirname "$SCRIPT_DIR")/config.env"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

PFSENSE_IP="${1:-${PFSENSE_HOST:-}}"
PFSENSE_USER="${PFSENSE_USER:-admin}"

if [ -z "$PFSENSE_IP" ]; then
    echo "ERROR: pfSense host not set."
    echo "Usage: $0 PFSENSE_IP"
    echo "   or: set PFSENSE_HOST in config.env / environment"
    exit 1
fi

FAILURES=0

echo "=== Multi-Interface Forwarder Test ==="
echo ""

echo "[1/3] Checking forwarder process..."
if ! ssh "${PFSENSE_USER}@${PFSENSE_IP}" 'ps aux | grep "[f]orward-suricata-eve.py"'; then
    echo "FAIL: forwarder process not found (or SSH failed)"
    FAILURES=$((FAILURES+1))
fi

echo ""
echo "[2/3] Checking which interfaces are being monitored..."
if ! ssh "${PFSENSE_USER}@${PFSENSE_IP}" 'ls -la /var/log/suricata/'; then
    echo "FAIL: could not list /var/log/suricata/ (or SSH failed)"
    FAILURES=$((FAILURES+1))
fi

echo ""
echo "[3/3] Checking recent syslog entries..."
if ! ssh "${PFSENSE_USER}@${PFSENSE_IP}" 'grep "suricata-forwarder" /var/log/system.log | tail -10'; then
    echo "FAIL: no suricata-forwarder syslog entries found (or SSH failed)"
    FAILURES=$((FAILURES+1))
fi

echo ""
echo "Expected: You should see log entries mentioning 'Found N interface(s) to monitor'"
echo "where N is the number of interfaces running Suricata."

if [ "$FAILURES" -gt 0 ]; then
    echo ""
    echo "RESULT: $FAILURES check(s) failed"
    exit 1
fi
echo ""
echo "RESULT: all checks passed"
exit 0
