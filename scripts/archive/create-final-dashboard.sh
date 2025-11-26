#!/bin/bash

DS_UID="bf53unpmdj0u8c"

echo "Creating comprehensive Suricata dashboard with working panel types..."

ssh chiefgyk3d@192.168.210.10 << 'SSHEOF'

cat > /tmp/suricata-complete-working.json << 'DASHEOF'
{
  "dashboard": {
    "title": "Suricata IDS/IPS Dashboard",
    "uid": "suricata-complete",
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
        "type": "timeseries",
        "title": "Events Over Time",
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "alias": "Total Events",
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
          },
          {
            "refId": "B",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:alert",
            "alias": "Alerts",
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
        "fieldConfig": {
          "defaults": {
            "custom": {
              "drawStyle": "line",
              "lineInterpolation": "smooth",
              "fillOpacity": 20,
              "showPoints": "never"
            },
            "color": {"mode": "palette-classic"}
          },
          "overrides": [
            {
              "matcher": {"id": "byName", "options": "Alerts"},
              "properties": [
                {
                  "id": "color",
                  "value": {"mode": "fixed", "fixedColor": "red"}
                }
              ]
            }
          ]
        },
        "options": {
          "tooltip": {"mode": "multi"},
          "legend": {"displayMode": "table", "placement": "bottom", "calcs": ["sum", "mean", "max"]}
        }
      },
      {
        "id": 2,
        "type": "table",
        "title": "Event Type Distribution",
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 8},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.event_type.keyword",
                "settings": {"size": "20", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "showHeader": true,
          "footer": {
            "show": true,
            "reducer": ["sum"]
          }
        },
        "fieldConfig": {
          "defaults": {
            "custom": {
              "align": "left",
              "cellOptions": {
                "type": "auto"
              }
            }
          }
        }
      },
      {
        "id": 3,
        "type": "table",
        "title": "Protocol Distribution",
        "gridPos": {"h": 8, "w": 8, "x": 8, "y": 8},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.proto.keyword",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "showHeader": true,
          "footer": {
            "show": true,
            "reducer": ["sum"]
          }
        }
      },
      {
        "id": 4,
        "type": "table",
        "title": "Interface Distribution",
        "gridPos": {"h": 8, "w": 8, "x": 16, "y": 8},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.in_iface.keyword",
                "settings": {"size": "10", "order": "desc", "orderBy": "_count"}
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
        "id": 5,
        "type": "table",
        "title": "Top Source IPs",
        "gridPos": {"h": 9, "w": 12, "x": 0, "y": 16},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.src_ip.keyword",
                "settings": {"size": "20", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "showHeader": true,
          "footer": {
            "show": true,
            "reducer": ["sum"]
          }
        }
      },
      {
        "id": 6,
        "type": "table",
        "title": "Top Destination IPs",
        "gridPos": {"h": 9, "w": 12, "x": 12, "y": 16},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.dest_ip.keyword",
                "settings": {"size": "20", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "showHeader": true,
          "footer": {
            "show": true,
            "reducer": ["sum"]
          }
        }
      },
      {
        "id": 7,
        "type": "table",
        "title": "Top Destination Ports",
        "gridPos": {"h": 9, "w": 8, "x": 0, "y": 25},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.dest_port",
                "settings": {"size": "15", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ],
        "options": {
          "showHeader": true,
          "footer": {
            "show": true,
            "reducer": ["sum"]
          }
        }
      },
      {
        "id": 8,
        "type": "table",
        "title": "TLS SNI (Server Names)",
        "gridPos": {"h": 9, "w": 8, "x": 8, "y": 25},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:tls",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.tls.sni.keyword",
                "settings": {"size": "15", "order": "desc", "orderBy": "_count"}
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
        "title": "DNS Queries (Top Domains)",
        "gridPos": {"h": 9, "w": 8, "x": 16, "y": 25},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:dns",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.dns.rrname.keyword",
                "settings": {"size": "15", "order": "desc", "orderBy": "_count"}
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
        "type": "table",
        "title": "HTTP Hosts",
        "gridPos": {"h": 9, "w": 12, "x": 0, "y": 34},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:http",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.http.hostname.keyword",
                "settings": {"size": "20", "order": "desc", "orderBy": "_count"}
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
        "id": 11,
        "type": "table",
        "title": "Alert Signatures",
        "gridPos": {"h": 9, "w": 12, "x": 12, "y": 34},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
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
        ],
        "options": {
          "showHeader": true
        }
      },
      {
        "id": 12,
        "type": "timeseries",
        "title": "Events by Type Over Time",
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 43},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:dns",
            "alias": "DNS",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "date_histogram",
                "field": "@timestamp",
                "settings": {"interval": "auto"}
              }
            ],
            "timeField": "@timestamp"
          },
          {
            "refId": "B",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:tls",
            "alias": "TLS",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "date_histogram",
                "field": "@timestamp",
                "settings": {"interval": "auto"}
              }
            ],
            "timeField": "@timestamp"
          },
          {
            "refId": "C",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:http",
            "alias": "HTTP",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "date_histogram",
                "field": "@timestamp",
                "settings": {"interval": "auto"}
              }
            ],
            "timeField": "@timestamp"
          },
          {
            "refId": "D",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "bf53unpmdj0u8c"},
            "query": "suricata.eve.event_type:alert",
            "alias": "Alerts",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "date_histogram",
                "field": "@timestamp",
                "settings": {"interval": "auto"}
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
              "fillOpacity": 10
            }
          }
        },
        "options": {
          "tooltip": {"mode": "multi"},
          "legend": {"displayMode": "table", "placement": "bottom", "calcs": ["sum", "mean"]}
        }
      }
    ]
  },
  "overwrite": true,
  "folderId": 0
}
DASHEOF

curl -s -X POST "http://localhost:3000/api/dashboards/db" -u "admin:admin" -H "Content-Type: application/json" -d @/tmp/suricata-complete-working.json | jq '{status, uid, url}'

SSHEOF

echo ""
echo "✅ Complete working dashboard created!"
echo "URL: http://192.168.210.10:3000/d/suricata-complete/suricata-ids-ips-dashboard"
