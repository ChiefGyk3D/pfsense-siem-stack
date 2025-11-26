#!/bin/bash
# Setup GeoIP enrichment in Graylog using MaxMind GeoLite2 databases

set -e

GEOIP_DIR="/etc/graylog/server"
GEOIP_CITY_DB="${GEOIP_DIR}/GeoLite2-City.mmdb"

echo "=== Setting up GeoIP Enrichment for Graylog ==="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "❌ Please run as root or with sudo"
    exit 1
fi

# Install geoipupdate if not present
if ! command -v geoipupdate &> /dev/null; then
    echo "📦 Installing geoipupdate..."
    apt-get update -qq
    apt-get install -y geoipupdate
fi

# Create GeoIP directory
mkdir -p ${GEOIP_DIR}

echo ""
echo "⚠️  MaxMind GeoIP Database Setup"
echo ""
echo "MaxMind requires a free account to download GeoIP databases."
echo ""
echo "Option 1: Use free GeoLite2 databases (recommended)"
echo "  1. Sign up at: https://www.maxmind.com/en/geolite2/signup"
echo "  2. Generate a license key at: https://www.maxmind.com/en/accounts/current/license-key"
echo "  3. Run: geoipupdate -v"
echo ""
echo "Option 2: Download manually"
echo "  Download from: https://dev.maxmind.com/geoip/geolite2-free-geolocation-data"
echo "  Extract GeoLite2-City.mmdb to: ${GEOIP_DIR}/"
echo ""
echo "After downloading, configure Graylog to use GeoIP:"
echo "  1. Edit /etc/graylog/server/server.conf"
echo "  2. Add/uncomment: geo_ip_resolver_enabled = true"
echo "  3. Add: geo_ip_resolver_db_path = ${GEOIP_CITY_DB}"
echo "  4. Restart: systemctl restart graylog-server"
echo ""
echo "Then create a GeoIP lookup in Graylog Web UI:"
echo "  System > Lookup Tables > Data Adapters > Create data adapter"
echo "  - Type: MaxMind GeoIP"
echo "  - Database file path: ${GEOIP_CITY_DB}"
echo ""
