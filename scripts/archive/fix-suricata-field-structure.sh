#!/bin/bash

# Fix Logstash filter to properly structure Suricata EVE data

echo "Updating Logstash pipeline to properly handle Suricata EVE JSON..."

# Backup existing config
sudo cp /etc/logstash/conf.d/suricata.conf /etc/logstash/conf.d/suricata.conf.before-fix

# Create corrected config
sudo tee /etc/logstash/conf.d/suricata.conf > /dev/null << 'EOF'
input {
  udp {
    port => 5140
    codec => json
  }
}

filter {
  # The JSON codec already parsed the data, now nest it under suricata.eve
  ruby {
    code => '
      # Get all fields except @timestamp, @version, host
      eve_data = event.to_hash.select { |k,v| !["@timestamp", "@version", "host"].include?(k) }
      
      # Create the nested structure
      event.set("[suricata][eve]", eve_data)
      
      # Remove top-level fields (keep only @timestamp, @version, host, suricata)
      eve_data.keys.each do |key|
        event.remove(key)
      end
    '
  }
  
  # Handle timestamp from Suricata
  if [suricata][eve][timestamp] {
    date {
      match => [ "[suricata][eve][timestamp]", "ISO8601" ]
      target => "@timestamp"
    }
  }
  
  # Add index date metadata
  mutate {
    add_field => { "[@metadata][index_date]" => "%{+YYYY.MM.dd}" }
  }
}

output {
  opensearch {
    hosts => ["http://localhost:9200"]
    index => "suricata-%{[@metadata][index_date]}"
    ssl => false
    ssl_certificate_verification => false
  }
  
  # Uncomment for debugging
  # stdout { codec => rubydebug }
}
EOF

echo ""
echo "✅ Pipeline config fixed!"
echo ""
echo "Restarting Logstash..."
sudo systemctl restart logstash

echo ""
echo "⏳ Waiting 20 seconds for startup and data flow..."
sleep 20

echo ""
echo "=== Checking new data ===" 
echo "Document count:"
curl -s "http://localhost:9200/suricata-*/_count" | jq .

echo ""
echo "Sample document structure:"
curl -s "http://localhost:9200/suricata-*/_search?size=1&sort=@timestamp:desc" | jq '.hits.hits[0]._source | {
  timestamp: .["@timestamp"],
  event_type: .suricata.eve.event_type,
  src_ip: .suricata.eve.src_ip,
  dest_ip: .suricata.eve.dest_ip,
  proto: .suricata.eve.proto,
  all_eve_keys: .suricata.eve | keys | sort
}'
