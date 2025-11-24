#!/bin/bash

# pfSense Telegraf Plugins Installer
# This script helps install Telegraf plugins to pfSense via SSH

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to display header
show_header() {
    echo ""
    echo "================================================"
    echo "  pfSense Telegraf Plugins Installer"
    echo "================================================"
    echo ""
}

# Function to check if SSH is available
check_ssh() {
    if ! command -v ssh &> /dev/null; then
        print_error "SSH client not found. Please install OpenSSH client."
        exit 1
    fi
    
    if ! command -v scp &> /dev/null; then
        print_error "SCP not found. Please install OpenSSH client."
        exit 1
    fi
}

# Function to get pfSense connection details
get_connection_details() {
    echo ""
    read -p "Enter pfSense IP address or hostname: " PFSENSE_HOST
    read -p "Enter pfSense SSH username [admin]: " PFSENSE_USER
    PFSENSE_USER=${PFSENSE_USER:-admin}
    read -p "Enter pfSense SSH port [22]: " PFSENSE_PORT
    PFSENSE_PORT=${PFSENSE_PORT:-22}
    
    echo ""
    print_info "Testing SSH connection to ${PFSENSE_USER}@${PFSENSE_HOST}:${PFSENSE_PORT}..."
    
    if ssh -p "${PFSENSE_PORT}" -o ConnectTimeout=5 -o BatchMode=yes "${PFSENSE_USER}@${PFSENSE_HOST}" exit 2>/dev/null; then
        print_success "SSH connection successful (using SSH key)"
    else
        print_warning "SSH key authentication failed. You will be prompted for password."
        if ! ssh -p "${PFSENSE_PORT}" -o ConnectTimeout=5 "${PFSENSE_USER}@${PFSENSE_HOST}" exit; then
            print_error "Cannot connect to pfSense. Please check your credentials and network."
            exit 1
        fi
    fi
}

# Function to display available plugins
show_plugins() {
    echo ""
    echo "Available Telegraf Plugins:"
    echo "================================================"
    echo "1) telegraf_pfifgw.php          - Gateway monitoring"
    echo "2) telegraf_temperature.sh      - Temperature sensors"
    echo "3) telegraf_unbound_lite.sh     - Unbound DNS (lite version)"
    echo "4) telegraf_unbound.sh          - Unbound DNS (full version)"
    echo "5) All plugins                  - Install all available plugins"
    echo "6) Custom selection             - Select multiple plugins"
    echo "0) Exit"
    echo "================================================"
    echo ""
}

# Function to install a single plugin
install_plugin() {
    local plugin_file=$1
    local plugin_path="plugins/${plugin_file}"
    local remote_path="/usr/local/bin/${plugin_file}"
    
    if [ ! -f "${plugin_path}" ]; then
        print_error "Plugin file not found: ${plugin_path}"
        return 1
    fi
    
    print_info "Installing ${plugin_file}..."
    
    # Copy file to pfSense
    if scp -P "${PFSENSE_PORT}" "${plugin_path}" "${PFSENSE_USER}@${PFSENSE_HOST}:${remote_path}"; then
        # Make executable
        if ssh -p "${PFSENSE_PORT}" "${PFSENSE_USER}@${PFSENSE_HOST}" "chmod +x ${remote_path}"; then
            print_success "${plugin_file} installed successfully"
            return 0
        else
            print_error "Failed to set execute permissions on ${plugin_file}"
            return 1
        fi
    else
        print_error "Failed to copy ${plugin_file}"
        return 1
    fi
}

# Function to install telegraf config
install_config() {
    local config_file="config/additional_config.conf"
    local remote_path="/usr/local/etc/telegraf_additional.conf"
    
    echo ""
    read -p "Do you want to install the additional Telegraf configuration? (y/n): " install_conf
    
    if [[ $install_conf =~ ^[Yy]$ ]]; then
        if [ ! -f "${config_file}" ]; then
            print_error "Config file not found: ${config_file}"
            return 1
        fi
        
        print_info "Installing additional Telegraf configuration..."
        
        if scp -P "${PFSENSE_PORT}" "${config_file}" "${PFSENSE_USER}@${PFSENSE_HOST}:${remote_path}"; then
            print_success "Configuration file installed successfully"
            print_warning "Don't forget to add 'files = [\"/usr/local/etc/telegraf_additional.conf\"]' to your main telegraf.conf"
            return 0
        else
            print_error "Failed to copy configuration file"
            return 1
        fi
    fi
}

# Function to handle plugin installation based on selection
process_selection() {
    local choice=$1
    
    case $choice in
        1)
            install_plugin "telegraf_pfifgw.php"
            ;;
        2)
            install_plugin "telegraf_temperature.sh"
            ;;
        3)
            install_plugin "telegraf_unbound_lite.sh"
            ;;
        4)
            install_plugin "telegraf_unbound.sh"
            ;;
        5)
            print_info "Installing all plugins..."
            install_plugin "telegraf_pfifgw.php"
            install_plugin "telegraf_temperature.sh"
            install_plugin "telegraf_unbound_lite.sh"
            install_plugin "telegraf_unbound.sh"
            ;;
        6)
            echo ""
            echo "Enter plugin numbers separated by spaces (e.g., 1 2 4):"
            read -p "> " selections
            for num in $selections; do
                process_selection "$num"
            done
            ;;
        0)
            print_info "Exiting..."
            exit 0
            ;;
        *)
            print_error "Invalid selection"
            return 1
            ;;
    esac
}

# Function to restart telegraf service
restart_telegraf() {
    echo ""
    read -p "Do you want to restart the Telegraf service on pfSense? (y/n): " restart_choice
    
    if [[ $restart_choice =~ ^[Yy]$ ]]; then
        print_info "Restarting Telegraf service..."
        if ssh -p "${PFSENSE_PORT}" "${PFSENSE_USER}@${PFSENSE_HOST}" "service telegraf restart"; then
            print_success "Telegraf service restarted successfully"
        else
            print_warning "Failed to restart Telegraf service. You may need to restart it manually."
        fi
    fi
}

# Main script
main() {
    show_header
    
    # Check prerequisites
    check_ssh
    
    # Get connection details
    get_connection_details
    
    # Show plugin menu
    show_plugins
    
    # Get user selection
    read -p "Select an option [0-6]: " selection
    
    # Process selection
    process_selection "$selection"
    
    # Offer to install config
    install_config
    
    # Offer to restart telegraf
    restart_telegraf
    
    echo ""
    print_success "Installation complete!"
    echo ""
    print_info "Next steps:"
    echo "  1. Verify plugins are in /usr/local/bin/ on pfSense"
    echo "  2. Update your telegraf.conf to use the plugins"
    echo "  3. If you installed the config, add it to telegraf.conf"
    echo "  4. Restart Telegraf if you haven't already"
    echo ""
}

# Run main function
main
