#!/bin/bash

echo "=== Checking Current Logstash Config ==="
sudo cat /etc/logstash/conf.d/suricata.conf

echo ""
echo ""
echo "=== Force Restart Logstash ==="
sudo systemctl stop logstash
sleep 5
sudo systemctl start logstash

echo ""
echo "⏳ Waiting 20 seconds for full startup..."
sleep 20

echo ""
echo "=== Logstash Status ==="
systemctl status logstash --no-pager | head -12

echo ""
echo "=== Port Check ==="
ss -ulnp | grep 5140

echo ""
echo "=== Wait 10 more seconds for data flow ==="
sleep 10

echo ""
echo "=== New Data Check ==="
curl -s "http://localhost:9200/suricata-*/_count" | jq .

echo ""
echo "=== Latest Document ==="
curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source | {
  timestamp: .["@timestamp"],
  event_type: .suricata.eve.event_type,
  src_ip: .suricata.eve.src_ip,
  dest_ip: .suricata.eve.dest_ip,
  proto: .suricata.eve.proto,
  has_suricata_eve: (.suricata.eve != null and .suricata.eve != {})
}'
