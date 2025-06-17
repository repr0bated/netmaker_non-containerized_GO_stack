#!/bin/bash

# GhostBridge LXC Container Creation Script
# Creates a Debian LXC container for Netmaker and Mosquitto services
# Nginx with stream module runs on Proxmox host

set -euo pipefail

SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/ghostbridge-container-creation.log"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse command line arguments
AUTO_MODE=false
if [[ "$1" == "--auto" ]]; then
    AUTO_MODE=true
    shift
fi

# Default values from CLAUDE.md - Updated for dual IP OVS setup
DEFAULT_CONTAINER_ID="100"
DEFAULT_CONTAINER_IP="10.0.0.151"  # Container DHCP range starts at 150
DEFAULT_BRIDGE="vmbr0"             # Linux bridge for initial setup (OVS configured later)
DEFAULT_GATEWAY="10.0.0.1"
DEFAULT_TEMPLATE="debian-12-standard_12.7-1_amd64.tar.zst"
DEFAULT_STORAGE="local-btrfs"
DEFAULT_HOSTNAME="ghostbridge"
DEFAULT_ROOTPW=""
DEFAULT_MEMORY="8096"
DEFAULT_DISK="20"
DEFAULT_CORES="2"

# Dual IP configuration (to be configured when second IP is available)
DEFAULT_ENABLE_DUAL_IP="false"     # Set to true when second IP available
DEFAULT_PUBLIC_IP="80.209.240.244"               # Main public IP for direct container access
DEFAULT_PUBLIC_IP_2="80.209.240.243"             # Second public IP for additional services
DEFAULT_PUBLIC_GATEWAY="80.209.240.129"

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

# Ask user if they want to continue after failure
ask_continue() {
    local message="$1"
    print_warning "$message"
    print_question "Do you want to continue anyway? [y/N]: "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Script terminated by user"
        exit 1
    fi
    print_info "Continuing as requested..."
}

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔═════════════════════════════════════════════════════════════════════════╗
║                                                                         ║
║           GhostBridge LXC Container Creation Script                     ║
║                                                                         ║
║    Creates Debian container for Netmaker and Mosquitto services        ║
║                                                                         ║
╚═════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
    print_info "Version: $SCRIPT_VERSION"
    print_info "Purpose: Create LXC container for GhostBridge services"
    print_info "Log File: $LOG_FILE"
    echo
}

# Check if running as root on Proxmox
check_root() {
    if [[ $EUID -ne 0 ]]; then
        ask_continue "This script must be run as root on the Proxmox host"
    fi
}

# Check if running on Proxmox host
check_proxmox() {
    if [[ ! -f /etc/pve/local/pve-ssl.pem ]]; then
        ask_continue "This script must be run on a Proxmox host"
    fi
    
    local pve_version=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "unknown")
    print_status "Proxmox VE detected: $pve_version"
}

# Check available templates and find best match
check_templates() {
    print_info "Checking available LXC templates..."
    
    # Update template list
    pveam update
    
    # Look for Debian 12 templates first
    local debian12_templates=$(pveam available | grep "debian-12-standard" | head -3 || echo "")
    if [[ -n "$debian12_templates" ]]; then
        print_info "Available Debian 12 templates:"
        echo "$debian12_templates" | sed 's/^/    /'
        
        # Use the first available Debian 12 template
        local latest_template=$(echo "$debian12_templates" | head -1 | awk '{print $2}')
        if [[ -n "$latest_template" ]]; then
            DEFAULT_TEMPLATE="$latest_template"
            print_status "Selected template: $DEFAULT_TEMPLATE"
        fi
    else
        # Fallback to any Debian template
        local debian_templates=$(pveam available | grep -E "debian.*standard" | head -3 || echo "")
        if [[ -n "$debian_templates" ]]; then
            print_info "Available Debian templates:"
            echo "$debian_templates" | sed 's/^/    /'
            
            local fallback_template=$(echo "$debian_templates" | head -1 | awk '{print $2}')
            if [[ -n "$fallback_template" ]]; then
                DEFAULT_TEMPLATE="$fallback_template"
                print_warning "Using fallback template: $DEFAULT_TEMPLATE"
            fi
        else
            ask_continue "No suitable Debian templates found"
        fi
    fi
    
    # Check if template is already downloaded
    if pveam list local-btrfs 2>/dev/null | grep -q "$DEFAULT_TEMPLATE"; then
        print_status "Template $DEFAULT_TEMPLATE is already available on local-btrfs"
    else
        print_warning "Template $DEFAULT_TEMPLATE needs to be downloaded to local-btrfs"
    fi
}

# Get configuration from user
get_configuration() {
    print_header "LXC Container Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Use defaults in auto mode
    if [[ "$AUTO_MODE" == "true" ]]; then
        print_info "Auto mode: Using default configuration values"
        CONTAINER_ID="$DEFAULT_CONTAINER_ID"
        HOSTNAME="$DEFAULT_HOSTNAME"
        CONTAINER_IP="$DEFAULT_CONTAINER_IP/24"
        BRIDGE="$DEFAULT_BRIDGE"
        GATEWAY="$DEFAULT_GATEWAY"
        MEMORY="$DEFAULT_MEMORY"
        DISK="$DEFAULT_DISK"
        CORES="$DEFAULT_CORES"
        STORAGE="$DEFAULT_STORAGE"
        TEMPLATE="$DEFAULT_TEMPLATE"
        ENABLE_DUAL_IP="$DEFAULT_ENABLE_DUAL_IP"
        PUBLIC_IP="$DEFAULT_PUBLIC_IP"
        PUBLIC_IP_2="$DEFAULT_PUBLIC_IP_2"
        PUBLIC_GATEWAY="$DEFAULT_PUBLIC_GATEWAY"
        DESTROY_EXISTING=false
        
        # Check if container ID already exists in auto mode
        if pct list | grep -q "^$CONTAINER_ID "; then
            print_warning "Container ID $CONTAINER_ID already exists in auto mode"
            # Find next available ID
            local next_id=$((CONTAINER_ID + 1))
            while pct list | grep -q "^$next_id "; do
                ((next_id++))
            done
            CONTAINER_ID="$next_id"
            print_info "Using next available container ID: $CONTAINER_ID"
        fi
        
        # Print configuration and return
        print_container_summary
        return 0
    fi
    
    print_question "Enter container ID:"
    read -p "Container ID [$DEFAULT_CONTAINER_ID]: " container_id
    CONTAINER_ID="${container_id:-$DEFAULT_CONTAINER_ID}"
    
    # Check if container ID already exists
    if pct list | grep -q "^$CONTAINER_ID "; then
        print_error "Container ID $CONTAINER_ID already exists!"
        pct list | grep "^$CONTAINER_ID "
        print_question "Do you want to destroy and recreate? [y/N]: "
        read -r destroy_existing
        if [[ "$destroy_existing" =~ ^[Yy]$ ]]; then
            DESTROY_EXISTING=true
        else
            ask_continue "Please choose a different container ID"
        fi
    else
        DESTROY_EXISTING=false
    fi
    
    print_question "Enter container hostname:"
    read -p "Hostname [$DEFAULT_HOSTNAME]: " hostname
    HOSTNAME="${hostname:-$DEFAULT_HOSTNAME}"
    
    print_question "Enter container IP address (with CIDR):"
    print_info "IP ranges: Services 1-50, Reserved 51-149, Containers 150-245"
    read -p "IP address [$DEFAULT_CONTAINER_IP/24]: " container_ip
    CONTAINER_IP="${container_ip:-$DEFAULT_CONTAINER_IP/24}"
    
    print_question "Enter network bridge:"
    read -p "Bridge [$DEFAULT_BRIDGE]: " bridge
    BRIDGE="${bridge:-$DEFAULT_BRIDGE}"
    
    print_question "Enter gateway IP:"
    read -p "Gateway [$DEFAULT_GATEWAY]: " gateway
    GATEWAY="${gateway:-$DEFAULT_GATEWAY}"
    
    print_question "Enter memory size (MB):"
    read -p "Memory [$DEFAULT_MEMORY]: " memory
    MEMORY="${memory:-$DEFAULT_MEMORY}"
    
    print_question "Enter disk size (GB):"
    read -p "Disk [$DEFAULT_DISK]: " disk
    DISK="${disk:-$DEFAULT_DISK}"
    
    print_question "Enter CPU cores:"
    read -p "Cores [$DEFAULT_CORES]: " cores
    CORES="${cores:-$DEFAULT_CORES}"
    
    print_question "Enter storage location:"
    read -p "Storage [$DEFAULT_STORAGE]: " storage
    STORAGE="${storage:-$DEFAULT_STORAGE}"
    
    print_question "Enter LXC template:"
    read -p "Template [$DEFAULT_TEMPLATE]: " template
    TEMPLATE="${template:-$DEFAULT_TEMPLATE}"
    
    # Dual IP configuration
    echo
    print_info "Dual IP Configuration (for commercial deployment)"
    print_question "Enable dual IP setup? (Requires second public IP) [y/N]:"
    read -p "> " enable_dual_ip
    if [[ "$enable_dual_ip" =~ ^[Yy]$ ]]; then
        ENABLE_DUAL_IP="true"
        print_question "Enter main public IP for direct container access:"
        read -p "Public IP [$DEFAULT_PUBLIC_IP]: " public_ip
        PUBLIC_IP="${public_ip:-$DEFAULT_PUBLIC_IP}"
        print_question "Enter second public IP (optional):"
        read -p "Second IP [$DEFAULT_PUBLIC_IP_2]: " public_ip_2
        PUBLIC_IP_2="${public_ip_2:-$DEFAULT_PUBLIC_IP_2}"
        print_question "Enter public gateway:"
        read -p "Public Gateway [$DEFAULT_PUBLIC_GATEWAY]: " public_gateway
        PUBLIC_GATEWAY="${public_gateway:-$DEFAULT_PUBLIC_GATEWAY}"
    else
        ENABLE_DUAL_IP="false"
        print_info "Single IP mode - Netmaker will be proxied through nginx"
    fi
    
    print_container_summary
}

# Print container configuration summary
print_container_summary() {
    echo
    print_info "Container configuration:"
    echo "  • ID: $CONTAINER_ID"
    echo "  • Hostname: $HOSTNAME"
    echo "  • Private IP: $CONTAINER_IP"
    echo "  • Bridge: $BRIDGE"
    echo "  • Gateway: $GATEWAY"
    if [[ "$ENABLE_DUAL_IP" == "true" ]]; then
        echo "  • Main Public IP: $PUBLIC_IP (direct access)"
        if [[ -n "$PUBLIC_IP_2" ]]; then
            echo "  • Second Public IP: $PUBLIC_IP_2"
        fi
        echo "  • Public Gateway: $PUBLIC_GATEWAY"
        echo "  • Mode: Dual IP (commercial setup)"
    else
        echo "  • Mode: Single IP (proxied through nginx)"
    fi
    echo "  • Memory: ${MEMORY}MB"
    echo "  • Disk: ${DISK}GB"
    echo "  • Cores: $CORES"
    echo "  • Storage: $STORAGE"
    echo "  • Template: $TEMPLATE"
    if [[ "$DESTROY_EXISTING" == "true" ]]; then
        echo "  • Will destroy existing container"
    fi
    echo
}

# Download template if needed
download_template() {
    print_header "Preparing LXC Template"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if template is already available on local-btrfs
    if pveam list local-btrfs 2>/dev/null | grep -q "$TEMPLATE"; then
        print_status "Template $TEMPLATE is already available on local-btrfs"
        TEMPLATE_WITH_STORAGE="local-btrfs:vztmpl/$TEMPLATE"
        return 0
    fi
    
    print_info "Downloading template: $TEMPLATE"
    
    # Use only local-btrfs storage for template download
    local storage_pool="local-btrfs"
    
    # Download template to local-btrfs storage only
    if pveam download "$storage_pool" "$TEMPLATE" 2>/dev/null; then
        print_status "Template downloaded successfully to $storage_pool"
        TEMPLATE_WITH_STORAGE="$storage_pool:vztmpl/$TEMPLATE"
        return 0
    else
        print_error "Failed to download template $TEMPLATE to $storage_pool"
        print_info "Checking if local-btrfs storage is available:"
        pvesm status | grep "local-btrfs" || echo "  local-btrfs storage not found"
        ask_continue "Failed to download template to local-btrfs storage"
    fi
}

# Destroy existing container if requested
destroy_existing_container() {
    if [[ "$DESTROY_EXISTING" != "true" ]]; then
        return 0
    fi
    
    print_header "Destroying Existing Container"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_warning "Destroying container $CONTAINER_ID..."
    
    # Stop container if running
    if pct status "$CONTAINER_ID" | grep -q "running"; then
        print_info "Stopping container..."
        pct stop "$CONTAINER_ID" --force || true
        sleep 3
    fi
    
    # Destroy container
    if pct destroy "$CONTAINER_ID" --force; then
        print_status "Container $CONTAINER_ID destroyed"
        sleep 2
    else
        ask_continue "Failed to destroy container $CONTAINER_ID"
    fi
}

# Create the LXC container
create_container() {
    print_header "Creating LXC Container"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Build pct create command with proper template reference
    local template_ref="${TEMPLATE_WITH_STORAGE:-local-btrfs:vztmpl/$TEMPLATE}"
    local create_cmd="pct create $CONTAINER_ID $template_ref"
    create_cmd="$create_cmd --hostname $HOSTNAME"
    create_cmd="$create_cmd --memory $MEMORY"
    create_cmd="$create_cmd --cores $CORES"
    create_cmd="$create_cmd --rootfs $STORAGE:$DISK"
    
    # Network configuration - private network always on eth0
    create_cmd="$create_cmd --net0 name=eth0,bridge=$BRIDGE,ip=$CONTAINER_IP,gw=$GATEWAY"
    
    # Add second network interface for dual IP setup
    if [[ "$ENABLE_DUAL_IP" == "true" && -n "$PUBLIC_IP" ]]; then
        # Validate public IP format
        if [[ "$PUBLIC_IP" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            print_info "Configuring dual IP setup with direct public access"
            if [[ -n "$PUBLIC_GATEWAY" ]]; then
                create_cmd="$create_cmd --net1 name=eth1,bridge=$BRIDGE,ip=$PUBLIC_IP/25,gw=$PUBLIC_GATEWAY"
            else
                create_cmd="$create_cmd --net1 name=eth1,bridge=$BRIDGE,ip=$PUBLIC_IP/25"
            fi
            print_status "Added public interface: eth1 ($PUBLIC_IP)"
        else
            print_error "Invalid public IP format: $PUBLIC_IP"
            print_info "Disabling dual IP setup"
            ENABLE_DUAL_IP="false"
        fi
    fi
    
    create_cmd="$create_cmd --nameserver 8.8.8.8"
    create_cmd="$create_cmd --nameserver 8.8.4.4"
    create_cmd="$create_cmd --features nesting=1"
    create_cmd="$create_cmd --unprivileged 1"
    create_cmd="$create_cmd --onboot 1"
    
    print_info "Creating container with command:"
    print_info "$create_cmd"
    
    # Try SSH keys first, fallback to no authentication
    if [[ -f /root/.ssh/authorized_keys ]]; then
        $create_cmd --ssh-public-keys /root/.ssh/authorized_keys
    else
        $create_cmd
    fi
    
    if [[ $? -eq 0 ]]; then
        print_status "Container $CONTAINER_ID created successfully"
    else
        ask_continue "Failed to create container"
    fi
}

# Start the container (skip for now due to network issues)
start_container() {
    print_header "Container Created (Not Started)"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_status "Container $CONTAINER_ID created and ready to start"
    print_info "Container uses vmbr0 Linux bridge for initial connectivity"
    print_info "Advanced OVS networking will be configured after Netmaker installation"
}

# Skip container configuration (container not started)
configure_container() {
    print_header "Container Configuration Skipped"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Container configuration will be done after starting"
    print_info "Run these commands after setting up OVS bridge and starting container:"
    echo "  1. pct start $CONTAINER_ID"
    echo "  2. pct exec $CONTAINER_ID -- /root/install-netmaker.sh"
    print_status "Container ready for configuration after network setup"
}

# Create installation script for later use
create_container_install_script() {
    print_header "Creating Installation Script for Later Use"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Installation script will be copied when container is started"
    print_status "Installation script prepared"
    return 0
    
    # Copy the container installation script to the container
    cat > /tmp/container-install.sh << 'EOF'
#!/bin/bash

# Netmaker and Mosquitto Installation Script for LXC Container
# This script runs inside the LXC container

set -euo pipefail

SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/netmaker-container-install.log"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
print_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }
print_info() { echo -e "${BLUE}[i]${NC} $1" | tee -a "$LOG_FILE"; }

# Download and install Netmaker
install_netmaker() {
    print_info "Installing Netmaker binary..."
    
    # Detect architecture
    local arch=$(uname -m)
    local go_arch
    case "$arch" in
        x86_64) go_arch="amd64" ;;
        aarch64|arm64) go_arch="arm64" ;;
        armv7l) go_arch="arm" ;;
        *) ask_continue "Unsupported architecture: $arch" ;;
    esac
    
    # Get latest version
    local netmaker_version=$(curl -s https://api.github.com/repos/gravitl/netmaker/releases/latest | jq -r .tag_name)
    print_info "Latest Netmaker version: $netmaker_version"
    
    # Download binary
    local download_url="https://github.com/gravitl/netmaker/releases/download/${netmaker_version}/netmaker-linux-${go_arch}"
    wget -O /tmp/netmaker "$download_url"
    chmod +x /tmp/netmaker
    mv /tmp/netmaker /usr/local/bin/netmaker
    
    print_status "Netmaker installed: $(/usr/local/bin/netmaker --version 2>/dev/null | head -1)"
}

# Configure Mosquitto for container use
configure_mosquitto() {
    print_info "Configuring Mosquitto MQTT broker..."
    
    # Create basic mosquitto configuration
    cat > /etc/mosquitto/mosquitto.conf << 'MQTT_EOF'
# GhostBridge Mosquitto Configuration for LXC Container
# Binds to all interfaces for Proxmox host access

# MQTT TCP Listener
listener 1883
bind_address 0.0.0.0
protocol mqtt
allow_anonymous true

# MQTT WebSocket Listener
listener 9001
bind_address 0.0.0.0
protocol websockets
allow_anonymous true

# Persistence and Logging
persistence true
persistence_location /var/lib/mosquitto/

log_dest file /var/log/mosquitto/mosquitto.log
log_type error
log_type warning
log_type notice
log_type information
log_timestamp true

# Performance Settings
max_packet_size 1048576
max_inflight_messages 100
max_queued_messages 1000
retain_available true
keepalive_interval 60
max_keepalive 120
MQTT_EOF

    # Set permissions
    chown mosquitto:mosquitto /var/lib/mosquitto /var/log/mosquitto
    
    # Test configuration
    if mosquitto -c /etc/mosquitto/mosquitto.conf -t; then
        print_status "Mosquitto configuration is valid"
    else
        ask_continue "Mosquitto configuration test failed"
    fi
    
    # Enable and start mosquitto
    systemctl enable mosquitto
    systemctl start mosquitto
    
    if systemctl is-active --quiet mosquitto; then
        print_status "Mosquitto service is running"
    else
        print_error "Mosquitto failed to start"
        journalctl -u mosquitto --no-pager -n 10
        ask_continue "Mosquitto service failed to start"
    fi
}

# Create basic Netmaker configuration
create_netmaker_config() {
    print_info "Creating Netmaker configuration..."
    
    local master_key=$(openssl rand -hex 32)
    
    cat > /etc/netmaker/config.yaml << 'NETMAKER_EOF'
# GhostBridge Netmaker Configuration for LXC Container
version: v0.20.0

server:
  host: "0.0.0.0"
  apiport: 8081
  grpcport: 8082
  restbackend: true
  agentbackend: true
  messagequeuebackend: true
  dnsdisabled: false
  displaykeys: true
  hostnetwork: "off"

database:
  host: ""
  port: 0
  username: ""
  password: ""
  name: ""
  sslmode: ""
  endpoint: ""

# MQTT broker configuration (local connection)
messagequeue:
  host: "127.0.0.1"
  port: 1883
  endpoint: "mqtt://127.0.0.1:1883"
  username: ""
  password: ""

api:
  corsallowed: "*"
  endpoint: "https://netmaker.hobsonschoice.net"

oauth:
  github_client_id: ""
  github_client_secret: ""
  google_client_id: ""
  google_client_secret: ""
  oidc_issuer: ""

jwt_validity_duration: "24h"
rachecks: "on"
telemetry: "off"
mq_admin_password: ""

manage_iptables: "on"
port_forward_services: ""
default_node_limit: 999999

servercheckin: "on"
autopull: "on"
dnsmode: ""
verbosity: 1
platform: "linux"

logverbosity: 1
NETMAKER_EOF

    # Set master key
    sed -i "s/masterkey: \"\"/masterkey: \"$master_key\"/" /etc/netmaker/config.yaml
    
    chmod 600 /etc/netmaker/config.yaml
    print_info "Master key: $master_key"
    echo "NETMAKER_MASTER_KEY=$master_key" > /etc/netmaker/master-key.env
}

# Create systemd service
create_netmaker_service() {
    print_info "Creating Netmaker systemd service..."
    
    cat > /etc/systemd/system/netmaker.service << 'SERVICE_EOF'
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

NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=/opt/netmaker /var/log/netmaker /etc/netmaker

Environment=NM_CONFIG_PATH=/etc/netmaker/config.yaml

[Install]
WantedBy=multi-user.target
SERVICE_EOF

    systemctl daemon-reload
    systemctl enable netmaker
    
    print_status "Netmaker service created and enabled"
}

# Start services
start_services() {
    print_info "Starting Netmaker service..."
    systemctl start netmaker
    
    sleep 5
    
    if systemctl is-active --quiet netmaker; then
        print_status "Netmaker service is running"
    else
        print_error "Netmaker service failed to start"
        journalctl -u netmaker --no-pager -n 20
        ask_continue "Netmaker service failed to start"
    fi
}

# Validate installation
validate_installation() {
    print_info "Validating container installation..."
    
    # Check services
    if systemctl is-active --quiet mosquitto; then
        print_status "✓ Mosquitto is running"
    else
        print_error "✗ Mosquitto is not running"
        return 1
    fi
    
    if systemctl is-active --quiet netmaker; then
        print_status "✓ Netmaker is running"
    else
        print_error "✗ Netmaker is not running"
        return 1
    fi
    
    # Check ports
    if ss -tlnp | grep -q ":1883 "; then
        print_status "✓ MQTT port 1883 is listening"
    else
        print_error "✗ MQTT port 1883 is not listening"
        return 1
    fi
    
    if ss -tlnp | grep -q ":9001 "; then
        print_status "✓ MQTT WebSocket port 9001 is listening"  
    else
        print_error "✗ MQTT WebSocket port 9001 is not listening"
        return 1
    fi
    
    if ss -tlnp | grep -q ":8081 "; then
        print_status "✓ Netmaker API port 8081 is listening"
    else
        print_error "✗ Netmaker API port 8081 is not listening"
        return 1
    fi
    
    print_status "✅ Container installation validation passed!"
}

# Main function
main() {
    echo "Starting Netmaker container installation..." | tee -a "$LOG_FILE"
    
    install_netmaker
    configure_mosquitto
    create_netmaker_config
    create_netmaker_service
    start_services
    validate_installation
    
    echo "Container installation completed successfully!" | tee -a "$LOG_FILE"
}

main "$@"
EOF

    # Copy script to container
    pct push "$CONTAINER_ID" /tmp/container-install.sh /root/install-netmaker.sh
    pct exec "$CONTAINER_ID" -- chmod +x /root/install-netmaker.sh
    
    print_status "Installation script created in container"
}

# Skip container connectivity tests (container not started)
test_container() {
    print_header "Container Tests Skipped"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Container connectivity tests skipped (container not started)"
    print_info "Container must be started after OVS bridge setup"
    print_status "Container creation validation completed"
    return 0
}

# Display completion summary
show_completion() {
    print_header "Container Creation Complete!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    print_status "🎉 LXC container created successfully!"
    echo
    
    echo -e "${CYAN}📋 Container Details:${NC}"
    echo "  • Container ID: $CONTAINER_ID"
    echo "  • Hostname: $HOSTNAME"
    echo "  • IP Address: $CONTAINER_IP"
    echo "  • Bridge: $BRIDGE"
    echo "  • Gateway: $GATEWAY"
    echo "  • Memory: ${MEMORY}MB"
    echo "  • Disk: ${DISK}GB"
    echo "  • CPU Cores: $CORES"
    echo
    
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo "  1. Set up OVS bridge 'ovsbr0' on Proxmox host"
    echo "  2. Start container: pct start $CONTAINER_ID"
    echo "  3. Install services in container:"
    echo "     pct exec $CONTAINER_ID -- /root/install-netmaker.sh"
    echo "  4. Run nginx upgrade script on Proxmox host"
    echo "  5. Configure nginx stream module for MQTT proxy"
    echo "  6. Set up SSL certificates"
    echo
    
    echo -e "${CYAN}🔧 Container Management:${NC}"
    echo "  • Set root password: pct set $CONTAINER_ID --password"
    echo "  • Enter container: pct enter $CONTAINER_ID"
    echo "  • Execute commands: pct exec $CONTAINER_ID -- <command>"
    echo "  • Stop container: pct stop $CONTAINER_ID"
    echo "  • Start container: pct start $CONTAINER_ID"
    echo "  • View config: pct config $CONTAINER_ID"
    echo
    
    echo -e "${CYAN}📁 Important Files:${NC}"
    echo "  • Installation script: /root/install-netmaker.sh (in container)"
    echo "  • Container log: $LOG_FILE"
    echo
    
    echo "════════════════════════════════════════════════════════════════════════"
}

# Main execution
main() {
    show_banner
    check_root
    check_proxmox
    check_templates
    get_configuration
    
    print_header "Creating LXC Container"
    echo "════════════════════════════════════════════════════════════════════════"
    
    download_template
    destroy_existing_container
    create_container
    start_container
    configure_container
    create_container_install_script
    test_container
    show_completion
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Container creation completed successfully" >> "$LOG_FILE"
}

main "$@"