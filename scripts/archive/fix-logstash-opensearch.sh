#!/bin/bash

# Fix Logstash configuration for OpenSearch compatibility

echo "Fixing Logstash configuration for OpenSearch..."

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
  elasticsearch {
    hosts => ["localhost:9200"]
    index => "suricata-%{+YYYY.MM.dd}"
    # Disable template and ILM for OpenSearch
    manage_template => false
    ilm_enabled => false
    # Critical: Skip version check for OpenSearch
    ecs_compatibility => disabled
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
systemctl status logstash --no-pager | head -15

echo ""
echo "Checking if port 5140 is listening..."
ss -ulnp | grep 5140 || echo "Port 5140 NOT listening yet"

echo ""
echo "Checking recent Logstash logs..."
journalctl -u logstash -n 10 --no-pager | tail -5
