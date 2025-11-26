#!/bin/sh
# Suricata Post-Restart Hook
# Automatically restarts the forwarder after Suricata restarts
# Place in: /usr/local/pkg/suricata/post-install/restart_forwarder.sh

LOG_FILE="/var/log/suricata-forwarder-restart.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

log_message "INFO: Suricata restart detected, waiting for Suricata to stabilize..."

# Wait for Suricata to fully start
sleep 5

# Check if any Suricata processes are running
if ! pgrep -q suricata; then
    log_message "WARNING: No Suricata processes found, forwarder restart may be premature"
fi

# Kill the forwarder
log_message "INFO: Stopping existing forwarder..."
killall python3.11 2>/dev/null

# Wait a moment
sleep 2

# Start the forwarder
log_message "INFO: Starting forwarder..."
/usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py >> "$LOG_FILE" 2>&1 &

# Verify it started
sleep 2
if pgrep -f "forward-suricata-eve.py" > /dev/null; then
    NEW_PID=$(pgrep -f "forward-suricata-eve.py")
    log_message "SUCCESS: Forwarder restarted successfully (PID: $NEW_PID)"
else
    log_message "ERROR: Failed to restart forwarder"
fi

# Rotate log if too large (keep last 1MB)
if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE") -gt 1048576 ]; then
    tail -n 1000 "$LOG_FILE" > "${LOG_FILE}.tmp"
    mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi
