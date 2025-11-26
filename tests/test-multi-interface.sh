#!/bin/bash
# Test multi-interface Suricata forwarder
# Simulates multiple interfaces for testing

PFSENSE_IP="${1}"

if [ -z "$PFSENSE_IP" ]; then
    echo "Usage: $0 PFSENSE_IP"
    echo "Example: $0 192.168.1.1"
    exit 1
fi

echo "=== Multi-Interface Forwarder Test ==="
echo ""

echo "[1/3] Checking forwarder process..."
ssh root@"$PFSENSE_IP" 'ps aux | grep "[f]orward-suricata-eve-python.py"'

echo ""
echo "[2/3] Checking which interfaces are being monitored..."
ssh root@"$PFSENSE_IP" 'ls -la /var/log/suricata/'

echo ""
echo "[3/3] Checking recent syslog entries..."
ssh root@"$PFSENSE_IP" 'grep "suricata-forwarder" /var/log/system.log | tail -10'

echo ""
echo "Expected: You should see log entries mentioning 'Found N interface(s) to monitor'"
echo "where N is the number of interfaces running Suricata."
