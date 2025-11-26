#!/bin/sh
#
# Custom Suricata restart wrapper that also manages the EVE forwarder
# Place this in /usr/local/bin/suricata-restart-with-forwarder.sh
# Make it executable: chmod +x /usr/local/bin/suricata-restart-with-forwarder.sh
#

# Function to restart the forwarder
restart_forwarder() {
    /usr/bin/logger -p daemon.info -i -t SuricataForwarder "Restarting Suricata EVE forwarder..."
    
    # Kill existing forwarder processes
    /usr/bin/pkill -9 -f "forward-suricata-eve.py" 2>/dev/null
    sleep 2
    
    # Start the forwarder using daemon to auto-restart on crash
    /usr/sbin/daemon -P /var/run/suricata_eve_forwarder.pid -r -t suricata_eve_forwarder \
        /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py
    
    # Verify it started
    sleep 2
    if /bin/pgrep -f "forward-suricata-eve.py" > /dev/null; then
        /usr/bin/logger -p daemon.info -i -t SuricataForwarder "Forwarder restarted successfully"
    else
        /usr/bin/logger -p daemon.err -i -t SuricataForwarder "ERROR: Forwarder failed to start"
    fi
}

# Main execution
case "$1" in
    start)
        /usr/local/etc/rc.d/suricata.sh start
        sleep 3
        restart_forwarder
        ;;
    stop)
        /usr/bin/pkill -9 -f "forward-suricata-eve.py" 2>/dev/null
        /usr/local/etc/rc.d/suricata.sh stop
        ;;
    restart)
        /usr/bin/logger -p daemon.info -i -t SuricataRestart "Restarting Suricata with forwarder..."
        /usr/bin/pkill -9 -f "forward-suricata-eve.py" 2>/dev/null
        /usr/local/etc/rc.d/suricata.sh restart
        sleep 5
        restart_forwarder
        ;;
    forwarder-only)
        restart_forwarder
        ;;
    status)
        echo "Suricata processes:"
        /bin/pgrep -fl suricata | grep -v grep
        echo ""
        echo "Forwarder processes:"
        /bin/pgrep -fl forward-suricata-eve.py | grep -v grep
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|forwarder-only|status}"
        exit 1
        ;;
esac

exit 0
