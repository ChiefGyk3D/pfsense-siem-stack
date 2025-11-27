#!/bin/bash

# Fix UDP buffer size issue in Logstash
# Large Suricata EVE JSON events were being truncated

echo "Backing up current Logstash config..."
sudo cp /etc/logstash/conf.d/suricata.conf /etc/logstash/conf.d/suricata.conf.backup.$(date +%Y%m%d-%H%M%S)

echo "Applying fixed config with larger UDP buffers..."
sudo cp /tmp/suricata-fixed.conf /etc/logstash/conf.d/suricata.conf

echo "Restarting Logstash..."
sudo systemctl restart logstash

echo "Waiting for Logstash to start..."
sleep 15

echo ""
echo "Checking Logstash status..."
sudo systemctl status logstash --no-pager | head -15

echo ""
echo "Waiting 10 seconds for new data..."
sleep 10

echo ""
echo "Checking if JSON parsing is working now..."
curl -s "http://localhost:9200/suricata-*/_search?size=2&sort=@timestamp:desc" | jq '.hits.hits[] | {
  timestamp: ._source["@timestamp"], 
  has_suricata_eve: (._source.suricata.eve != null and (._source.suricata.eve | keys | length) > 0),
  event_type: ._source.suricata.eve.event_type,
  has_parse_failure: (._source.tags != null and (._source.tags | contains(["_jsonparsefailure"])))
}'

echo ""
echo "✅ If has_suricata_eve is true and has_parse_failure is false, the fix worked!"
