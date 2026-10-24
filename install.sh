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

# Safe-default helpers (loopback OpenSearch, source-limited firewall, Grafana password check)
# shellcheck source=scripts/lib-install-safety.sh
source "$SCRIPT_DIR/scripts/lib-install-safety.sh"
# Pick up the safety settings from config.env if present (read, never executed)
load_safety_config "$SCRIPT_DIR/config.env"

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

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
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
    
    # Who may reach the services. Nothing is opened to "anyone" unless
    # INSECURE_OPEN_ACCESS=true is set on purpose (see config.env.example).
    if _lis_true "${INSECURE_OPEN_ACCESS:-}"; then
        print_warning "INSECURE_OPEN_ACCESS=true: OpenSearch, Logstash and Grafana will be open to every source."
    fi
    LOGSTASH_ALLOWED_SOURCES="${LOGSTASH_ALLOWED_SOURCES:-$PFSENSE_IP}"
    if [ -z "${GRAFANA_ALLOWED_SOURCES:-}" ]; then
        read -r -p "IPs/CIDRs allowed to reach Grafana (comma separated, e.g. your workstation or LAN): " GRAFANA_ALLOWED_SOURCES
    fi
    export LOGSTASH_ALLOWED_SOURCES GRAFANA_ALLOWED_SOURCES MONITOR_MODE
    # Fail now, before anything is installed, if the plan is not valid
    if ! firewall_plan > /dev/null; then
        print_error "Fix the source settings above and re-run (see config.env.example)."
        exit 1
    fi
    if ! render_opensearch_yml > /dev/null; then
        print_error "OpenSearch bind settings are not valid (see config.env.example)."
        exit 1
    fi

    # Get Grafana password: set one or let the installer generate one
    GRAFANA_PASSWORD_GENERATED=false
    read -sp "Set Grafana admin password [leave empty to generate a random one]: " GRAFANA_PASSWORD
    echo ""
    if [ -z "$GRAFANA_PASSWORD" ]; then
        GRAFANA_PASSWORD=$(generate_password)
        GRAFANA_PASSWORD_GENERATED=true
    fi
    if ! grafana_password_ok "$GRAFANA_PASSWORD"; then
        exit 1
    fi
    
    # Summary
    echo ""
    print_header "Configuration Summary"
    echo "  Monitoring Mode:    $MONITOR_MODE"
    echo "  SIEM Server IP:     $SIEM_IP"
    echo "  pfSense IP:         $PFSENSE_IP"
    echo "  Data Retention:     $RETENTION_DAYS days"
    echo "  Grafana Password:   ${GRAFANA_PASSWORD//?/*}"
    echo "  OpenSearch bind:    $(resolve_opensearch_bind)"
    echo "  Logstash sources:   ${LOGSTASH_ALLOWED_SOURCES}"
    echo "  Grafana sources:    ${GRAFANA_ALLOWED_SOURCES}"
    echo ""
    read -p "Proceed with installation? [Y/n]: " CONFIRM
    CONFIRM=${CONFIRM:-Y}
    
    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        print_error "Installation cancelled"
        exit 0
    fi
    
    # Save config (restrictive permissions — contains the Grafana password)
    touch /tmp/monitoring-config.env
    chmod 600 /tmp/monitoring-config.env
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
        if grep -q '^network.host: *0\.0\.0\.0' /opt/opensearch/config/opensearch.yml 2>/dev/null; then
            print_warning "Existing opensearch.yml binds 0.0.0.0 with the security plugin disabled (the old default)."
            print_warning "It was left as is. To bind loopback only: set 'network.host: 127.0.0.1' in /opt/opensearch/config/opensearch.yml and restart opensearch."
        fi
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
    # Loopback by default; see render_opensearch_yml in scripts/lib-install-safety.sh
    render_opensearch_yml > /opt/opensearch/config/opensearch.yml
    
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
            print_error "No Telegraf Logstash pipeline ships with this project yet"
            print_info "Telegraf/both mode requires you to write /etc/logstash/conf.d/telegraf.conf manually"
            print_info "See docs/pfsense/TELEGRAF_PFBLOCKER_SETUP.md for the Telegraf-to-OpenSearch approach"
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

    # Set the admin password after first start (the database exists by then).
    # A failure here must stop the install: the account would still be admin/admin.
    print_step "Setting Grafana admin password..."
    if ! grafana-cli admin reset-admin-password "$GRAFANA_PASSWORD" > /dev/null 2>&1; then
        print_error "Could not set the Grafana admin password. Grafana may still use admin/admin."
        print_error "Run: sudo grafana-cli admin reset-admin-password '<new password>'"
        exit 1
    fi
    print_success "Grafana admin password set"
}

configure_firewall() {
    print_header "Configuring Firewall"
    
    print_step "Opening required ports (only to the sources you named)..."

    # firewall_plan prints SRC|PORT|PROTO|COMMENT; SRC is "any" only with INSECURE_OPEN_ACCESS=true
    local plan rule_src rule_port rule_proto rule_comment
    plan=$(firewall_plan) || { print_error "Firewall plan is not valid"; exit 1; }
    while IFS='|' read -r rule_src rule_port rule_proto rule_comment; do
        [ -z "$rule_src" ] && continue
        if [ "$rule_src" = "any" ]; then
            ufw allow "$rule_port/$rule_proto" comment "$rule_comment"
        else
            ufw allow from "$rule_src" to any port "$rule_port" proto "$rule_proto" comment "$rule_comment"
        fi
    done <<< "$plan"

    # Older installs opened these ports to everyone; the installer does not delete rules, it tells you
    if ufw status 2>/dev/null | grep -E '^(9200|5140|3000|8086)(/(tcp|udp))? +ALLOW +Anywhere' > /dev/null; then
        print_warning "ufw still has rules that allow 9200/5140/3000/8086 from anywhere (from an older install)."
        print_warning "Review with 'sudo ufw status numbered' and delete them, e.g. 'sudo ufw delete allow 9200/tcp'."
    fi

    # SSH — must be allowed BEFORE enabling ufw or we lock ourselves out
    ufw allow OpenSSH

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

print_next_steps() {
    print_header "Installation Complete!"
    
    echo -e "${GREEN}✓ OpenSearch${NC} is running on http://$(resolve_opensearch_bind):9200 (loopback unless you set OPENSEARCH_BIND)"
    echo -e "${GREEN}✓ Logstash${NC} is running and listening on UDP 5140"
    echo -e "${GREEN}✓ Grafana${NC} is running on http://${SIEM_IP}:3000"
    echo ""
    
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}  Next Steps${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${YELLOW}1. Deploy to pfSense:${NC}"
    echo "   Copy config.env.example to config.env, edit your IPs, then run:"
    echo "   ./setup.sh   (deploys the Suricata forwarder + watchdog to pfSense)"
    echo ""
    
    echo -e "${YELLOW}2. Access Grafana:${NC}"
    echo "   URL:      http://${SIEM_IP}:3000"
    echo "   Username: admin"
    if [ "$GRAFANA_PASSWORD_GENERATED" = "true" ]; then
        echo "   Password: $GRAFANA_PASSWORD   (generated; shown once, also in /tmp/monitoring-config.env)"
    else
        echo "   Password: the one you entered"
    fi
    echo ""
    
    echo -e "${YELLOW}3. Verify Data Flow:${NC}"
    echo "   bash scripts/status.sh"
    echo "   bash scripts/diagnose-and-repair.sh"
    echo ""
    
    if [[ "$MONITOR_MODE" == "suricata" ]] || [[ "$MONITOR_MODE" == "both" ]]; then
        echo -e "${YELLOW}4. Import Suricata Dashboard:${NC}"
        echo "   Follow: docs/install/INSTALL_DASHBOARD.md"
        echo ""
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    echo -e "${BLUE}Documentation:${NC}"
    echo "  • Quick Start:          QUICK_START.md"
    echo "  • Multi-Interface:      docs/operations/MULTI_INTERFACE_RETENTION.md"
    echo "  • Troubleshooting:      docs/troubleshooting/TROUBLESHOOTING.md"
    echo "  • Full Documentation:   README.md"
    echo ""
    
    print_info "Installation log saved to: /var/log/pfsense-monitoring-install.log"
    print_info "Config saved to /tmp/monitoring-config.env — it contains your Grafana password."
    print_info "Delete it when you no longer need it: rm /tmp/monitoring-config.env"
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

    # Completion
    print_next_steps
}

# Run main function and log output (preserve main's exit code, not tee's)
main 2>&1 | tee /var/log/pfsense-monitoring-install.log

exit "${PIPESTATUS[0]}"
