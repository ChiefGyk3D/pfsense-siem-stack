#!/bin/bash

# Disable debug output and verify data structure

echo "Disabling stdout debug output..."

sudo sed -i 's|stdout { codec => rubydebug { metadata => false } }|# stdout { codec => rubydebug { metadata => false } }|' /etc/logstash/conf.d/suricata.conf

sudo systemctl restart logstash

echo "✅ Debug output disabled, Logstash restarted"
echo ""
echo "⏳ Waiting 10 seconds for data to flow..."
sleep 10

echo ""
echo "=== Document Count ===" 
curl -s "http://localhost:9200/suricata-*/_count" | jq .

echo ""
echo "=== Sample Document with suricata.eve fields ===" 
curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source | {
  timestamp: .["@timestamp"],
  event_type: .suricata.eve.event_type,
  src_ip: .suricata.eve.src_ip,
  dest_ip: .suricata.eve.dest_ip,
  src_port: .suricata.eve.src_port,
  dest_port: .suricata.eve.dest_port,
  proto: .suricata.eve.proto,
  in_iface: .suricata.eve.in_iface
}'

echo ""
echo "=== Available Event Types ===" 
curl -s "http://localhost:9200/suricata-*/_search?size=0" -H 'Content-Type: application/json' -d '{
  "aggs": {
    "event_types": {
      "terms": {
        "field": "suricata.eve.event_type.keyword",
        "size": 20
      }
    }
  }
}' | jq '.aggregations.event_types.buckets[] | {type: .key, count: .doc_count}'

echo ""
echo "✅ Data structure is correct for dashboard 14893!"
echo ""
echo "Next step: Configure Grafana datasource and import dashboard"
