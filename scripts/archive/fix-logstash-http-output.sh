#!/bin/bash

# Use Logstash HTTP output to bypass Elasticsearch version check

echo "Switching to HTTP output for OpenSearch compatibility..."

sudo tee /etc/logstash/conf.d/suricata.conf > /dev/null << 'EOF'
input {
  udp {
    port => 5140
    codec => json
  }
}

filter {
  # Add suricata.eve prefix to all fields
  ruby {
    code => '
      suricata_eve = {}
      event.to_hash.each do |key, value|
        next if key.start_with?("@") || ["host", "port"].include?(key)
        suricata_eve[key] = value
      end
      event.set("[suricata][eve]", suricata_eve)
    '
  }
  
  # Add @timestamp from suricata timestamp if available
  if [timestamp] {
    date {
      match => [ "timestamp", "ISO8601" ]
      target => "@timestamp"
    }
  }
}

output {
  # Use HTTP output to bypass Elasticsearch version check
  http {
    url => "http://localhost:9200/suricata-%{+YYYY.MM.dd}/_doc"
    http_method => "post"
    format => "json"
  }
}
EOF

echo "Restarting Logstash..."
sudo systemctl restart logstash

echo ""
echo "Waiting 30 seconds for Logstash to start..."
sleep 30

echo ""
echo "Checking Logstash status..."
systemctl is-active logstash && echo "✓ Logstash is running" || echo "✗ Logstash failed"

echo ""
echo "Checking if port 5140 is listening..."
ss -ulnp | grep 5140 && echo "✓ Port 5140 is listening" || echo "✗ Port 5140 not listening"

echo ""
echo "Wait 30 more seconds for data to flow, then check:"
echo "  curl 'http://localhost:9200/suricata-*/_count'"
