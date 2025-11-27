#!/bin/bash

echo "Installing OpenSearch datasource plugin for Grafana..."
sudo grafana-cli plugins install grafana-opensearch-datasource

echo ""
echo "Restarting Grafana..."
sudo systemctl restart grafana-server

echo ""
echo "Waiting for Grafana to start..."
sleep 15

echo ""
echo "Creating OpenSearch datasource..."
curl -s -X POST "http://localhost:3000/api/datasources" -u "admin:admin" -H "Content-Type: application/json" -d '{
  "name": "OpenSearch-Suricata-Native",
  "type": "grafana-opensearch-datasource",
  "access": "proxy",
  "url": "http://localhost:9200",
  "jsonData": {
    "database": "suricata-*",
    "timeField": "@timestamp",
    "version": "2.0.0",
    "pplEnabled": false,
    "logMessageField": "",
    "logLevelField": ""
  }
}' | jq '{id, uid, name}'

# Get the UID of the datasource
DS_UID=$(curl -s "http://localhost:3000/api/datasources/name/OpenSearch-Suricata-Native" -u "admin:admin" | jq -r '.uid')

echo ""
echo "Datasource created with UID: $DS_UID"
echo ""
echo "Creating dashboard with native OpenSearch plugin..."

cat > /tmp/opensearch-suricata-dashboard.json << DASHEOF
{
  "dashboard": {
    "title": "Suricata IDS/IPS - OpenSearch",
    "uid": "suricata-opensearch",
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
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ]
      },
      {
        "id": 2,
        "type": "stat",
        "title": "Alerts",
        "gridPos": {"h": 5, "w": 6, "x": 6, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
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
                {"value": 10, "color": "red"}
              ]
            }
          }
        }
      },
      {
        "id": 3,
        "type": "stat",
        "title": "Unique Src IPs",
        "gridPos": {"h": 5, "w": 6, "x": 12, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
            "query": "",
            "metrics": [{"id": "1", "type": "cardinality", "field": "suricata.eve.src_ip.keyword"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ]
      },
      {
        "id": 4,
        "type": "stat",
        "title": "Unique Dest IPs",
        "gridPos": {"h": 5, "w": 6, "x": 18, "y": 0},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
            "query": "",
            "metrics": [{"id": "1", "type": "cardinality", "field": "suricata.eve.dest_ip.keyword"}],
            "bucketAggs": [],
            "timeField": "@timestamp"
          }
        ]
      },
      {
        "id": 5,
        "type": "timeseries",
        "title": "Events Over Time",
        "gridPos": {"h": 8, "w": 24, "x": 0, "y": 5},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
            "query": "",
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
        ]
      },
      {
        "id": 6,
        "type": "piechart",
        "title": "Event Types",
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 13},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
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
        ]
      },
      {
        "id": 7,
        "type": "table",
        "title": "Alert Signatures",
        "gridPos": {"h": 8, "w": 16, "x": 8, "y": 13},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
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
        "id": 8,
        "type": "table",
        "title": "Top Source IPs",
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 21},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.src_ip.keyword",
                "settings": {"size": "15", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ]
      },
      {
        "id": 9,
        "type": "table",
        "title": "Top Destination IPs",
        "gridPos": {"h": 8, "w": 12, "x": 12, "y": 21},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
            "query": "",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.dest_ip.keyword",
                "settings": {"size": "15", "order": "desc", "orderBy": "_count"}
              }
            ],
            "timeField": "@timestamp"
          }
        ]
      },
      {
        "id": 10,
        "type": "piechart",
        "title": "Protocol Distribution",
        "gridPos": {"h": 8, "w": 8, "x": 0, "y": 29},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
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
        ]
      },
      {
        "id": 11,
        "type": "table",
        "title": "Alert Categories",
        "gridPos": {"h": 8, "w": 16, "x": 8, "y": 29},
        "targets": [
          {
            "refId": "A",
            "datasource": {"type": "grafana-opensearch-datasource", "uid": "${DS_UID}"},
            "query": "suricata.eve.event_type:alert",
            "metrics": [{"id": "1", "type": "count"}],
            "bucketAggs": [
              {
                "id": "2",
                "type": "terms",
                "field": "suricata.eve.alert.category.keyword",
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

curl -s -X POST "http://localhost:3000/api/dashboards/db" -u "admin:admin" -H "Content-Type: application/json" -d @/tmp/opensearch-suricata-dashboard.json | jq '{status, uid, url}'

echo ""
echo "✅ Setup complete!"
echo ""
echo "Dashboard URL: http://192.168.210.10:3000/d/suricata-opensearch/suricata-ids-ips-opensearch"
