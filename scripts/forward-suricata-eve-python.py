#!/usr/local/bin/python3.11
"""
Reliable Suricata EVE JSON forwarder for pfSense with GeoIP enrichment
Forwards Suricata EVE JSON events via UDP to Logstash
Adds GeoIP information using MaxMind GeoLite2 databases
"""
import socket
import sys
import syslog
import time
import glob
import json
import os
import threading

# Configuration - can be overridden via environment variables or during deployment
GRAYLOG_SERVER = os.getenv("SIEM_HOST", "192.168.210.10")
GRAYLOG_PORT = int(os.getenv("LOGSTASH_UDP_PORT", "5140"))
DEBUG_ENABLED = os.getenv("DEBUG_ENABLED", "False").lower() in ("true", "1", "yes")
DEBUG_LOG = os.getenv("DEBUG_LOG", "/var/log/suricata_forwarder_debug.log")

# Common pfSense GeoIP database locations (in priority order)
GEOIP_DB_PATHS = [
    # ntopng location (City database with coordinates - required for geomap)
    # NOTE: Requires ntopng package to be installed on pfSense
    "/usr/local/share/ntopng/GeoLite2-City.mmdb",
    # Suricata locations (check next since we're forwarding Suricata logs)
    "/usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb",
    "/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb",
    # pfBlockerNG / standard GeoIP locations
    "/usr/local/share/GeoIP/GeoLite2-City.mmdb",
    "/usr/local/share/GeoIP/GeoLite2-Country.mmdb",
    # Unbound location
    "/var/unbound/usr/local/share/GeoIP/GeoLite2-City.mmdb",
    "/var/unbound/usr/local/share/GeoIP/GeoLite2-Country.mmdb",
    # Other common locations
    "/var/db/GeoIP/GeoLite2-City.mmdb",
    "/usr/share/GeoIP/GeoLite2-City.mmdb",
]

# Initialize GeoIP reader
geoip_reader = None
debug_file = None

def debug_log(message):
    """Write debug message to log file (only if DEBUG_ENABLED is True)"""
    if not DEBUG_ENABLED:
        return
    try:
        with open(DEBUG_LOG, 'a') as f:
            timestamp = time.strftime('%Y-%m-%d %H:%M:%S')
            f.write(f"[{timestamp}] {message}\n")
            f.flush()
    except:
        pass

try:
    import geoip2.database
    import geoip2.errors
    
    debug_log("=== GeoIP Forwarder Starting ===")
    
    for db_path in GEOIP_DB_PATHS:
        debug_log(f"Checking for GeoIP database at: {db_path}")
        if os.path.exists(db_path):
            try:
                geoip_reader = geoip2.database.Reader(db_path)
                msg = f"suricata-forwarder: Loaded GeoIP database from {db_path}"
                syslog.syslog(syslog.LOG_INFO, msg)
                debug_log(f"SUCCESS: {msg}")
                break
            except Exception as e:
                msg = f"suricata-forwarder: Failed to load {db_path}: {e}"
                syslog.syslog(syslog.LOG_WARNING, msg)
                debug_log(f"ERROR: {msg}")
    
    if not geoip_reader:
        msg = "suricata-forwarder: No GeoIP database found, running without GeoIP enrichment"
        syslog.syslog(syslog.LOG_WARNING, msg)
        debug_log(f"WARNING: {msg}")
    else:
        debug_log(f"GeoIP reader initialized successfully")
except ImportError as e:
    msg = f"suricata-forwarder: geoip2 module not installed: {e}"
    syslog.syslog(syslog.LOG_WARNING, msg)
    debug_log(f"IMPORT ERROR: {msg}")

def enrich_geoip(event):
    """Add GeoIP information to src_ip and dest_ip"""
    if not geoip_reader:
        debug_log("GeoIP enrichment skipped: no reader available")
        return event
    
    enriched = False
    try:
        # Enrich source IP
        if "src_ip" in event:
            try:
                # Try city method first, fall back to country if that fails
                try:
                    response = geoip_reader.city(event["src_ip"])
                except (AttributeError, TypeError):
                    # Country database doesn't have city() method
                    response = geoip_reader.country(event["src_ip"])
                event["geoip_src"] = {
                    "country_code": response.country.iso_code,
                    "country_name": response.country.name,
                    "continent_code": response.continent.code
                }
                # Add city data if available (City database)
                if hasattr(response, 'city') and response.city.name:
                    event["geoip_src"]["city_name"] = response.city.name
                if hasattr(response, 'location') and response.location.latitude:
                    # Use GeoJSON format [lon, lat] for proper geo_point mapping
                    event["geoip_src"]["location"] = [
                        response.location.longitude,
                        response.location.latitude
                    ]
                if hasattr(response, 'subdivisions') and response.subdivisions.most_specific.name:
                    event["geoip_src"]["region_name"] = response.subdivisions.most_specific.name
                enriched = True
                debug_log(f"Enriched src_ip {event['src_ip']} -> {event['geoip_src'].get('country_code')}")
            except (geoip2.errors.AddressNotFoundError, ValueError, AttributeError) as e:
                debug_log(f"Failed to enrich src_ip {event['src_ip']}: {type(e).__name__}")
                pass  # Private/local IP or lookup failed
        
        # Enrich destination IP
        if "dest_ip" in event:
            try:
                # Try city method first, fall back to country if that fails
                try:
                    response = geoip_reader.city(event["dest_ip"])
                except (AttributeError, TypeError):
                    # Country database doesn't have city() method
                    response = geoip_reader.country(event["dest_ip"])
                event["geoip_dest"] = {
                    "country_code": response.country.iso_code,
                    "country_name": response.country.name,
                    "continent_code": response.continent.code
                }
                # Add city data if available (City database)
                if hasattr(response, 'city') and response.city.name:
                    event["geoip_dest"]["city_name"] = response.city.name
                if hasattr(response, 'location') and response.location.latitude:
                    # Use GeoJSON format [lon, lat] for proper geo_point mapping
                    event["geoip_dest"]["location"] = [
                        response.location.longitude,
                        response.location.latitude
                    ]
                if hasattr(response, 'subdivisions') and response.subdivisions.most_specific.name:
                    event["geoip_dest"]["region_name"] = response.subdivisions.most_specific.name
                enriched = True
                debug_log(f"Enriched dest_ip {event['dest_ip']} -> {event['geoip_dest'].get('country_code')}")
            except (geoip2.errors.AddressNotFoundError, ValueError, AttributeError) as e:
                debug_log(f"Failed to enrich dest_ip {event['dest_ip']}: {type(e).__name__}")
                pass  # Private/local IP or lookup failed
    
    except Exception as e:
        msg = f"suricata-forwarder: GeoIP enrichment error: {e}"
        syslog.syslog(syslog.LOG_WARNING, msg)
        debug_log(f"ERROR: {msg}")
    
    if enriched:
        debug_log(f"Event enriched successfully")
    
    return event

def find_eve_logs():
    """Find ALL Suricata EVE JSON log files"""
    matches = glob.glob("/var/log/suricata/*/eve.json")
    return sorted(matches)  # Return sorted list for consistent order

def tail_log_file(eve_log, sock):
    """Tail a single EVE log file and forward events"""
    interface = eve_log.split('/')[-2]  # Extract interface directory name
    geoip_status = "enabled" if geoip_reader else "disabled"
    msg = f"suricata-forwarder: Thread monitoring {interface} ({eve_log}) - GeoIP: {geoip_status}"
    syslog.syslog(syslog.LOG_INFO, msg)
    debug_log(msg)
    
    event_count = 0
    try:
        with open(eve_log, 'r') as f:
            # Seek to end of file (tail -f behavior)
            f.seek(0, 2)
            debug_log(f"[{interface}] Monitoring, waiting for events...")
            
            while True:
                line = f.readline()
                if line:
                    # Process non-empty lines
                    line = line.strip()
                    if line:
                        try:
                            # Parse JSON
                            event = json.loads(line)
                            
                            # Add GeoIP enrichment if available
                            if geoip_reader:
                                event = enrich_geoip(event)
                            
                            # Convert back to JSON and send
                            enriched_line = json.dumps(event)
                            sock.sendto(enriched_line.encode('utf-8'), (GRAYLOG_SERVER, GRAYLOG_PORT))
                            
                            event_count += 1
                            if event_count % 100 == 0:
                                debug_log(f"[{interface}] Processed {event_count} events")
                        except json.JSONDecodeError as e:
                            # If not valid JSON, send as-is
                            debug_log(f"[{interface}] JSON decode error, sending raw: {str(e)[:50]}")
                            sock.sendto(line.encode('utf-8'), (GRAYLOG_SERVER, GRAYLOG_PORT))
                        except Exception as e:
                            msg = f"suricata-forwarder [{interface}]: Processing error: {e}"
                            syslog.syslog(syslog.LOG_WARNING, msg)
                            debug_log(f"[{interface}] ERROR: {msg}")
                else:
                    # No new data, sleep briefly
                    time.sleep(0.1)
    except Exception as e:
        msg = f"suricata-forwarder [{interface}]: Fatal error in thread: {e}"
        syslog.syslog(syslog.LOG_ERR, msg)
        debug_log(f"[{interface}] FATAL: {msg}")

def main():
    eve_logs = find_eve_logs()
    if not eve_logs:
        syslog.syslog(syslog.LOG_ERR, "suricata-forwarder: No EVE JSON files found")
        sys.exit(1)
    
    geoip_status = "enabled" if geoip_reader else "disabled"
    msg = f"suricata-forwarder: Starting forwarder for {len(eve_logs)} interface(s) to {GRAYLOG_SERVER}:{GRAYLOG_PORT} (GeoIP: {geoip_status})"
    syslog.syslog(syslog.LOG_INFO, msg)
    debug_log(msg)
    debug_log(f"Debug logging to: {DEBUG_LOG}")
    for log in eve_logs:
        debug_log(f"  - {log}")
    
    # Create UDP socket (shared by all threads)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    
    # Start a thread for each log file
    threads = []
    for eve_log in eve_logs:
        thread = threading.Thread(target=tail_log_file, args=(eve_log, sock), daemon=True)
        thread.start()
        threads.append(thread)
        debug_log(f"Started thread for {eve_log}")
    
    # Keep main thread alive
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        syslog.syslog(syslog.LOG_INFO, "suricata-forwarder: Interrupted, stopping")
        raise

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        syslog.syslog(syslog.LOG_INFO, "suricata-forwarder: Stopped")
        sys.exit(0)
    except Exception as e:
        syslog.syslog(syslog.LOG_ERR, f"suricata-forwarder: Fatal error: {e}")
        sys.exit(1)
