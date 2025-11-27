#!/bin/sh
# Suricata EVE JSON Forwarder to Logstash
# This script forwards Suricata events to a remote Logstash server via UDP
# Version: 2.0 - More reliable with buffering and error handling

LOGSTASH_SERVER="192.168.210.10"
LOGSTASH_PORT="5140"
BUFFER_SIZE=65536  # Match Logstash UDP buffer size

# Find the Suricata EVE JSON file
EVE_LOG=$(find /var/log/suricata -name 'eve.json' -type f 2>/dev/null | head -1)

if [ -z "$EVE_LOG" ]; then
    logger -t suricata-forwarder "ERROR: No EVE JSON file found in /var/log/suricata/"
    exit 1
fi

logger -t suricata-forwarder "Starting: Forwarding from ${EVE_LOG} to ${LOGSTASH_SERVER}:${LOGSTASH_PORT}"

# Simple approach: tail and send each line via nc
# The old approach with while read was causing issues
tail -F -n 0 "$EVE_LOG" 2>/dev/null | \
    while read line; do
        echo "$line" | nc -u -w1 "$LOGSTASH_SERVER" "$LOGSTASH_PORT"
    done

# If we exit the loop, something went wrong
logger -t suricata-forwarder "ERROR: Forwarder stopped unexpectedly"
exit 1
