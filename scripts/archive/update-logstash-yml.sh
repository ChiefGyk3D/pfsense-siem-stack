#!/bin/bash

# Update logstash.yml for Logstash 8.x and OpenSearch compatibility

echo "Updating /etc/logstash/logstash.yml for Logstash 8.x..."

# Backup original
sudo cp /etc/logstash/logstash.yml /etc/logstash/logstash.yml.backup

# Create optimized logstash.yml
sudo tee /etc/logstash/logstash.yml > /dev/null << 'EOF'
# Logstash 8.x configuration optimized for OpenSearch

# Pipeline settings
pipeline.workers: 2
pipeline.batch.size: 125
pipeline.batch.delay: 50

# API settings
api.http.host: "127.0.0.1"
api.http.port: 9600

# Log settings
log.level: info
path.logs: /var/log/logstash

# Config settings
path.config: /etc/logstash/conf.d/*.conf
config.reload.automatic: true
config.reload.interval: 3s

# Queue settings
queue.type: memory
queue.max_bytes: 1gb

# Disable monitoring to Elasticsearch (we're using OpenSearch)
xpack.monitoring.enabled: false

# Dead letter queue (optional, for failed events)
dead_letter_queue.enable: false
EOF

echo ""
echo "✅ logstash.yml updated!"
echo ""
echo "Key changes for Logstash 8.x + OpenSearch:"
echo "  - Disabled X-Pack monitoring (not compatible with OpenSearch)"
echo "  - Set pipeline workers to 2 (adjust based on CPU cores)"
echo "  - Enabled auto-config reload"
echo "  - Memory queue (1GB max)"
echo ""
echo "Restart Logstash for changes to take effect:"
echo "  sudo systemctl restart logstash"
