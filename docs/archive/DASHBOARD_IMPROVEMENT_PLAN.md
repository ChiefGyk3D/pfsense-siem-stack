# Dashboard Improvement Plan

## Current Status

**Current Dashboard:** `dashboards/suricata-complete.json`
- Uses legacy "Elasticsearch" datasource  
- Has pie charts (grafana-piechart-panel - legacy plugin)
- Has worldmap panels (legacy plugin)
- Has stat panels
- 15 total panels

**Event Count:** 52,979 events in OpenSearch

## Panel Plugin Availability

Grafana 12.3.0 has these **built-in** panel types:
✅ **piechart** - Native pie chart (not legacy plugin!)
✅ **stat** - Single value metrics
✅ **gauge** - Gauge visualization
✅ **barchart** - Horizontal/vertical bars
✅ **table** - Data tables (confirmed working)
✅ **timeseries** - Time-based graphs (confirmed working)
✅ **geomap** - Modern geographic visualization
✅ **heatmap** - Heat maps
✅ **histogram** - Histograms

## Improvement Strategy

### Phase 1: Test Core Panel Types (Do First)

Test these with your OpenSearch datasource:

1. **Stat panels** - Top signatures, categories, IPs, countries
   - Query: Terms aggregation on `.keyword` fields
   - Should work: Simple aggregations

2. **Native pie charts** - Protocol, port, category distribution
   - Query: Terms aggregation  
   - Test: Protocol distribution, alert categories
   - If fails: Fall back to bar chart

3. **Bar charts** - Alternative to pie if needed
   - Query: Same as pie chart
   - Horizontal bars work well for top-N

4. **Geomap** - Modern replacement for worldmap
   - Query: Geohash or terms aggregation with geo data
   - Test: Source/dest IP locations

### Phase 2: Enhanced Visualizations

5. **Heatmap** - Alert frequency by hour/day
6. **Histogram** - Port distribution, packet sizes
7. **Gauge** - Alert severity levels

### Phase 3: Advanced Panels

8. **State timeline** - Interface state over time
9. **Candlestick** - Traffic patterns (if applicable)

## Proposed Dashboard Layout

```
┌─────────────────────────────────────────────────────────────┐
│  Row 1: Key Metrics (Stat Panels)                          │
├──────────┬──────────┬──────────┬──────────┬───────────────┤
│ Total    │ Top Alert│ Top      │ Top      │ Alert Rate    │
│ Events   │ Signature│ Category │ Src IP   │ (events/min)  │
└──────────┴──────────┴──────────┴──────────┴───────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Row 2: Distribution (Pie Charts / Bar Charts)              │
├────────────────────┬────────────────────┬───────────────────┤
│ Protocol           │ Top Alert          │ Top Dest          │
│ Distribution       │ Categories         │ Ports             │
│ (Pie/Bar)          │ (Pie/Bar)          │ (Pie/Bar)         │
└────────────────────┴────────────────────┴───────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Row 3: Time Series                                          │
├──────────────────────────────────────────────────────────────┤
│ Events Over Time (by event_type or alert.severity)          │
│ (Timeseries - stacked or multi-line)                        │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Row 4: Geographic (if working)                              │
├─────────────────────────────┬────────────────────────────────┤
│ Source IP Locations         │ Destination IP Locations       │
│ (Geomap)                    │ (Geomap)                       │
└─────────────────────────────┴────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  Row 5: Detailed Table                                       │
├──────────────────────────────────────────────────────────────┤
│ Recent Events Table                                          │
│ Columns: timestamp, interface, src_ip, dest_ip, proto,      │
│          event_type, alert.signature, alert.category         │
└──────────────────────────────────────────────────────────────┘
```

## Example Queries for New Panels

### Stat Panel - Top Alert Signature
```json
{
  "bucketAggs": [
    {
      "field": "suricata.eve.alert.signature.keyword",
      "id": "2",
      "settings": {
        "min_doc_count": 1,
        "order": "desc",
        "orderBy": "_count",
        "size": "1"
      },
      "type": "terms"
    }
  ],
  "metrics": [
    {
      "id": "1",
      "type": "count"
    }
  ],
  "query": "",
  "timeField": "@timestamp"
}
```

### Pie Chart - Protocol Distribution
```json
{
  "bucketAggs": [
    {
      "field": "suricata.eve.proto.keyword",
      "id": "2",
      "settings": {
        "min_doc_count": 1,
        "order": "desc",
        "orderBy": "_count",
        "size": "10"
      },
      "type": "terms"
    }
  ],
  "metrics": [
    {
      "id": "1",
      "type": "count"
    }
  ],
  "query": "suricata.eve.event_type.keyword:*",
  "timeField": "@timestamp"
}
```

### Bar Chart - Top Ports
```json
{
  "bucketAggs": [
    {
      "field": "suricata.eve.dest_port",
      "id": "2",
      "settings": {
        "min_doc_count": 1,
        "order": "desc",
        "orderBy": "_count",
        "size": "20"
      },
      "type": "terms"
    }
  ],
  "metrics": [
    {
      "id": "1",
      "type": "count"
    }
  ],
  "query": "",
  "timeField": "@timestamp"
}
```

### Timeseries - Events by Type
```json
{
  "bucketAggs": [
    {
      "field": "@timestamp",
      "id": "2",
      "settings": {
        "interval": "auto"
      },
      "type": "date_histogram"
    },
    {
      "field": "suricata.eve.event_type.keyword",
      "id": "3",
      "settings": {
        "min_doc_count": 1,
        "order": "desc",
        "orderBy": "_count",
        "size": "10"
      },
      "type": "terms"
    }
  ],
  "metrics": [
    {
      "id": "1",
      "type": "count"
    }
  ],
  "query": "",
  "timeField": "@timestamp"
}
```

## Testing Procedure

1. **Backup current dashboard:**
   ```bash
   ./scripts/export-dashboard.sh suricata-complete dashboards/suricata-complete-v1-backup.json
   ```

2. **Create test dashboard in Grafana UI:**
   - Add new dashboard
   - Test each panel type one by one
   - Document which work, which don't

3. **Build incrementally:**
   - Start with 1-2 panels
   - Test thoroughly
   - Add more only when previous ones work

4. **Export working dashboard:**
   ```bash
   ./scripts/export-dashboard.sh suricata-improved dashboards/suricata-improved.json
   ```

## Compatibility Matrix (To Be Filled)

| Panel Type | Works? | Notes |
|------------|--------|-------|
| stat | ❓ | Test first |
| piechart (native) | ❓ | Test with protocol query |
| barchart | ❓ | Fallback for pie |
| table | ✅ | Confirmed working |
| timeseries | ✅ | Confirmed working |
| geomap | ❓ | Test if geo data available |
| gauge | ❓ | Test with count metrics |
| heatmap | ❓ | Test later |

## Expected Challenges

1. **Datasource compatibility** - grafana-opensearch-datasource may not support all query types
2. **Aggregation format** - Query format may differ from Elasticsearch
3. **Field mapping** - Need `.keyword` suffix for term aggregations
4. **Geo data** - May need GeoIP enrichment for location-based panels

## Fallback Strategy

If pie charts don't work:
1. Use horizontal bar charts (just as effective)
2. Focus on tables and timeseries (proven to work)
3. Use stat panels for single values
4. Document limitations for future reference

## Success Criteria

✅ **Minimum Viable Dashboard:**
- 4+ stat panels (key metrics)
- 2+ timeseries (trends over time)
- 1+ table (event details)
- Clean layout, readable

✅ **Enhanced Dashboard:**
- Above + pie or bar charts
- Distribution visualizations
- Multi-interface filtering

✅ **Advanced Dashboard:**
- Above + geographic visualization
- Heatmaps for patterns
- Advanced filtering/variables

## Next Steps

**Immediate:**
1. Run `./scripts/test-panel-compatibility.sh` (done)
2. Log into Grafana Web UI
3. Create new test dashboard
4. Test one panel type at a time

**This Week:**
1. Document what works in compatibility matrix
2. Build improved dashboard with working panels
3. Export and commit to repository
4. Update documentation

**Future:**
1. Add dashboard variables for filtering
2. Create additional dashboards for specific use cases
3. Set up alerting rules
4. Performance optimization
