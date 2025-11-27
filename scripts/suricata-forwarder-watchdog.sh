#!/bin/sh
#
# Suricata Forwarder Watchdog - Ensures forwarder stays running
# Place in: /usr/local/bin/suricata-forwarder-watchdog.sh
# chmod +x /usr/local/bin/suricata-forwarder-watchdog.sh
# Add to cron: * * * * * /usr/local/bin/suricata-forwarder-watchdog.sh
#

FORWARDER_SCRIPT="/usr/local/bin/forward-suricata-eve.py"
PYTHON="/usr/local/bin/python3.11"
PIDFILE="/var/run/suricata_eve_forwarder.pid"
UPTIME_FILE="/var/run/suricata_last_start"
FORWARDER_UPTIME_FILE="/var/run/suricata_forwarder_last_start"

# Check if Suricata is running
suricata_running=0
if pgrep -f "suricata --netmap" > /dev/null 2>&1; then
    suricata_running=1
fi

# Get current Suricata uptime (approximate via PID age)
if [ $suricata_running -eq 1 ]; then
    current_suricata_start=$(pgrep -f "suricata --netmap" | head -1 | xargs ps -o lstart= -p 2>/dev/null | xargs -I {} date -j -f "%a %b %d %T %Y" "{}" "+%s" 2>/dev/null)
    if [ -z "$current_suricata_start" ]; then
        current_suricata_start=$(date +%s)
    fi
else
    # Suricata not running, no need to check forwarder
    exit 0
fi

# Check if forwarder is running and count processes
forwarder_running=0
forwarder_count=$(pgrep -f "$FORWARDER_SCRIPT" | wc -l | tr -d ' ')

if [ "$forwarder_count" -gt 0 ]; then
    forwarder_running=1
    forwarder_start=$(pgrep -f "$FORWARDER_SCRIPT" | head -1 | xargs ps -o lstart= -p 2>/dev/null | xargs -I {} date -j -f "%a %b %d %T %Y" "{}" "+%s" 2>/dev/null)
    if [ -z "$forwarder_start" ]; then
        forwarder_start=$(date +%s)
    fi
    
    # Check for multiple forwarder processes (should only be 3-4: 1 main + threads/children)
    if [ "$forwarder_count" -gt 5 ]; then
        logger -p daemon.warning -i -t SuricataForwarderWatchdog "WARNING: Too many forwarder processes ($forwarder_count), will restart"
        should_restart=1
    fi
fi

# Read last known Suricata start time
if [ -f "$UPTIME_FILE" ]; then
    last_suricata_start=$(cat "$UPTIME_FILE")
else
    last_suricata_start=0
fi

# Update last known Suricata start time
echo "$current_suricata_start" > "$UPTIME_FILE"

# Detect if Suricata restarted (start time changed)
suricata_restarted=0
if [ "$last_suricata_start" != "0" ] && [ "$current_suricata_start" != "$last_suricata_start" ]; then
    suricata_restarted=1
    logger -p daemon.info -i -t SuricataForwarderWatchdog "Detected Suricata restart, will restart forwarder"
fi

# Restart forwarder if:
# 1. Suricata just restarted
# 2. Forwarder is not running
# 3. Forwarder is older than Suricata (shouldn't happen but catches edge cases)
should_restart=0

if [ $suricata_restarted -eq 1 ]; then
    should_restart=1
    logger -p daemon.info -i -t SuricataForwarderWatchdog "Reason: Suricata restarted"
elif [ $forwarder_running -eq 0 ]; then
    should_restart=1
    logger -p daemon.warning -i -t SuricataForwarderWatchdog "Reason: Forwarder not running"
elif [ -n "$forwarder_start" ] && [ -n "$current_suricata_start" ] && [ $forwarder_start -lt $current_suricata_start ]; then
    # Forwarder is older than Suricata
    should_restart=1
    logger -p daemon.info -i -t SuricataForwarderWatchdog "Reason: Forwarder older than Suricata"
fi

if [ $should_restart -eq 1 ]; then
    # Aggressively kill ALL forwarder processes and daemon wrappers
    pkill -9 -f "$FORWARDER_SCRIPT" 2>/dev/null
    pkill -9 -f "suricata_eve_forwarder" 2>/dev/null
    sleep 1
    
    # Second pass to ensure everything is dead
    pkill -9 -f "$FORWARDER_SCRIPT" 2>/dev/null
    pkill -9 -f "suricata_eve_forwarder" 2>/dev/null
    
    # Remove stale PID files
    rm -f "$PIDFILE" 2>/dev/null
    rm -f /var/run/suricata_eve_forwarder*.pid 2>/dev/null
    
    sleep 2
    
    # Verify everything is dead
    if pgrep -f "$FORWARDER_SCRIPT" > /dev/null 2>&1; then
        logger -p daemon.err -i -t SuricataForwarderWatchdog "WARNING: Forwarder still running after kill, trying again"
        killall -9 python3.11 2>/dev/null
        sleep 1
    fi
    
    # Start forwarder with nohup (daemon command hangs)
    nohup "$PYTHON" "$FORWARDER_SCRIPT" > /dev/null 2>&1 &
    FORWARDER_PID=$!
    echo $FORWARDER_PID > "$PIDFILE"
    
    sleep 3
    
    # Verify it started and count processes
    forwarder_count=$(pgrep -f "$FORWARDER_SCRIPT" | wc -l | tr -d ' ')
    if [ "$forwarder_count" -gt 0 ]; then
        logger -p daemon.info -i -t SuricataForwarderWatchdog "Forwarder restarted successfully ($forwarder_count processes)"
        echo $(date +%s) > "$FORWARDER_UPTIME_FILE"
    else
        logger -p daemon.err -i -t SuricataForwarderWatchdog "ERROR: Forwarder failed to start"
    fi
fi

exit 0
