#!/bin/sh
#
# Suricata Forwarder Watchdog — restarts the forwarder's rc.d service if the
# process is gone. setup.sh generates and installs an identical copy at
# /usr/local/bin/suricata-forwarder-watchdog.sh and adds it to root's crontab:
#     * * * * * /usr/local/bin/suricata-forwarder-watchdog.sh
#
# Manual install (if you are not using setup.sh):
#     scp scripts/suricata-forwarder-watchdog.sh admin@<PFSENSE_IP>:/usr/local/bin/
#     ssh admin@<PFSENSE_IP> 'chmod +x /usr/local/bin/suricata-forwarder-watchdog.sh;
#         (crontab -l 2>/dev/null; echo "* * * * * /usr/local/bin/suricata-forwarder-watchdog.sh") | crontab -'
#
# It never calls killall or a hardcoded Python path: the rc.d script carries the
# interpreter detected at deploy time. If the start fails, re-run setup.sh.
#
RCD="/usr/local/etc/rc.d/suricata_forwarder.sh"
TAG="suricata-watchdog"

if ! pgrep -f "forward-suricata-eve.py" > /dev/null 2>&1; then
    logger -t "$TAG" "Forwarder not running — starting via rc.d"
    rm -f /var/run/suricata_forwarder.pid /var/run/suricata_forwarder.child.pid
    "$RCD" start > /dev/null 2>&1
    sleep 2
    PID=$(pgrep -f "forward-suricata-eve.py" | head -1)
    if [ -n "$PID" ]; then
        logger -t "$TAG" "Started (PID: $PID)"
    else
        logger -t "$TAG" "FAILED to start — run setup.sh again (interpreter may have changed after a pfSense upgrade)"
    fi
fi
