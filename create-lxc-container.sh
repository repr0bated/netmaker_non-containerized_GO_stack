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

# Default values from CLAUDE.md - Updated for dual IP OVS setup
DEFAULT_CONTAINER_ID="100"
DEFAULT_CONTAINER_IP="10.0.0.151"  # Container DHCP range starts at 150
DEFAULT_BRIDGE="ovsbr0"             # OVS bridge, not Linux bridge
DEFAULT_GATEWAY="10.0.0.1"
DEFAULT_TEMPLATE="debian-12-standard"
DEFAULT_STORAGE="local-lvm"
DEFAULT_HOSTNAME="ghostbridge"
DEFAULT_ROOTPW=""
DEFAULT_MEMORY="2048"
DEFAULT_DISK="8"
DEFAULT_CORES="2"

# Dual IP configuration (to be configured when second IP is available)
DEFAULT_ENABLE_DUAL_IP="false"     # Set to true when second IP available
DEFAULT_PUBLIC_IP=""               # Second public IP for direct container access

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
        print_error "This script must be run as root on the Proxmox host"
        exit 1
    fi
}

# Check if running on Proxmox host
check_proxmox() {
    if [[ ! -f /etc/pve/local/pve-ssl.pem ]]; then
        print_error "This script must be run on a Proxmox host"
        exit 1
    fi
    
    local pve_version=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "unknown")
    print_status "Proxmox VE detected: $pve_version"
}

# Check available templates
check_templates() {
    print_info "Checking available LXC templates..."
    
    local templates=$(pveam available --section turnkeylinux | grep -E "debian|ubuntu" | head -5 || echo "")
    if [[ -n "$templates" ]]; then
        print_info "Available templates:"
        echo "$templates" | sed 's/^/    /'
    fi
    
    # Check if our default template exists
    if pveam list local | grep -q "$DEFAULT_TEMPLATE"; then
        print_status "Template $DEFAULT_TEMPLATE is available"
    else
        print_warning "Template $DEFAULT_TEMPLATE not found - will attempt to download"
    fi
}

# Get configuration from user
get_configuration() {
    print_header "LXC Container Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
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
            print_error "Please choose a different container ID"
            exit 1
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
    
    print_question "Enter root password (leave empty for SSH key auth):"
    read -s -p "Password: " rootpw
    echo
    ROOT_PASSWORD="$rootpw"
    
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
        print_question "Enter second public IP for direct container access:"
        read -p "Public IP: " public_ip
        PUBLIC_IP="$public_ip"
        print_question "Enter public gateway:"
        read -p "Public Gateway: " public_gateway
        PUBLIC_GATEWAY="$public_gateway"
    else
        ENABLE_DUAL_IP="false"
        print_info "Single IP mode - Netmaker will be proxied through nginx"
    fi
    
    echo
    print_info "Container configuration:"
    echo "  • ID: $CONTAINER_ID"
    echo "  • Hostname: $HOSTNAME"
    echo "  • Private IP: $CONTAINER_IP"
    echo "  • Bridge: $BRIDGE"
    echo "  • Gateway: $GATEWAY"
    if [[ "$ENABLE_DUAL_IP" == "true" ]]; then
        echo "  • Public IP: $PUBLIC_IP (direct access)"
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
    print_header "Checking LXC Template"
    echo "────────────────────────────────────────────────────────────────────────"
    
    if pveam list local | grep -q "$TEMPLATE"; then
        print_status "Template $TEMPLATE is available"
        return 0
    fi
    
    print_info "Downloading template: $TEMPLATE"
    
    # Update available templates
    pveam update
    
    # Download the template
    if pveam download local "$TEMPLATE.tar.zst"; then
        print_status "Template downloaded successfully"
    else
        print_error "Failed to download template $TEMPLATE"
        print_info "Available templates:"
        pveam available --section turnkeylinux | grep -E "debian|ubuntu"
        exit 1
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
        print_error "Failed to destroy container $CONTAINER_ID"
        exit 1
    fi
}

# Create the LXC container
create_container() {
    print_header "Creating LXC Container"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Build pct create command
    local create_cmd="pct create $CONTAINER_ID local:vztmpl/$TEMPLATE.tar.zst"
    create_cmd="$create_cmd --hostname $HOSTNAME"
    create_cmd="$create_cmd --memory $MEMORY"
    create_cmd="$create_cmd --cores $CORES"
    create_cmd="$create_cmd --storage $STORAGE"
    create_cmd="$create_cmd --rootfs $STORAGE:$DISK"
    
    # Network configuration - private network always on eth0
    create_cmd="$create_cmd --net0 name=eth0,bridge=$BRIDGE,ip=$CONTAINER_IP,gw=$GATEWAY"
    
    # Add second network interface for dual IP setup
    if [[ "$ENABLE_DUAL_IP" == "true" ]]; then
        print_info "Configuring dual IP setup with direct public access"
        create_cmd="$create_cmd --net1 name=eth1,bridge=$BRIDGE,ip=$PUBLIC_IP,gw=$PUBLIC_GATEWAY"
        print_status "Added public interface: eth1 ($PUBLIC_IP)"
    fi
    
    create_cmd="$create_cmd --nameserver 8.8.8.8"
    create_cmd="$create_cmd --nameserver 8.8.4.4"
    create_cmd="$create_cmd --features nesting=1"
    create_cmd="$create_cmd --unprivileged 1"
    create_cmd="$create_cmd --onboot 1"
    
    if [[ -n "$ROOT_PASSWORD" ]]; then
        create_cmd="$create_cmd --password"
    fi
    
    print_info "Creating container with command:"
    print_info "$create_cmd"
    
    if [[ -n "$ROOT_PASSWORD" ]]; then
        echo "$ROOT_PASSWORD" | $create_cmd
    else
        $create_cmd --ssh-public-keys /root/.ssh/authorized_keys 2>/dev/null || $create_cmd
    fi
    
    if [[ $? -eq 0 ]]; then
        print_status "Container $CONTAINER_ID created successfully"
    else
        print_error "Failed to create container"
        exit 1
    fi
}

# Start the container
start_container() {
    print_header "Starting Container"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Starting container $CONTAINER_ID..."
    if pct start "$CONTAINER_ID"; then
        print_status "Container started successfully"
        
        # Wait for container to be fully started
        print_info "Waiting for container to be ready..."
        local timeout=30
        local count=0
        
        while [[ $count -lt $timeout ]]; do
            if pct exec "$CONTAINER_ID" -- systemctl is-system-running --wait >/dev/null 2>&1; then
                break
            fi
            sleep 2
            ((count++))
        done
        
        if [[ $count -ge $timeout ]]; then
            print_warning "Container startup timeout (may still be initializing)"
        else
            print_status "Container is ready"
        fi
    else
        print_error "Failed to start container"
        exit 1
    fi
}

# Configure container for Netmaker services
configure_container() {
    print_header "Configuring Container for Netmaker Services"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Update container
    print_info "Updating container packages..."
    pct exec "$CONTAINER_ID" -- apt update
    pct exec "$CONTAINER_ID" -- apt upgrade -y
    
    # Install essential packages
    print_info "Installing essential packages..."
    pct exec "$CONTAINER_ID" -- apt install -y \
        curl wget unzip sqlite3 jq openssl dnsutils net-tools \
        systemd systemd-sysv ca-certificates gnupg lsb-release
    
    # Install Mosquitto
    print_info "Installing Mosquitto MQTT broker..."
    pct exec "$CONTAINER_ID" -- apt install -y mosquitto mosquitto-clients
    
    # Stop mosquitto to configure it properly later
    pct exec "$CONTAINER_ID" -- systemctl stop mosquitto || true
    pct exec "$CONTAINER_ID" -- systemctl disable mosquitto || true
    
    # Create directories
    print_info "Creating Netmaker directories..."
    pct exec "$CONTAINER_ID" -- mkdir -p /etc/netmaker
    pct exec "$CONTAINER_ID" -- mkdir -p /opt/netmaker/{data,logs}
    pct exec "$CONTAINER_ID" -- mkdir -p /var/log/netmaker
    pct exec "$CONTAINER_ID" -- mkdir -p /var/backups/netmaker
    
    print_status "Container configured for Netmaker services"
}

# Create installation script inside container
create_container_install_script() {
    print_header "Creating Installation Script in Container"
    echo "────────────────────────────────────────────────────────────────────────"
    
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
        *) print_error "Unsupported architecture: $arch"; exit 1 ;;
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
        print_error "Mosquitto configuration test failed"
        exit 1
    fi
    
    # Enable and start mosquitto
    systemctl enable mosquitto
    systemctl start mosquitto
    
    if systemctl is-active --quiet mosquitto; then
        print_status "Mosquitto service is running"
    else
        print_error "Mosquitto failed to start"
        journalctl -u mosquitto --no-pager -n 10
        exit 1
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
        exit 1
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

# Test container connectivity
test_container() {
    print_header "Testing Container Connectivity"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Test basic connectivity
    local container_ip_only=$(echo "$CONTAINER_IP" | cut -d'/' -f1)
    
    print_info "Testing container connectivity..."
    if ping -c 2 "$container_ip_only" >/dev/null 2>&1; then
        print_status "Container is reachable at $container_ip_only"
    else
        print_warning "Container ping test failed (may be normal if ICMP blocked)"
    fi
    
    # Test SSH (if available)
    if pct exec "$CONTAINER_ID" -- systemctl is-active --quiet ssh 2>/dev/null; then
        print_status "SSH service is available in container"
    else
        print_info "SSH service not available (normal for basic container)"
    fi
    
    # Test command execution
    if pct exec "$CONTAINER_ID" -- whoami >/dev/null 2>&1; then
        print_status "Container command execution working"
    else
        print_error "Container command execution failed"
        return 1
    fi
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
    echo "  1. Install services in container:"
    echo "     pct exec $CONTAINER_ID -- /root/install-netmaker.sh"
    echo "  2. Run nginx upgrade script on Proxmox host"
    echo "  3. Configure nginx stream module for MQTT proxy"
    echo "  4. Set up SSL certificates"
    echo
    
    echo -e "${CYAN}🔧 Container Management:${NC}"
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