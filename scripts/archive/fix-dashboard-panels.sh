#!/bin/bash

DS_UID="bf53unpmdj0u8c"

echo "Creating fixed Suricata dashboard..."

cat > /tmp/suricata-dashboard-fixed.json << 'DASHEOF'
{
  "dashboard": {
    "title": "Suricata IDS/IPS Dashboard",
    "uid": "suricata-final-working",
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
        "gridPos": {"h": 5, "w": 6, "x": 0, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"]
          },
          "text": {}
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"}
              ]
            },
            "unit": "short"
          }
        }
      },
      {
        "id": 2,
        "type": "stat",
        "title": "Alerts",
        "gridPos": {"h": 5, "w": 6, "x": 6, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:alert",
            "alias": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"]
          }
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "thresholds"},
            "thresholds": {
              "mode": "absolute",
              "steps": [
                {"value": null, "color": "green"},
                {"value": 1, "color": "yellow"},
                {"value": 10, "color": "red"}
              ]
            },
            "unit": "short"
          }
        }
      },
      {
        "id": 3,
        "type": "stat",
        "title": "Unique Source IPs",
        "gridPos": {"h": 5, "w": 6, "x": 12, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "",
            "metrics": [{"id": "1", "type": "cardinality", "field": "suricata.eve.src_ip.keyword"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"]
          }
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "short"
          }
        }
      },
      {
        "id": 4,
        "type": "stat",
        "title": "Unique Dest IPs",
        "gridPos": {"h": 5, "w": 6, "x": 18, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "",
            "metrics": [{"id": "1", "type": "cardinality", "field": "suricata.eve.dest_ip.keyword"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "reduceOptions": {
            "values": false,
            "calcs": ["lastNotNull"]
          }
        },
        "fieldConfig": {
          "defaults": {
            "color": {"mode": "palette-classic"},
            "unit": "short"
          }
        }
      },
      {
        "id": 5,
        "type": "timeseries",
        "title": "Events Over Time",
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 5},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "Events",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "date_histogram",
                "field": "@timestamp",
                "settings": {"interval": "auto", "min_doc_count": 0}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "tooltip": {"mode": "multi"},
          "legend": {"displayMode": "list", "placement": "bottom"}
        },
        "fieldConfig": {
          "defaults": {
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "fillOpacity": 10,
              "showPoints": "never"
            },
            "color": {"mode": "palette-classic"}
          }
        }
      },
      {
        "id": 6,
        "type": "piechart",
        "title": "Event Types",
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 13},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "{{term}}",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.event_type.keyword",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count", "missing": "N/A"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "legend": {
            "displayMode": "table",
            "placement": "right",
            "showLegend": true,
            "values": ["value", "percent"]
          },
          "pieType": "pie",
          "tooltip": {"mode": "single"}
        },
        "fieldConfig": {
          "defaults": {
            "unit": "short"
          }
        }
      },
      {
        "id": 7,
        "type": "table",
        "title": "Alert Signatures",
        "gridPos": {"h": 8, "w": 16, "x": 8, "y": 13},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:alert",
            "alias": "",
            "metrics": [{"id": "1", "type": "count", "field": "select field"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.alert.signature.keyword",
                "settings": {"size": "20", "order": "desc", "orderBy": "_count", "missing": "N/A"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "showHeader": true,
          "footer": {"show": false}
        },
        "fieldConfig": {
          "defaults": {
            "custom": {
              "align": "left"
            }
          }
        }
      },
      {
        "id": 8,
        "type": "table",
        "title": "Top Source IPs",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 21},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.src_ip.keyword",
                "settings": {"size": "15", "order": "desc", "orderBy": "_count", "missing": "N/A"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "showHeader": true
        }
      },
      {
        "id": 9,
        "type": "table",
        "title": "Top Destination IPs",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 21},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.dest_ip.keyword",
                "settings": {"size": "15", "order": "desc", "orderBy": "_count", "missing": "N/A"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "showHeader": true
        }
      },
      {
        "id": 10,
        "type": "piechart",
        "title": "Protocol Distribution",
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 29},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "{{term}}",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.proto.keyword",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count", "missing": "N/A"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "legend": {
            "displayMode": "table",
            "placement": "right",
            "showLegend": true,
            "values": ["value", "percent"]
          },
          "pieType": "pie",
          "tooltip": {"mode": "single"}
        }
      },
      {
        "id": 11,
        "type": "barchart",
        "title": "Top Destination Ports",
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 29},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.dest_port",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count", "missing": "N/A"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "orientation": "horizontal",
          "xTickLabelRotation": 0,
          "showValue": "always"
        }
      },
      {
        "id": 12,
        "type": "table",
        "title": "Alert Categories",
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 29},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:alert",
            "alias": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.alert.category.keyword",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count", "missing": "N/A"}
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

curl -s -X POST "http://localhost:3000/api/dashboards/db" -u "admin:admin" -H "Content-Type: application/json" -d @/tmp/suricata-dashboard-fixed.json | jq '{status, uid, url}'

echo ""
echo "✅ Fixed dashboard created!"
echo "URL: http://192.168.210.10:3000/d/suricata-final-working/suricata-ids-ips-dashboard"
