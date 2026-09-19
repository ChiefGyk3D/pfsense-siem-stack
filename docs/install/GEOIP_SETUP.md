# GeoIP Setup for Suricata Dashboard

## Overview

The Suricata dashboard includes geographic visualization of network events using MaxMind
GeoLite2 databases. The Python forwarder on pfSense uses the `maxminddb` library to enrich
each event with GeoIP data **before** sending it to Logstash/OpenSearch, so no GeoIP filter
is needed on the SIEM side.

> **Note**: The forwarder uses `maxminddb` directly instead of `geoip2` to avoid C compiler
> dependencies on pfSense. `maxminddb` ships with the pfSense Suricata and pfBlockerNG
> packages (`py311-maxminddb` on pfSense 2.8.x; a future pfSense with a different Python
> will carry the matching `py3XX-maxminddb`). If the module is missing the forwarder still
> runs — it logs `maxminddb not installed — no GeoIP enrichment` to syslog and sends
> events without the `geoip_*` fields.

## Do I Need a MaxMind Account?

**The forwarder itself does not.** It reuses a GeoLite2 database that another pfSense
package has already downloaded — it never contacts MaxMind.

**The package that downloads the database does.** MaxMind requires a free account and
license key to fetch GeoLite2. On pfSense that key is configured in the GUI of the package
that owns the database:

- **pfBlockerNG**: Firewall → pfBlockerNG → IP → **MaxMind License Key**
- **ntopng**: Diagnostics → ntopng Settings → MaxMind license key

The pfSense Suricata package does not download a GeoLite2 database of its own.

Sign up at [MaxMind GeoLite2 Signup](https://www.maxmind.com/en/geolite2/signup), generate
a license key, paste it into one of the packages above, and let that package update the
database (weekly is typical). See also
[Hardware Requirements → GeoIP](HARDWARE_REQUIREMENTS.md#-geoip-requirements).

## Database Requirements

### For Full Geographic Visualization (with Map)
- **Required**: GeoLite2-City database
- **Provides**: Country, region, city, latitude, longitude
- **Dashboard features enabled**: Geomap, country table, city details

### For Country-Level Visualization Only
- **Required**: GeoLite2-Country database
- **Provides**: Country code, country name, continent
- **Dashboard features enabled**: Country table (no map)

## Database Search Order on pfSense

The forwarder checks the following paths in order and uses the **first one that exists**
(see `GEOIP_DB_PATHS` in `scripts/forward-suricata-eve.py`):

| # | Path | Owner | Level |
|---|------|-------|-------|
| 1 | `/usr/local/share/ntopng/GeoLite2-City.mmdb` | ntopng | City (best for the map) |
| 2 | `/usr/local/share/suricata/GeoLite2/GeoLite2-City.mmdb` | Suricata | City |
| 3 | `/usr/local/share/suricata/GeoLite2/GeoLite2-Country.mmdb` | Suricata | Country |
| 4 | `/usr/local/share/GeoIP/GeoLite2-City.mmdb` | pfBlockerNG / system | City |
| 5 | `/usr/local/share/GeoIP/GeoLite2-Country.mmdb` | pfBlockerNG / system | Country |
| 6 | `/var/unbound/usr/local/share/GeoIP/GeoLite2-City.mmdb` | Unbound chroot copy | City |
| 7 | `/var/unbound/usr/local/share/GeoIP/GeoLite2-Country.mmdb` | Unbound chroot copy | Country |
| 8 | `/var/db/GeoIP/GeoLite2-City.mmdb` | generic | City |
| 9 | `/usr/share/GeoIP/GeoLite2-City.mmdb` | generic | City |

Which one you get depends on the packages you have installed:

- **ntopng** (recommended for the map): downloads GeoLite2-City to path 1 once its MaxMind
  key is set.
- **pfBlockerNG**: with a MaxMind key configured, its GeoIP feature places GeoLite2 files
  under `/usr/local/share/GeoIP/` (paths 4-5). Whether you get City or Country depends on
  the pfBlockerNG version and settings.
- **Suricata**: the pfSense Suricata package does not bundle a database; paths 2-3 are
  only populated if you place a file there yourself.

If none of the paths exist, the forwarder logs
`No GeoIP database found — running without enrichment` and keeps forwarding.

## Recommended Configuration

Install **ntopng** (or enable pfBlockerNG GeoIP) with a free MaxMind key and let it keep
GeoLite2-City current. The forwarder picks it up automatically and you get:

- No manual database downloads on the SIEM side
- Automatic updates by the owning package
- Full city-level precision with coordinates for the Grafana geomap
- City names and region/state information

### Installing ntopng (if needed)

1. Install the ntopng package via the pfSense Package Manager
2. Enter your MaxMind license key in the ntopng settings and let it download GeoLite2-City
3. Restart the forwarder so it re-scans the database paths:
   ```bash
   ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'
   ```

The forwarder runs as an rc.d service installed by `setup.sh`; use `service
suricata_forwarder.sh start|stop|restart|status` rather than starting the Python script by
hand. `setup.sh` detects the interpreter (python3.11 on pfSense 2.8.x) and writes it into
the script's shebang, so `python3` below refers to whatever it found.

## GeoIP Fields in OpenSearch

Events are enriched with flat root-level fields (the Logstash pipeline does not nest them):

### Source IP Enrichment
- `geoip_src.country_code` - Two-letter country code (e.g., "US")
- `geoip_src.country_name` - Full country name (e.g., "United States")
- `geoip_src.continent_code` - Two-letter continent code (e.g., "NA")
- `geoip_src.city_name` - City name (City database only)
- `geoip_src.region_name` - State/region name (City database only)
- `geoip_src.location` - `[longitude, latitude]` array, mapped as `geo_point` by the index template (City database only)

### Destination IP Enrichment
- `geoip_dest.country_code`
- `geoip_dest.country_name`
- `geoip_dest.continent_code`
- `geoip_dest.city_name` (City database only)
- `geoip_dest.region_name` (City database only)
- `geoip_dest.location` (City database only)

Private, loopback, link-local and reserved addresses are never looked up, so LAN-to-LAN
events carry no `geoip_*` fields.

## Troubleshooting

### Check which database is loaded

The forwarder logs the database it opened to syslog at startup:

```bash
ssh admin@<PFSENSE_IP> 'grep "suricata-forwarder" /var/log/system.log | grep -i geoip | tail -3'
```

Look for a line like:
```
suricata-forwarder: Loaded GeoIP from /usr/local/share/ntopng/GeoLite2-City.mmdb
```

With `DEBUG_ENABLED=true` the same information is in `/var/log/suricata_forwarder_debug.log`.

### Verify GeoIP enrichment is working
```bash
ssh admin@<PFSENSE_IP> 'tail -20 /var/log/suricata_forwarder_debug.log | grep -i enrich'
```

(Debug logging must be enabled; see
[INSTALL_PFSENSE_FORWARDER.md → Enable Debug Mode](INSTALL_PFSENSE_FORWARDER.md#enable-debug-mode-troubleshooting).)

### Check OpenSearch for GeoIP data
```bash
curl -s 'http://<SIEM_IP>:9200/suricata-*/_search?size=1&sort=@timestamp:desc&q=_exists_:geoip_src' | jq '.hits.hits[0]._source | {src_ip, dest_ip, geoip_src, geoip_dest}'
```

Should return an enriched event with country codes and, for a City database, coordinates.

### Map panel is empty but country tables work

`geoip_src.location` is probably mapped as a plain array or `float` instead of `geo_point`.
Check and, if needed, install the index template (applies to new indices only):

```bash
curl -s 'http://<SIEM_IP>:9200/suricata-*/_mapping' | jq '.[].mappings.properties.geoip_src.properties.location'
./scripts/install-opensearch-config.sh
```

### No GeoIP data in events
1. Verify a database exists on pfSense:
   `ssh admin@<PFSENSE_IP> 'ls -lh /usr/local/share/ntopng/GeoLite2-City.mmdb /usr/local/share/GeoIP/GeoLite2-*.mmdb 2>/dev/null'`
2. Check the forwarder is running: `ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh status'`
3. Check the module is present: `ssh admin@<PFSENSE_IP> '/usr/local/bin/python3 -c "import maxminddb; print(maxminddb.__version__)"'`
4. Review syslog/debug log for `GeoIP` or `maxminddb` warnings
5. Restart the forwarder: `ssh admin@<PFSENSE_IP> 'service suricata_forwarder.sh restart'`

After a pfSense upgrade or package reinstall the database path or the Python version may
change; re-run `./setup.sh` from the SIEM side (see
[pfSense Upgrade Guide](../pfsense/PFSENSE_UPGRADE_GUIDE.md)).

## License and Legal

MaxMind GeoLite2 databases are provided under the
[GeoLite2 End User License Agreement](https://www.maxmind.com/en/geolite2/eula); a free
MaxMind account is required to download them.

This setup reuses GeoIP databases that are already present on pfSense for other purposes
(ntopng, pfBlockerNG). The forwarder adds no additional downloads and needs no MaxMind
credentials of its own.

For more accurate data, consider MaxMind's commercial GeoIP2 databases — drop the `.mmdb`
at one of the paths above and the forwarder will use it.

## Python Dependencies

The forwarder uses only libraries already present on pfSense:
- `maxminddb` - shipped with the pfSense Suricata/pfBlockerNG packages (`py311-maxminddb` on 2.8.x); optional, forwarder degrades gracefully without it
- `socket`, `json`, `threading`, `ipaddress`, `syslog` - Python standard library

**No pip installation required** - the forwarder works out of the box on pfSense 2.7.2+
with Suricata installed (2.8.1 tested; 2.9.0 supported, see the upgrade guide).
