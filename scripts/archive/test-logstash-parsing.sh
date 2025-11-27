#!/bin/bash

# Test Logstash JSON parsing
# This script creates a test config to debug what's being received

echo "Creating test Logstash config..."
cat > /tmp/logstash-test.conf << 'EOF'
input {
  udp {
    port => 5141  # Different port for testing
    codec => plain
  }
}

filter {
  json {
    source => "message"
    target => "suricata_raw"
    tag_on_failure => ["_jsonparsefailure"]
  }
}

output {
  stdout { 
    codec => rubydebug { metadata => true } 
  }
}
EOF

echo ""
echo "Test config created. To test:"
echo "1. On pfSense, temporarily run:"
echo "   tail -3 /var/log/suricata/suricata_ix055721/eve.json | nc -u -w1 192.168.210.10 5141"
echo ""
echo "2. On SIEM server, run:"
echo "   /usr/share/logstash/bin/logstash -f /tmp/logstash-test.conf"
echo ""
echo "This will show you the raw data being received and whether JSON parsing succeeds."
