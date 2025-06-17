#!/bin/bash

# GhostBridge Netmaker Non-Containerized GO Stack - Interactive Installer
# Based on real-world troubleshooting from GhostBridge project deployment
# Addresses critical MQTT broker, nginx stream, and network configuration issues

set -euo pipefail

SCRIPT_VERSION="2.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/ghostbridge-netmaker-install.log"
BACKUP_DIR="/var/backups/ghostbridge-netmaker"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration storage
declare -A CONFIG
declare -A DETECTED
declare -A VALIDATION

# Default values based on GhostBridge project
DEFAULT_DOMAIN="hobsonschoice.net"
DEFAULT_CONTAINER_IP="10.0.0.101"
DEFAULT_HOST_PUBLIC_IP="80.209.240.244"
DEFAULT_BRIDGE="vmbr0"
DEFAULT_MQTT_PORT="1883"
DEFAULT_MQTT_WS_PORT="9001"
DEFAULT_API_PORT="8081"

# Initialize logging
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

# Utility functions
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${CYAN}[INSTALLER]${NC} $1" | tee -a "$LOG_FILE"
}

print_question() {
    echo -e "${PURPLE}[?]${NC} $1"
}

prompt_continue() {
    echo
    print_question "Press Enter to continue..."
    read
}

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║             GhostBridge Netmaker GO Stack Interactive Installer           ║
║                     Non-Containerized Deployment Suite                    ║
║                                                                           ║
║          Based on Real-World Troubleshooting & Deployment Experience     ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
    print_info "Version: $SCRIPT_VERSION"
    print_info "Log File: $LOG_FILE"
    echo
}

# Root check
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Pre-flight validation checks based on GhostBridge troubleshooting
preflight_validation() {
    print_header "Running Pre-flight Validation Checks"
    echo "════════════════════════════════════════════════════════════════════════"
    
    local validation_failed=false
    
    # Check 1: Operating System
    print_info "Checking operating system..."
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DETECTED[os_name]="$NAME"
        DETECTED[os_version]="$VERSION_ID"
        DETECTED[os_id]="$ID"
        
        case "$ID" in
            ubuntu|debian)
                print_status "Supported OS detected: $NAME $VERSION_ID"
                ;;
            *)
                print_warning "Untested OS: $NAME $VERSION_ID (proceeding with caution)"
                ;;
        esac
    else
        print_error "Cannot detect operating system"
        validation_failed=true
    fi
    
    # Check 2: System Resources
    print_info "Checking system resources..."
    DETECTED[memory_mb]=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    DETECTED[cpu_cores]=$(nproc)
    DETECTED[disk_space_gb]=$(df / | awk 'NR==2 {printf "%.0f", $4/1024/1024}')
    
    print_status "Memory: ${DETECTED[memory_mb]}MB, CPU: ${DETECTED[cpu_cores]} cores, Disk: ${DETECTED[disk_space_gb]}GB"
    
    if [[ ${DETECTED[memory_mb]} -lt 1024 ]]; then
        print_warning "Low memory detected (${DETECTED[memory_mb]}MB). Minimum 1GB recommended."
    fi
    
    # Check 3: Network Configuration (Critical for GhostBridge)
    print_info "Checking network configuration..."
    DETECTED[public_ip]=$(curl -s ifconfig.me 2>/dev/null || curl -s ipinfo.io/ip 2>/dev/null || echo "unknown")
    print_status "Public IP: ${DETECTED[public_ip]}"
    
    # Check 4: Critical Port Availability
    print_info "Checking critical port availability..."
    local critical_ports=("80" "443" "1883" "8081" "9001")
    for port in "${critical_ports[@]}"; do
        if ss -tlnp | grep -q ":$port "; then
            print_warning "Port $port is already in use:"
            ss -tlnp | grep ":$port " | head -1
            VALIDATION[port_$port]="occupied"
        else
            print_status "Port $port is available"
            VALIDATION[port_$port]="available"
        fi
    done
    
    # Check 5: Nginx Package and Stream Module (Critical Issue from Troubleshooting)
    print_info "Checking nginx installation and stream module availability..."
    if command -v nginx >/dev/null 2>&1; then
        local nginx_version=$(nginx -v 2>&1 | cut -d' ' -f3)
        print_status "Nginx found: $nginx_version"
        
        # Check if nginx supports stream module
        if nginx -V 2>&1 | grep -q 'stream'; then
            print_status "Nginx stream module is available"
            VALIDATION[nginx_stream]="available"
        else
            print_error "Nginx stream module NOT available"
            print_error "This will cause MQTT broker connection failures"
            print_info "Solution: Install nginx-full package instead of nginx-light"
            VALIDATION[nginx_stream]="missing"
            validation_failed=true
        fi
    else
        print_info "Nginx not installed (will be installed with stream module support)"
        VALIDATION[nginx_stream]="not_installed"
    fi
    
    # Check 6: Existing Mosquitto Installation
    print_info "Checking for existing Mosquitto installation..."
    if systemctl is-active --quiet mosquitto 2>/dev/null; then
        print_warning "Mosquitto service is already running"
        VALIDATION[mosquitto_existing]="running"
    elif dpkg -l | grep -q mosquitto; then
        print_warning "Mosquitto is installed but not running"
        VALIDATION[mosquitto_existing]="installed"
    else
        print_status "No existing Mosquitto installation found"
        VALIDATION[mosquitto_existing]="none"
    fi
    
    # Check 7: Container/VM Detection (Important for GhostBridge LXC setup)
    print_info "Detecting virtualization environment..."
    DETECTED[virtualization]="bare-metal"
    if [[ -f /.dockerenv ]]; then
        DETECTED[virtualization]="docker"
    elif [[ -d /proc/vz ]]; then
        DETECTED[virtualization]="openvz"
    elif grep -q "QEMU\|VMware\|VirtualBox" /proc/cpuinfo 2>/dev/null; then
        DETECTED[virtualization]="vm"
    elif [[ -f /proc/xen/version ]] 2>/dev/null; then
        DETECTED[virtualization]="xen"
    fi
    
    # Check specifically for Proxmox LXC (GhostBridge environment)
    if [[ -f /etc/pve/local/pve-ssl.pem ]]; then
        DETECTED[proxmox_host]="true"
        DETECTED[proxmox_version]=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "unknown")
        print_status "Proxmox host detected: ${DETECTED[proxmox_version]}"
    elif [[ -f /proc/self/cgroup ]] && grep -q lxc /proc/self/cgroup; then
        DETECTED[lxc_container]="true"
        print_status "LXC container environment detected"
    fi
    
    print_status "Virtualization: ${DETECTED[virtualization]}"
    
    # Check 8: DNS Resolution (Critical for GhostBridge domains)
    print_info "Testing DNS resolution for common GhostBridge domains..."
    local test_domains=("$DEFAULT_DOMAIN" "netmaker.$DEFAULT_DOMAIN" "broker.$DEFAULT_DOMAIN")
    for domain in "${test_domains[@]}"; do
        if dig +short "$domain" >/dev/null 2>&1; then
            local resolved_ip=$(dig +short "$domain" | tail -n1)
            print_status "$domain resolves to: $resolved_ip"
            VALIDATION[dns_$domain]="$resolved_ip"
        else
            print_warning "$domain DNS resolution failed"
            VALIDATION[dns_$domain]="failed"
        fi
    done
    
    echo
    print_header "Pre-flight Validation Summary"
    echo "────────────────────────────────────────────────────────────────────────"
    
    if [[ "$validation_failed" == "true" ]]; then
        print_error "Critical validation issues detected!"
        print_error "These issues will likely cause installation failures"
        echo
        print_question "Do you want to:"
        echo "  1) Fix issues and retry validation"
        echo "  2) Continue anyway (not recommended)"
        echo "  3) Exit and fix manually"
        echo
        read -p "Enter choice (1-3): " choice
        
        case $choice in
            1)
                print_info "Please address the issues above and restart the installer"
                exit 1
                ;;
            2)
                print_warning "Continuing with known issues - installation may fail"
                ;;
            3)
                print_info "Exiting for manual fixes"
                exit 0
                ;;
            *)
                print_error "Invalid choice"
                exit 1
                ;;
        esac
    else
        print_status "All pre-flight checks passed!"
    fi
    
    prompt_continue
}

# Interactive configuration gathering
gather_configuration() {
    print_header "Interactive Configuration Setup"
    echo "════════════════════════════════════════════════════════════════════════"
    
    # Deployment Type Selection
    print_info "GhostBridge supports several deployment scenarios:"
    echo "  1) Complete Single-Server Setup (All services on one system)"
    echo "  2) Proxmox Host + LXC Container Setup (GhostBridge standard)"
    echo "  3) Multi-Server Deployment (Distributed services)"
    echo "  4) Development/Testing Setup (Minimal configuration)"
    echo
    
    while true; do
        read -p "Select deployment type (1-4) [2]: " deployment_type
        deployment_type=${deployment_type:-2}
        
        case $deployment_type in
            1)
                CONFIG[deployment_type]="single-server"
                print_status "Selected: Complete Single-Server Setup"
                break
                ;;
            2)
                CONFIG[deployment_type]="proxmox-lxc"
                print_status "Selected: Proxmox Host + LXC Container Setup (GhostBridge)"
                break
                ;;
            3)
                CONFIG[deployment_type]="multi-server"
                print_status "Selected: Multi-Server Deployment"
                break
                ;;
            4)
                CONFIG[deployment_type]="development"
                print_status "Selected: Development/Testing Setup"
                break
                ;;
            *)
                print_warning "Invalid selection. Please choose 1-4."
                ;;
        esac
    done
    
    echo
    
    # Domain Configuration
    print_info "Domain and Network Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_question "Enter your primary domain name:"
    read -p "Domain [$DEFAULT_DOMAIN]: " domain_input
    CONFIG[domain]="${domain_input:-$DEFAULT_DOMAIN}"
    
    # Network Configuration based on deployment type
    if [[ "${CONFIG[deployment_type]}" == "proxmox-lxc" ]]; then
        print_info "Proxmox + LXC Container Configuration"
        
        print_question "Enter Proxmox host public IP:"
        read -p "Host Public IP [$DEFAULT_HOST_PUBLIC_IP]: " host_ip_input
        CONFIG[host_public_ip]="${host_ip_input:-$DEFAULT_HOST_PUBLIC_IP}"
        
        print_question "Enter LXC container IP:"
        read -p "Container IP [$DEFAULT_CONTAINER_IP]: " container_ip_input
        CONFIG[container_ip]="${container_ip_input:-$DEFAULT_CONTAINER_IP}"
        
        print_question "Enter network bridge name:"
        read -p "Bridge [$DEFAULT_BRIDGE]: " bridge_input
        CONFIG[bridge]="${bridge_input:-$DEFAULT_BRIDGE}"
        
        CONFIG[install_location]="container"
        print_info "Services will be installed in LXC container at ${CONFIG[container_ip]}"
        
    else
        print_question "Enter server IP address:"
        read -p "Server IP [${DETECTED[public_ip]}]: " server_ip_input
        CONFIG[server_ip]="${server_ip_input:-${DETECTED[public_ip]}}"
        CONFIG[install_location]="local"
    fi
    
    # Port Configuration
    print_info "Service Port Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_question "Use default ports? (Recommended: API:8081, MQTT:1883, WebSocket:9001)"
    read -p "Use defaults? [Y/n]: " use_defaults
    
    if [[ "$use_defaults" =~ ^[Nn]$ ]]; then
        read -p "Netmaker API port [$DEFAULT_API_PORT]: " api_port_input
        CONFIG[api_port]="${api_port_input:-$DEFAULT_API_PORT}"
        
        read -p "MQTT TCP port [$DEFAULT_MQTT_PORT]: " mqtt_port_input
        CONFIG[mqtt_port]="${mqtt_port_input:-$DEFAULT_MQTT_PORT}"
        
        read -p "MQTT WebSocket port [$DEFAULT_MQTT_WS_PORT]: " mqtt_ws_port_input
        CONFIG[mqtt_ws_port]="${mqtt_ws_port_input:-$DEFAULT_MQTT_WS_PORT}"
    else
        CONFIG[api_port]="$DEFAULT_API_PORT"
        CONFIG[mqtt_port]="$DEFAULT_MQTT_PORT"
        CONFIG[mqtt_ws_port]="$DEFAULT_MQTT_WS_PORT"
    fi
    
    # Component Selection
    print_info "Component Installation Selection"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_question "Install Netmaker server? [Y/n]:"
    read -p "> " install_netmaker_input
    CONFIG[install_netmaker]=$([[ "$install_netmaker_input" =~ ^[Nn]$ ]] && echo "false" || echo "true")
    
    print_question "Install Mosquitto MQTT broker? [Y/n]:"
    read -p "> " install_mosquitto_input
    CONFIG[install_mosquitto]=$([[ "$install_mosquitto_input" =~ ^[Nn]$ ]] && echo "false" || echo "true")
    
    print_question "Install/configure Nginx reverse proxy? [Y/n]:"
    read -p "> " install_nginx_input
    CONFIG[install_nginx]=$([[ "$install_nginx_input" =~ ^[Nn]$ ]] && echo "false" || echo "true")
    
    print_question "Setup SSL certificates with Let's Encrypt? [Y/n]:"
    read -p "> " setup_ssl_input
    CONFIG[setup_ssl]=$([[ "$setup_ssl_input" =~ ^[Nn]$ ]] && echo "false" || echo "true")
    
    # Security Configuration
    print_info "Security Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_warning "MQTT broker security is critical for Netmaker functionality"
    print_question "Generate secure MQTT credentials? [Y/n]:"
    read -p "> " secure_mqtt_input
    CONFIG[secure_mqtt]=$([[ "$secure_mqtt_input" =~ ^[Nn]$ ]] && echo "false" || echo "true")
    
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        CONFIG[mqtt_username]="netmaker"
        CONFIG[mqtt_password]=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        print_status "Generated MQTT credentials for secure access"
    fi
    
    echo
}

# Display configuration summary
display_configuration_summary() {
    clear
    print_header "Configuration Summary"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    echo -e "${CYAN}Deployment Configuration:${NC}"
    echo "  • Type: ${CONFIG[deployment_type]}"
    echo "  • Domain: ${CONFIG[domain]}"
    
    if [[ "${CONFIG[deployment_type]}" == "proxmox-lxc" ]]; then
        echo "  • Host Public IP: ${CONFIG[host_public_ip]}"
        echo "  • Container IP: ${CONFIG[container_ip]}"
        echo "  • Bridge: ${CONFIG[bridge]}"
    else
        echo "  • Server IP: ${CONFIG[server_ip]}"
    fi
    echo
    
    echo -e "${CYAN}Service Endpoints:${NC}"
    echo "  • Netmaker API: https://netmaker.${CONFIG[domain]}:${CONFIG[api_port]}"
    echo "  • MQTT Broker: mqtt://broker.${CONFIG[domain]}:${CONFIG[mqtt_port]}"
    echo "  • MQTT WebSocket: wss://broker.${CONFIG[domain]}:${CONFIG[mqtt_ws_port]}"
    echo "  • Dashboard: https://dashboard.${CONFIG[domain]}"
    echo
    
    echo -e "${CYAN}Components to Install:${NC}"
    echo "  • Netmaker Server: ${CONFIG[install_netmaker]}"
    echo "  • Mosquitto MQTT: ${CONFIG[install_mosquitto]}"
    echo "  • Nginx Proxy: ${CONFIG[install_nginx]}"
    echo "  • SSL Certificates: ${CONFIG[setup_ssl]}"
    echo
    
    echo -e "${CYAN}Security Configuration:${NC}"
    echo "  • MQTT Authentication: ${CONFIG[secure_mqtt]}"
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        echo "  • MQTT Username: ${CONFIG[mqtt_username]}"
        echo "  • MQTT Password: [Generated securely]"
    fi
    echo
    
    # Warning about critical issues from troubleshooting
    print_warning "Critical Installation Notes (Based on GhostBridge Troubleshooting):"
    echo "  • Nginx will be installed with stream module support (nginx-full)"
    echo "  • MQTT broker will use proper protocol endpoints (mqtt://, not http://)"
    echo "  • Anonymous MQTT access will be disabled for security"
    echo "  • All services will be tested at each installation step"
    echo
    
    echo "════════════════════════════════════════════════════════════════════════"
    
    while true; do
        print_question "Proceed with installation?"
        echo "  1) Install with current configuration"
        echo "  2) Modify configuration"
        echo "  3) Save configuration and exit"
        echo "  4) Exit without installing"
        echo
        read -p "Enter choice (1-4): " choice
        
        case $choice in
            1)
                return 0
                ;;
            2)
                gather_configuration
                display_configuration_summary
                ;;
            3)
                save_configuration
                exit 0
                ;;
            4)
                print_info "Installation cancelled by user"
                exit 0
                ;;
            *)
                print_warning "Invalid choice. Please enter 1-4."
                ;;
        esac
    done
}

# Save configuration for future reference
save_configuration() {
    local config_file="$SCRIPT_DIR/ghostbridge-config-$TIMESTAMP.conf"
    
    {
        echo "# GhostBridge Netmaker Configuration"
        echo "# Generated: $(date)"
        echo ""
        for key in "${!CONFIG[@]}"; do
            echo "${key^^}=${CONFIG[$key]}"
        done
    } > "$config_file"
    
    print_status "Configuration saved to: $config_file"
}

# Create backup directory and backup existing configs
create_backup() {
    print_header "Creating Configuration Backups"
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup existing configurations
    local configs_to_backup=(
        "/etc/mosquitto/mosquitto.conf"
        "/etc/nginx/nginx.conf"
        "/etc/netmaker/config.yaml"
        "/etc/systemd/system/netmaker.service"
    )
    
    for config in "${configs_to_backup[@]}"; do
        if [[ -f "$config" ]]; then
            cp "$config" "$BACKUP_DIR/$(basename "$config")-$TIMESTAMP.backup"
            print_status "Backed up: $config"
        fi
    done
}

# Install system dependencies with stream module support
install_dependencies() {
    print_header "Installing System Dependencies"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Update package list
    print_info "Updating package lists..."
    apt update
    
    # Install base packages
    print_info "Installing base system packages..."
    local base_packages=("curl" "wget" "unzip" "sqlite3" "jq" "openssl" "dnsutils" "net-tools")
    apt install -y "${base_packages[@]}"
    
    # Install nginx with stream module (Critical fix from troubleshooting)
    if [[ "${CONFIG[install_nginx]}" == "true" ]]; then
        print_info "Installing nginx with stream module support..."
        
        # Remove any existing nginx installation that lacks stream module
        if dpkg -l | grep -q nginx-light; then
            print_warning "Removing nginx-light (lacks stream module)"
            apt remove -y nginx-light
        fi
        
        # Install nginx-full with stream module
        apt install -y nginx-full
        
        # Verify stream module availability
        if nginx -V 2>&1 | grep -q 'stream'; then
            print_status "Nginx installed with stream module support"
        else
            print_error "Failed to install nginx with stream module"
            exit 1
        fi
    fi
    
    # Install Mosquitto MQTT broker
    if [[ "${CONFIG[install_mosquitto]}" == "true" ]]; then
        print_info "Installing Mosquitto MQTT broker..."
        apt install -y mosquitto mosquitto-clients
        
        # Stop default service to prevent conflicts during configuration
        systemctl stop mosquitto || true
        systemctl disable mosquitto || true
    fi
    
    # Install SSL certificate tools
    if [[ "${CONFIG[setup_ssl]}" == "true" ]]; then
        print_info "Installing SSL certificate tools..."
        apt install -y certbot python3-certbot-nginx
    fi
    
    print_status "All dependencies installed successfully"
}

# Download and install Netmaker binary
install_netmaker_binary() {
    if [[ "${CONFIG[install_netmaker]}" != "true" ]]; then
        return 0
    fi
    
    print_header "Installing Netmaker Binary"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Detect architecture
    local arch=$(uname -m)
    local go_arch
    case "$arch" in
        x86_64) go_arch="amd64" ;;
        aarch64|arm64) go_arch="arm64" ;;
        armv7l) go_arch="arm" ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    
    print_info "Detected architecture: $arch (GO: $go_arch)"
    
    # Get latest version
    print_info "Fetching latest Netmaker version..."
    local netmaker_version=$(curl -s https://api.github.com/repos/gravitl/netmaker/releases/latest | jq -r .tag_name)
    print_status "Latest version: $netmaker_version"
    
    # Download binary
    local download_url="https://github.com/gravitl/netmaker/releases/download/${netmaker_version}/netmaker-linux-${go_arch}"
    print_info "Downloading Netmaker binary..."
    
    wget -O /tmp/netmaker "$download_url"
    chmod +x /tmp/netmaker
    mv /tmp/netmaker /usr/local/bin/netmaker
    
    # Verify installation
    local installed_version=$(/usr/local/bin/netmaker --version 2>/dev/null | head -1 || echo "unknown")
    print_status "Netmaker installed: $installed_version"
    
    # Create directories
    mkdir -p /etc/netmaker
    mkdir -p /opt/netmaker/{data,logs}
    mkdir -p /var/log/netmaker
}

# Configure Mosquitto with proper security (addresses critical MQTT issues)
configure_mosquitto() {
    if [[ "${CONFIG[install_mosquitto]}" != "true" ]]; then
        return 0
    fi
    
    print_header "Configuring Mosquitto MQTT Broker"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Create mosquitto configuration addressing all troubleshooting issues
    print_info "Creating secure Mosquitto configuration..."
    
    cat > /etc/mosquitto/mosquitto.conf << EOF
# GhostBridge Mosquitto Configuration
# Generated by GhostBridge installer - addresses critical MQTT connection issues
# Based on troubleshooting: properly binds to 0.0.0.0, uses correct protocols

# MQTT TCP Listener (Critical: must bind to 0.0.0.0, not 127.0.0.1)
listener ${CONFIG[mqtt_port]}
bind_address 0.0.0.0
protocol mqtt
allow_anonymous false

# MQTT WebSocket Listener (Critical: required for web-based connections)
listener ${CONFIG[mqtt_ws_port]}
bind_address 0.0.0.0
protocol websockets
allow_anonymous false

# Authentication Configuration (Critical: disable anonymous access)
EOF
    
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        cat >> /etc/mosquitto/mosquitto.conf << EOF
password_file /etc/mosquitto/passwd
acl_file /etc/mosquitto/acl

EOF
        
        # Create password file
        print_info "Setting up MQTT authentication..."
        mosquitto_passwd -c -b /etc/mosquitto/passwd "${CONFIG[mqtt_username]}" "${CONFIG[mqtt_password]}"
        
        # Create ACL file
        cat > /etc/mosquitto/acl << EOF
# GhostBridge MQTT Access Control List
user ${CONFIG[mqtt_username]}
topic readwrite #
EOF
        
        print_status "MQTT authentication configured for user: ${CONFIG[mqtt_username]}"
    else
        cat >> /etc/mosquitto/mosquitto.conf << EOF
allow_anonymous true

EOF
        print_warning "MQTT anonymous access enabled (not recommended for production)"
    fi
    
    cat >> /etc/mosquitto/mosquitto.conf << EOF
# Persistence and Logging
persistence true
persistence_location /var/lib/mosquitto/

# Logging configuration
log_dest file /var/log/mosquitto/mosquitto.log
log_type error
log_type warning
log_type notice
log_type information
log_timestamp true

# Performance and Security Settings
max_packet_size 1048576
max_inflight_messages 100
max_queued_messages 1000
retain_available true

# Connection timeouts
keepalive_interval 60
max_keepalive 120
EOF
    
    # Set proper permissions
    chown mosquitto:mosquitto /var/lib/mosquitto /var/log/mosquitto
    if [[ -f /etc/mosquitto/passwd ]]; then
        chown mosquitto:mosquitto /etc/mosquitto/passwd /etc/mosquitto/acl
        chmod 600 /etc/mosquitto/passwd /etc/mosquitto/acl
    fi
    
    print_info "Testing Mosquitto configuration..."
    if mosquitto -c /etc/mosquitto/mosquitto.conf -t; then
        print_status "Mosquitto configuration is valid"
    else
        print_error "Mosquitto configuration test failed"
        exit 1
    fi
    
    # Start and enable Mosquitto
    systemctl enable mosquitto
    systemctl start mosquitto
    
    # Wait for startup and verify
    sleep 3
    if systemctl is-active --quiet mosquitto; then
        print_status "Mosquitto service is running"
        
        # Verify port binding (critical check from troubleshooting)
        if ss -tlnp | grep -q ":${CONFIG[mqtt_port]} "; then
            print_status "MQTT TCP listening on port ${CONFIG[mqtt_port]}"
        else
            print_error "MQTT TCP failed to bind to port ${CONFIG[mqtt_port]}"
            journalctl -u mosquitto --no-pager -n 20
            exit 1
        fi
        
        if ss -tlnp | grep -q ":${CONFIG[mqtt_ws_port]} "; then
            print_status "MQTT WebSocket listening on port ${CONFIG[mqtt_ws_port]}"
        else
            print_error "MQTT WebSocket failed to bind to port ${CONFIG[mqtt_ws_port]}"
            journalctl -u mosquitto --no-pager -n 20
            exit 1
        fi
    else
        print_error "Mosquitto service failed to start"
        journalctl -u mosquitto --no-pager -n 20
        exit 1
    fi
}

# Configure Netmaker with proper MQTT broker endpoints
configure_netmaker() {
    if [[ "${CONFIG[install_netmaker]}" != "true" ]]; then
        return 0
    fi
    
    print_header "Configuring Netmaker Server"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Generate master key
    local master_key=$(openssl rand -hex 32)
    
    # Determine broker endpoint based on deployment type
    local broker_endpoint
    if [[ "${CONFIG[deployment_type]}" == "proxmox-lxc" ]]; then
        # For LXC container deployment, use local connection
        if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
            broker_endpoint="mqtt://${CONFIG[mqtt_username]}:${CONFIG[mqtt_password]}@127.0.0.1:${CONFIG[mqtt_port]}"
        else
            broker_endpoint="mqtt://127.0.0.1:${CONFIG[mqtt_port]}"
        fi
    else
        # For other deployments, use external endpoint
        if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
            broker_endpoint="mqtt://${CONFIG[mqtt_username]}:${CONFIG[mqtt_password]}@broker.${CONFIG[domain]}:${CONFIG[mqtt_port]}"
        else
            broker_endpoint="mqtt://broker.${CONFIG[domain]}:${CONFIG[mqtt_port]}"
        fi
    fi
    
    print_info "MQTT Broker Endpoint: ${broker_endpoint%:*}:****@*** (credentials hidden)"
    
    # Create Netmaker configuration with proper MQTT settings
    cat > /etc/netmaker/config.yaml << EOF
# GhostBridge Netmaker Configuration
# Generated by GhostBridge installer
# Addresses critical MQTT broker connection issues from troubleshooting

version: v0.20.0

server:
  host: "0.0.0.0"
  apiport: ${CONFIG[api_port]}
  grpcport: $((${CONFIG[api_port]} + 1))
  restbackend: true
  agentbackend: true
  messagequeuebackend: true
  dnsdisabled: false
  displaykeys: true
  hostnetwork: "off"

# Database Configuration
database:
  host: ""
  port: 0
  username: ""
  password: ""
  name: ""
  sslmode: ""
  endpoint: ""

# CRITICAL: Proper MQTT broker configuration (addresses connection timeout issues)
messagequeue:
  host: "127.0.0.1"
  port: ${CONFIG[mqtt_port]}
  endpoint: "${broker_endpoint}"
  username: "${CONFIG[mqtt_username]:-}"
  password: "${CONFIG[mqtt_password]:-}"

# API Configuration
api:
  corsallowed: "*"
  endpoint: "https://netmaker.${CONFIG[domain]}"

# OAuth Configuration
oauth:
  github_client_id: ""
  github_client_secret: ""
  google_client_id: ""
  google_client_secret: ""
  oidc_issuer: ""

# Security Configuration
jwt_validity_duration: "24h"
rachecks: "on"
telemetry: "off"
mq_admin_password: ""

# Network Settings
manage_iptables: "on"
port_forward_services: ""
default_node_limit: 999999

# Server Configuration
servercheckin: "on"
autopull: "on"
dnsmode: ""
verbosity: 1
platform: "linux"

# Master Key (Critical for API access)
masterkey: "${master_key}"

# Logging
logverbosity: 1
EOF
    
    # Set proper permissions
    chown root:root /etc/netmaker/config.yaml
    chmod 600 /etc/netmaker/config.yaml
    
    print_status "Netmaker configuration created"
    
    # Initialize database
    print_info "Initializing Netmaker database..."
    cd /opt/netmaker
    if /usr/local/bin/netmaker --config /etc/netmaker/config.yaml --version >/dev/null 2>&1; then
        print_status "Netmaker binary is functional"
    else
        print_error "Netmaker binary test failed"
        exit 1
    fi
    
    # Save master key for user reference
    CONFIG[master_key]="$master_key"
}

# Configure Nginx with stream module for MQTT proxying
configure_nginx() {
    if [[ "${CONFIG[install_nginx]}" != "true" ]]; then
        return 0
    fi
    
    print_header "Configuring Nginx Reverse Proxy with Stream Module"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Backup original nginx.conf
    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup-$TIMESTAMP
    
    # Create main nginx configuration with stream module
    print_info "Configuring nginx with stream module for MQTT TCP proxy..."
    
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    multi_accept on;
    use epoll;
}

# HTTP Configuration
http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/javascript application/xml+rss application/json;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

# Stream Configuration (Critical for MQTT TCP proxy)
stream {
    log_format basic '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time';

    access_log /var/log/nginx/stream.log basic;
    error_log /var/log/nginx/stream_error.log;

    include /etc/nginx/stream-conf.d/*.conf;
}
EOF
    
    # Create stream configuration directory
    mkdir -p /etc/nginx/stream-conf.d
    
    # Configure MQTT TCP stream proxy (addresses critical connection issue)
    local target_ip
    if [[ "${CONFIG[deployment_type]}" == "proxmox-lxc" ]]; then
        target_ip="${CONFIG[container_ip]}"
    else
        target_ip="127.0.0.1"
    fi
    
    cat > /etc/nginx/stream-conf.d/mqtt.conf << EOF
# MQTT TCP Stream Proxy
# Critical configuration for GhostBridge MQTT broker access
upstream mqtt_backend {
    server ${target_ip}:${CONFIG[mqtt_port]};
}

server {
    listen ${CONFIG[mqtt_port]};
    proxy_pass mqtt_backend;
    proxy_timeout 1s;
    proxy_responses 1;
    error_log /var/log/nginx/mqtt_stream.log;
}
EOF
    
    # Create HTTP site configuration
    cat > /etc/nginx/sites-available/netmaker << EOF
# GhostBridge Netmaker Nginx Configuration
# HTTP to HTTPS redirects and reverse proxy configuration

# Netmaker API Server
server {
    listen 80;
    server_name netmaker.${CONFIG[domain]};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name netmaker.${CONFIG[domain]};
    
    # SSL configuration (will be populated by certbot)
    # ssl_certificate /etc/letsencrypt/live/netmaker.${CONFIG[domain]}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/netmaker.${CONFIG[domain]}/privkey.pem;
    
    location / {
        proxy_pass http://${target_ip}:${CONFIG[api_port]};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# MQTT Broker WebSocket
server {
    listen 80;
    server_name broker.${CONFIG[domain]};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name broker.${CONFIG[domain]};
    
    # SSL configuration (will be populated by certbot)
    # ssl_certificate /etc/letsencrypt/live/broker.${CONFIG[domain]}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/broker.${CONFIG[domain]}/privkey.pem;
    
    location / {
        proxy_pass http://${target_ip}:${CONFIG[mqtt_ws_port]};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support for MQTT
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}

# Dashboard/UI
server {
    listen 80;
    server_name dashboard.${CONFIG[domain]};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name dashboard.${CONFIG[domain]};
    
    # SSL configuration (will be populated by certbot)
    # ssl_certificate /etc/letsencrypt/live/dashboard.${CONFIG[domain]}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/dashboard.${CONFIG[domain]}/privkey.pem;
    
    # Serve static files or proxy to dashboard service
    root /var/www/netmaker-ui;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ @netmaker_api;
    }
    
    location @netmaker_api {
        proxy_pass http://${target_ip}:${CONFIG[api_port]};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    
    # Enable the site
    ln -sf /etc/nginx/sites-available/netmaker /etc/nginx/sites-enabled/netmaker
    
    # Remove default site
    rm -f /etc/nginx/sites-enabled/default
    
    # Test nginx configuration
    print_info "Testing nginx configuration..."
    if nginx -t; then
        print_status "Nginx configuration is valid"
    else
        print_error "Nginx configuration test failed"
        exit 1
    fi
    
    # Reload nginx
    systemctl reload nginx || systemctl restart nginx
    print_status "Nginx configured and reloaded"
}

# Create systemd services
create_systemd_services() {
    if [[ "${CONFIG[install_netmaker]}" != "true" ]]; then
        return 0
    fi
    
    print_header "Creating SystemD Services"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Create Netmaker systemd service
    cat > /etc/systemd/system/netmaker.service << EOF
[Unit]
Description=Netmaker Server
Documentation=https://netmaker.readthedocs.io
Wants=network-online.target
After=network-online.target
After=mosquitto.service
Requires=mosquitto.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
WorkingDirectory=/opt/netmaker
ExecStart=/usr/local/bin/netmaker --config /etc/netmaker/config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=netmaker

# Security settings
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/netmaker /var/log/netmaker /etc/netmaker

# Environment
Environment=NM_CONFIG_PATH=/etc/netmaker/config.yaml

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable netmaker
    
    print_status "Netmaker systemd service created and enabled"
}

# Setup SSL certificates
setup_ssl_certificates() {
    if [[ "${CONFIG[setup_ssl]}" != "true" ]]; then
        return 0
    fi
    
    print_header "Setting up SSL Certificates"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check DNS resolution
    local domains=("netmaker.${CONFIG[domain]}" "broker.${CONFIG[domain]}" "dashboard.${CONFIG[domain]}")
    local dns_ok=true
    
    for domain in "${domains[@]}"; do
        print_info "Checking DNS resolution for $domain..."
        local resolved_ip=$(dig +short "$domain" | tail -n1 2>/dev/null || echo "")
        
        if [[ -n "$resolved_ip" ]]; then
            print_status "$domain resolves to: $resolved_ip"
            
            # Check if it matches our expected IP
            local expected_ip
            if [[ "${CONFIG[deployment_type]}" == "proxmox-lxc" ]]; then
                expected_ip="${CONFIG[host_public_ip]}"
            else
                expected_ip="${CONFIG[server_ip]}"
            fi
            
            if [[ "$resolved_ip" != "$expected_ip" ]]; then
                print_warning "$domain resolves to unexpected IP: $resolved_ip (expected: $expected_ip)"
            fi
        else
            print_error "$domain DNS resolution failed"
            dns_ok=false
        fi
    done
    
    if [[ "$dns_ok" != "true" ]]; then
        print_warning "DNS resolution issues detected"
        print_question "Continue with SSL setup anyway? [y/N]:"
        read -p "> " continue_ssl
        if [[ ! "$continue_ssl" =~ ^[Yy]$ ]]; then
            print_info "Skipping SSL setup. You can run certbot manually later."
            return 0
        fi
    fi
    
    # Obtain SSL certificates
    print_info "Obtaining SSL certificates for all domains..."
    
    local domain_args=""
    for domain in "${domains[@]}"; do
        domain_args="$domain_args -d $domain"
    done
    
    if certbot --nginx $domain_args --non-interactive --agree-tos --email "admin@${CONFIG[domain]}" --no-eff-email; then
        print_status "SSL certificates obtained successfully"
        
        # Verify certificates
        for domain in "${domains[@]}"; do
            if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
                print_status "Certificate verified for $domain"
            fi
        done
    else
        print_warning "SSL certificate setup failed"
        print_info "You can run certbot manually later with:"
        print_info "certbot --nginx $domain_args"
    fi
}

# Start all services
start_services() {
    print_header "Starting Services"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Start Mosquitto
    if [[ "${CONFIG[install_mosquitto]}" == "true" ]]; then
        print_info "Starting Mosquitto..."
        systemctl start mosquitto
        
        if systemctl is-active --quiet mosquitto; then
            print_status "Mosquitto is running"
        else
            print_error "Mosquitto failed to start"
            journalctl -u mosquitto --no-pager -n 10
        fi
    fi
    
    # Start Nginx
    if [[ "${CONFIG[install_nginx]}" == "true" ]]; then
        print_info "Starting Nginx..."
        systemctl restart nginx
        
        if systemctl is-active --quiet nginx; then
            print_status "Nginx is running"
        else
            print_error "Nginx failed to start"
            journalctl -u nginx --no-pager -n 10
        fi
    fi
    
    # Start Netmaker
    if [[ "${CONFIG[install_netmaker]}" == "true" ]]; then
        print_info "Starting Netmaker..."
        systemctl start netmaker
        
        # Wait for startup
        sleep 5
        
        if systemctl is-active --quiet netmaker; then
            print_status "Netmaker is running"
            
            # Monitor for MQTT connection success
            print_info "Monitoring Netmaker startup for MQTT connection..."
            local timeout=30
            local count=0
            
            while [[ $count -lt $timeout ]]; do
                if journalctl -u netmaker --no-pager -n 50 | grep -q "Fatal.*could not connect to broker"; then
                    print_error "Netmaker MQTT connection failed - check broker configuration"
                    journalctl -u netmaker --no-pager -n 10
                    break
                elif journalctl -u netmaker --no-pager -n 20 | grep -qE "(server starting|API server listening)"; then
                    print_status "Netmaker started successfully"
                    break
                fi
                
                sleep 1
                ((count++))
            done
            
            if [[ $count -ge $timeout ]]; then
                print_warning "Netmaker startup monitoring timed out"
            fi
        else
            print_error "Netmaker failed to start"
            journalctl -u netmaker --no-pager -n 20
        fi
    fi
}

# Comprehensive installation validation
validate_installation() {
    print_header "Installation Validation"
    echo "────────────────────────────────────────────────────────────────────────"
    
    local validation_passed=true
    
    # Service status checks
    print_info "Checking service status..."
    
    if [[ "${CONFIG[install_mosquitto]}" == "true" ]]; then
        if systemctl is-active --quiet mosquitto; then
            print_status "✓ Mosquitto service is running"
        else
            print_error "✗ Mosquitto service is not running"
            validation_passed=false
        fi
    fi
    
    if [[ "${CONFIG[install_nginx]}" == "true" ]]; then
        if systemctl is-active --quiet nginx; then
            print_status "✓ Nginx service is running"
        else
            print_error "✗ Nginx service is not running"
            validation_passed=false
        fi
    fi
    
    if [[ "${CONFIG[install_netmaker]}" == "true" ]]; then
        if systemctl is-active --quiet netmaker; then
            print_status "✓ Netmaker service is running"
        else
            print_error "✗ Netmaker service is not running"
            validation_passed=false
        fi
    fi
    
    # Port listening checks
    print_info "Checking port bindings..."
    
    local expected_ports=()
    [[ "${CONFIG[install_nginx]}" == "true" ]] && expected_ports+=("80" "443")
    [[ "${CONFIG[install_mosquitto]}" == "true" ]] && expected_ports+=("${CONFIG[mqtt_port]}" "${CONFIG[mqtt_ws_port]}")
    [[ "${CONFIG[install_netmaker]}" == "true" ]] && expected_ports+=("${CONFIG[api_port]}")
    
    for port in "${expected_ports[@]}"; do
        if ss -tlnp | grep -q ":$port "; then
            print_status "✓ Port $port is listening"
        else
            print_error "✗ Port $port is not listening"
            validation_passed=false
        fi
    done
    
    # MQTT connectivity test
    if [[ "${CONFIG[install_mosquitto]}" == "true" ]]; then
        print_info "Testing MQTT broker connectivity..."
        
        local mqtt_test_cmd="mosquitto_pub -h 127.0.0.1 -p ${CONFIG[mqtt_port]} -t test/connection -m 'test'"
        
        if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
            mqtt_test_cmd="$mqtt_test_cmd -u ${CONFIG[mqtt_username]} -P ${CONFIG[mqtt_password]}"
        fi
        
        if timeout 5 $mqtt_test_cmd 2>/dev/null; then
            print_status "✓ MQTT broker accepts connections"
        else
            print_error "✗ MQTT broker connection test failed"
            validation_passed=false
        fi
    fi
    
    # API endpoint test
    if [[ "${CONFIG[install_netmaker]}" == "true" ]]; then
        print_info "Testing Netmaker API endpoint..."
        
        local api_url="http://127.0.0.1:${CONFIG[api_port]}/api/server/health"
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" "$api_url" 2>/dev/null || echo "000")
        
        if [[ "$response_code" == "200" ]] || [[ "$response_code" == "401" ]]; then
            print_status "✓ Netmaker API is responding (HTTP $response_code)"
        else
            print_warning "⚠ Netmaker API test returned HTTP $response_code (may still be starting)"
        fi
    fi
    
    # SSL certificate validation
    if [[ "${CONFIG[setup_ssl]}" == "true" ]]; then
        print_info "Validating SSL certificates..."
        
        local ssl_domains=("netmaker.${CONFIG[domain]}" "broker.${CONFIG[domain]}" "dashboard.${CONFIG[domain]}")
        for domain in "${ssl_domains[@]}"; do
            if [[ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]]; then
                print_status "✓ SSL certificate exists for $domain"
            else
                print_warning "⚠ SSL certificate not found for $domain"
            fi
        done
    fi
    
    echo
    if [[ "$validation_passed" == "true" ]]; then
        print_status "✅ All validation checks passed!"
    else
        print_warning "⚠️  Some validation checks failed - review errors above"
    fi
    
    return 0
}

# Generate installation summary and next steps
generate_completion_summary() {
    print_header "Installation Complete!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    print_status "🎉 GhostBridge Netmaker GO stack installation completed!"
    echo
    
    echo -e "${CYAN}📋 Installation Summary:${NC}"
    echo "  • Deployment Type: ${CONFIG[deployment_type]}"
    echo "  • Domain: ${CONFIG[domain]}"
    echo "  • Netmaker API: https://netmaker.${CONFIG[domain]}"
    echo "  • MQTT Broker: mqtt://broker.${CONFIG[domain]}:${CONFIG[mqtt_port]}"
    echo "  • Dashboard: https://dashboard.${CONFIG[domain]}"
    echo
    
    echo -e "${CYAN}🔧 Service Status:${NC}"
    [[ "${CONFIG[install_netmaker]}" == "true" ]] && echo "  • Netmaker: $(systemctl is-active netmaker)"
    [[ "${CONFIG[install_mosquitto]}" == "true" ]] && echo "  • Mosquitto: $(systemctl is-active mosquitto)"
    [[ "${CONFIG[install_nginx]}" == "true" ]] && echo "  • Nginx: $(systemctl is-active nginx)"
    echo
    
    echo -e "${CYAN}📁 Important Files:${NC}"
    echo "  • Configuration: /etc/netmaker/config.yaml"
    echo "  • MQTT Config: /etc/mosquitto/mosquitto.conf"
    echo "  • Nginx Config: /etc/nginx/sites-available/netmaker"
    echo "  • Installation Log: $LOG_FILE"
    echo "  • Backups: $BACKUP_DIR"
    echo
    
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        echo -e "${CYAN}🔐 MQTT Credentials:${NC}"
        echo "  • Username: ${CONFIG[mqtt_username]}"
        echo "  • Password: ${CONFIG[mqtt_password]}"
        echo "  ⚠️  Save these credentials securely!"
        echo
    fi
    
    if [[ -n "${CONFIG[master_key]:-}" ]]; then
        echo -e "${CYAN}🔑 Netmaker Master Key:${NC}"
        echo "  • Master Key: ${CONFIG[master_key]}"
        echo "  ⚠️  Save this key securely for API access!"
        echo
    fi
    
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo "  1. Verify all services are running: systemctl status netmaker mosquitto nginx"
    echo "  2. Access the Netmaker dashboard at https://dashboard.${CONFIG[domain]}"
    echo "  3. Create your first admin user and network"
    echo "  4. Download and configure netclient on your devices"
    
    if [[ "${CONFIG[deployment_type]}" == "proxmox-lxc" ]]; then
        echo "  5. Run the netmaker-ovs-integration script for advanced networking"
    fi
    echo
    
    echo -e "${CYAN}🔍 Troubleshooting:${NC}"
    echo "  • Check logs: journalctl -u netmaker -f"
    echo "  • MQTT test: mosquitto_pub -h 127.0.0.1 -p ${CONFIG[mqtt_port]} -t test -m hello"
    echo "  • API test: curl http://127.0.0.1:${CONFIG[api_port]}/api/server/health"
    echo "  • Installation log: $LOG_FILE"
    echo
    
    # Save installation summary
    local summary_file="/etc/netmaker/installation-summary.txt"
    {
        echo "GhostBridge Netmaker Installation Summary"
        echo "Generated: $(date)"
        echo ""
        echo "Deployment Type: ${CONFIG[deployment_type]}"
        echo "Domain: ${CONFIG[domain]}"
        echo ""
        echo "Service Endpoints:"
        echo "  API: https://netmaker.${CONFIG[domain]}"
        echo "  MQTT: mqtt://broker.${CONFIG[domain]}:${CONFIG[mqtt_port]}"
        echo "  Dashboard: https://dashboard.${CONFIG[domain]}"
        echo ""
        echo "Authentication:"
        [[ "${CONFIG[secure_mqtt]}" == "true" ]] && echo "  MQTT Username: ${CONFIG[mqtt_username]}"
        [[ "${CONFIG[secure_mqtt]}" == "true" ]] && echo "  MQTT Password: ${CONFIG[mqtt_password]}"
        [[ -n "${CONFIG[master_key]:-}" ]] && echo "  Master Key: ${CONFIG[master_key]}"
        echo ""
        echo "Installation Log: $LOG_FILE"
        echo "Configuration Backup: $BACKUP_DIR"
    } > "$summary_file"
    
    print_status "Installation summary saved to: $summary_file"
    
    echo "════════════════════════════════════════════════════════════════════════"
}

# Main execution function
main() {
    show_banner
    
    log "Starting GhostBridge Netmaker installer v$SCRIPT_VERSION"
    
    check_root
    preflight_validation
    gather_configuration
    display_configuration_summary
    
    print_header "Beginning Installation Process"
    echo "════════════════════════════════════════════════════════════════════════"
    
    create_backup
    install_dependencies
    install_netmaker_binary
    configure_mosquitto
    configure_netmaker
    configure_nginx
    create_systemd_services
    setup_ssl_certificates
    start_services
    validate_installation
    generate_completion_summary
    
    log "GhostBridge Netmaker installation completed successfully"
    
    save_configuration
}

# Execute main function with all arguments
main "$@"