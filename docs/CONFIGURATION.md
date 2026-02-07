# Configuration Reference

Detailed reference for all configuration files in the Suricata monitoring stack.

## Table of Contents
- [OpenSearch Configuration](#opensearch-configuration)
- [Logstash Configuration](#logstash-configuration)
- [Grafana Configuration](#grafana-configuration)
- [pfSense Forwarder Configuration](#pfsense-forwarder-configuration)

## OpenSearch Configuration

### File Location
`/etc/opensearch/opensearch.yml`

### Key Settings

```yaml
# Cluster identification
cluster.name: suricata-cluster
node.name: node-1

# Paths
path.data: /var/lib/opensearch      # Data storage
path.logs: /var/log/opensearch      # Log files

# Network
network.host: 0.0.0.0               # Listen on all interfaces
http.port: 9200                     # HTTP API port
transport.port: 9300                # Internal transport port

# Discovery (single-node setup)
discovery.type: single-node          # No clustering

# Security (disabled for simplicity)
plugins.security.disabled: true      # Enable in production!

# Performance
bootstrap.memory_lock: true          # Lock memory to prevent swapping
```

### JVM Heap Configuration

**File:** `/etc/opensearch/jvm.options.d/heap.options`

```
# Set heap size to 50% of system RAM (max 31GB)
# For 32GB system:
-Xms6g
-Xmx6g

# For 16GB system:
-Xms4g
-Xmx4g
```

**Rules:**
- Set min and max to same value
- Use 50% of available RAM
- Never exceed 31GB (Java compressed pointers limit)
- Leave at least 50% RAM for OS and page cache

### System Limits

**File:** `/etc/security/limits.conf`

```
* soft nofile 65536
* hard nofile 65536
* soft memlock unlimited
* hard memlock unlimited
```

**File:** `/etc/sysctl.conf`

```
vm.max_map_count=262144
net.core.rmem_max=33554432
```

Apply with: `sudo sysctl -p`

### Common Tunables

**Increase query performance:**
```yaml
# /etc/opensearch/opensearch.yml
thread_pool.search.size: 30
thread_pool.search.queue_size: 10000
```

**Reduce memory pressure:**
```yaml
indices.memory.index_buffer_size: 20%
indices.fielddata.cache.size: 25%
```

**Increase bulk indexing performance:**
```yaml
thread_pool.bulk.size: 8
thread_pool.bulk.queue_size: 1000
```

## Logstash Configuration

### Pipeline Configuration

**File:** `/etc/logstash/conf.d/suricata.conf`

```ruby
input {
  udp {
    port => 5140                      # Listening port
    codec => plain                    # No pre-parsing
    buffer_size => 65536              # UDP receive buffer (64KB)
    receive_buffer_bytes => 33554432  # OS socket buffer (32MB)
    workers => 2                      # Number of UDP listeners
  }
}

filter {
  # Parse JSON from event.original field
  # UDP codec => plain populates event.original but not message
  if [event][original] {
    json {
      source => "[event][original]"
      target => "suricata_raw"
      tag_on_failure => ["_jsonparsefailure"]
    }
  } else if [message] {
    # Fallback to message field
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
    
    # Parse Suricata timestamp to @timestamp
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
  
  # Add index date for daily indices
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
  
  # Optional: Debug output (comment out in production)
  # stdout { codec => rubydebug }
}
```

### Main Configuration

**File:** `/etc/logstash/logstash.yml`

```yaml
# Pipeline settings
pipeline.workers: 2                  # Number of filter/output workers
pipeline.batch.size: 125             # Events per batch
pipeline.batch.delay: 50             # Max wait time (ms)

# Performance
pipeline.unsafe_shutdown: false      # Wait for in-flight events on shutdown
pipeline.ordered: auto               # Maintain event order when possible

# Monitoring
monitoring.enabled: false            # Disable if not using Elastic monitoring
```

### JVM Heap Configuration

**File:** `/etc/logstash/jvm.options`

```
# Set heap to 25% of system RAM (min 1GB, max 8GB)
-Xms1g
-Xmx1g
```

### Common Filter Patterns

**Add geographic location:**
```ruby
if [suricata][eve][src_ip] {
  geoip {
    source => "[suricata][eve][src_ip]"
    target => "[suricata][eve][geoip][src]"
  }
}
```

**Add custom tags:**
```ruby
if [suricata][eve][alert][severity] <= 2 {
  mutate {
    add_tag => ["high_severity"]
  }
}
```

**Enrich with threat intelligence:**
```ruby
translate {
  field => "[suricata][eve][src_ip]"
  destination => "[threat][status]"
  dictionary_path => "/etc/logstash/threat_ips.yml"
}
```

## Grafana Configuration

### Main Configuration

**File:** `/etc/grafana/grafana.ini`

Key sections:

```ini
[server]
protocol = http
http_port = 3000
domain = YOUR_DOMAIN
root_url = %(protocol)s://%(domain)s:%(http_port)s/

[security]
admin_user = admin
admin_password = CHANGE_ME
disable_gravatar = true

[auth.anonymous]
enabled = false

[analytics]
reporting_enabled = false
check_for_updates = false

[log]
mode = console file
level = info

[paths]
data = /var/lib/grafana
logs = /var/log/grafana
plugins = /var/lib/grafana/plugins
```

### Datasource Configuration (JSON)

**OpenSearch-Suricata:**
```json
{
  "name": "OpenSearch-Suricata",
  "type": "grafana-opensearch-datasource",
  "access": "proxy",
  "url": "http://localhost:9200",
  "basicAuth": false,
  "jsonData": {
    "database": "suricata-*",
    "timeField": "@timestamp",
    "version": "2.19.4",
    "flavor": "opensearch",
    "pplEnabled": false,
    "logMessageField": "message",
    "logLevelField": ""
  }
}
```

**OpenSearch-pfBlockerNG:**
```json
{
  "name": "OpenSearch-pfBlockerNG",
  "type": "grafana-opensearch-datasource",
  "access": "proxy",
  "url": "http://localhost:9200",
  "basicAuth": false,
  "jsonData": {
    "database": "pfblockerng-*",
    "timeField": "@timestamp",
    "version": "2.19.4",
    "flavor": "opensearch",
    "pplEnabled": false
  }
}
```

> **Note:** pfBlockerNG data is sent by Telegraf's `[[outputs.opensearch]]` plugin directly to OpenSearch. Do NOT use the `[[outputs.elasticsearch]]` plugin — it is incompatible with OpenSearch 2.x.

### Dashboard Variables

Useful variables for filtering:

**Interface:**
```
Type: Query
Query: {"find": "terms", "field": "suricata.eve.in_iface.keyword"}
Multi-value: true
Include All option: true
```

**Event Type:**
```
Type: Query
Query: {"find": "terms", "field": "suricata.eve.event_type.keyword"}
Multi-value: true
Include All option: true
```

**Source Network:**
```
Type: Custom
Values: 192.168.0.0/16,10.0.0.0/8,172.16.0.0/12
Multi-value: false
```

## pfSense Forwarder Configuration

### Python Forwarder

**File:** `/usr/local/bin/forward-suricata-eve-python.py`

**Configuration Variables:**
```python
GRAYLOG_SERVER = "192.168.210.10"  # SIEM server IP
GRAYLOG_PORT = 5140                # Logstash UDP port
```

**EVE JSON Path Detection:**
```python
def find_eve_log():
    """Auto-detects Suricata EVE JSON file"""
    matches = glob.glob("/var/log/suricata/*/eve.json")
    if matches:
        return matches[0]  # Returns first match
    return None
```

**Tuning Parameters:**
```python
# Adjust sleep time between reads (default 0.1 seconds)
time.sleep(0.1)  # Increase to reduce CPU usage

# Adjust socket buffer (advanced)
sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 65536)
```

### Watchdog Script

**File:** `/usr/local/bin/suricata-forwarder-watchdog.sh`

**Configuration:**
```bash
FORWARDER_SCRIPT="/usr/local/bin/forward-suricata-eve.sh"
PYTHON_SCRIPT="/usr/local/bin/forward-suricata-eve-python.py"
LOG_TAG="suricata-forwarder-watchdog"
```

**Cron Schedule:**
```
* * * * *  # Every minute
```

Change to run less frequently:
```
*/5 * * * *  # Every 5 minutes
*/15 * * * * # Every 15 minutes
```

### Suricata Configuration (pfSense)

**Enable EVE JSON Output:**

In pfSense: Services → Suricata → Interface Settings → EVE Output Settings

```yaml
eve-log:
  enabled: yes
  filetype: regular
  filename: eve.json
  types:
    - alert:
        tagged-packets: yes
    - http:
        extended: yes
    - dns:
        query: yes
        answer: yes
    - tls:
        extended: yes
    - files:
        force-magic: yes
    - ssh
    - stats:
        totals: yes
        threads: yes
    - flow
```

**Critical Settings:**
- ✅ Eve JSON log: Enabled
- ✅ File type: regular
- ✅ Log types: alert, http, dns, tls, files (at minimum)

## Field Reference

### Suricata EVE JSON Fields

Common fields available for querying:

```
suricata.eve.timestamp         # Original Suricata timestamp
suricata.eve.flow_id           # Flow identifier
suricata.eve.in_iface          # Interface name (e.g., "ix0")
suricata.eve.event_type        # alert, dns, http, tls, quic, etc.
suricata.eve.src_ip            # Source IP address
suricata.eve.src_port          # Source port
suricata.eve.dest_ip           # Destination IP address
suricata.eve.dest_port         # Destination port
suricata.eve.proto             # TCP, UDP, ICMP, etc.

# Alert-specific fields
suricata.eve.alert.signature   # Alert signature text
suricata.eve.alert.category    # Alert category
suricata.eve.alert.severity    # 1-4 (1=critical, 4=low)
suricata.eve.alert.gid         # Generator ID
suricata.eve.alert.sid         # Signature ID

# DNS-specific fields
suricata.eve.dns.type          # query or answer
suricata.eve.dns.rrname        # Domain name
suricata.eve.dns.rrtype        # A, AAAA, CNAME, etc.
suricata.eve.dns.rcode         # Response code

# TLS-specific fields
suricata.eve.tls.sni           # Server Name Indication
suricata.eve.tls.version       # TLS version
suricata.eve.tls.subject       # Certificate subject
suricata.eve.tls.issuerdn      # Certificate issuer

# HTTP-specific fields
suricata.eve.http.hostname     # HTTP Host header
suricata.eve.http.url          # Request URL
suricata.eve.http.http_method  # GET, POST, etc.
suricata.eve.http.status       # HTTP status code
suricata.eve.http.http_user_agent  # User agent string
```

## Performance Tuning

### For High Event Rate (>1000/sec)

**OpenSearch:**
```yaml
# /etc/opensearch/opensearch.yml
indices.memory.index_buffer_size: 30%
thread_pool.bulk.queue_size: 2000
```

**Logstash:**
```yaml
# /etc/logstash/logstash.yml
pipeline.workers: 4
pipeline.batch.size: 250
pipeline.batch.delay: 50
```

**Logstash suricata.conf:**
```ruby
input {
  udp {
    workers => 4  # Increase UDP listeners
    receive_buffer_bytes => 134217728  # 128MB
  }
}
```

### For Low Resource Systems

**OpenSearch heap:**
```
-Xms2g
-Xmx2g
```

**Logstash heap:**
```
-Xms512m
-Xmx512m
```

**Reduce retention:**
```bash
# Delete indices older than 7 days instead of 30
```

## Environment Variables

### OpenSearch
```bash
OPENSEARCH_JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
OPENSEARCH_PATH_CONF=/etc/opensearch
```

### Logstash
```bash
LS_HOME=/usr/share/logstash
LS_SETTINGS_DIR=/etc/logstash
LS_JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
```

### Grafana
```bash
GF_PATHS_DATA=/var/lib/grafana
GF_PATHS_LOGS=/var/log/grafana
GF_PATHS_PLUGINS=/var/lib/grafana/plugins
```

## Backup and Restore

### OpenSearch Indices
```bash
# Backup
curl -X PUT "http://localhost:9200/_snapshot/my_backup" -H 'Content-Type: application/json' -d'
{
  "type": "fs",
  "settings": {
    "location": "/backup/opensearch"
  }
}'

# Create snapshot
curl -X PUT "http://localhost:9200/_snapshot/my_backup/snapshot_1?wait_for_completion=true"
```

### Grafana Dashboards
```bash
# Export dashboard
curl -s -H "Authorization: Bearer YOUR_API_KEY" \
  http://localhost:3000/api/dashboards/uid/suricata-complete | \
  jq .dashboard > dashboard-backup.json

# Import dashboard
curl -X POST -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -d @dashboard-backup.json \
  http://localhost:3000/api/dashboards/db
```

### Configuration Files
```bash
# Backup all configs
tar -czf config-backup.tar.gz \
  /etc/opensearch/opensearch.yml \
  /etc/logstash/conf.d/ \
  /etc/grafana/grafana.ini \
  /usr/local/bin/forward-suricata-eve-python.py
```

## See Also

- [Installation Guide](INSTALL_SIEM_STACK.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [pfSense Forwarder Setup](INSTALL_PFSENSE_FORWARDER.md)
