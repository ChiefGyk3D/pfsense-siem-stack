# GeoIP Setup for Suricata Dashboard

## Overview

The Suricata dashboard includes geographic visualization of network events using MaxMind GeoLite2 databases. The Python forwarder enriches events with GeoIP data before sending them to Logstash/OpenSearch.

## Database Requirements

### For Full Geographic Visualization (with Map)
- **Required**: GeoLite2-City database
- **Provides**: Country, region, city, latitude, longitude
- **Dashboard features enabled**: Geomap, country table, city details

### For Country-Level Visualization Only
- **Required**: GeoLite2-Country database  
- **Provides**: Country code, country name, continent
- **Dashboard features enabled**: Country table (no map)

## Database Sources on pfSense

The forwarder searches for GeoIP databases in the following priority order:

1. **ntopng** (RECOMMENDED for full features)
   - Path: `/usr/local/share/ntopng/GeoLite2-City.mmdb`
   - Requirement: ntopng package must be installed
   - Provides: City-level data with coordinates
   - Updated: Automatically by ntopng package

2. **Suricata**
   - Paths: 
     - `/usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb` (if available)
     - `/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb` (default)
   - Requirement: Built-in with Suricata package
   - Provides: Country-level data only by default
   - Updated: Automatically by Suricata package

3. **pfBlockerNG**
   - Paths:
     - `/usr/local/share/GeoIP/GeoLite2-City.mmdb`
     - `/usr/local/share/GeoIP/GeoLite2-Country.mmdb`
   - Requirement: pfBlockerNG package with GeoIP enabled
   - Provides: Depends on pfBlockerNG configuration
   - Updated: Automatically by pfBlockerNG

4. **Unbound**
   - Paths:
     - `/var/unbound/usr/local/share/GeoIP/GeoLite2-City.mmdb`
     - `/var/unbound/usr/local/share/GeoIP/GeoLite2-Country.mmdb`
   - Requirement: Unbound with GeoIP enabled
   - Provides: Varies by configuration

## Current Configuration

This setup **piggybacks on ntopng's GeoLite2-City database** to provide full geographic features without requiring separate GeoIP database management.

### Benefits
- ✅ No manual database downloads required
- ✅ Automatic updates via ntopng package
- ✅ Full city-level precision with coordinates
- ✅ Includes city names and region/state information

### Requirements
- ntopng package must be installed on pfSense
- If ntopng is not installed, forwarder falls back to Suricata's Country database (country-level data only)

## Installing ntopng (if needed)

If you don't have ntopng installed and want full geographic features:

1. Install ntopng package via pfSense Package Manager
2. No additional configuration needed - database is included
3. Restart the Suricata forwarder to use the City database:
   ```bash
   ssh root@<pfsense-ip> 'pkill -f forward-suricata-eve.py; nohup /usr/local/bin/python3.11 /usr/local/bin/forward-suricata-eve.py > /dev/null 2>&1 &'
   ```

## GeoIP Fields in OpenSearch

Events are enriched with the following fields:

### Source IP Enrichment
- `suricata.eve.geoip_src.country_code` - Two-letter country code (e.g., "US")
- `suricata.eve.geoip_src.country_name` - Full country name (e.g., "United States")
- `suricata.eve.geoip_src.continent_code` - Two-letter continent code (e.g., "NA")
- `suricata.eve.geoip_src.city_name` - City name (City database only)
- `suricata.eve.geoip_src.region_name` - State/region name (City database only)
- `suricata.eve.geoip_src.location.lat` - Latitude (City database only)
- `suricata.eve.geoip_src.location.lon` - Longitude (City database only)

### Destination IP Enrichment
- `suricata.eve.geoip_dest.country_code`
- `suricata.eve.geoip_dest.country_name`
- `suricata.eve.geoip_dest.continent_code`
- `suricata.eve.geoip_dest.city_name` (City database only)
- `suricata.eve.geoip_dest.region_name` (City database only)
- `suricata.eve.geoip_dest.location.lat` (City database only)
- `suricata.eve.geoip_dest.location.lon` (City database only)

## Troubleshooting

### Check which database is loaded
```bash
ssh root@<pfsense-ip> 'head -10 /var/log/suricata_forwarder_debug.log'
```

Look for a line like:
```
SUCCESS: suricata-forwarder: Loaded GeoIP database from /usr/local/share/ntopng/GeoLite2-City.mmdb
```

### Verify GeoIP enrichment is working
```bash
ssh root@<pfsense-ip> 'tail -20 /var/log/suricata_forwarder_debug.log | grep "Enriched"'
```

Should show messages like:
```
Enriched src_ip 8.8.8.8 -> US
Enriched dest_ip 1.1.1.1 -> AU
```

### Check OpenSearch for GeoIP data
```bash
curl -s 'http://<opensearch-ip>:9200/suricata-*/_search?size=1&sort=@timestamp:desc' | jq '.hits.hits[0]._source.suricata.eve | {src_ip, dest_ip, geoip_src, geoip_dest}'
```

Should return enriched events with country codes and coordinates.

### No GeoIP data in events
1. Verify database exists: `ssh root@<pfsense-ip> 'ls -lh /usr/local/share/ntopng/GeoLite2-City.mmdb'`
2. Check forwarder is running: `ssh root@<pfsense-ip> 'ps aux | grep forward-suricata-eve.py'`
3. Review debug log for errors: `ssh root@<pfsense-ip> 'tail -50 /var/log/suricata_forwarder_debug.log'`
4. Restart forwarder if needed

## License and Legal

MaxMind GeoLite2 databases are provided under the Creative Commons Attribution-ShareAlike 4.0 International License.

This setup uses GeoIP databases that are already present on pfSense for other purposes (ntopng, Suricata, pfBlockerNG). No additional database downloads or MaxMind accounts are required.

For production deployments or more accurate data, consider MaxMind's commercial GeoIP2 databases.
