#!/bin/sh

# pfSense cleanup - stop and remove the Suricata EVE JSON forwarding script
# Run this on pfSense as root

echo "=== pfSense CLEANUP ==="
echo ""
echo "Checking for Suricata forwarding script..."

# Find the process
PID=$(ps aux | grep 'forward-suricata-eve.sh' | grep -v grep | awk '{print $2}')

if [ -z "$PID" ]; then
    echo "No forwarding script is running."
else
    echo "Found forwarding script running as PID: $PID"
    echo "Killing process..."
    kill $PID
    sleep 2
    # Force kill if still running
    if ps -p $PID > /dev/null 2>&1; then
        kill -9 $PID
    fi
    echo "Process stopped."
fi

# Remove the script
if [ -f "/usr/local/bin/forward-suricata-eve.sh" ]; then
    echo "Removing script..."
    rm -f /usr/local/bin/forward-suricata-eve.sh
    echo "Script removed."
else
    echo "Script not found at /usr/local/bin/forward-suricata-eve.sh"
fi

echo ""
echo "✅ pfSense cleanup complete!"
echo ""
echo "NOTE: The script was forwarding Suricata EVE JSON to Graylog."
echo "Since you're now using Logstash which listens on the same port (5140),"
echo "we need to restart the forwarding with the same command."
echo ""
echo "To restart forwarding to Logstash, run:"
echo ""
echo "  tail -F /var/log/suricata/suricata_ix055721/eve.json | while read -r line; do echo \"\$line\" | nc -u -w1 192.168.210.10 5140; done &"
echo ""
echo "Or reinstall the script pointing to Logstash (same IP:port as before)"
