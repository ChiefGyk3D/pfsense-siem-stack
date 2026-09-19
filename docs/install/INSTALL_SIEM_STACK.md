# SIEM Stack Installation Guide

Manual, step-by-step installation of OpenSearch, Logstash, and Grafana on Ubuntu 24.04 LTS.

> **This is the bare-metal, single-box path.** The recommended server side for this project is
> [siem-docker-stack](https://github.com/ChiefGyk3D/siem-docker-stack) (Docker, hot/warm tiers,
> ISM, Wazuh); `setup.sh` works against it or any existing OpenSearch + Grafana with no server
> install at all. Use `install.sh` / this page when you want everything on one Ubuntu host.

> **Most users should run `sudo ./install.sh` instead.** It performs every step on this
> page (same versions, same paths, same settings) with interactive prompts. This guide is
> the manual alternative — use it when you want to understand what the installer does, need
> to adapt a step to your environment, or are recovering a partially installed host. The
> layout documented here matches `install.sh`: OpenSearch from the official **tarball** in
> `/opt/opensearch`, Logstash from the Elastic apt repo, Grafana from the Grafana apt repo.

## Prerequisites

- Ubuntu 24.04 LTS server (tested; 22.04 should work)
- Root or sudo access
- 16 GB RAM minimum, 32 GB recommended (see [Hardware Requirements](HARDWARE_REQUIREMENTS.md))
- 100 GB+ SSD (500 GB+ for 30-day retention on busy networks)
- Static IP address configured

Versions installed by `install.sh` and documented here: **OpenSearch 2.19.4**, **Logstash 8.19.7**, **Grafana 12.3.0**.

InfluxDB and Prometheus are **not** installed by `install.sh` and are not required for the
Suricata dashboards. They are optional, separate installs used only by the pfSense system /
pfBlockerNG dashboard (see [Telegraf pfBlockerNG Setup](../pfsense/TELEGRAF_PFBLOCKER_SETUP.md)).

## Installation Steps

### 1. System Preparation

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl wget gnupg2 apt-transport-https software-properties-common \
                    jq python3 python3-pip net-tools

# Set system limits for OpenSearch
sudo tee -a /etc/security/limits.conf > /dev/null <<EOF
# OpenSearch/Logstash limits
* soft nofile 65536
* hard nofile 65536
* soft memlock unlimited
* hard memlock unlimited
EOF

# Kernel parameters for OpenSearch (install.sh keeps swap but sets swappiness=1)
sudo tee -a /etc/sysctl.conf > /dev/null <<EOF
# OpenSearch requirements
vm.max_map_count=262144
vm.swappiness=1
EOF
sudo sysctl -p
```

### 2. Install Java (Required for Logstash)

OpenSearch bundles its own JDK; Logstash uses the system JDK.

```bash
# Install OpenJDK 21
sudo apt install -y openjdk-21-jdk

# Verify installation
java -version
```

### 3. Install OpenSearch 2.19.4 (tarball to /opt/opensearch)

```bash
# Download and unpack the tarball
cd /tmp
wget https://artifacts.opensearch.org/releases/bundle/opensearch/2.19.4/opensearch-2.19.4-linux-x64.tar.gz
tar -xzf opensearch-2.19.4-linux-x64.tar.gz
sudo mv opensearch-2.19.4 /opt/opensearch

# Dedicated service user
sudo useradd -r -s /bin/bash -d /opt/opensearch opensearch || true
sudo chown -R opensearch:opensearch /opt/opensearch

# Configure OpenSearch (single node, security plugin disabled)
sudo tee /opt/opensearch/config/opensearch.yml > /dev/null <<EOF
cluster.name: pfsense-monitoring
node.name: siem-node-1
path.data: /opt/opensearch/data
path.logs: /opt/opensearch/logs
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
plugins.security.disabled: true
EOF

# Set heap size: 50% of RAM, capped at 16 GB by install.sh (never exceed 31 GB)
# Example for a 16 GB host:
sudo sed -i 's/-Xms1g/-Xms8g/; s/-Xmx1g/-Xmx8g/' /opt/opensearch/config/jvm.options

# systemd unit (this is what install.sh writes)
sudo tee /etc/systemd/system/opensearch.service > /dev/null <<EOF
[Unit]
Description=OpenSearch
Documentation=https://opensearch.org/
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=opensearch
Group=opensearch
Environment=OPENSEARCH_HOME=/opt/opensearch
Environment=OPENSEARCH_PATH_CONF=/opt/opensearch/config
WorkingDirectory=/opt/opensearch
ExecStart=/opt/opensearch/bin/opensearch
LimitNOFILE=65536
LimitNPROC=4096
LimitMEMLOCK=infinity

[Install]
WantedBy=multi-user.target
EOF

# Enable and start OpenSearch
sudo systemctl daemon-reload
sudo systemctl enable --now opensearch

# Wait for OpenSearch to start, then verify
sleep 30
curl -s http://localhost:9200
```

Expected output:
```json
{
  "name" : "siem-node-1",
  "cluster_name" : "pfsense-monitoring",
  "version" : {
    "number" : "2.19.4"
  }
}
```

> **Security warning.** With `network.host: 0.0.0.0` and `plugins.security.disabled: true`
> — the defaults `install.sh` uses — OpenSearch on port 9200 is reachable from the network
> **without authentication**. Restrict it with ufw to trusted hosts (see step 6) or enable
> the security plugin. Hardening this default is tracked in
> [ROADMAP.md, Phase A](../../ROADMAP.md).

> **.deb install instead?** If you install OpenSearch from the `.deb` package rather than
> the tarball, the config lives in `/etc/opensearch/opensearch.yml`, data in
> `/var/lib/opensearch`, logs in `/var/log/opensearch`, and heap is set in
> `/etc/opensearch/jvm.options.d/`. Adjust the paths in this guide accordingly.

### 4. Install Logstash 8.19.7

```bash
# Add Elastic repository
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | sudo gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | sudo tee /etc/apt/sources.list.d/elastic-8.x.list

# Install Logstash
sudo apt update
sudo apt install -y logstash

# Install OpenSearch output plugin
sudo /usr/share/logstash/bin/logstash-plugin install logstash-output-opensearch
```

**Deploy the Suricata pipeline.** Do not hand-write the pipeline: the file
`config/logstash-suricata.conf` in this repository is the single source of truth. It parses
each EVE JSON event to **flat root-level fields** (`event_type`, `src_ip`, `dest_ip`,
`alert.signature`, `in_iface`, `geoip_src.location`, ...), which is what the shipped
dashboards and the index template expect. Nothing is nested under `suricata.eve.*`.

```bash
# From your clone of the repository
sudo cp config/logstash-suricata.conf /etc/logstash/conf.d/suricata.conf

# Larger UDP receive buffer for bursty EVE traffic
echo "net.core.rmem_max=33554432" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Enable and start Logstash
sudo systemctl enable --now logstash

# Wait for Logstash to start, then check status
sleep 30
sudo systemctl status logstash
```

The pipeline listens on **UDP 5140** and writes daily indices named `suricata-YYYY.MM.dd`.
Also install the index template so `geoip_src.location` is mapped as `geo_point`:

```bash
./scripts/install-opensearch-config.sh    # or let setup.sh do it (step 2)
```

### 5. Install Grafana 12.3.0

```bash
# Add Grafana repository
wget -q -O - https://packages.grafana.com/gpg.key | sudo gpg --dearmor -o /usr/share/keyrings/grafana-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/grafana-keyring.gpg] https://packages.grafana.com/oss/deb stable main" | sudo tee /etc/apt/sources.list.d/grafana.list

# Install Grafana
sudo apt update
sudo apt install -y grafana

# Install OpenSearch datasource plugin
sudo grafana-cli plugins install grafana-opensearch-datasource

# Enable and start Grafana
sudo systemctl enable --now grafana-server
sudo systemctl status grafana-server
```

### 6. Configure Firewall

`install.sh` opens 9200/tcp, 5140/udp, 3000/tcp and SSH, then enables ufw. Because
OpenSearch has no authentication by default, tighten 9200 to the hosts that need it
(the SIEM server itself, and the workstation you run `setup.sh` from):

```bash
# SSH first, or you lock yourself out when ufw is enabled
sudo ufw allow OpenSSH

# Grafana web UI
sudo ufw allow 3000/tcp comment "Grafana Web UI"

# Logstash input — only from pfSense
sudo ufw allow from <PFSENSE_IP> to any port 5140 proto udp comment "Logstash Suricata input"

# OpenSearch — only from trusted hosts (install.sh opens this to everyone; narrow it)
sudo ufw allow from <WORKSTATION_IP> to any port 9200 proto tcp comment "OpenSearch HTTP"

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
sudo journalctl -u opensearch -f       # OpenSearch (also /opt/opensearch/logs/)
sudo journalctl -u logstash -f         # Logstash
sudo journalctl -u grafana-server -f   # Grafana
```

### Test Logstash Pipeline

```bash
# Send a test Suricata event
echo '{"timestamp":"2026-09-19T12:00:00.000000-0500","flow_id":123456,"event_type":"test","src_ip":"192.168.1.100","dest_ip":"203.0.113.10","proto":"UDP"}' | nc -u -w1 localhost 5140

# Wait 5 seconds for processing
sleep 5

# Check if event was indexed
curl -s "http://localhost:9200/suricata-*/_search?q=event_type:test&size=1" | jq '.hits.hits[0]._source'
```

The returned document should have `event_type`, `src_ip`, `dest_ip` and `proto` at the
root level (flat), with `@timestamp` taken from the event's own `timestamp`.

## Access Grafana

1. Open browser to `http://<SIEM_IP>:3000`
2. Default credentials: `admin` / `admin`
3. Change password when prompted
4. Proceed to [Dashboard Installation Guide](INSTALL_DASHBOARD.md)

## Resource Usage

After installation, verify resource usage:

```bash
# Check memory usage
free -h

# Check disk usage (OpenSearch data lives here)
df -h /opt/opensearch/data

# Check service resource consumption
sudo systemctl status opensearch
sudo systemctl status logstash
sudo systemctl status grafana-server
```

Expected resource usage on a 16 GB host:
- OpenSearch: ~9-10 GB RAM (8 GB heap + overhead)
- Logstash: ~1-1.5 GB RAM
- Grafana: ~200-500 MB RAM

## Troubleshooting

### OpenSearch won't start
```bash
# Check logs
sudo journalctl -u opensearch -n 100
sudo tail -n 100 /opt/opensearch/logs/pfsense-monitoring.log

# Common issues:
# - Insufficient memory: reduce -Xms/-Xmx in /opt/opensearch/config/jvm.options
# - vm.max_map_count too low: sudo sysctl -w vm.max_map_count=262144
# - Wrong ownership after manual edits: sudo chown -R opensearch:opensearch /opt/opensearch
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
- **[Dashboard Installation](INSTALL_DASHBOARD.md)** - Import Grafana dashboards

## Configuration Files Location

Tarball layout (what `install.sh` creates):

- OpenSearch config: `/opt/opensearch/config/opensearch.yml`
- OpenSearch heap: `/opt/opensearch/config/jvm.options`
- OpenSearch data / logs: `/opt/opensearch/data`, `/opt/opensearch/logs`
- OpenSearch systemd unit: `/etc/systemd/system/opensearch.service`
- Logstash pipeline: `/etc/logstash/conf.d/suricata.conf` (copied from `config/logstash-suricata.conf`)
- Grafana config: `/etc/grafana/grafana.ini`

A `.deb` install of OpenSearch uses `/etc/opensearch` and `/var/lib/opensearch` instead.
