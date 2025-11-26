#!/bin/bash

# Upgrade to Logstash 8.x OSS for better OpenSearch compatibility

set -e

echo "=== Upgrading to Logstash 8.x OSS ==="
echo ""

echo "Stopping current Logstash..."
sudo systemctl stop logstash

echo "Removing Logstash 7.x..."
sudo apt-get remove -y logstash

echo "Adding Elastic 8.x repository..."
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /tmp/elasticsearch-keyring.gpg
sudo mv /tmp/elasticsearch-keyring.gpg /usr/share/keyrings/elasticsearch-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

echo "Installing Logstash 8.x..."
sudo apt-get update
sudo apt-get install -y logstash

echo "Creating Logstash configuration for OpenSearch..."
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
  # Use native Elasticsearch output (works with OpenSearch)
  elasticsearch {
    hosts => ["http://localhost:9200"]
    index => "suricata-%{+YYYY.MM.dd}"
    # Disable ILM and other ES-specific features
    ilm_enabled => false
    manage_template => false
  }
}
EOF

echo "Starting Logstash 8.x..."
sudo systemctl enable logstash
sudo systemctl start logstash

echo ""
echo "✅ Logstash 8.x installed!"
echo ""
echo "Checking version..."
/usr/share/logstash/bin/logstash --version

echo ""
echo "Waiting 45 seconds for Logstash to start..."
sleep 45

echo ""
echo "Checking status..."
systemctl is-active logstash && echo "✓ Logstash is running" || echo "✗ Logstash failed"

echo ""
echo "Checking port 5140..."
ss -ulnp | grep 5140 && echo "✓ Port 5140 is listening" || echo "✗ Port not listening"

echo ""
echo "Wait 30 more seconds for data, then check:"
echo "  curl 'http://localhost:9200/suricata-*/_count'"
echo "  curl 'http://localhost:9200/suricata-*/_search?size=1' | jq '.hits.hits[0]._source.suricata.eve | keys'"
