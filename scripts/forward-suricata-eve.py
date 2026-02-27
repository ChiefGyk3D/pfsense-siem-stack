#!/usr/local/bin/python3.11
"""
Suricata EVE JSON Forwarder for pfSense
========================================
Tails all Suricata EVE JSON log files and forwards events via UDP to Logstash.
Adds GeoIP enrichment using MaxMind GeoLite2 databases (via maxminddb).

Handles log rotation automatically by detecting:
  - File inode changes (file replaced/rotated)
  - File size shrink (file truncated)
  - File disappearance and reappearance

Configuration (via environment variables or baked-in defaults):
  SIEM_HOST          - Logstash server IP (default: 192.168.210.10)
  LOGSTASH_UDP_PORT  - Logstash UDP port (default: 5140)
  DEBUG_ENABLED      - Enable debug logging (default: False)
  DEBUG_LOG          - Debug log path (default: /var/log/suricata_forwarder_debug.log)
"""
import socket
import sys
import syslog
import time
import glob
import json
import os
import threading
import ipaddress

# ── Configuration ─────────────────────────────────────────────────────────────
# These defaults are replaced by setup.sh during deployment.
# They can also be overridden via environment variables at runtime.
SIEM_HOST = os.getenv("SIEM_HOST", "192.168.210.10")
LOGSTASH_PORT = int(os.getenv("LOGSTASH_UDP_PORT", "5140"))
DEBUG_ENABLED = os.getenv("DEBUG_ENABLED", "False").lower() in ("true", "1", "yes")
DEBUG_LOG = os.getenv("DEBUG_LOG", "/var/log/suricata_forwarder_debug.log")

# GeoIP database search paths (checked in order, first match wins)
GEOIP_DB_PATHS = [
    "/usr/local/share/ntopng/GeoLite2-City.mmdb",          # ntopng (best — has coordinates)
    "/usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb",
    "/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb",
    "/usr/local/share/GeoIP/GeoLite2-City.mmdb",           # pfBlockerNG / standard
    "/usr/local/share/GeoIP/GeoLite2-Country.mmdb",
    "/var/unbound/usr/local/share/GeoIP/GeoLite2-City.mmdb",
    "/var/unbound/usr/local/share/GeoIP/GeoLite2-Country.mmdb",
    "/var/db/GeoIP/GeoLite2-City.mmdb",
    "/usr/share/GeoIP/GeoLite2-City.mmdb",
]

# How often to check for log rotation (N idle cycles × 0.1s sleep = ~5 seconds)
ROTATION_CHECK_CYCLES = 50

# ── Globals ───────────────────────────────────────────────────────────────────
geoip_reader = None
geoip_db_path = None


# ── Helpers ───────────────────────────────────────────────────────────────────
def debug_log(message):
    """Write a debug message to the debug log file (only if DEBUG_ENABLED)."""
    if not DEBUG_ENABLED:
        return
    try:
        with open(DEBUG_LOG, "a") as f:
            ts = time.strftime("%Y-%m-%d %H:%M:%S")
            f.write(f"[{ts}] {message}\n")
    except Exception:
        pass


def is_private_ip(ip_str):
    """Return True if the IP address is private, reserved, or invalid."""
    try:
        ip = ipaddress.ip_address(ip_str)
        return ip.is_private or ip.is_reserved or ip.is_loopback or ip.is_link_local
    except ValueError:
        return True


# ── GeoIP initialization ─────────────────────────────────────────────────────
try:
    import maxminddb

    debug_log("=== Suricata Forwarder Starting (maxminddb available) ===")
    for db_path in GEOIP_DB_PATHS:
        if os.path.exists(db_path):
            try:
                geoip_reader = maxminddb.open_database(db_path)
                geoip_db_path = db_path
                syslog.syslog(syslog.LOG_INFO, f"suricata-forwarder: Loaded GeoIP from {db_path}")
                debug_log(f"Loaded GeoIP: {db_path}")
                break
            except Exception as e:
                syslog.syslog(syslog.LOG_WARNING, f"suricata-forwarder: Failed to load {db_path}: {e}")
                debug_log(f"GeoIP load failed: {db_path}: {e}")

    if not geoip_reader:
        syslog.syslog(syslog.LOG_WARNING, "suricata-forwarder: No GeoIP database found — running without enrichment")
        debug_log("No GeoIP database found")
except ImportError:
    syslog.syslog(syslog.LOG_WARNING, "suricata-forwarder: maxminddb not installed — no GeoIP enrichment")
    debug_log("maxminddb module not available")


# ── GeoIP enrichment ─────────────────────────────────────────────────────────
def _lookup_geoip(ip_str):
    """Look up GeoIP data for a single IP. Returns a dict or None."""
    if not geoip_reader or is_private_ip(ip_str):
        return None
    try:
        response = geoip_reader.get(ip_str)
        if not response:
            return None

        data = {}
        # Country
        country = response.get("country", {})
        if "iso_code" in country:
            data["country_code"] = country["iso_code"]
        names = country.get("names", {})
        if "en" in names:
            data["country_name"] = names["en"]

        # Continent
        continent = response.get("continent", {})
        if "code" in continent:
            data["continent_code"] = continent["code"]

        # City (City DB only)
        city = response.get("city", {})
        city_names = city.get("names", {})
        if "en" in city_names:
            data["city_name"] = city_names["en"]

        # Location (City DB only) — GeoJSON [lon, lat] for OpenSearch geo_point
        location = response.get("location", {})
        if "latitude" in location and "longitude" in location:
            data["location"] = [location["longitude"], location["latitude"]]

        # Region/subdivision
        subdivisions = response.get("subdivisions", [])
        if subdivisions:
            subdiv_names = subdivisions[0].get("names", {})
            if "en" in subdiv_names:
                data["region_name"] = subdiv_names["en"]

        return data if data else None
    except Exception as e:
        debug_log(f"GeoIP lookup failed for {ip_str}: {e}")
        return None


def enrich_geoip(event):
    """Add geoip_src and geoip_dest fields to the event if IPs are public."""
    if not geoip_reader:
        return event

    src_ip = event.get("src_ip")
    if src_ip:
        geo = _lookup_geoip(src_ip)
        if geo:
            event["geoip_src"] = geo
            debug_log(f"GeoIP src {src_ip} → {geo.get('country_code')}")

    dest_ip = event.get("dest_ip")
    if dest_ip:
        geo = _lookup_geoip(dest_ip)
        if geo:
            event["geoip_dest"] = geo
            debug_log(f"GeoIP dest {dest_ip} → {geo.get('country_code')}")

    return event


# ── Log file discovery ────────────────────────────────────────────────────────
def find_eve_logs():
    """Find all Suricata EVE JSON log files on this pfSense system."""
    return sorted(glob.glob("/var/log/suricata/*/eve.json"))


def _get_inode(path):
    """Get inode of a file, or None if it doesn't exist."""
    try:
        return os.stat(path).st_ino
    except OSError:
        return None


# ── Log tailing with rotation handling ────────────────────────────────────────
def tail_log_file(eve_log, sock):
    """
    Tail a single EVE log file and forward events via UDP.

    Handles log rotation by detecting:
      1. Inode change (file replaced by rotation)
      2. File size shrink (file truncated)
      3. File disappearance and reappearance
    """
    interface = eve_log.split("/")[-2]
    geoip_status = "enabled" if geoip_reader else "disabled"
    syslog.syslog(syslog.LOG_INFO,
                  f"suricata-forwarder: Monitoring {interface} ({eve_log}) — GeoIP: {geoip_status}")

    event_count = 0
    idle_count = 0

    while True:
        try:
            # Wait for file to exist
            while not os.path.exists(eve_log):
                debug_log(f"[{interface}] Waiting for {eve_log}...")
                time.sleep(5)

            original_inode = _get_inode(eve_log)
            with open(eve_log, "r") as f:
                f.seek(0, 2)  # Start at end (tail -f behavior)
                debug_log(f"[{interface}] Opened (inode={original_inode}, pos={f.tell()})")

                while True:
                    line = f.readline()
                    if line:
                        idle_count = 0
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            event = json.loads(line)
                            if geoip_reader:
                                event = enrich_geoip(event)
                            payload = json.dumps(event).encode("utf-8")
                            sock.sendto(payload, (SIEM_HOST, LOGSTASH_PORT))
                            event_count += 1
                            if event_count % 1000 == 0:
                                debug_log(f"[{interface}] Forwarded {event_count} events")
                        except json.JSONDecodeError:
                            debug_log(f"[{interface}] Bad JSON, skipping line")
                        except Exception as e:
                            syslog.syslog(syslog.LOG_WARNING,
                                          f"suricata-forwarder [{interface}]: Send error: {e}")
                    else:
                        # No new data
                        idle_count += 1
                        time.sleep(0.1)

                        # Periodically check for log rotation
                        if idle_count >= ROTATION_CHECK_CYCLES:
                            idle_count = 0
                            current_inode = _get_inode(eve_log)

                            # File replaced or deleted
                            if current_inode is None or current_inode != original_inode:
                                syslog.syslog(syslog.LOG_INFO,
                                              f"suricata-forwarder [{interface}]: Rotation detected, reopening")
                                break

                            # File truncated
                            try:
                                if f.tell() > os.path.getsize(eve_log):
                                    syslog.syslog(syslog.LOG_INFO,
                                                  f"suricata-forwarder [{interface}]: Truncation detected, reseeking")
                                    f.seek(0, 2)
                            except OSError:
                                break

        except FileNotFoundError:
            syslog.syslog(syslog.LOG_WARNING,
                          f"suricata-forwarder [{interface}]: File gone, waiting...")
            time.sleep(5)
        except Exception as e:
            syslog.syslog(syslog.LOG_ERR,
                          f"suricata-forwarder [{interface}]: Error: {e}, restarting in 5s")
            time.sleep(5)


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    eve_logs = find_eve_logs()
    if not eve_logs:
        syslog.syslog(syslog.LOG_ERR, "suricata-forwarder: No EVE JSON logs found")
        print("ERROR: No EVE JSON files found in /var/log/suricata/*/eve.json", file=sys.stderr)
        sys.exit(1)

    geoip_status = "enabled" if geoip_reader else "disabled"
    msg = (f"suricata-forwarder: Starting — {len(eve_logs)} interface(s), "
           f"target={SIEM_HOST}:{LOGSTASH_PORT}, GeoIP={geoip_status}")
    syslog.syslog(syslog.LOG_INFO, msg)
    print(msg, file=sys.stderr)
    for log in eve_logs:
        debug_log(f"  {log}")

    # Single shared UDP socket for all threads
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    # One thread per EVE log file
    for eve_log in eve_logs:
        t = threading.Thread(target=tail_log_file, args=(eve_log, sock), daemon=True)
        t.start()

    # Keep main thread alive
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        syslog.syslog(syslog.LOG_INFO, "suricata-forwarder: Stopped (Ctrl+C)")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
    except Exception as e:
        syslog.syslog(syslog.LOG_ERR, f"suricata-forwarder: Fatal: {e}")
        print(f"FATAL: {e}", file=sys.stderr)
        sys.exit(1)
