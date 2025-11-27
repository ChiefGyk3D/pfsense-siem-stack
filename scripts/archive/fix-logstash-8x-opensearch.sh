#!/bin/bash

# Fix Logstash 8.x elasticsearch output to work with OpenSearch

echo "Updating Logstash pipeline for OpenSearch compatibility..."

# Backup existing config
sudo cp /etc/logstash/conf.d/suricata.conf /etc/logstash/conf.d/suricata.conf.backup

# Create new config with compatibility settings
sudo tee /etc/logstash/conf.d/suricata.conf > /dev/null << 'EOF'
input {
  udp {
    port => 5140
    codec => json
  }
}

filter {
  # Create the nested suricata.eve structure
  ruby {
    code => '
      event.set("suricata", {}) if event.get("suricata").nil?
      event.set("suricata.eve", event.to_hash.select { |k,v| !["@timestamp", "@version", "host", "suricata"].include?(k) })
      
      # Clean up top-level fields (keep only essential ones)
      event.to_hash.keys.each do |key|
        unless ["@timestamp", "@version", "host", "suricata"].include?(key)
          event.remove(key)
        end
      end
    '
  }
  
  # Add @timestamp if not present
  if ![timestamp] {
    mutate {
      add_field => { "[@metadata][index_date]" => "%{+YYYY.MM.dd}" }
    }
  } else {
    date {
      match => [ "timestamp", "ISO8601" ]
      target => "@timestamp"
    }
    mutate {
      add_field => { "[@metadata][index_date]" => "%{+YYYY.MM.dd}" }
    }
  }
}

output {
  elasticsearch {
    hosts => ["http://localhost:9200"]
    index => "suricata-%{[@metadata][index_date]}"
    
    # Critical settings for OpenSearch compatibility
    ilm_enabled => false
    manage_template => false
    
    # Disable version check that causes the error
    ssl_certificate_verification => false
  }
  
  # Uncomment for debugging
  # stdout { codec => rubydebug }
}
EOF

echo ""
echo "✅ Pipeline config updated with OpenSearch compatibility settings!"
echo ""
echo "Restarting Logstash..."
sudo systemctl restart logstash

echo ""
echo "⏳ Waiting 20 seconds for startup..."
sleep 20

echo ""
echo "=== Logstash Status ==="
systemctl status logstash --no-pager -l | head -10

echo ""
echo "=== Port 5140 Status ==="
ss -ulnp | grep 5140

echo ""
echo "=== Recent Logs ==="
journalctl -u logstash --since "30 seconds ago" --no-pager | tail -20
