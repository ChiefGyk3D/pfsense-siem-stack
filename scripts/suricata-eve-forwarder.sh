#!/bin/sh
#
# suricata-eve-forwarder - Manages the Suricata EVE JSON forwarder
#
# This script ensures the forwarder restarts when Suricata restarts
# and provides management commands for the forwarder service
#

# PROVIDE: suricata_eve_forwarder
# REQUIRE: DAEMON suricata
# KEYWORD: shutdown

. /etc/rc.subr

name="suricata_eve_forwarder"
rcvar="${name}_enable"
desc="Suricata EVE JSON forwarder to Graylog"

load_rc_config $name

# Defaults
: ${suricata_eve_forwarder_enable:="YES"}
: ${suricata_eve_forwarder_script:="/usr/local/bin/forward-suricata-eve.py"}
: ${suricata_eve_forwarder_python:="/usr/local/bin/python3.11"}
: ${suricata_eve_forwarder_pidfile:="/var/run/suricata_eve_forwarder.pid"}

pidfile="${suricata_eve_forwarder_pidfile}"
procname="${suricata_eve_forwarder_python}"

command="/usr/sbin/daemon"
command_args="-P ${pidfile} -r -t ${name} ${suricata_eve_forwarder_python} ${suricata_eve_forwarder_script}"

start_precmd="forwarder_prestart"
stop_postcmd="forwarder_poststop"

forwarder_prestart()
{
    # Kill any existing forwarder processes
    /usr/bin/pkill -9 -f "forward-suricata-eve.py" 2>/dev/null
    sleep 1
}

forwarder_poststop()
{
    # Ensure all forwarder processes are stopped
    /usr/bin/pkill -9 -f "forward-suricata-eve.py" 2>/dev/null
    if [ -f ${pidfile} ]; then
        rm -f ${pidfile}
    fi
}

run_rc_command "$1"
