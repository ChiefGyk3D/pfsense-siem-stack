#!/bin/bash

# Create OpenSearch index and update Logstash config to allow auto-creation

echo "Creating suricata index template in OpenSearch..."

# Create index template for suricata-* indices
curl -X PUT "http://localhost:9200/_index_template/suricata-template" -H 'Content-Type: application/json' -d'
{
  "index_patterns": ["suricata-*"],
  "template": {
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0,
      "index.mapping.total_fields.limit": 2000
    },
    "mappings": {
      "properties": {
        "@timestamp": { "type": "date" },
        "@version": { "type": "keyword" },
        "host": {
          "properties": {
            "ip": { "type": "ip" }
          }
        },
        "suricata": {
          "properties": {
            "eve": {
              "type": "object",
              "dynamic": true
            }
          }
        }
      }
    }
  }
}'

echo ""
echo ""
echo "✅ Index template created!"
echo ""
echo "Creating today's index..."

# Create today's index explicitly
TODAY=$(date +%Y.%m.%d)
curl -X PUT "http://localhost:9200/suricata-$TODAY"

echo ""
echo ""
echo "✅ Index created!"
echo ""
echo "Waiting 10 seconds for Logstash to retry..."
sleep 10

echo ""
echo "=== Checking data count ===" 
curl -s "http://localhost:9200/suricata-*/_count" | jq .

echo ""
echo "=== Checking indices ===" 
curl -s "http://localhost:9200/_cat/indices/suricata-*?v"
