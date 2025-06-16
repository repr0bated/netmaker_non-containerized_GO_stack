#!/bin/bash

# GhostBridge Container Services Installation Script
# Installs Netmaker and Mosquitto inside the LXC container
# This script should be copied to and run inside the container

set -euo pipefail

SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/netmaker-container-install.log"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default configuration from CLAUDE.md
DEFAULT_DOMAIN="hobsonschoice.net"
DEFAULT_MQTT_PORT="1883"
DEFAULT_MQTT_WS_PORT="9001" 
DEFAULT_API_PORT="8081"
DEFAULT_MQTT_USERNAME="netmaker"

# Configuration storage
declare -A CONFIG

# Utility functions
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
    echo -e "${CYAN}[CONTAINER]${NC} $1" | tee -a "$LOG_FILE"
}

print_question() {
    echo -e "${PURPLE}[?]${NC} $1"
}

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║        GhostBridge Container Services Installation Script                 ║
║                                                                           ║
║         Installs Netmaker and Mosquitto inside LXC container             ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
    print_info "Version: $SCRIPT_VERSION"
    print_info "Purpose: Install Netmaker and Mosquitto in container"
    print_info "Log File: $LOG_FILE"
    echo
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root inside the LXC container"
        exit 1
    fi
}

# Check if running inside LXC container
check_container() {
    if [[ ! -f /proc/self/cgroup ]] || ! grep -q lxc /proc/self/cgroup; then
        print_warning "This script is designed to run inside an LXC container"
        print_question "Continue anyway? [y/N]: "
        read -r continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        print_status "Running inside LXC container"
    fi
}

# Get configuration from user or environment
get_configuration() {
    print_header "Container Service Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if we have environment variables (set by container creation script)
    if [[ -n "${GHOSTBRIDGE_DOMAIN:-}" ]]; then
        CONFIG[domain]="$GHOSTBRIDGE_DOMAIN"
        print_info "Using domain from environment: ${CONFIG[domain]}"
    else
        print_question "Enter domain name:"
        read -p "Domain [$DEFAULT_DOMAIN]: " domain
        CONFIG[domain]="${domain:-$DEFAULT_DOMAIN}"
    fi
    
    print_question "Use secure MQTT authentication? [Y/n]:"
    read -p "> " secure_mqtt
    if [[ "$secure_mqtt" =~ ^[Nn]$ ]]; then
        CONFIG[secure_mqtt]="false"
        print_warning "MQTT will allow anonymous access (not recommended for production)"
    else
        CONFIG[secure_mqtt]="true"
        CONFIG[mqtt_username]="$DEFAULT_MQTT_USERNAME"
        CONFIG[mqtt_password]=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-25)
        print_status "Generated secure MQTT credentials"
    fi
    
    # Use default ports
    CONFIG[mqtt_port]="$DEFAULT_MQTT_PORT"
    CONFIG[mqtt_ws_port]="$DEFAULT_MQTT_WS_PORT"
    CONFIG[api_port]="$DEFAULT_API_PORT"
    
    echo
    print_info "Configuration summary:"
    echo "  • Domain: ${CONFIG[domain]}"
    echo "  • MQTT TCP Port: ${CONFIG[mqtt_port]}"
    echo "  • MQTT WebSocket Port: ${CONFIG[mqtt_ws_port]}"
    echo "  • API Port: ${CONFIG[api_port]}"
    echo "  • Secure MQTT: ${CONFIG[secure_mqtt]}"
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        echo "  • MQTT Username: ${CONFIG[mqtt_username]}"
        echo "  • MQTT Password: [Generated]"
    fi
    echo
}

# Update system packages
update_system() {
    print_header "Updating System Packages"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Updating package lists..."
    apt update
    
    print_info "Upgrading system packages..."
    apt upgrade -y
    
    print_info "Installing essential packages..."
    apt install -y \
        curl wget unzip sqlite3 jq openssl dnsutils net-tools \
        systemd systemd-sysv ca-certificates gnupg lsb-release \
        iptables iproute2
    
    print_status "System updated successfully"
}

# Download and install Netmaker binary
install_netmaker() {
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
    mkdir -p /var/backups/netmaker
    
    print_status "Netmaker installation completed"
}

# Install and configure Mosquitto
install_mosquitto() {
    print_header "Installing and Configuring Mosquitto"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Installing Mosquitto MQTT broker..."
    apt install -y mosquitto mosquitto-clients
    
    # Stop default service to configure it
    systemctl stop mosquitto || true
    systemctl disable mosquitto || true
    
    print_status "Mosquitto installed successfully"
}

# Configure Mosquitto with proper security
configure_mosquitto() {
    print_header "Configuring Mosquitto MQTT Broker"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Creating Mosquitto configuration..."
    
    # Create mosquitto configuration addressing critical issues from CLAUDE.md
    cat > /etc/mosquitto/mosquitto.conf << EOF
# GhostBridge Mosquitto Configuration for LXC Container
# Generated by GhostBridge container installer
# Addresses critical MQTT connection issues: binds to 0.0.0.0, not 127.0.0.1

# MQTT TCP Listener (Critical: must bind to 0.0.0.0 for Proxmox host access)
listener ${CONFIG[mqtt_port]}
bind_address 0.0.0.0
protocol mqtt
EOF
    
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        cat >> /etc/mosquitto/mosquitto.conf << EOF
allow_anonymous false

# MQTT WebSocket Listener (Critical: required for web-based connections)
listener ${CONFIG[mqtt_ws_port]}
bind_address 0.0.0.0
protocol websockets
allow_anonymous false

# Authentication Configuration
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
        
        # Set proper permissions
        chown mosquitto:mosquitto /etc/mosquitto/passwd /etc/mosquitto/acl
        chmod 600 /etc/mosquitto/passwd /etc/mosquitto/acl
        
    else
        cat >> /etc/mosquitto/mosquitto.conf << EOF
allow_anonymous true

# MQTT WebSocket Listener
listener ${CONFIG[mqtt_ws_port]}
bind_address 0.0.0.0
protocol websockets
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
    mkdir -p /var/log/mosquitto
    chown mosquitto:mosquitto /var/log/mosquitto
    
    # Test configuration
    print_info "Testing Mosquitto configuration..."
    if mosquitto -c /etc/mosquitto/mosquitto.conf -t; then
        print_status "Mosquitto configuration is valid"
    else
        print_error "Mosquitto configuration test failed"
        exit 1
    fi
    
    print_status "Mosquitto configured successfully"
}

# Create Netmaker configuration
configure_netmaker() {
    print_header "Configuring Netmaker Server"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Generate master key
    local master_key=$(openssl rand -hex 32)
    
    # Create broker endpoint for local MQTT connection
    local broker_endpoint
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        broker_endpoint="mqtt://${CONFIG[mqtt_username]}:${CONFIG[mqtt_password]}@127.0.0.1:${CONFIG[mqtt_port]}"
    else
        broker_endpoint="mqtt://127.0.0.1:${CONFIG[mqtt_port]}"
    fi
    
    print_info "MQTT Broker Endpoint: mqtt://127.0.0.1:${CONFIG[mqtt_port]} (credentials hidden)"
    
    # Create Netmaker configuration addressing MQTT connection issues
    cat > /etc/netmaker/config.yaml << EOF
# GhostBridge Netmaker Configuration for LXC Container
# Generated by GhostBridge container installer
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

# Database Configuration (SQLite)
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

# OAuth Configuration (empty for now)
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
    
    # Save credentials for user reference and API access
    cat > /etc/netmaker/credentials.env << EOF
# GhostBridge Netmaker Credentials
# Generated: $(date)
# Source this file to access variables: source /etc/netmaker/credentials.env

export NETMAKER_MASTER_KEY="${master_key}"
export NETMAKER_DOMAIN="${CONFIG[domain]}"
export NETMAKER_API_ENDPOINT="https://netmaker.${CONFIG[domain]}"
export NETMAKER_API_URL="https://netmaker.${CONFIG[domain]}/api"
export GHOSTBRIDGE_CONTROL_PANEL="https://ghostbridge.${CONFIG[domain]}"
EOF

    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        cat >> /etc/netmaker/credentials.env << EOF
export MQTT_USERNAME="${CONFIG[mqtt_username]}"
export MQTT_PASSWORD="${CONFIG[mqtt_password]}"
export MQTT_ENDPOINT="mqtt://broker.${CONFIG[domain]}:${CONFIG[mqtt_port]}"
export MQTT_WS_ENDPOINT="wss://broker.${CONFIG[domain]}:${CONFIG[mqtt_ws_port]}"
EOF
    fi
    
    # Also create a simple access script for the master key
    cat > /etc/netmaker/get-master-key.sh << EOF
#!/bin/bash
# Quick access to Netmaker master key for API calls
source /etc/netmaker/credentials.env
echo "\$NETMAKER_MASTER_KEY"
EOF
    
    chmod 600 /etc/netmaker/credentials.env
    chmod 700 /etc/netmaker/get-master-key.sh
    
    print_status "Credentials saved to /etc/netmaker/credentials.env"
    print_info "Master Key: $master_key"
    
    # Test Netmaker binary
    print_info "Testing Netmaker binary..."
    cd /opt/netmaker
    if /usr/local/bin/netmaker --config /etc/netmaker/config.yaml --version >/dev/null 2>&1; then
        print_status "Netmaker binary is functional"
    else
        print_error "Netmaker binary test failed"
        exit 1
    fi
}

# Create systemd services
create_systemd_services() {
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
    systemctl enable mosquitto
    systemctl enable netmaker
    
    print_status "SystemD services created and enabled"
}

# Start services in proper order
start_services() {
    print_header "Starting Services"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Start Mosquitto first
    print_info "Starting Mosquitto MQTT broker..."
    systemctl start mosquitto
    
    sleep 3
    
    if systemctl is-active --quiet mosquitto; then
        print_status "✓ Mosquitto service is running"
        
        # Verify port binding (critical check from troubleshooting)
        if ss -tlnp | grep -q ":${CONFIG[mqtt_port]} "; then
            print_status "✓ MQTT TCP listening on port ${CONFIG[mqtt_port]}"
        else
            print_error "✗ MQTT TCP failed to bind to port ${CONFIG[mqtt_port]}"
            journalctl -u mosquitto --no-pager -n 20
            exit 1
        fi
        
        if ss -tlnp | grep -q ":${CONFIG[mqtt_ws_port]} "; then
            print_status "✓ MQTT WebSocket listening on port ${CONFIG[mqtt_ws_port]}"
        else
            print_error "✗ MQTT WebSocket failed to bind to port ${CONFIG[mqtt_ws_port]}"
            journalctl -u mosquitto --no-pager -n 20
            exit 1
        fi
    else
        print_error "✗ Mosquitto service failed to start"
        journalctl -u mosquitto --no-pager -n 20
        exit 1
    fi
    
    # Start Netmaker
    print_info "Starting Netmaker server..."
    systemctl start netmaker
    
    # Wait for startup and monitor
    print_info "Monitoring Netmaker startup..."
    local timeout=30
    local count=0
    
    while [[ $count -lt $timeout ]]; do
        if systemctl is-active --quiet netmaker; then
            # Check for specific error messages from troubleshooting
            if journalctl -u netmaker --no-pager -n 50 | grep -q "Fatal.*could not connect to broker"; then
                print_error "✗ Netmaker MQTT connection failed - check broker configuration"
                journalctl -u netmaker --no-pager -n 10
                exit 1
            elif journalctl -u netmaker --no-pager -n 20 | grep -qE "(server starting|API server listening)"; then
                print_status "✓ Netmaker started successfully"
                break
            fi
        fi
        
        sleep 1
        ((count++))
    done
    
    if [[ $count -ge $timeout ]]; then
        print_warning "⚠ Netmaker startup monitoring timed out"
        if systemctl is-active --quiet netmaker; then
            print_status "✓ Netmaker service is running (may still be initializing)"
        else
            print_error "✗ Netmaker service failed to start"
            journalctl -u netmaker --no-pager -n 20
            exit 1
        fi
    fi
}

# Test MQTT connectivity
test_mqtt_connectivity() {
    print_header "Testing MQTT Connectivity"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Testing MQTT broker connectivity..."
    
    local mqtt_test_cmd="mosquitto_pub -h 127.0.0.1 -p ${CONFIG[mqtt_port]} -t test/connection -m 'container-test'"
    
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        mqtt_test_cmd="$mqtt_test_cmd -u ${CONFIG[mqtt_username]} -P ${CONFIG[mqtt_password]}"
    fi
    
    if timeout 5 $mqtt_test_cmd 2>/dev/null; then
        print_status "✓ MQTT broker accepts connections"
    else
        print_error "✗ MQTT broker connection test failed"
        return 1
    fi
    
    # Test WebSocket endpoint (if available)
    if command -v nc >/dev/null 2>&1; then
        if timeout 3 nc -z 127.0.0.1 "${CONFIG[mqtt_ws_port]}" 2>/dev/null; then
            print_status "✓ MQTT WebSocket port is accessible"
        else
            print_warning "⚠ MQTT WebSocket port connection test failed"
        fi
    fi
}

# Test Netmaker API
test_netmaker_api() {
    print_header "Testing Netmaker API"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Testing Netmaker API endpoint..."
    
    local api_url="http://127.0.0.1:${CONFIG[api_port]}/api/server/health"
    local response_code=$(curl -s -o /dev/null -w "%{http_code}" "$api_url" 2>/dev/null || echo "000")
    
    if [[ "$response_code" == "200" ]]; then
        print_status "✓ Netmaker API is responding (HTTP $response_code)"
    elif [[ "$response_code" == "401" ]]; then
        print_status "✓ Netmaker API is responding (HTTP $response_code - authentication required)"
    else
        print_warning "⚠ Netmaker API test returned HTTP $response_code (may still be starting)"
    fi
}

# Comprehensive validation
validate_installation() {
    print_header "Validating Container Installation"
    echo "────────────────────────────────────────────────────────────────────────"
    
    local validation_passed=true
    
    # Service status checks
    print_info "Checking service status..."
    
    if systemctl is-active --quiet mosquitto; then
        print_status "✓ Mosquitto service is running"
    else
        print_error "✗ Mosquitto service is not running"
        validation_passed=false
    fi
    
    if systemctl is-active --quiet netmaker; then
        print_status "✓ Netmaker service is running"
    else
        print_error "✗ Netmaker service is not running"
        validation_passed=false
    fi
    
    # Port listening checks
    print_info "Checking port bindings..."
    local expected_ports=("${CONFIG[mqtt_port]}" "${CONFIG[mqtt_ws_port]}" "${CONFIG[api_port]}")
    
    for port in "${expected_ports[@]}"; do
        if ss -tlnp | grep -q ":$port "; then
            print_status "✓ Port $port is listening"
        else
            print_error "✗ Port $port is not listening"
            validation_passed=false
        fi
    done
    
    # MQTT connectivity test
    if test_mqtt_connectivity; then
        print_status "✓ MQTT connectivity test passed"
    else
        print_error "✗ MQTT connectivity test failed"
        validation_passed=false
    fi
    
    # API test
    test_netmaker_api
    
    echo
    if [[ "$validation_passed" == "true" ]]; then
        print_status "✅ Container installation validation passed!"
    else
        print_warning "⚠️ Some validation checks failed - review errors above"
    fi
    
    return 0
}

# Display completion summary
show_completion() {
    print_header "Container Installation Complete!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    print_status "🎉 Container services installation completed!"
    echo
    
    echo -e "${CYAN}📋 Installed Services:${NC}"
    echo "  • Netmaker Server: $(systemctl is-active netmaker)"
    echo "  • Mosquitto MQTT: $(systemctl is-active mosquitto)"
    echo
    
    echo -e "${CYAN}🌐 Service Endpoints (Container):${NC}"
    echo "  • Netmaker API: http://$(hostname -I | awk '{print $1}'):${CONFIG[api_port]}"
    echo "  • MQTT TCP: mqtt://$(hostname -I | awk '{print $1}'):${CONFIG[mqtt_port]}"
    echo "  • MQTT WebSocket: ws://$(hostname -I | awk '{print $1}'):${CONFIG[mqtt_ws_port]}"
    echo
    
    if [[ "${CONFIG[secure_mqtt]}" == "true" ]]; then
        echo -e "${CYAN}🔐 MQTT Credentials:${NC}"
        echo "  • Username: ${CONFIG[mqtt_username]}"
        echo "  • Password: ${CONFIG[mqtt_password]}"
        echo
    fi
    
    echo -e "${CYAN}📁 Important Files:${NC}"
    echo "  • Netmaker config: /etc/netmaker/config.yaml"
    echo "  • MQTT config: /etc/mosquitto/mosquitto.conf"
    echo "  • Credentials: /etc/netmaker/credentials.env"
    echo "  • Installation log: $LOG_FILE"
    echo
    
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo "  1. Configure nginx reverse proxy on Proxmox host"
    echo "  2. Set up SSL certificates for external access"
    echo "  3. Configure DNS to point to Proxmox host"
    echo "  4. Access Netmaker at https://netmaker.${CONFIG[domain]}"
    echo "  5. Create your first admin user and network"
    echo
    
    echo -e "${CYAN}🔍 Container Management:${NC}"
    echo "  • Check services: systemctl status netmaker mosquitto"
    echo "  • View logs: journalctl -u netmaker -f"
    echo "  • Test MQTT: mosquitto_pub -h 127.0.0.1 -p ${CONFIG[mqtt_port]} -t test -m hello"
    echo "  • Test API: curl http://127.0.0.1:${CONFIG[api_port]}/api/server/health"
    echo
    
    echo "════════════════════════════════════════════════════════════════════════"
}

# Main execution function
main() {
    show_banner
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting container services installation v$SCRIPT_VERSION" >> "$LOG_FILE"
    
    check_root
    check_container
    get_configuration
    
    print_header "Installing Container Services"
    echo "════════════════════════════════════════════════════════════════════════"
    
    update_system
    install_netmaker
    install_mosquitto
    configure_mosquitto
    configure_netmaker
    create_systemd_services
    start_services
    validate_installation
    show_completion
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Container installation completed successfully" >> "$LOG_FILE"
}

# Execute main function with all arguments
main "$@"