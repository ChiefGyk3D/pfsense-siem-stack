# Suricata Dashboard v2 - Features & Testing Guide

## Overview
Modern Grafana 12.3.0 dashboard using native panels and grafana-opensearch-datasource plugin.

**Location**: `dashboards/suricata-improved-v2.json`  
**Datasource**: OpenSearch-Suricata-Native (UID: bf53unpmdj0u8c)  
**Panel Count**: 13 panels across 5 rows  
**Refresh**: 30 seconds (configurable)

---

## Panel Inventory

### Row 1: Key Metrics (5 Stat Panels)
All stat panels use modern native visualization with threshold colors.

| Panel ID | Title | Metric | Query | Thresholds |
|----------|-------|--------|-------|------------|
| 1 | Total Events | Count of all events | `*` | Green<1k, Yellow<10k, Red≥10k |
| 2 | Top Alert Signature | Most frequent alert | `event_type:alert` + terms on signature.keyword | Blue |
| 3 | Top Source IP | Most active source | `*` + terms on src_ip.keyword | Purple |
| 4 | Top Alert Category | Most common category | `event_type:alert` + terms on category.keyword | Orange |
| 5 | Alert Rate | Alerts per minute | `event_type:alert` + date_histogram 1m | Green<10, Yellow<50, Red≥50 |

### Row 2: Distribution Charts (3 Native Pie Charts)
Native `piechart` plugin - **TESTING REQUIRED** to verify compatibility with OpenSearch datasource.

| Panel ID | Title | Chart Type | Field | Size | Notes |
|----------|-------|------------|-------|------|-------|
| 10 | Protocol Distribution | Pie | proto.keyword | Top 10 | TCP/UDP/ICMP/etc |
| 11 | Event Type Distribution | Pie | event_type.keyword | Top 15 | alert/flow/dns/http/etc |
| 12 | Top Destination Ports | Donut | dest_port | Top 15 | Shows port numbers |

**Testing Checklist**:
- [ ] Pie charts render correctly
- [ ] Legend shows values and percentages
- [ ] Tooltips display on hover
- [ ] Colors are distinct
- [ ] Labels are readable

**Fallback**: If pie charts don't work, replace with horizontal `barchart` panels (see Row 4).

### Row 3: Timeseries (1 Panel)
Proven working - timeseries with OpenSearch is well-supported.

| Panel ID | Title | Visualization | Features |
|----------|-------|---------------|----------|
| 20 | Events Over Time by Type | Stacked area chart | Auto interval, top 10 event types, sum/mean in legend |

### Row 4: Bar Charts (2 Horizontal Bar Charts)
Native `barchart` plugin - **TESTING REQUIRED** for OpenSearch compatibility.

| Panel ID | Title | Field | Size | Orientation |
|----------|-------|-------|------|-------------|
| 30 | Top Alert Signatures | alert.signature.keyword | Top 20 | Horizontal |
| 31 | Top Alert Categories | alert.category.keyword | Top 15 | Horizontal |

**Testing Checklist**:
- [ ] Bars render horizontally
- [ ] Values display on bars
- [ ] Sorting works (descending count)
- [ ] Long labels don't truncate badly

### Row 5: Details Table (1 Panel)
Proven working - table panel is fully compatible.

| Panel ID | Title | Query Type | Features |
|----------|-------|------------|----------|
| 40 | Recent Events | Logs | Sortable, all fields, auto-sizing |

---

## Technical Details

### Datasource Configuration
```json
{
  "type": "grafana-opensearch-datasource",
  "uid": "bf53unpmdj0u8c"
}
```

### Query Patterns

**Count Query** (Stat panels):
```json
{
  "metrics": [{"id": "1", "type": "count"}],
  "bucketAggs": [],
  "query": "*"
}
```

**Terms Aggregation** (Pie/Bar charts):
```json
{
  "bucketAggs": [
    {
      "field": "suricata.eve.proto.keyword",
      "type": "terms",
      "settings": {
        "size": "10",
        "order": "desc",
        "orderBy": "_count"
      }
    }
  ]
}
```

**Date Histogram** (Timeseries):
```json
{
  "bucketAggs": [
    {
      "field": "@timestamp",
      "type": "date_histogram",
      "settings": {"interval": "auto"}
    },
    {
      "field": "suricata.eve.event_type.keyword",
      "type": "terms",
      "settings": {"size": "10"}
    }
  ]
}
```

### Field Mappings
All text fields use `.keyword` suffix for aggregations:
- `suricata.eve.proto.keyword` - TCP/UDP/ICMP
- `suricata.eve.event_type.keyword` - alert/flow/dns/http/fileinfo/etc
- `suricata.eve.alert.signature.keyword` - Alert rule description
- `suricata.eve.alert.category.keyword` - Classification
- `suricata.eve.src_ip.keyword` - Source IP address
- `suricata.eve.dest_port` - Numeric, no .keyword needed

---

## Installation & Testing

### Manual Import (Recommended)
1. Open Grafana: http://192.168.210.10:3000
2. Navigate to: **Dashboards** → **New** → **Import**
3. Upload: `dashboards/suricata-improved-v2.json`
4. Verify datasource selection: **OpenSearch-Suricata-Native**
5. Click **Import**

### API Import (Requires Auth)
```bash
# Create API key in Grafana first
curl -X POST \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  --data @<(jq -n --slurpfile d dashboards/suricata-improved-v2.json \
    '{dashboard: $d[0], overwrite: true}') \
  http://192.168.210.10:3000/api/dashboards/db
```

### Testing Steps

**Phase 1: Verify Data Flow**
1. Open dashboard
2. Check time range: Last 24 hours
3. Verify "Total Events" stat shows >0
4. Check "Recent Events" table has data
5. Confirm timestamps are recent

**Phase 2: Test Native Pie Charts** ⚠️ CRITICAL
1. Inspect "Protocol Distribution" panel
   - Should show pie slices for TCP, UDP, etc.
   - Legend should show counts and percentages
   - Tooltips should work on hover
2. Inspect "Event Type Distribution"
   - Verify all event types appear
   - Check colors are distinct
3. Inspect "Top Destination Ports"
   - Donut chart should render (pie with hole)
   - Port numbers should be readable

**If pie charts FAIL**:
- Note error messages
- Check browser console for JS errors
- Try switching to different datasource UID
- Fall back to bar charts (proven working)

**Phase 3: Test Bar Charts**
1. "Top Alert Signatures" - horizontal bars, top 20
2. "Top Alert Categories" - horizontal bars, top 15
3. Verify bars are sorted by count (descending)
4. Check long text labels don't break layout

**Phase 4: Verify Timeseries**
1. "Events Over Time by Type" should show stacked areas
2. Legend should list all event types
3. Zoom in/out should work
4. Time range selector should update data

---

## Improvements Over Legacy Dashboard

### What Changed

| Feature | Legacy (v1) | Improved (v2) |
|---------|-------------|---------------|
| Datasource | `elasticsearch` (deprecated) | `grafana-opensearch-datasource` (native) |
| Pie Charts | `grafana-piechart-panel` plugin | Native `piechart` |
| Worldmap | `grafana-worldmap-panel` | Removed (geomap planned for v3) |
| Graph | Old `graph` panel | Modern `timeseries` |
| Panel Count | 15 | 13 (consolidated) |
| Stats | 4 basic | 5 with thresholds & sparklines |
| Layout | Mixed | Organized 5-row structure |

### Performance Benefits
- **Faster rendering**: Native panels use modern React components
- **Better caching**: OpenSearch datasource has improved query caching
- **Future-proof**: All panels maintained by Grafana team
- **No plugin dependencies**: Reduced risk of compatibility issues

---

## Known Issues & Workarounds

### Issue 1: Pie Charts May Not Render
**Symptom**: Pie chart panels show "No data" or error message  
**Cause**: grafana-opensearch-datasource may have limitations with pie chart queries  
**Workaround**: Replace pie charts with horizontal bar charts (same data)

**Quick Fix**:
1. Edit panel
2. Change visualization to "Bar chart"
3. Set orientation to "Horizontal"
4. Save

### Issue 2: Table Shows Too Many Fields
**Symptom**: Recent Events table is cluttered with nested fields  
**Solution**: Add field transformation
1. Edit panel 40
2. Add transformation: "Organize fields"
3. Select only: @timestamp, event_type, src_ip, dest_ip, proto, alert.signature
4. Apply

### Issue 3: Dashboard Shows "No data" for All Panels
**Checklist**:
1. Verify OpenSearch is running: `curl http://192.168.210.10:9200/_cat/indices/suricata-*`
2. Check datasource connection: Grafana → Configuration → Data sources → Test
3. Verify index pattern: Should be `suricata-*` in datasource settings
4. Check time range: Expand to "Last 7 days"
5. Confirm field mappings: `curl http://192.168.210.10:9200/suricata-*/_mapping | jq`

---

## Next Iteration (v3 Planned)

### Features to Add
- [ ] **Geomap panel** - Map source/dest IPs (if geoip data available)
- [ ] **Heatmap panel** - Time-based alert patterns (hour vs day of week)
- [ ] **Gauge panels** - Severity distribution (low/medium/high/critical)
- [ ] **State timeline** - Show interface activity over time
- [ ] **Histogram** - Byte/packet distribution
- [ ] **Alert annotations** - Mark critical events on timeseries

### Variables to Add
- [ ] `$interface` - Filter by Suricata interface (igb0/igb1/etc)
- [ ] `$severity` - Filter by alert severity
- [ ] `$protocol` - Filter by protocol (TCP/UDP/ICMP)
- [ ] `$src_network` - Filter by source subnet

### Additional Queries
- [ ] Top talkers (bytes transferred)
- [ ] Connection duration statistics
- [ ] DNS query volume
- [ ] HTTP status codes
- [ ] TLS/SSL versions

---

## Compatibility Matrix

| Panel Type | OpenSearch Native | Works? | Notes |
|------------|-------------------|---------|-------|
| Stat | ✅ | Yes | Fully supported |
| Table | ✅ | Yes | Proven working |
| Timeseries | ✅ | Yes | Proven working |
| Piechart | ❓ | **TO TEST** | Native panel, may have issues |
| Barchart | ❓ | **TO TEST** | Likely works, similar to graph |
| Geomap | ❓ | Not tested | Requires geo_point field |
| Heatmap | ❓ | Not tested | May need matrix aggregation |
| Gauge | ❓ | Not tested | Should work with bucket queries |

**Legend**:
- ✅ Confirmed working with current data
- ❓ Needs testing with OpenSearch datasource
- ⚠️ Known issues, see workarounds
- ❌ Does not work, use alternative

---

## Testing Commands

### Check Event Count
```bash
curl -s http://192.168.210.10:9200/suricata-*/_count | jq
```

### Verify Field Mappings
```bash
curl -s http://192.168.210.10:9200/suricata-*/_mapping | \
  jq '.[] | .mappings.properties.suricata.properties.eve.properties | keys'
```

### Test Protocol Aggregation (Pie Chart Query)
```bash
curl -s -X POST http://192.168.210.10:9200/suricata-*/_search -H 'Content-Type: application/json' -d '{
  "size": 0,
  "aggs": {
    "protocols": {
      "terms": {
        "field": "suricata.eve.proto.keyword",
        "size": 10,
        "order": {"_count": "desc"}
      }
    }
  }
}' | jq '.aggregations.protocols.buckets'
```

### Test Alert Signature Aggregation
```bash
curl -s -X POST http://192.168.210.10:9200/suricata-*/_search -H 'Content-Type: application/json' -d '{
  "size": 0,
  "query": {
    "term": {"suricata.eve.event_type.keyword": "alert"}
  },
  "aggs": {
    "signatures": {
      "terms": {
        "field": "suricata.eve.alert.signature.keyword",
        "size": 20,
        "order": {"_count": "desc"}
      }
    }
  }
}' | jq '.aggregations.signatures.buckets[] | {signature: .key, count: .doc_count}'
```

---

## Documentation References

- **Grafana OpenSearch Datasource**: https://grafana.com/docs/grafana/latest/datasources/opensearch/
- **Pie Chart Panel**: https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/pie-chart/
- **Bar Chart Panel**: https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/bar-chart/
- **Stat Panel**: https://grafana.com/docs/grafana/latest/panels-visualizations/visualizations/stat/
- **Dashboard JSON Model**: https://grafana.com/docs/grafana/latest/dashboards/build-dashboards/view-dashboard-json-model/

---

## Support & Troubleshooting

### Get Dashboard UID
```bash
jq -r '.uid' dashboards/suricata-improved-v2.json
```

### Export Modified Dashboard
```bash
# From Grafana UI: Dashboard → Share → Export → Save to file
# Or via API (requires auth):
curl -H "Authorization: Bearer YOUR_API_KEY" \
  http://192.168.210.10:3000/api/dashboards/uid/suricata-improved-v2 | \
  jq '.dashboard' > dashboards/suricata-improved-v2-modified.json
```

### Debug Panel Queries
1. Open panel in edit mode
2. Click "Query inspector"
3. View "Query" tab to see actual OpenSearch query
4. Copy query and test directly against OpenSearch
5. Check "Stats" tab for performance metrics

---

**Last Updated**: Dashboard v2 created $(date -Iseconds)  
**Next Steps**: Import dashboard → Test pie charts → Document results → Create v3 with working panels
