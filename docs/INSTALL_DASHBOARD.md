# Dashboard Installation Guide

Complete guide for setting up Grafana datasources and importing the pre-built dashboards.

## Prerequisites

- Grafana 12.3.0+ installed and running
- grafana-opensearch-datasource plugin installed
- OpenSearch accessible from Grafana server
- Suricata events flowing into OpenSearch (verify event count > 0)
- InfluxDB configured with Telegraf metrics (for system dashboard)

## Installation Steps

### 1. Access Grafana

```bash
# Open browser to your Grafana instance
http://YOUR_SIEM_IP:3000

# Default credentials
Username: admin
Password: admin
```

Change the password when prompted on first login.

### 2. Add Datasources

You need **three** datasources: one InfluxDB and two OpenSearch.

#### 2a. InfluxDB Datasource (System Metrics)

1. Click **☰ menu** → **Connections** → **Data sources**
2. Click **Add data source** → Search **InfluxDB**
3. Configure:

```
Name: pfsense
URL: http://localhost:8086
Database: pfsense
User: pfsense
Password: (your InfluxDB password)
```

4. Click **Save & test** → ✅ **Data source is working**

#### 2b. OpenSearch-Suricata Datasource

1. Click **Add data source** → Search **OpenSearch**
2. Configure:

```
Name: OpenSearch-Suricata
URL: http://localhost:9200
Access: Server (default)
Index name: suricata-*
Time field name: @timestamp
Version: 2.0+
```

3. Leave auth unchecked (no basic auth needed)
4. Click **Save & test** → ✅ **Data source is working**

#### 2c. OpenSearch-pfBlockerNG Datasource

1. Click **Add data source** → Search **OpenSearch**
2. Configure:

```
Name: OpenSearch-pfBlockerNG
URL: http://localhost:9200
Access: Server (default)
Index name: pfblockerng-*
Time field name: @timestamp
Version: 2.0+
```

3. Leave auth unchecked
4. Click **Save & test** → ✅ **Data source is working**

### 3. Import Dashboards

#### Dashboard 1: pfSense System & pfBlockerNG

1. Click **☰ menu** → **Dashboards** → **New** → **Import**
2. Click **Upload JSON file**
3. Select `dashboards/pfsense_pfblockerng_system.json`
4. Grafana will prompt for two datasource variables:
   - **InfluxDB**: Select your `pfsense` InfluxDB datasource (system metrics)
   - **OpenSearch**: Select your `OpenSearch-pfBlockerNG` datasource (pfBlockerNG panels)
5. Click **Import**

> This dashboard uses **both** InfluxDB (CPU, RAM, interfaces, gateways) and OpenSearch-pfBlockerNG (IP blocks, DNSBL blocks, block logs).

#### Dashboard 2: Suricata WAN Monitoring

1. Click **Import** → **Upload JSON file**
2. Select `dashboards/Suricata IDS_IPS Dashboard.json`
3. Select datasource: **OpenSearch-Suricata**
4. Click **Import**

#### Dashboard 3: Suricata Per-Interface (LAN)

1. Click **Import** → **Upload JSON file**
2. Select `dashboards/Suricata_Per_Interface.json`
3. Select datasource: **OpenSearch-Suricata**
4. Click **Import**

#### Option B: Create Dashboard Manually

If you don't have the JSON file, create the dashboard step-by-step:

**1. Create New Dashboard**
- Click **☰ menu** → **Dashboards** → **New** → **New Dashboard**
- Click **Add visualization**
- Select **OpenSearch-Suricata** datasource

**2. Add Panels (Repeat for Each)**

##### Panel 1: Events Over Time
```
Type: Time series
Query: *
Metrics: Count
Group by: Date Histogram (@timestamp, Auto)
```

##### Panel 2: Event Type Distribution
```
Type: Table
Query: *
Metrics: Count
Group by: Terms (suricata.eve.event_type.keyword, 20)
Columns: suricata.eve.event_type, Count
```

##### Panel 3: Protocol Distribution
```
Type: Table
Query: *
Metrics: Count
Group by: Terms (suricata.eve.proto.keyword, 10)
```

##### Panel 4: Top Source IPs
```
Type: Table
Query: *
Metrics: Count
Group by: Terms (suricata.eve.src_ip.keyword, 20)
Columns: suricata.eve.src_ip, Count
Sort: Count (descending)
```

##### Panel 5: Top Destination IPs
```
Type: Table
Query: *
Metrics: Count
Group by: Terms (suricata.eve.dest_ip.keyword, 20)
```

##### Panel 6: Top Destination Ports
```
Type: Table
Query: *
Metrics: Count
Group by: Terms (suricata.eve.dest_port, 20)
```

##### Panel 7: TLS Server Names (SNI)
```
Type: Table
Query: suricata.eve.event_type:tls
Metrics: Count
Group by: Terms (suricata.eve.tls.sni.keyword, 20)
```

##### Panel 8: DNS Queries
```
Type: Table
Query: suricata.eve.event_type:dns
Metrics: Count
Group by: Terms (suricata.eve.dns.rrname.keyword, 20)
```

##### Panel 9: HTTP Hosts
```
Type: Table
Query: suricata.eve.event_type:http
Metrics: Count
Group by: Terms (suricata.eve.http.hostname.keyword, 20)
```

##### Panel 10: Security Alerts
```
Type: Table
Query: suricata.eve.event_type:alert
Metrics: Count
Group by: Terms (suricata.eve.alert.signature.keyword, 20)
Columns: Alert Signature, Count, Severity
```

##### Panel 11: Events by Type (Timeseries)
```
Type: Time series
Query: *
Metrics: Count
Group by: 
  - Date Histogram (@timestamp, Auto)
  - Terms (suricata.eve.event_type.keyword, 10)
Legend: {{suricata.eve.event_type.keyword}}
```

##### Panel 12: Interface Distribution
```
Type: Table
Query: *
Metrics: Count
Group by: Terms (suricata.eve.in_iface.keyword, 10)
```

**3. Configure Dashboard Settings**
- Click **Dashboard settings** (gear icon)
- General:
  - Name: `Suricata IDS/IPS Dashboard`
  - UID: `suricata-complete`
- Time options:
  - Timezone: Browser Time
  - Auto refresh: 30s
  - Default time range: Last 24 hours
- Save dashboard

### 4. Verify Dashboard Data

After importing, you should see:

1. **Events Over Time** - Line graph showing event rate
2. **Event Type Distribution** - Table with counts for DNS, TLS, HTTP, QUIC, etc.
3. **Top Source/Dest IPs** - Tables with internal and external IPs
4. **Security Alerts** - Table with IDS signatures (if any alerts generated)

If panels show "No data":
- Check time range (top right) - try "Last 24 hours"
- Verify events in OpenSearch: `curl http://localhost:9200/suricata-*/_count`
- Check datasource connection: Dashboard settings → Data sources

## Dashboard Features

### Time Range Controls

- **Top right corner**: Select time range
- **Presets**: Last 5m, 15m, 1h, 6h, 24h, 7d, 30d
- **Custom**: Click time range → Custom → Set dates
- **Refresh**: Auto-refresh every 30 seconds (configurable)

### Panel Interactions

- **Click data point**: Drill down to specific events
- **Hover**: See detailed values
- **Table sorting**: Click column headers
- **Table filtering**: Use search box above tables

### Variables (Optional)

Add dashboard variables for filtering:

1. Click **Dashboard settings** → **Variables** → **Add variable**
2. Create variables:
   - `interface` - suricata.eve.in_iface.keyword
   - `event_type` - suricata.eve.event_type.keyword
   - `src_ip` - suricata.eve.src_ip.keyword

3. Use in queries: `suricata.eve.in_iface:$interface`

## Customization

### Change Panel Visualization

1. Click panel title → **Edit**
2. Change visualization type from dropdown
3. Adjust query or settings
4. Click **Apply** to save

### Add New Panel

1. Click **Add** → **Visualization**
2. Select **OpenSearch-Suricata** datasource
3. Build query (see examples above)
4. Configure visualization
5. Click **Apply**

### Organize Panels

1. Click **Dashboard settings** (gear icon)
2. Enable **Edit mode**
3. Drag panels to reposition
4. Resize panels by dragging corners
5. Save dashboard

### Panel-Specific Tips

**Table Panels:**
- ✅ Use for aggregations and top-N lists
- ✅ Reliable with .keyword fields
- ✅ Good for detailed data

**Timeseries Panels:**
- ✅ Use for trends over time
- ✅ Can overlay multiple series
- ✅ Good for alerts timeline

**Stat Panels:**
- ⚠️ May not display correctly with OpenSearch
- Use tables instead for single-value metrics

**Pie Charts:**
- ⚠️ May not display correctly with OpenSearch
- Use tables for distribution data

## Troubleshooting

### No Data in Panels

```bash
# 1. Check OpenSearch has data
curl -s http://localhost:9200/suricata-*/_count | jq .count
# Should return number > 0

# 2. Check index pattern
curl -s http://localhost:9200/_cat/indices/suricata-* | head -5
# Should list indices like: suricata-2025.11.24

# 3. Check latest event
curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source | {"@timestamp", "event_type": .suricata.eve.event_type}'
# Should return recent event

# 4. Test datasource in Grafana
# Dashboards → Panel → Edit → Query inspector → Refresh
```

### Panels Show "Field Not Found"

Check field mapping in OpenSearch:
```bash
curl -s "http://localhost:9200/suricata-*/_mapping" | jq '.["suricata-2025.11.24"].mappings.properties.suricata.properties.eve.properties | keys'
```

Expected fields:
- `event_type`
- `src_ip`
- `dest_ip`
- `proto`
- `timestamp`

If fields missing, check Logstash is parsing correctly:
```bash
sudo journalctl -u logstash -n 50 | grep -i error
```

### Panels Show Wrong Data

1. **Check query filter**: Edit panel → Query → Verify lucene query syntax
2. **Check aggregation**: Metrics → Should be "Count" for most panels
3. **Check field name**: Use `.keyword` suffix for string fields (e.g., `suricata.eve.event_type.keyword`)

### Dashboard Performance Issues

If dashboard is slow:

1. **Reduce time range**: Use shorter periods (6h instead of 7d)
2. **Limit aggregation size**: Change "Size" in Group by from 100 to 20
3. **Increase auto-refresh interval**: Change from 30s to 1m
4. **Add query filters**: Filter to specific event types or IPs

### Export/Backup Dashboard

```bash
# Get dashboard JSON via API
curl -s -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/dashboards/uid/suricata-complete | \
  jq .dashboard > suricata-dashboard-backup.json

# Or export from UI:
# Dashboard settings → JSON Model → Copy to clipboard
```

## Useful Queries

Common Lucene query examples for panels:

```
# All events
*

# Specific event type
suricata.eve.event_type:alert

# Multiple event types
suricata.eve.event_type:(alert OR dns)

# Specific IP
suricata.eve.src_ip:"192.168.1.100"

# Port range
suricata.eve.dest_port:[1 TO 1024]

# Protocol
suricata.eve.proto:TCP

# Exclude internal IPs
NOT suricata.eve.dest_ip:192.168.*

# High severity alerts
suricata.eve.event_type:alert AND suricata.eve.alert.severity:[1 TO 2]

# TLS with specific SNI
suricata.eve.event_type:tls AND suricata.eve.tls.sni:*.google.com
```

## Next Steps

- **[Troubleshooting Guide](TROUBLESHOOTING.md)** - Common issues and solutions
- **[Configuration Reference](CONFIGURATION.md)** - Detailed configuration options
- Explore OpenSearch indices: `http://YOUR_SIEM_IP:9200/_cat/indices`

## Dashboard Sharing

### Share with Team

1. Click **Share** (arrow icon) at top of dashboard
2. Choose sharing method:
   - **Link**: Copy URL (requires Grafana login)
   - **Snapshot**: Create public snapshot
   - **Export**: Download JSON for importing elsewhere

### Create Playlists

For NOC/SOC displays:

1. **☰ menu** → **Dashboards** → **Playlists**
2. **New playlist**
3. Add dashboards and set interval
4. Start playlist → Full screen

### Set as Home Dashboard

1. Click **★** (star) on dashboard to favorite
2. **☰ menu** → **Profile** → **Preferences**
3. **Home Dashboard**: Select "Suricata IDS/IPS Dashboard"
4. Save

## Additional Resources

- [Grafana OpenSearch Datasource Docs](https://grafana.com/docs/plugins/grafana-opensearch-datasource/)
- [OpenSearch Query DSL](https://opensearch.org/docs/latest/query-dsl/)
- [Lucene Query Syntax](https://www.elastic.co/guide/en/elasticsearch/reference/current/query-dsl-query-string-query.html#query-string-syntax)
