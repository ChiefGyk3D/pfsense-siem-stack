#!/bin/bash

# Fix Logstash HTTP output to use correct OpenSearch bulk API

echo "Fixing Logstash HTTP output for OpenSearch bulk API..."

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
  # Use HTTP output with bulk API
  http {
    url => "http://localhost:9200/_bulk"
    http_method => "post"
    format => "json_batch"
    content_type => "application/x-ndjson"
    mapping => {
      "index" => "suricata-%{+YYYY.MM.dd}"
    }
  }
}
EOF

echo "Restarting Logstash..."
sudo systemctl restart logstash

echo ""
echo "Wait 30 seconds, then check for data:"
echo "  curl 'http://localhost:9200/suricata-*/_count'"
