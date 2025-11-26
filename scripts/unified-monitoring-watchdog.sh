#!/bin/sh
# Unified Monitoring Watchdog for pfSense
# Monitors both Telegraf (metrics) and Suricata forwarder (alerts)
# Restarts services automatically if they crash or hang

LOG_FILE="/var/log/unified-watchdog.log"
PID_TRACKER="/var/run/suricata-pids.txt"
MAX_LOG_SIZE=1048576  # 1MB

# Rotate log if too large
if [ -f "$LOG_FILE" ] && [ $(stat -f%z "$LOG_FILE") -gt $MAX_LOG_SIZE ]; then
    mv "$LOG_FILE" "$LOG_FILE.old"
fi

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Detect if Suricata was restarted by checking PIDs
detect_suricata_restart() {
    CURRENT_PIDS=$(pgrep suricata | sort | tr '\n' ' ')
    
    if [ -f "$PID_TRACKER" ]; then
        PREVIOUS_PIDS=$(cat "$PID_TRACKER")
        
        if [ "$CURRENT_PIDS" != "$PREVIOUS_PIDS" ]; then
            log_message "DETECTED: Suricata PIDs changed (was: $PREVIOUS_PIDS, now: $CURRENT_PIDS)"
            log_message "INFO: Suricata was restarted, triggering forwarder restart..."
            
            # Force restart forwarder
            killall python3.11 >> "$LOG_FILE" 2>&1
            sleep 2
            /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py >> "$LOG_FILE" 2>&1 &
            
            if pgrep -f "forward-suricata-eve.py" > /dev/null; then
                NEW_PID=$(pgrep -f "forward-suricata-eve.py")
                log_message "SUCCESS: Forwarder auto-restarted after Suricata restart (PID: $NEW_PID)"
            fi
        fi
    fi
    
    # Update tracker
    echo "$CURRENT_PIDS" > "$PID_TRACKER"
}

# Check and restart Telegraf
check_telegraf() {
    if ! pgrep -f "/usr/local/bin/telegraf" > /dev/null; then
        log_message "ERROR: Telegraf not running, restarting..."
        /usr/local/etc/rc.d/telegraf.sh start >> "$LOG_FILE" 2>&1
        sleep 3
        if pgrep -f "/usr/local/bin/telegraf" > /dev/null; then
            log_message "SUCCESS: Telegraf restarted successfully"
        else
            log_message "CRITICAL: Failed to restart Telegraf"
        fi
    fi
}

# Check and restart Suricata forwarder
check_forwarder() {
    if ! pgrep -f "forward-suricata-eve.py" > /dev/null; then
        log_message "ERROR: Suricata forwarder not running, restarting..."
        /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py >> "$LOG_FILE" 2>&1 &
        sleep 2
        if pgrep -f "forward-suricata-eve.py" > /dev/null; then
            log_message "SUCCESS: Suricata forwarder restarted successfully"
        else
            log_message "CRITICAL: Failed to restart Suricata forwarder"
        fi
    fi
}

# Check for stuck forwarder (no recent log updates)
check_forwarder_activity() {
    # Only check during business hours (9 AM - 11 PM)
    HOUR=$(date +%H)
    if [ "$HOUR" -ge 9 ] && [ "$HOUR" -lt 23 ]; then
        # Check if any eve.json files were modified in the last 15 minutes
        RECENT_FILES=$(find /var/log/suricata/*/eve.json -mmin -15 2>/dev/null | wc -l)
        if [ "$RECENT_FILES" -eq 0 ]; then
            log_message "WARNING: No recent Suricata log activity, forwarder may be stuck, restarting..."
            killall python3.11 >> "$LOG_FILE" 2>&1
            sleep 2
            /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py >> "$LOG_FILE" 2>&1 &
            log_message "INFO: Suricata forwarder restarted due to inactivity"
        fi
    fi
}

# Main execution
log_message "INFO: Starting unified monitoring check"

# Check for Suricata restarts first (most important)
detect_suricata_restart

# Check both services
check_telegraf
check_forwarder

# Every 15 minutes, check for stuck forwarder (run from cron with different schedule)
if [ "$1" = "activity" ]; then
    check_forwarder_activity
fi

log_message "INFO: Monitoring check complete"
