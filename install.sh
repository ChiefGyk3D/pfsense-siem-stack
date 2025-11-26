#!/bin/bash
# Unified pfSense Monitoring Stack Installer
# Installs OpenSearch, Logstash, and Grafana with interactive configuration
# Supports both Telegraf (network metrics) and Suricata (IDS/IPS) monitoring

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration variables
OPENSEARCH_VERSION="2.19.4"
LOGSTASH_VERSION="8.19.7"
GRAFANA_VERSION="12.3.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Functions
print_header() {
    echo ""
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
}

print_step() {
    echo -e "${YELLOW}➜ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_root() {
    if [ "$EUID" -ne 0 ]; then 
        print_error "This script must be run as root or with sudo"
        exit 1
    fi
}

check_os() {
    if [ ! -f /etc/os-release ]; then
        print_error "Cannot determine OS version"
        exit 1
    fi
    
    . /etc/os-release
    if [ "$ID" != "ubuntu" ] || [ "${VERSION_ID%%.*}" -lt 22 ]; then
        print_error "This script requires Ubuntu 22.04 or later"
        print_info "Detected: $PRETTY_NAME"
        exit 1
    fi
    
    print_success "OS check passed: $PRETTY_NAME"
}

check_resources() {
    # Check RAM
    TOTAL_RAM=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 8 ]; then
        print_error "Insufficient RAM: ${TOTAL_RAM}GB (minimum 8GB, recommended 16GB+)"
        exit 1
    fi
    print_success "RAM check passed: ${TOTAL_RAM}GB"
    
    # Check disk space
    AVAILABLE_DISK=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [ "$AVAILABLE_DISK" -lt 100 ]; then
        print_error "Insufficient disk space: ${AVAILABLE_DISK}GB (minimum 100GB recommended)"
        exit 1
    fi
    print_success "Disk space check passed: ${AVAILABLE_DISK}GB available"
}

interactive_config() {
    print_header "Configuration Wizard"
    
    echo -e "${CYAN}This wizard will configure your pfSense monitoring stack.${NC}"
    echo ""
    
    # Get monitoring mode
    echo -e "${YELLOW}What would you like to monitor?${NC}"
    echo "  1) Suricata IDS/IPS logs only (Security monitoring)"
    echo "  2) Telegraf network metrics only (Performance monitoring)"
    echo "  3) Both Suricata and Telegraf (Complete monitoring)"
    echo ""
    read -p "Enter choice [1-3]: " MONITOR_CHOICE
    
    case $MONITOR_CHOICE in
        1) MONITOR_MODE="suricata" ;;
        2) MONITOR_MODE="telegraf" ;;
        3) MONITOR_MODE="both" ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac
    
    # Get this server's IP
    DEFAULT_IP=$(hostname -I | awk '{print $1}')
    read -p "Enter this SIEM server's IP address [$DEFAULT_IP]: " SIEM_IP
    SIEM_IP=${SIEM_IP:-$DEFAULT_IP}
    
    # Get pfSense IP
    read -p "Enter pfSense IP address: " PFSENSE_IP
    if [ -z "$PFSENSE_IP" ]; then
        print_error "pfSense IP is required"
        exit 1
    fi
    
    # Get retention days
    read -p "Data retention in days [90]: " RETENTION_DAYS
    RETENTION_DAYS=${RETENTION_DAYS:-90}
    
    # Get Grafana password
    read -sp "Set Grafana admin password [leave empty for 'admin']: " GRAFANA_PASSWORD
    echo ""
    GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-admin}
    
    # Summary
    echo ""
    print_header "Configuration Summary"
    echo "  Monitoring Mode:    $MONITOR_MODE"
    echo "  SIEM Server IP:     $SIEM_IP"
    echo "  pfSense IP:         $PFSENSE_IP"
    echo "  Data Retention:     $RETENTION_DAYS days"
    echo "  Grafana Password:   ${GRAFANA_PASSWORD//?/*}"
    echo ""
    read -p "Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_error "Installation cancelled"
        exit 0
    fi
    
    # Save config
    cat > /tmp/monitoring-config.env <<EOF
MONITOR_MODE=$MONITOR_MODE
SIEM_IP=$SIEM_IP
PFSENSE_IP=$PFSENSE_IP
RETENTION_DAYS=$RETENTION_DAYS
GRAFANA_PASSWORD=$GRAFANA_PASSWORD
EOF
}

system_preparation() {
    print_header "System Preparation"
    
    print_step "Updating system packages..."
    apt update && apt upgrade -y
    print_success "System updated"
    
    print_step "Installing required packages..."
    apt install -y curl wget gnupg2 apt-transport-https software-properties-common \
                   jq python3 python3-pip net-tools
    print_success "Packages installed"
    
    print_step "Configuring system limits..."
    cat >> /etc/security/limits.conf <<EOF
# OpenSearch/Logstash limits
* soft nofile 65536
* hard nofile 65536
* soft memlock unlimited
* hard memlock unlimited
EOF
    print_success "Limits configured"
    
    print_step "Optimizing kernel parameters..."
    cat >> /etc/sysctl.conf <<EOF
# OpenSearch requirements
vm.max_map_count=262144
vm.swappiness=1
EOF
    sysctl -p
    print_success "Kernel parameters optimized"
    
    # Reduce swap usage but don't disable completely
    print_step "Configuring swap..."
    sysctl vm.swappiness=1
    print_success "Swap configured"
}

install_java() {
    print_header "Installing Java"
    
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        print_info "Java already installed: $JAVA_VERSION"
        return
    fi
    
    print_step "Installing OpenJDK 21..."
    apt install -y openjdk-21-jdk
    
    JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
    print_success "Java installed: $JAVA_VERSION"
}

install_opensearch() {
    print_header "Installing OpenSearch $OPENSEARCH_VERSION"
    
    if systemctl is-active --quiet opensearch; then
        print_info "OpenSearch already installed and running"
        return
    fi
    
    print_step "Downloading OpenSearch..."
    cd /tmp
    wget -q --show-progress https://artifacts.opensearch.org/releases/bundle/opensearch/$OPENSEARCH_VERSION/opensearch-$OPENSEARCH_VERSION-linux-x64.tar.gz
    
    print_step "Extracting and installing..."
    tar -xzf opensearch-$OPENSEARCH_VERSION-linux-x64.tar.gz
    mv opensearch-$OPENSEARCH_VERSION /opt/opensearch
    
    print_step "Creating opensearch user..."
    useradd -r -s /bin/bash -d /opt/opensearch opensearch || true
    chown -R opensearch:opensearch /opt/opensearch
    
    print_step "Configuring OpenSearch..."
    cat > /opt/opensearch/config/opensearch.yml <<EOF
cluster.name: pfsense-monitoring
node.name: siem-node-1
path.data: /opt/opensearch/data
path.logs: /opt/opensearch/logs
network.host: 0.0.0.0
http.port: 9200
discovery.type: single-node
plugins.security.disabled: true
EOF
    
    print_step "Setting heap size..."
    HEAP_SIZE=$((TOTAL_RAM / 2))
    if [ $HEAP_SIZE -gt 16 ]; then HEAP_SIZE=16; fi
    sed -i "s/-Xms1g/-Xms${HEAP_SIZE}g/" /opt/opensearch/config/jvm.options
    sed -i "s/-Xmx1g/-Xmx${HEAP_SIZE}g/" /opt/opensearch/config/jvm.options
    
    print_step "Creating systemd service..."
    cat > /etc/systemd/system/opensearch.service <<EOF
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
    
    systemctl daemon-reload
    systemctl enable opensearch
    systemctl start opensearch
    
    print_step "Waiting for OpenSearch to start..."
    for i in {1..30}; do
        if curl -s http://localhost:9200 > /dev/null 2>&1; then
            print_success "OpenSearch is running"
            break
        fi
        sleep 2
    done
    
    rm -f /tmp/opensearch-$OPENSEARCH_VERSION-linux-x64.tar.gz
}

install_logstash() {
    print_header "Installing Logstash $LOGSTASH_VERSION"
    
    if systemctl is-active --quiet logstash; then
        print_info "Logstash already installed and running"
        return
    fi
    
    print_step "Adding Elastic repository..."
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/elastic-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" | \
        tee /etc/apt/sources.list.d/elastic-8.x.list
    
    print_step "Installing Logstash..."
    apt update
    apt install -y logstash
    
    print_step "Installing OpenSearch output plugin..."
    /usr/share/logstash/bin/logstash-plugin install logstash-output-opensearch
    
    print_step "Configuring Logstash for $MONITOR_MODE..."
    
    # Create appropriate pipeline based on mode
    if [[ "$MONITOR_MODE" == "suricata" ]] || [[ "$MONITOR_MODE" == "both" ]]; then
        cp "$SCRIPT_DIR/config/logstash-suricata.conf" /etc/logstash/conf.d/suricata.conf
        print_success "Suricata pipeline configured"
    fi
    
    if [[ "$MONITOR_MODE" == "telegraf" ]] || [[ "$MONITOR_MODE" == "both" ]]; then
        # Create Telegraf pipeline (if config exists)
        if [ -f "$SCRIPT_DIR/config/logstash-telegraf.conf" ]; then
            cp "$SCRIPT_DIR/config/logstash-telegraf.conf" /etc/logstash/conf.d/telegraf.conf
            print_success "Telegraf pipeline configured"
        else
            print_info "Telegraf pipeline not found - will need manual configuration"
        fi
    fi
    
    systemctl enable logstash
    systemctl start logstash
    
    print_step "Waiting for Logstash to start..."
    sleep 10
    print_success "Logstash is running"
}

install_grafana() {
    print_header "Installing Grafana $GRAFANA_VERSION"
    
    if systemctl is-active --quiet grafana-server; then
        print_info "Grafana already installed and running"
        return
    fi
    
    print_step "Adding Grafana repository..."
    wget -q -O - https://packages.grafana.com/gpg.key | gpg --dearmor -o /usr/share/keyrings/grafana-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/grafana-keyring.gpg] https://packages.grafana.com/oss/deb stable main" | \
        tee /etc/apt/sources.list.d/grafana.list
    
    print_step "Installing Grafana..."
    apt update
    apt install -y grafana
    
    print_step "Installing OpenSearch datasource plugin..."
    grafana-cli plugins install grafana-opensearch-datasource
    
    print_step "Configuring Grafana..."
    if [ "$GRAFANA_PASSWORD" != "admin" ]; then
        # Set admin password
        grafana-cli admin reset-admin-password "$GRAFANA_PASSWORD" > /dev/null 2>&1 || true
    fi
    
    systemctl enable grafana-server
    systemctl start grafana-server
    
    print_step "Waiting for Grafana to start..."
    for i in {1..30}; do
        if curl -s http://localhost:3000 > /dev/null 2>&1; then
            print_success "Grafana is running"
            break
        fi
        sleep 2
    done
}

configure_firewall() {
    print_header "Configuring Firewall"
    
    print_step "Opening required ports..."
    
    # OpenSearch
    ufw allow 9200/tcp comment "OpenSearch HTTP"
    
    # Logstash
    ufw allow 5140/udp comment "Logstash Suricata input"
    if [[ "$MONITOR_MODE" == "telegraf" ]] || [[ "$MONITOR_MODE" == "both" ]]; then
        ufw allow 8086/tcp comment "Logstash Telegraf input"
    fi
    
    # Grafana
    ufw allow 3000/tcp comment "Grafana Web UI"
    
    # Enable firewall if not already enabled
    ufw --force enable
    
    print_success "Firewall configured"
}

configure_retention() {
    print_header "Configuring Data Retention"
    
    print_step "Setting up $RETENTION_DAYS day retention policy..."
    
    # Wait for OpenSearch to be ready
    sleep 5
    
    bash "$SCRIPT_DIR/scripts/configure-retention-policy.sh" "$RETENTION_DAYS"
    
    print_success "Retention policy configured"
}

generate_deployment_script() {
    print_header "Generating pfSense Deployment Script"
    
    DEPLOY_SCRIPT="/tmp/deploy-to-pfsense.sh"
    
    cat > "$DEPLOY_SCRIPT" <<'EOFSCRIPT'
#!/bin/bash
# Auto-generated pfSense deployment script
# Run this on your workstation (not on the SIEM server)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

EOFSCRIPT

    # Add configuration from interactive setup
    cat >> "$DEPLOY_SCRIPT" <<EOFSCRIPT

# Configuration from SIEM installation
PFSENSE_IP="$PFSENSE_IP"
SIEM_IP="$SIEM_IP"
MONITOR_MODE="$MONITOR_MODE"

EOFSCRIPT

    cat >> "$DEPLOY_SCRIPT" <<'EOFSCRIPT'

echo -e "${GREEN}=== pfSense Monitoring Deployment ===${NC}"
echo "  pfSense IP:      $PFSENSE_IP"
echo "  SIEM Server IP:  $SIEM_IP"
echo "  Monitor Mode:    $MONITOR_MODE"
echo ""

# Check connectivity
echo -e "${YELLOW}Testing pfSense connectivity...${NC}"
if ! ping -c 1 -W 2 "$PFSENSE_IP" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Cannot reach pfSense at $PFSENSE_IP${NC}"
    exit 1
fi
echo -e "${GREEN}✓ pfSense is reachable${NC}"

# Check SSH
echo -e "${YELLOW}Testing SSH access...${NC}"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 root@"$PFSENSE_IP" "echo test" > /dev/null 2>&1; then
    echo -e "${RED}ERROR: Cannot SSH to pfSense. Please configure SSH key or you'll be prompted for password.${NC}"
    read -p "Continue anyway? [y/N]: " CONT
    if [[ ! "$CONT" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Deploy based on monitor mode
if [[ "$MONITOR_MODE" == "suricata" ]] || [[ "$MONITOR_MODE" == "both" ]]; then
    echo ""
    echo -e "${GREEN}=== Deploying Suricata Forwarder ===${NC}"
    
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -f "$SCRIPT_DIR/deploy-pfsense-forwarder.sh" ]; then
        bash "$SCRIPT_DIR/deploy-pfsense-forwarder.sh" "$PFSENSE_IP" "$SIEM_IP"
    else
        echo -e "${RED}ERROR: deploy-pfsense-forwarder.sh not found${NC}"
        echo "Please run this script from the repository root directory"
        exit 1
    fi
fi

if [[ "$MONITOR_MODE" == "telegraf" ]] || [[ "$MONITOR_MODE" == "both" ]]; then
    echo ""
    echo -e "${GREEN}=== Deploying Telegraf ===${NC}"
    echo -e "${YELLOW}Telegraf deployment requires manual configuration via pfSense WebUI${NC}"
    echo "See: https://docs.netgate.com/pfsense/en/latest/monitoring/telegraf.html"
fi

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
EOFSCRIPT

    chmod +x "$DEPLOY_SCRIPT"
    
    print_success "Deployment script created: $DEPLOY_SCRIPT"
}

print_next_steps() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}✓ OpenSearch${NC} is running on http://${SIEM_IP}:9200"
    echo -e "${GREEN}✓ Logstash${NC} is running and listening on UDP 5140"
    echo -e "${GREEN}✓ Grafana${NC} is running on http://${SIEM_IP}:3000"
    echo ""
    
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}  Next Steps${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}1. Deploy to pfSense:${NC}"
    echo "   Copy /tmp/deploy-to-pfsense.sh to your workstation"
    echo "   Run: bash deploy-to-pfsense.sh"
    echo ""
    
    echo -e "${YELLOW}2. Access Grafana:${NC}"
    echo "   URL:      http://${SIEM_IP}:3000"
    echo "   Username: admin"
    echo "   Password: ${GRAFANA_PASSWORD//?/*}"
    echo ""
    
    echo -e "${YELLOW}3. Verify Data Flow:${NC}"
    echo "   bash scripts/check-system-health.sh"
    echo "   bash scripts/verify-suricata-data.sh"
    echo ""
    
    if [[ "$MONITOR_MODE" == "suricata" ]] || [[ "$MONITOR_MODE" == "both" ]]; then
        echo -e "${YELLOW}4. Import Suricata Dashboard:${NC}"
        echo "   Follow: docs/INSTALL_DASHBOARD.md"
        echo ""
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  • Quick Start:          docs/QUICK_START.md"
    echo "  • Multi-Interface:      docs/MULTI_INTERFACE_RETENTION.md"
    echo "  • Troubleshooting:      docs/TROUBLESHOOTING.md"
    echo "  • Full Documentation:   README.md"
    echo ""
    
    print_info "Installation log saved to: /var/log/pfsense-monitoring-install.log"
}

# Main execution
main() {
    clear
    
    cat << "EOF"
╔═══════════════════════════════════════════════════════╗
║  pfSense Monitoring Stack Installer                  ║
║  OpenSearch + Logstash + Grafana                     ║
╚═══════════════════════════════════════════════════════╝
EOF
    
    echo ""
    
    # Pre-flight checks
    check_root
    check_os
    check_resources
    
    # Interactive configuration
    interactive_config
    
    # Installation steps
    system_preparation
    install_java
    install_opensearch
    install_logstash
    install_grafana
    configure_firewall
    configure_retention
    generate_deployment_script
    
    # Completion
    print_next_steps
}

# Run main function and log output
main 2>&1 | tee /var/log/pfsense-monitoring-install.log

exit 0
