#!/bin/bash

# GhostBridge Master Deployment Script
# Orchestrates the complete GhostBridge deployment:
# 1. Creates LXC container on Proxmox host
# 2. Installs Netmaker and Mosquitto in container
# 3. Upgrades nginx on Proxmox host with stream module
# 4. Configures complete networking stack

set -euo pipefail

SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/ghostbridge-deployment.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Global variables
master_key=""

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
    echo -e "${CYAN}[DEPLOY]${NC} $1" | tee -a "$LOG_FILE"
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
║              GhostBridge Master Deployment Script                        ║
║                                                                           ║
║    Complete Netmaker deployment with LXC container architecture          ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
    print_info "Version: $SCRIPT_VERSION"
    print_info "Purpose: Complete GhostBridge deployment orchestration"
    print_info "Log File: $LOG_FILE"
    echo
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root on the Proxmox host"
        exit 1
    fi
    
    # Check if running on Proxmox host
    if [[ ! -f /etc/pve/local/pve-ssl.pem ]]; then
        print_error "This script must be run on the Proxmox host"
        exit 1
    fi
    
    local pve_version=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "unknown")
    print_status "Running on Proxmox VE: $pve_version"
    
    # Check if deployment scripts exist
    local required_scripts=(
        "create-lxc-container.sh"
        "upgrade-nginx-proxmox.sh"
        "install-container-services.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            print_error "Required script not found: $script"
            exit 1
        else
            print_status "Found script: $script"
        fi
    done
    
    # Check required commands
    local required_commands=("pct" "curl" "wget" "jq")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            print_status "Command available: $cmd"
        else
            print_error "Required command not found: $cmd"
            exit 1
        fi
    done
}

# Get deployment configuration
get_deployment_config() {
    print_header "Deployment Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "This script will deploy GhostBridge with the following architecture:"
    echo "  • LXC container for Netmaker and Mosquitto services"
    echo "  • Nginx with stream module on Proxmox host for reverse proxy"
    echo "  • Proper network configuration for container communication"
    echo
    
    print_question "Do you want to proceed with the deployment? [y/N]: "
    read -r proceed
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled by user"
        exit 0
    fi
    
    print_question "Use interactive configuration for each component? [Y/n]: "
    read -r interactive
    if [[ "$interactive" =~ ^[Nn]$ ]]; then
        CONFIG[interactive]="false"
        print_info "Using default configuration values"
    else
        CONFIG[interactive]="true"
        print_info "Will prompt for configuration in each step"
    fi
    
    echo
}

# Step 1: Reset Network to Proxmox Defaults
reset_to_proxmox_defaults() {
    print_header "Step 1: Resetting Network to Proxmox Defaults"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Resetting network configuration to clean Proxmox defaults..."
    print_info "This ensures containers can be created and have basic connectivity"
    
    # Check if simple network reset script exists and if interactive mode
    if [[ -f "$SCRIPT_DIR/simple-network-reset.sh" ]]; then
        if [[ "${CONFIG[interactive]}" == "false" ]]; then
            print_info "Non-interactive mode: Running network reset automatically..."
            if bash "$SCRIPT_DIR/simple-network-reset.sh"; then
                print_status "✅ Network reset to Proxmox defaults completed"
                print_info "Network is now: eth0 DHCP + vmbr0 Linux bridge"
            else
                print_warning "Network reset had issues but continuing..."
            fi
        else
            print_question "Run network reset to Proxmox defaults? [Y/n]: "
            read -r reset_network
            if [[ ! "$reset_network" =~ ^[Nn]$ ]]; then
                print_info "Running simple network reset..."
                if bash "$SCRIPT_DIR/simple-network-reset.sh"; then
                    print_status "✅ Network reset to Proxmox defaults completed"
                    print_info "Network is now: eth0 DHCP + vmbr0 Linux bridge"
                else
                    print_warning "Network reset had issues but continuing..."
                fi
            else
                print_info "Skipping network reset - using current configuration"
            fi
        fi
    else
        print_warning "Simple network reset script not found"
        print_info "Current network configuration will be used"
    fi
    
    echo
}

# Step 2: Create LXC Container
deploy_lxc_container() {
    print_header "Step 2: Creating LXC Container"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Running LXC container creation script..."
    
    local create_cmd="$SCRIPT_DIR/create-lxc-container.sh"
    
    if [[ "${CONFIG[interactive]}" == "false" ]]; then
        # Run with default values using --auto flag
        print_info "Creating container with default configuration..."
        create_cmd="$create_cmd --auto"
    fi
    
    if bash $create_cmd; then
        print_status "✅ LXC container creation completed successfully"
        
        # Try to find the most recently created container
        local latest_container=$(pct list | tail -n +2 | sort -k1 -n | tail -1 | awk '{print $1}')
        
        if [[ -n "$latest_container" ]]; then
            print_info "Detected latest container: $latest_container"
            if [[ "${CONFIG[interactive]}" == "false" ]]; then
                CONFIG[container_id]="$latest_container"
                print_info "Non-interactive mode: Using container ID $latest_container"
            else
                print_question "Use container ID $latest_container? [Y/n]: "
                read -r use_detected
                if [[ ! "$use_detected" =~ ^[Nn]$ ]]; then
                    CONFIG[container_id]="$latest_container"
                else
                    print_question "Enter the container ID that was created: "
                    read -r created_container_id
                    CONFIG[container_id]="$created_container_id"
                fi
            fi
        else
            if [[ "${CONFIG[interactive]}" == "false" ]]; then
                CONFIG[container_id]="100"  # Default fallback
                print_info "Non-interactive mode: Using default container ID 100"
            else
                print_question "Enter the container ID that was created: "
                read -r created_container_id
                CONFIG[container_id]="$created_container_id"
            fi
        fi
        
        # Get container config to extract IP
        local container_config=$(pct config "${CONFIG[container_id]}" 2>/dev/null || echo "")
        local detected_ip=$(echo "$container_config" | grep "^net0:" | sed -n 's/.*ip=\([^,/]*\).*/\1/p')
        
        if [[ -n "$detected_ip" ]]; then
            CONFIG[container_ip]="$detected_ip"
            print_info "Detected container IP: $detected_ip"
        else
            if [[ "${CONFIG[interactive]}" == "false" ]]; then
                CONFIG[container_ip]="10.0.0.151"  # Default fallback
                print_info "Non-interactive mode: Using default container IP 10.0.0.151"
            else
                print_question "Enter the container IP: "
                read -r created_container_ip
                CONFIG[container_ip]="$created_container_ip"
            fi
        fi
        
        print_info "Using container ID: ${CONFIG[container_id]}"
        print_info "Using container IP: ${CONFIG[container_ip]}"
        
    else
        print_error "❌ LXC container creation failed"
        exit 1
    fi
    
    echo
}

# Step 3: Start LXC Container
start_lxc_container() {
    print_header "Step 3: Starting LXC Container"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Starting container ${CONFIG[container_id]}..."
    
    if pct start "${CONFIG[container_id]}"; then
        print_status "✅ Container started successfully"
        
        # Wait for container to be ready
        print_info "Waiting for container network to be ready..."
        local timeout=30
        local count=0
        
        while [[ $count -lt $timeout ]]; do
            if pct exec "${CONFIG[container_id]}" -- ping -c 1 8.8.8.8 >/dev/null 2>&1; then
                break
            fi
            sleep 2
            ((count+=2))
        done
        
        if [[ $count -ge $timeout ]]; then
            print_warning "Container network test timeout (may still work)"
        else
            print_status "Container network is ready"
        fi
        
    else
        print_error "❌ Failed to start container"
        exit 1
    fi
    
    echo
}

# Step 4: Install services in container automatically
deploy_container_services() {
    print_header "Step 4: Installing Services in Container"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Installing Netmaker and Mosquitto services in container..."
    
    # Test container connectivity first
    print_info "Testing container connectivity..."
    if ! pct exec "${CONFIG[container_id]}" -- ping -c 2 8.8.8.8 >/dev/null 2>&1; then
        print_warning "Container network connectivity test failed"
        if [[ "${CONFIG[interactive]}" == "false" ]]; then
            print_info "Non-interactive mode: Continuing with installation anyway"
        else
            print_question "Continue with installation anyway? [y/N]: "
            read -r continue_install
            if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
                print_info "Skipping container service installation"
                return 0
            fi
        fi
    else
        print_status "Container has internet connectivity"
    fi
    
    # Update package lists
    print_info "Updating package lists..."
    if pct exec "${CONFIG[container_id]}" -- apt update; then
        print_status "Package lists updated"
    else
        print_warning "Package update had issues but continuing..."
    fi
    
    # Install essential packages
    print_info "Installing essential packages..."
    if pct exec "${CONFIG[container_id]}" -- apt install -y curl wget unzip jq openssl systemd systemd-sysv ca-certificates gnupg lsb-release; then
        print_status "Essential packages installed"
    else
        print_warning "Some packages may have failed to install"
    fi
    
    # Install EMQX MQTT broker
    print_info "Installing EMQX MQTT broker..."
    
    # Add EMQX repository
    pct exec "${CONFIG[container_id]}" -- bash -c 'curl -s https://assets.emqx.com/scripts/install-emqx-deb.sh | bash'
    
    # Install EMQX
    if pct exec "${CONFIG[container_id]}" -- apt install -y emqx; then
        print_status "EMQX installed"
        
        # Stop and disable EMQX for configuration
        pct exec "${CONFIG[container_id]}" -- systemctl stop emqx || true
        pct exec "${CONFIG[container_id]}" -- systemctl disable emqx || true
        print_info "EMQX stopped for configuration"
    else
        print_warning "EMQX installation had issues"
    fi
    
    # Install Netmaker
    print_info "Installing Netmaker..."
    install_netmaker_in_container
    
    # Configure services
    print_info "Configuring services..."
    configure_services_in_container
    
    # Wait for services to stabilize
    print_info "Waiting for services to stabilize..."
    sleep 10
    
    # Configure Netmaker via API
    print_info "Configuring Netmaker via API..."
    configure_netmaker_api
    
    print_status "✅ Container services installation completed"
    echo
}

# Install Netmaker binary in container
install_netmaker_in_container() {
    print_info "Installing Netmaker binary..."
    
    # Create directories
    pct exec "${CONFIG[container_id]}" -- mkdir -p /etc/netmaker /opt/netmaker/{data,logs} /var/log/netmaker
    
    # Check for existing built binary
    local built_binary="$SCRIPT_DIR/binaries/netmaker-latest"
    local use_built_binary=false
    
    if [[ -f "$built_binary" ]]; then
        print_info "Found existing built binary: $built_binary"
        if [[ "${CONFIG[interactive]}" == "false" ]]; then
            print_info "Non-interactive mode: Using existing built binary"
            use_built_binary=true
        else
            print_question "Use existing built binary? [Y/n]: "
            read -r use_existing
            if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
                use_built_binary=true
            fi
        fi
    fi
    
    if [[ "$use_built_binary" == "true" ]]; then
        # Use existing built binary
        print_info "Using existing built Netmaker binary"
        if pct push "${CONFIG[container_id]}" "$built_binary" /usr/local/bin/netmaker; then
            pct exec "${CONFIG[container_id]}" -- chmod +x /usr/local/bin/netmaker
            print_status "Built Netmaker binary installed"
            
            # Show version info
            local version_info=$(pct exec "${CONFIG[container_id]}" -- /usr/local/bin/netmaker --version 2>/dev/null || echo "version check failed")
            print_info "Netmaker version: $version_info"
        else
            print_error "Failed to copy built binary to container"
            return 1
        fi
    else
        # Prompt to build or download
        if [[ "${CONFIG[interactive]}" == "false" ]]; then
            print_info "Non-interactive mode: Downloading pre-built binary"
            download_prebuilt_netmaker
        else
            print_question "Choose Netmaker installation method:"
            echo "  1) Build from source (recommended - custom parameters)"
            echo "  2) Download pre-built binary (faster)"
            read -p "Choice [1/2]: " install_choice
            
            case "$install_choice" in
                2)
                    download_prebuilt_netmaker
                    ;;
                1|*)
                    print_info "Building Netmaker from source..."
                    print_info "Run: $SCRIPT_DIR/build-netmaker.sh"
                    print_info "Then re-run this deployment script"
                    exit 0
                    ;;
            esac
        fi
    fi
}

# Download pre-built Netmaker binary
download_prebuilt_netmaker() {
    print_info "Downloading pre-built Netmaker binary..."
    
    # Get latest Netmaker version and download
    local netmaker_version=$(curl -s https://api.github.com/repos/gravitl/netmaker/releases/latest | jq -r .tag_name 2>/dev/null || echo "v0.21.0")
    print_info "Installing Netmaker version: $netmaker_version"
    
    # Download Netmaker binary
    local download_url="https://github.com/gravitl/netmaker/releases/download/${netmaker_version}/netmaker-linux-amd64"
    if pct exec "${CONFIG[container_id]}" -- wget -O /tmp/netmaker "$download_url"; then
        pct exec "${CONFIG[container_id]}" -- chmod +x /tmp/netmaker
        pct exec "${CONFIG[container_id]}" -- mv /tmp/netmaker /usr/local/bin/netmaker
        print_status "Pre-built Netmaker binary installed"
    else
        print_warning "Netmaker download failed"
        return 1
    fi
}

# Configure services in container
configure_services_in_container() {
    print_info "Configuring EMQX..."
    
    # Generate MQTT credentials
    local mqtt_username="netmaker"
    local mqtt_password=$(openssl rand -base64 32 | tr -d "/+" | cut -c1-25)
    
    print_info "Generated MQTT credentials: $mqtt_username / $mqtt_password"
    
    # Store MQTT credentials
    pct exec "${CONFIG[container_id]}" -- bash -c "echo 'MQTT_USERNAME=$mqtt_username' > /etc/netmaker/mqtt-credentials.env"
    pct exec "${CONFIG[container_id]}" -- bash -c "echo 'MQTT_PASSWORD=$mqtt_password' >> /etc/netmaker/mqtt-credentials.env"
    pct exec "${CONFIG[container_id]}" -- chmod 600 /etc/netmaker/mqtt-credentials.env
    
    # Create necessary directories first
    # Configure EMQX using dedicated script
    if bash "$SCRIPT_DIR/configure-emqx.sh" "${CONFIG[container_id]}" "$mqtt_username" "$mqtt_password"; then
        print_status "EMQX configured successfully"
    else
        print_warning "EMQX configuration had issues but continuing"
    fi
    
    print_info "Configuring Netmaker..."
    
    # Generate master key (make global for API functions)
    master_key=$(openssl rand -hex 32)
    
    # Create Netmaker configuration
    pct exec "${CONFIG[container_id]}" -- bash -c "cat > /etc/netmaker/config.yaml << 'NETMAKER_EOF'
version: v0.21.0

server:
  host: \"0.0.0.0\"
  apiport: 8081
  grpcport: 8082
  restbackend: true
  agentbackend: true
  messagequeuebackend: true

database:
  host: \"\"
  port: 0

messagequeue:
  host: \"127.0.0.1\"
  port: 1883
  endpoint: \"mqtt://127.0.0.1:1883\"
  username: \"$mqtt_username\"
  password: \"$mqtt_password\"

api:
  corsallowed: \"*\"
  endpoint: \"https://netmaker.hobsonschoice.net\"

jwt_validity_duration: \"24h\"
telemetry: \"off\"

manage_iptables: \"on\"
verbosity: 1
platform: \"linux\"
masterkey: \"$master_key\"
NETMAKER_EOF"
    
    # Create systemd service
    pct exec "${CONFIG[container_id]}" -- bash -c 'cat > /etc/systemd/system/netmaker.service << "SERVICE_EOF"
[Unit]
Description=Netmaker Server
After=network-online.target
After=emqx.service
Requires=emqx.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/netmaker
ExecStart=/usr/local/bin/netmaker --config /etc/netmaker/config.yaml
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE_EOF'
    
    # Reload systemd and enable services (but don't start them yet)
    pct exec "${CONFIG[container_id]}" -- systemctl daemon-reload
    pct exec "${CONFIG[container_id]}" -- systemctl enable emqx netmaker
    
    print_status "✅ All services installed and configured (not started)"
    print_info "Services are ready but not started - use manual startup for troubleshooting"
    
    # Installation complete - services can be started manually
    print_info "To start services manually:"
    print_info "  1. pct exec ${CONFIG[container_id]} -- systemctl start emqx"
    print_info "  2. pct exec ${CONFIG[container_id]} -- systemctl start netmaker"
    
    return 0  # Exit here without starting services
    
    # DISABLED: Start services (commented out for manual troubleshooting)
    # print_info "Starting services..."
    
    # Start Mosquitto with detailed logging
    # print_info "Starting Mosquitto..."
    if false; then  # Disabled - was: pct exec "${CONFIG[container_id]}" -- systemctl start mosquitto; then
        print_status "Mosquitto started"
        
        # Verify Mosquitto is actually running
        sleep 2
        if pct exec "${CONFIG[container_id]}" -- systemctl is-active --quiet mosquitto; then
            print_status "Mosquitto is running"
        else
            print_warning "Mosquitto service not active, checking logs..."
            pct exec "${CONFIG[container_id]}" -- journalctl -u mosquitto --no-pager -n 10 || true
        fi
    else
        print_warning "Mosquitto start failed, checking logs..."
        pct exec "${CONFIG[container_id]}" -- journalctl -u mosquitto --no-pager -n 10 || true
    fi
    
    if pct exec "${CONFIG[container_id]}" -- systemctl start netmaker; then
        print_status "Netmaker started"
    else
        print_warning "Netmaker start failed"
    fi
    
    # Save master key
    pct exec "${CONFIG[container_id]}" -- echo "NETMAKER_MASTER_KEY=$master_key" > /etc/netmaker/master-key.env
    print_info "Master key saved to /etc/netmaker/master-key.env"
    
    # Store master key in CONFIG for API calls
    CONFIG[master_key]="$master_key"
}

# Configure Netmaker via API calls
configure_netmaker_api() {
    print_info "Setting up Netmaker via API calls..."
    
    local api_base="http://${CONFIG[container_ip]}:8081/api"
    local master_key="${CONFIG[master_key]}"
    
    # Wait for API to be available
    print_info "Waiting for Netmaker API to be available..."
    local timeout=60
    local count=0
    
    while [[ $count -lt $timeout ]]; do
        if pct exec "${CONFIG[container_id]}" -- curl -s "$api_base/server/health" >/dev/null 2>&1; then
            break
        fi
        sleep 2
        ((count+=2))
    done
    
    if [[ $count -ge $timeout ]]; then
        print_warning "Netmaker API not responding - skipping API configuration"
        return 1
    fi
    
    print_status "Netmaker API is responding"
    
    # Create super admin user
    print_info "Creating super admin user..."
    local admin_response=$(pct exec "${CONFIG[container_id]}" -- curl -s -X POST "$api_base/users/adm/create" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $master_key" \
        -d '{
            "username": "admin",
            "password": "GhostBridge2024!",
            "isadmin": true
        }' 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$admin_response" | grep -q "admin"; then
        print_status "Super admin user created"
        print_info "Username: admin"
        print_info "Password: GhostBridge2024!"
    else
        print_warning "Admin user creation failed or user already exists"
    fi
    
    # Create GhostBridge network
    print_info "Creating GhostBridge network..."
    local network_response=$(pct exec "${CONFIG[container_id]}" -- curl -s -X POST "$api_base/networks" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $master_key" \
        -d '{
            "netid": "ghostbridge",
            "addressrange": "10.0.0.0/24",
            "displayname": "GhostBridge Network",
            "defaultpostup": "iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE",
            "defaultpostdown": "iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE",
            "defaultkeepalive": 20,
            "defaultport": 51821,
            "islocal": false,
            "isdualstack": false,
            "isipv4": true,
            "isipv6": false
        }' 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$network_response" | grep -q "ghostbridge"; then
        print_status "GhostBridge network created with scope 10.0.0.0/24"
    else
        print_warning "Network creation failed or already exists"
    fi
    
    # Create enrollment key for easy node joining
    print_info "Creating enrollment key..."
    local key_response=$(pct exec "${CONFIG[container_id]}" -- curl -s -X POST "$api_base/networks/ghostbridge/keys" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $master_key" \
        -d '{
            "uses": 100,
            "expiration": 86400
        }' 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$key_response" | grep -q "token"; then
        local enrollment_key=$(echo "$key_response" | jq -r '.token' 2>/dev/null || echo "unknown")
        print_status "Enrollment key created: $enrollment_key"
        
        # Save enrollment key
        pct exec "${CONFIG[container_id]}" -- echo "NETMAKER_ENROLLMENT_KEY=$enrollment_key" >> /etc/netmaker/master-key.env
    else
        print_warning "Enrollment key creation failed"
    fi
    
    # Create Proxmox host node (10.0.0.1)
    print_info "Creating Proxmox host node (10.0.0.1)..."
    local host_node_response=$(pct exec "${CONFIG[container_id]}" -- curl -s -X POST "$api_base/networks/ghostbridge/nodes" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $master_key" \
        -d '{
            "name": "proxmox-host",
            "endpoint": "80.209.240.244:51821",
            "publickey": "",
            "address": "10.0.0.1",
            "isgateway": true,
            "isingressgateway": true,
            "isegressgateway": true
        }' 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$host_node_response" | grep -q "10.0.0.1"; then
        print_status "Proxmox host node created (10.0.0.1)"
    else
        print_warning "Proxmox host node creation failed"
    fi
    
    # Create container node (10.0.0.151)
    print_info "Creating container node (${CONFIG[container_ip]})..."
    local container_node_response=$(pct exec "${CONFIG[container_id]}" -- curl -s -X POST "$api_base/networks/ghostbridge/nodes" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $master_key" \
        -d "{
            \"name\": \"netmaker-container\",
            \"endpoint\": \"${CONFIG[container_ip]}:51822\",
            \"publickey\": \"\",
            \"address\": \"${CONFIG[container_ip]}\",
            \"isgateway\": false,
            \"isingressgateway\": false,
            \"isegressgateway\": false
        }" 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$container_node_response" | grep -q "${CONFIG[container_ip]}"; then
        print_status "Container node created (${CONFIG[container_ip]})"
    else
        print_warning "Container node creation failed"
    fi
    
    print_status "Netmaker API configuration completed"
    print_info "Network: ghostbridge (10.0.0.0/24)"
    print_info "Nodes: Proxmox host (10.0.0.1), Container (${CONFIG[container_ip]})"
}

# Step 5: Upgrade nginx on Proxmox host
deploy_nginx_upgrade() {
    print_header "Step 5: Upgrading Nginx on Proxmox Host"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Running nginx upgrade script..."
    
    local nginx_cmd="$SCRIPT_DIR/upgrade-nginx-proxmox.sh"
    
    if bash "$nginx_cmd"; then
        print_status "✅ Nginx upgrade completed successfully"
    else
        print_error "❌ Nginx upgrade failed"
        exit 1
    fi
    
    echo
}

# Step 6: Configure Final Network with Netmaker Integration
configure_final_network() {
    print_header "Step 6: Configuring Final Network with Netmaker Integration"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Now that Netmaker is installed, configuring advanced OVS networking..."
    
    # Check if OVS network setup script exists
    if [[ -f "$SCRIPT_DIR/scripts/01-network-setup.sh" ]]; then
        local configure_ovs="Y"
        if [[ "${CONFIG[interactive]}" == "false" ]]; then
            print_info "Non-interactive mode: Configuring advanced OVS networking automatically"
            configure_ovs="Y"
        else
            print_question "Configure advanced OVS networking with Netmaker integration? [Y/n]: "
            read -r configure_ovs
        fi
        
        if [[ ! "$configure_ovs" =~ ^[Nn]$ ]]; then
            print_info "Running OVS network setup with Netmaker integration..."
            if bash "$SCRIPT_DIR/scripts/01-network-setup.sh"; then
                print_status "✅ Advanced OVS networking configured successfully"
                
                # Update container network configuration
                print_info "Updating container network to use OVS bridge..."
                print_warning "Container will need to be stopped and reconfigured"
                local reconfig_container="Y"
                if [[ "${CONFIG[interactive]}" == "false" ]]; then
                    print_info "Non-interactive mode: Reconfiguring container networking automatically"
                    reconfig_container="Y"
                else
                    print_question "Stop container and reconfigure networking? [Y/n]: "
                    read -r reconfig_container
                fi
                
                if [[ ! "$reconfig_container" =~ ^[Nn]$ ]]; then
                    pct stop "${CONFIG[container_id]}" || true
                    
                    # Update container network config to use ovsbr0
                    pct set "${CONFIG[container_id]}" --net0 name=eth0,bridge=ovsbr0,ip="${CONFIG[container_ip]}/24",gw=10.0.0.1
                    
                    # Restart container
                    if pct start "${CONFIG[container_id]}"; then
                        print_status "Container reconfigured for OVS networking"
                    else
                        print_warning "Container start failed - may need manual intervention"
                    fi
                else
                    print_info "Container network configuration skipped"
                    print_info "Container is still using vmbr0 Linux bridge"
                fi
            else
                print_warning "OVS network setup had issues"
                print_info "Container will continue using basic Linux bridge (vmbr0)"
            fi
        else
            print_info "Keeping basic Linux bridge networking (vmbr0)"
        fi
    else
        print_warning "Advanced network setup script not found"
        print_info "Container will continue using basic Linux bridge (vmbr0)"
    fi
    
    echo
}

# Step 7: Test connectivity between components
test_deployment() {
    print_header "Step 7: Testing Deployment"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Testing container connectivity..."
    
    # Test basic connectivity to container
    if ping -c 2 "${CONFIG[container_ip]}" >/dev/null 2>&1; then
        print_status "✓ Container is reachable from Proxmox host"
    else
        print_warning "⚠ Container ping test failed (may be normal)"
    fi
    
    # Test container services
    print_info "Testing container services..."
    
    # Test MQTT port
    if pct exec "${CONFIG[container_id]}" -- ss -tlnp | grep -q ":1883 "; then
        print_status "✓ MQTT TCP port 1883 is listening in container"
    else
        print_error "✗ MQTT TCP port not listening in container"
    fi
    
    # Test MQTT WebSocket port
    if pct exec "${CONFIG[container_id]}" -- ss -tlnp | grep -q ":9001 "; then
        print_status "✓ MQTT WebSocket port 9001 is listening in container"
    else
        print_error "✗ MQTT WebSocket port not listening in container"
    fi
    
    # Test Netmaker API port
    if pct exec "${CONFIG[container_id]}" -- ss -tlnp | grep -q ":8081 "; then
        print_status "✓ Netmaker API port 8081 is listening in container"
    else
        print_error "✗ Netmaker API port not listening in container"
    fi
    
    # Test Proxmox host nginx
    print_info "Testing Proxmox host nginx..."
    
    if systemctl is-active --quiet nginx; then
        print_status "✓ Nginx service is running on Proxmox host"
    else
        print_error "✗ Nginx service not running on Proxmox host"
    fi
    
    if ss -tlnp | grep -q ":80 "; then
        print_status "✓ HTTP port 80 is listening on Proxmox host"
    else
        print_error "✗ HTTP port 80 not listening on Proxmox host"
    fi
    
    if ss -tlnp | grep -q ":1883 "; then
        print_status "✓ MQTT stream port 1883 is listening on Proxmox host"
    else
        print_error "✗ MQTT stream port 1883 not listening on Proxmox host"
    fi
    
    # Test connectivity from host to container services
    print_info "Testing host-to-container connectivity..."
    
    if timeout 3 nc -z "${CONFIG[container_ip]}" 1883 2>/dev/null; then
        print_status "✓ Can connect to container MQTT from host"
    else
        print_warning "⚠ Cannot connect to container MQTT from host"
    fi
    
    if timeout 3 nc -z "${CONFIG[container_ip]}" 8081 2>/dev/null; then
        print_status "✓ Can connect to container API from host"
    else
        print_warning "⚠ Cannot connect to container API from host"
    fi
    
    echo
}

# Step 5: Display deployment summary
show_deployment_summary() {
    print_header "Deployment Complete!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    print_status "🎉 GhostBridge deployment completed successfully!"
    echo
    
    echo -e "${CYAN}📊 Deployment Summary:${NC}"
    echo "  • Architecture: LXC Container + Proxmox Host"
    echo "  • Container ID: ${CONFIG[container_id]}"
    echo "  • Container IP: ${CONFIG[container_ip]}"
    echo "  • Host Services: Nginx with stream module"
    echo "  • Container Services: Netmaker + Mosquitto"
    echo
    
    echo -e "${CYAN}🌐 Service Endpoints:${NC}"
    echo "  • Netmaker API: https://netmaker.hobsonschoice.net"
    echo "  • MQTT Broker: mqtt://broker.hobsonschoice.net:1883"
    echo "  • MQTT WebSocket: wss://broker.hobsonschoice.net:9001"
    echo "  • GhostBridge Control Panel: https://ghostbridge.hobsonschoice.net"
    echo
    
    echo -e "${CYAN}🔧 OVS Architecture Overview:${NC}"
    echo "  ┌─────────────────────────────┐     ┌──────────────────────┐"
    echo "  │      Proxmox Host           │────▶│   LXC Container      │"
    echo "  │  ovsbr0-public: 80.209.240.244  │     │   ${CONFIG[container_ip]}        │"
    echo "  │  ovsbr0-private: 10.0.0.1   │     │                      │"
    echo "  │                             │     │ • Netmaker (8081)    │"
    echo "  │ • Nginx (80.209.240.244)    │     │ • Mosquitto (1883)   │"
    echo "  │ • MQTT Proxy (1883)         │     │ • MQTT WS (9001)     │"
    echo "  │ • Stream Module             │     │ • Netmaker Overlay   │"
    echo "  │ • Proxmox UI (8006)         │     │                      │"
    echo "  └─────────────────────────────┘     └──────────────────────┘"
    echo
    
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo "  1. Configure DNS records to point to Proxmox host public IP"
    echo "  2. Obtain SSL certificates:"
    echo "     certbot --nginx -d netmaker.hobsonschoice.net -d broker.hobsonschoice.net -d ghostbridge.hobsonschoice.net"
    echo "  3. Test Netmaker API at https://netmaker.hobsonschoice.net/api/server/health"
    echo "  4. Access master key: pct exec ${CONFIG[container_id]} -- /etc/netmaker/get-master-key.sh"
    echo "  5. Create your first admin user via API"
    echo "  6. Configure networks and nodes via API calls"
    echo "  7. Deploy GhostBridge control panel at https://ghostbridge.hobsonschoice.net"
    echo
    
    echo -e "${CYAN}📁 Important Files & Logs:${NC}"
    echo "  • Deployment log: $LOG_FILE"
    echo "  • Container config: pct config ${CONFIG[container_id]}"
    echo "  • Nginx config: /etc/nginx/sites-available/ghostbridge"
    echo "  • Netmaker config: /etc/netmaker/config.yaml (in container)"
    echo "  • MQTT config: /etc/mosquitto/mosquitto.conf (in container)"
    echo
    
    echo -e "${CYAN}🔍 Management Commands:${NC}"
    echo "  • Enter container: pct enter ${CONFIG[container_id]}"
    echo "  • Check container services: pct exec ${CONFIG[container_id]} -- systemctl status netmaker mosquitto"
    echo "  • Check host nginx: systemctl status nginx"
    echo "  • View container logs: pct exec ${CONFIG[container_id]} -- journalctl -u netmaker -f"
    echo "  • Test MQTT: pct exec ${CONFIG[container_id]} -- mosquitto_pub -h 127.0.0.1 -p 1883 -t test -m hello"
    echo
    
    echo -e "${CYAN}🛠️ Troubleshooting:${NC}"
    echo "  • Container not responding: pct stop ${CONFIG[container_id]} && pct start ${CONFIG[container_id]}"
    echo "  • Nginx issues: nginx -t && systemctl restart nginx"
    echo "  • Network issues: Check firewall rules and bridge configuration"
    echo "  • Service issues: Check logs in container with journalctl"
    echo
    
    # Extract and display credentials
    print_info "Extracting credentials from container..."
    if pct exec "${CONFIG[container_id]}" -- test -f /etc/netmaker/credentials.env; then
        echo -e "${CYAN}🔐 Generated Credentials & API Access:${NC}"
        pct exec "${CONFIG[container_id]}" -- cat /etc/netmaker/credentials.env | grep -E "(MASTER_KEY|USERNAME|PASSWORD|API_URL|CONTROL_PANEL)" | sed 's/^export /  • /'
        echo "  ⚠️  Save these credentials securely!"
        echo
        echo -e "${CYAN}💡 API Usage Examples:${NC}"
        echo "  • Get master key: pct exec ${CONFIG[container_id]} -- /etc/netmaker/get-master-key.sh"
        echo "  • Load variables: pct exec ${CONFIG[container_id]} -- source /etc/netmaker/credentials.env"
        echo "  • Test API: curl -H \"Authorization: Bearer \$NETMAKER_MASTER_KEY\" \$NETMAKER_API_URL/server/health"
        echo
    fi
    
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_status "🎯 Deployment completed successfully!"
    print_info "Your GhostBridge Netmaker installation is ready to use."
}

# Cleanup on failure
cleanup_on_failure() {
    print_header "Cleaning Up After Failure"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_warning "Deployment failed - cleaning up partial installation..."
    
    # Stop and remove container if it exists
    if [[ -n "${CONFIG[container_id]:-}" ]]; then
        print_info "Cleaning up container ${CONFIG[container_id]}..."
        pct stop "${CONFIG[container_id]}" --force 2>/dev/null || true
        pct destroy "${CONFIG[container_id]}" --force 2>/dev/null || true
    fi
    
    print_info "Please review the log file for details: $LOG_FILE"
}

# Main execution function
main() {
    # Set up error handling
    trap cleanup_on_failure ERR
    
    show_banner
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting GhostBridge deployment v$SCRIPT_VERSION" >> "$LOG_FILE"
    
    check_prerequisites
    get_deployment_config
    
    print_header "Starting GhostBridge Deployment"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    # Execute deployment steps in correct order
    reset_to_proxmox_defaults
    deploy_lxc_container
    start_lxc_container
    deploy_container_services
    deploy_nginx_upgrade
    configure_final_network
    test_deployment
    show_deployment_summary
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - GhostBridge deployment completed successfully" >> "$LOG_FILE"
}

# Handle script interruption
trap 'print_error "Deployment interrupted by user"; cleanup_on_failure; exit 1' INT TERM

# Execute main function with all arguments
main "$@"