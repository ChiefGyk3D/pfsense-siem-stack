#!/bin/bash

# Create comprehensive Suricata dashboard with correct query format
ssh chiefgyk3d@192.168.210.10 'cat > /tmp/suricata-full-dashboard.json << '\''DASHEOF'\''
{
  "dashboard": {
    "title": "Suricata IDS/IPS",
    "uid": "suricata-ids-final",
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "30s",
    "time": {
      "from": "now-6h",
      "to": "now"
    },
    "panels": [
      {
        "id": 1,
        "type": "stat",
        "title": "Total Events",
        "gridPos": {"h": 5, "w": 4, "x": 0, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "elasticsearch", "uid": "df53ub8014wsgf"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 1000, "color": "yellow"},
                {"value": 5000, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 2,
        "type": "stat",
        "title": "Alerts",
        "gridPos": {"h": 5, "w": 4, "x": 4, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "elasticsearch", "uid": "df53ub8014wsgf"},
            "query": "suricata.eve.event_type:alert",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 1, "color": "yellow"},
                {"value": 5, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 3,
        "type": "timeseries",
        "title": "Events Over Time",
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 5},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "elasticsearch", "uid": "df53ub8014wsgf"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "date_histogram",
                "field": "@timestamp",
                "settings": {"interval": "auto", "min_doc_count": "0"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "fillOpacity": 20
            }
          }
        }
      },
      {
        "id": 4,
        "type": "piechart",
        "title": "Event Types Distribution",
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 13},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "elasticsearch", "uid": "df53ub8014wsgf"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.event_type.keyword",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "legend": {"displayMode": "table", "placement": "right"},
          "pieType": "pie"
        }
      },
      {
        "id": 5,
        "type": "table",
        "title": "Alert Signatures",
        "gridPos": {"h": 8, "w": 16, "x": 8, "y": 13},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "elasticsearch", "uid": "df53ub8014wsgf"},
            "query": "suricata.eve.event_type:alert",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.alert.signature.keyword",
                "settings": {"size": "20", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ]
      },
      {
        "id": 6,
        "type": "table",
        "title": "Top Source IPs",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 21},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "elasticsearch", "uid": "df53ub8014wsgf"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.src_ip.keyword",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ]
      },
      {
        "id": 7,
        "type": "table",
        "title": "Top Destination IPs",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 21},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "elasticsearch", "uid": "df53ub8014wsgf"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.dest_ip.keyword",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ]
      }
    ]
  },
  "overwrite": true,
  "folderId": 0
}
DASHEOF

# Import the dashboard
curl -s -X POST "http://localhost:3000/api/dashboards/db" -u "admin:admin" -H "Content-Type: application/json" -d @/tmp/suricata-full-dashboard.json | jq "{status, uid, url}"
'
