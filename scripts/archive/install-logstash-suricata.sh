#!/bin/bash

# Install Logstash and configure it to read Suricata EVE JSON
# and send to OpenSearch with proper field structure

set -e

echo "Stopping Filebeat (we'll use Logstash instead)..."
sudo systemctl stop filebeat
sudo systemctl disable filebeat

echo "Installing Logstash..."
sudo apt-get install -y logstash

echo "Creating Logstash pipeline for Suricata..."

# Create Logstash pipeline that reads from UDP, parses JSON, and adds suricata.eve prefix
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
  }
  
  # Debug output
  stdout {
    codec => rubydebug {
      metadata => false
    }
  }
}
EOF

echo "Starting Logstash..."
sudo systemctl enable logstash
sudo systemctl start logstash

echo ""
echo "✅ Logstash installed and configured!"
echo ""
echo "Logstash is now:"
echo "  - Listening on UDP 5140 for EVE JSON from pfSense"
echo "  - Parsing JSON and adding suricata.eve.* field structure"
echo "  - Sending to OpenSearch index: suricata-*"
echo ""
echo "Next steps:"
echo "  1. Wait 60 seconds for Logstash to start up"
echo "  2. Check: curl 'http://localhost:9200/suricata-*/_search?size=1' | jq"
echo "  3. Verify fields: curl 'http://localhost:9200/suricata-*/_search?size=1' | jq '.hits.hits[0]._source.suricata.eve | keys'"
