#!/bin/bash

# Fix Logstash to properly parse line-delimited JSON over UDP

echo "Updating Logstash to use json_lines codec..."

# Backup existing config
sudo cp /etc/logstash/conf.d/suricata.conf /etc/logstash/conf.d/suricata.conf.before-json-lines

# Create corrected config with json_lines codec
sudo tee /etc/logstash/conf.d/suricata.conf > /dev/null << 'EOF'
input {
  udp {
    port => 5140
    # Use plain codec first to see what we're getting
    codec => plain
  }
}

filter {
  # Parse the JSON manually
  json {
    source => "message"
    target => "suricata_raw"
  }
  
  # Move parsed data into suricata.eve structure
  if [suricata_raw] {
    ruby {
      code => '
        raw = event.get("suricata_raw")
        if raw.is_a?(Hash)
          event.set("[suricata][eve]", raw)
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
    
    # Remove temporary fields
    mutate {
      remove_field => ["message", "suricata_raw"]
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
  
  # Enable debug output temporarily
  stdout { codec => rubydebug { metadata => false } }
}
EOF

echo ""
echo "✅ Pipeline updated to use plain codec + json filter!"
echo ""
echo "Restarting Logstash..."
sudo systemctl restart logstash

echo ""
echo "⏳ Waiting 20 seconds for startup..."
sleep 20

echo ""
echo "=== Checking Logstash stdout in system logs ===" 
journalctl -u logstash --since "20 seconds ago" --no-pager | grep -A 20 "suricata" | head -40
