#!/bin/sh
GRAYLOG_SERVER="192.168.210.10"
GRAYLOG_PORT="5140"

# Find the first EVE JSON file
EVE_LOG=$(find /var/log/suricata -name 'eve.json' -type f 2>/dev/null | head -1)

if [ -z "$EVE_LOG" ]; then
    logger -t suricata-forwarder "ERROR: No EVE JSON file found"
    exit 1
fi

logger -t suricata-forwarder "Starting SOCAT forwarder from ${EVE_LOG} to ${GRAYLOG_SERVER}:${GRAYLOG_PORT}"

# Use tail with stdbuf to disable buffering, then socat to send each line via UDP
tail -F -n 0 "$EVE_LOG" 2>&1 | stdbuf -oL cat | while IFS= read -r line; do
    echo "$line" | socat -t 0 - UDP:"$GRAYLOG_SERVER":"$GRAYLOG_PORT"
done
