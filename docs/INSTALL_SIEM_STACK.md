# SIEM Stack Installation Guide

Complete guide for installing OpenSearch, Logstash, and Grafana on Ubuntu 24.04 LTS.

## Prerequisites

- Ubuntu 24.04 LTS server
- Root or sudo access
- 16GB+ RAM (32GB recommended)
- 500GB+ storage
- Static IP address configured

## Installation Steps

### 1. System Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget gnupg2 apt-transport-https software-properties-common

# Set system limits for OpenSearch
echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
echo "* soft memlock unlimited" | sudo tee -a /etc/security/limits.conf
echo "* hard memlock unlimited" | sudo tee -a /etc/security/limits.conf

# Disable swap for better performance
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Set vm.max_map_count for OpenSearch
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 2. Install Java (Required for OpenSearch and Logstash)

```bash
# Install OpenJDK 21
sudo apt install -y openjdk-21-jdk

# Verify installation
java -version
```

### 3. Install OpenSearch 2.19.4

```bash
# Download and install OpenSearch
cd /tmp
wget https://artifacts.opensearch.org/releases/bundle/opensearch/2.19.4/opensearch-2.19.4-linux-x64.deb
sudo dpkg -i opensearch-2.19.4-linux-x64.deb

# Configure OpenSearch
sudo tee /etc/opensearch/opensearch.yml > /dev/null <<EOF
cluster.name: suricata-cluster
node.name: node-1
path.data: /var/lib/opensearch
path.logs: /var/log/opensearch
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node

# Disable security for simplicity (enable in production)
plugins.security.disabled: true

# Performance settings
bootstrap.memory_lock: true
EOF

# Set heap size (50% of RAM, max 31GB)
# For 32GB RAM system, use 16GB
sudo tee /etc/opensearch/jvm.options.d/heap.options > /dev/null <<EOF
-Xms6g
-Xmx6g
EOF

# Enable and start OpenSearch
sudo systemctl daemon-reload
sudo systemctl enable opensearch
sudo systemctl start opensearch

# Wait for OpenSearch to start
sleep 30

# Verify OpenSearch is running
curl -X GET http://localhost:9200
```

Expected output:
```json
{
  "name" : "node-1",
  "cluster_name" : "suricata-cluster",
  "version" : {
    "number" : "2.19.4"
  }
}
```

### 4. Install Logstash 8.19.7

```bash
# Add Elastic repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

# Install Logstash
sudo apt update
sudo apt install -y logstash

# Install OpenSearch output plugin
cd /usr/share/logstash
sudo bin/logstash-plugin install logstash-output-opensearch

# Create Suricata pipeline configuration
sudo tee /etc/logstash/conf.d/suricata.conf > /dev/null <<'EOF'
input {
  udp {
    port => 5140
    codec => plain
    buffer_size => 65536
    receive_buffer_bytes => 33554432
  }
}

filter {
  # Parse JSON from event.original (UDP codec => plain populates this)
  if [event][original] {
    json {
      source => "[event][original]"
      target => "suricata_raw"
      tag_on_failure => ["_jsonparsefailure"]
    }
  } else if [message] {
    # Fallback to message field if event.original not present
    json {
      source => "message"
      target => "suricata_raw"
      tag_on_failure => ["_jsonparsefailure"]
    }
  }
  
  # Nest parsed data under suricata.eve
  if [suricata_raw] {
    ruby {
      code => '
        raw = event.get("suricata_raw")
        if raw.is_a?(Hash)
          event.set("[suricata][eve]", raw)
        end
      '
    }
    
    # Parse timestamp from Suricata event
    if [suricata][eve][timestamp] {
      date {
        match => [ "[suricata][eve][timestamp]", "ISO8601" ]
        target => "@timestamp"
      }
    }
    
    # Clean up temporary fields
    mutate {
      remove_field => ["message", "suricata_raw", "[event][original]"]
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
}
EOF

# Set UDP buffer size in system
echo "net.core.rmem_max=33554432" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Enable and start Logstash
sudo systemctl enable logstash
sudo systemctl start logstash

# Wait for Logstash to start
sleep 30

# Check Logstash status
sudo systemctl status logstash
```

### 5. Install Grafana 12.3.0

```bash
# Add Grafana repository
wget -q -O - https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana-keyring.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Install Grafana
sudo apt update
sudo apt install -y grafana

# Enable and start Grafana
sudo systemctl enable grafana-server
sudo systemctl start grafana-server

# Install OpenSearch datasource plugin
sudo grafana-cli plugins install grafana-opensearch-datasource

# Restart Grafana to load plugin
sudo systemctl restart grafana-server

# Check Grafana status
sudo systemctl status grafana-server
```

### 6. Configure Firewall

```bash
# Allow Grafana (3000), OpenSearch (9200), and Logstash UDP (5140)
sudo ufw allow 3000/tcp comment "Grafana"
sudo ufw allow 5140/udp comment "Logstash Suricata"
# Only allow OpenSearch from localhost (security)
# sudo ufw allow from 127.0.0.1 to any port 9200

# Enable firewall if not already enabled
sudo ufw --force enable
sudo ufw status
```

## Verification

### Check All Services

```bash
# Check OpenSearch
curl -s http://localhost:9200 | jq

# Check Logstash is listening on UDP 5140
sudo netstat -ulnp | grep 5140

# Check Grafana
curl -s http://localhost:3000/api/health

# View service logs
sudo journalctl -u opensearch -f       # OpenSearch logs
sudo journalctl -u logstash -f         # Logstash logs
sudo journalctl -u grafana-server -f   # Grafana logs
```

### Test Logstash Pipeline

```bash
# Send a test Suricata event
echo '{"timestamp":"2025-11-24T12:00:00.000000-0500","flow_id":123456,"event_type":"test","src_ip":"192.168.1.100","dest_ip":"8.8.8.8","proto":"UDP"}' | nc -u -w1 localhost 5140

# Wait 5 seconds for processing
sleep 5

# Check if event was indexed
curl -s "http://localhost:9200/suricata-*/_search?size=1" | jq '.hits.hits[0]._source.suricata.eve'
```

Expected output should show the test event with properly nested fields.

## Access Grafana

1. Open browser to `http://YOUR_SERVER_IP:3000`
2. Default credentials: `admin` / `admin`
3. Change password when prompted
4. Proceed to [Dashboard Installation Guide](INSTALL_DASHBOARD.md)

## Resource Usage

After installation, verify resource usage:

```bash
# Check memory usage
free -h

# Check disk usage
df -h

# Check service resource consumption
sudo systemctl status opensearch
sudo systemctl status logstash
sudo systemctl status grafana-server
```

Expected resource usage:
- OpenSearch: ~7-8GB RAM (6GB heap + overhead)
- Logstash: ~1-1.5GB RAM
- Grafana: ~200-500MB RAM

## Troubleshooting

### OpenSearch won't start
```bash
# Check logs
sudo journalctl -u opensearch -n 100

# Common issues:
# - Insufficient memory: Reduce heap size in /etc/opensearch/jvm.options.d/heap.options
# - vm.max_map_count too low: Run sudo sysctl -w vm.max_map_count=262144
```

### Logstash not receiving data
```bash
# Check if UDP port is open
sudo netstat -ulnp | grep 5140

# Check Logstash logs
sudo tail -f /var/log/logstash/logstash-plain.log

# Test UDP reception
sudo tcpdump -i any -n port 5140
```

### Grafana plugin not loading
```bash
# Reinstall plugin
sudo grafana-cli plugins install grafana-opensearch-datasource

# Restart Grafana
sudo systemctl restart grafana-server

# Check plugin directory
ls -la /var/lib/grafana/plugins/
```

## Next Steps

Continue to:
- **[pfSense Forwarder Installation](INSTALL_PFSENSE_FORWARDER.md)** - Set up log forwarding
- **[Dashboard Installation](INSTALL_DASHBOARD.md)** - Import Grafana dashboard

## Configuration Files Location

- OpenSearch config: `/etc/opensearch/opensearch.yml`
- OpenSearch heap: `/etc/opensearch/jvm.options.d/heap.options`
- Logstash pipeline: `/etc/logstash/conf.d/suricata.conf`
- Grafana config: `/etc/grafana/grafana.ini`
