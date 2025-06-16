#!/bin/bash

# GhostBridge Netmaker Dummy Installer
# Creates minimal Netmaker interface and configuration to satisfy netmaker-ovs-integration requirements
# This is a lightweight dummy install that creates just enough for OVS integration to work

set -euo pipefail

SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/ghostbridge-netmaker-dummy-install.log"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration defaults
DEFAULT_INTERFACE_NAME="nm-dummy"
DEFAULT_NETWORK_RANGE="10.100.0.0/24"
DEFAULT_DUMMY_IP="10.100.0.1/24"
DEFAULT_BRIDGE_NAME="ovsbr0"

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
    echo -e "${CYAN}[DUMMY INSTALLER]${NC} $1" | tee -a "$LOG_FILE"
}

print_question() {
    echo -e "${PURPLE}[?]${NC} $1"
}

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║            GhostBridge Netmaker Dummy Installer                ║
║                                                                ║
║    Creates minimal setup for netmaker-ovs-integration          ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
    print_info "Version: $SCRIPT_VERSION"
    print_info "Purpose: Prepare system for netmaker-ovs-integration script"
    print_info "Log File: $LOG_FILE"
    echo
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Explain what this script does
explain_purpose() {
    print_header "Dummy Installation Overview"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    print_info "This script creates a minimal Netmaker dummy setup to satisfy"
    print_info "the requirements of the netmaker-ovs-integration script:"
    echo
    echo "  • Creates a dummy Netmaker interface (nm-dummy)"
    echo "  • Sets up minimal configuration files"
    echo "  • Creates systemd service placeholders"
    echo "  • Prepares OVS configuration"
    echo
    print_warning "This is NOT a real Netmaker installation!"
    print_warning "Use this only to test OVS integration, then do a real install."
    echo
    
    print_question "Continue with dummy installation? [y/N]:"
    read -r continue_install
    if [[ ! "$continue_install" =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled by user"
        exit 0
    fi
}

# Get configuration from user
get_configuration() {
    print_header "Dummy Configuration Setup"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_question "Enter dummy interface name:"
    read -p "Interface name [$DEFAULT_INTERFACE_NAME]: " interface_name
    INTERFACE_NAME="${interface_name:-$DEFAULT_INTERFACE_NAME}"
    
    print_question "Enter dummy IP address:"
    read -p "IP address [$DEFAULT_DUMMY_IP]: " dummy_ip
    DUMMY_IP="${dummy_ip:-$DEFAULT_DUMMY_IP}"
    
    print_question "Enter OVS bridge name:"
    read -p "Bridge name [$DEFAULT_BRIDGE_NAME]: " bridge_name
    BRIDGE_NAME="${bridge_name:-$DEFAULT_BRIDGE_NAME}"
    
    print_question "Enter network range:"
    read -p "Network range [$DEFAULT_NETWORK_RANGE]: " network_range
    NETWORK_RANGE="${network_range:-$DEFAULT_NETWORK_RANGE}"
    
    echo
    print_info "Configuration:"
    echo "  • Dummy Interface: $INTERFACE_NAME"
    echo "  • IP Address: $DUMMY_IP"
    echo "  • Bridge Name: $BRIDGE_NAME"
    echo "  • Network Range: $NETWORK_RANGE"
    echo
}

# Create dummy network interface
create_dummy_interface() {
    print_header "Creating Dummy Netmaker Interface"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if interface already exists
    if ip link show "$INTERFACE_NAME" >/dev/null 2>&1; then
        print_warning "Interface $INTERFACE_NAME already exists"
        
        print_question "Remove existing interface and recreate? [y/N]:"
        read -r recreate
        if [[ "$recreate" =~ ^[Yy]$ ]]; then
            print_info "Removing existing interface..."
            ip link delete "$INTERFACE_NAME" 2>/dev/null || true
        else
            print_info "Using existing interface"
            return 0
        fi
    fi
    
    # Create dummy interface
    print_info "Creating dummy interface: $INTERFACE_NAME"
    ip link add "$INTERFACE_NAME" type dummy
    
    # Set IP address
    print_info "Setting IP address: $DUMMY_IP"
    ip addr add "$DUMMY_IP" dev "$INTERFACE_NAME"
    
    # Bring interface up
    print_info "Bringing interface up..."
    ip link set "$INTERFACE_NAME" up
    
    # Verify interface creation
    if ip link show "$INTERFACE_NAME" >/dev/null 2>&1; then
        print_status "Dummy interface $INTERFACE_NAME created successfully"
        
        # Show interface details
        print_info "Interface details:"
        ip addr show "$INTERFACE_NAME" | sed 's/^/    /'
    else
        print_error "Failed to create dummy interface"
        exit 1
    fi
}

# Create directory structure
create_directories() {
    print_header "Creating Directory Structure"
    echo "────────────────────────────────────────────────────────────────────────"
    
    local dirs=(
        "/etc/netmaker"
        "/opt/netmaker/data"
        "/opt/netmaker/logs" 
        "/var/log/netmaker"
        "/var/backups/netmaker"
    )
    
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            print_status "Created directory: $dir"
        else
            print_info "Directory already exists: $dir"
        fi
    done
}

# Create minimal Netmaker configuration
create_netmaker_config() {
    print_header "Creating Minimal Netmaker Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Create basic netmaker config
    cat > /etc/netmaker/config.yaml << EOF
# Dummy Netmaker Configuration for OVS Integration Testing
# Generated by GhostBridge dummy installer

version: v0.20.0

server:
  host: "127.0.0.1"
  apiport: 8081
  grpcport: 8082
  restbackend: false
  agentbackend: false
  messagequeuebackend: false

# Dummy database configuration
database:
  host: ""
  port: 0
  username: ""
  password: ""
  name: ""
  sslmode: ""
  endpoint: ""

# Dummy message queue configuration
messagequeue:
  host: "127.0.0.1"
  port: 1883
  endpoint: "mqtt://127.0.0.1:1883"
  username: ""
  password: ""

# API Configuration
api:
  corsallowed: "*"
  endpoint: "http://127.0.0.1:8081"

# Security Configuration
jwt_validity_duration: "24h"
rachecks: "off"
telemetry: "off"

# Network Settings - DUMMY VALUES
manage_iptables: "off"
default_node_limit: 999999

# Server Configuration
servercheckin: "off"
autopull: "off"
dnsmode: ""
verbosity: 1
platform: "linux"

# Dummy master key
masterkey: "dummy-key-for-ovs-integration-testing"

# Logging
logverbosity: 1
EOF

    chmod 600 /etc/netmaker/config.yaml
    print_status "Created dummy Netmaker configuration: /etc/netmaker/config.yaml"
}

# Create OVS configuration for integration script
create_ovs_config() {
    print_header "Creating OVS Integration Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Determine interface pattern based on created interface
    local interface_pattern
    if [[ "$INTERFACE_NAME" =~ ^nm- ]]; then
        interface_pattern="nm-*"
    elif [[ "$INTERFACE_NAME" =~ ^netmaker- ]]; then
        interface_pattern="netmaker-*"
    else
        interface_pattern="${INTERFACE_NAME}*"
    fi
    
    # Create OVS config file that the integration script expects
    cat > /etc/netmaker/ovs-config << EOF
# OVS Configuration for Netmaker Integration
# Generated by GhostBridge dummy installer

# OpenVSwitch bridge name
BRIDGE_NAME=$BRIDGE_NAME

# Netmaker interface pattern (matches dummy interface)
NM_INTERFACE_PATTERN="$interface_pattern"

# Dummy obfuscation settings (disabled for testing)
ENABLE_OBFUSCATION=false
VLAN_OBFUSCATION=false
MAC_RANDOMIZATION=false
TIMING_OBFUSCATION=false
TRAFFIC_SHAPING=false

# Test configuration markers
DUMMY_INSTALL=true
DUMMY_INTERFACE_NAME=$INTERFACE_NAME
DUMMY_NETWORK_RANGE=$NETWORK_RANGE
EOF

    print_status "Created OVS configuration: /etc/netmaker/ovs-config"
    
    # Display the configuration
    print_info "OVS configuration contents:"
    cat /etc/netmaker/ovs-config | sed 's/^/    /'
}

# Create dummy systemd services
create_dummy_services() {
    print_header "Creating Dummy SystemD Services"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Create dummy netmaker service
    cat > /etc/systemd/system/netmaker.service << EOF
[Unit]
Description=Netmaker Server (Dummy for OVS Integration Testing)
Documentation=https://netmaker.readthedocs.io
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/sleep 86400
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=netmaker-dummy

[Install]
WantedBy=multi-user.target
EOF

    # Create dummy netclient service 
    cat > /etc/systemd/system/netclient.service << EOF
[Unit]
Description=Netclient (Dummy for OVS Integration Testing)
Documentation=https://netmaker.readthedocs.io
After=network-online.target

[Service]
Type=simple
ExecStart=/bin/sleep 86400
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=netclient-dummy

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable netmaker.service netclient.service
    
    print_status "Created and enabled dummy systemd services"
    print_info "Services created: netmaker.service, netclient.service"
}

# Install minimal dependencies for OVS integration
install_dependencies() {
    print_header "Installing Dependencies for OVS Integration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Update package list
    print_info "Updating package lists..."
    apt update
    
    # Install only what's needed for OVS integration testing
    local packages=("openvswitch-switch" "bridge-utils" "iproute2" "net-tools")
    
    print_info "Installing OVS and networking tools..."
    apt install -y "${packages[@]}"
    
    print_status "Dependencies installed successfully"
}

# Create persistent interface configuration
create_persistent_interface() {
    print_header "Creating Persistent Interface Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Create systemd service to recreate dummy interface on boot
    cat > /etc/systemd/system/netmaker-dummy-interface.service << EOF
[Unit]
Description=Create Netmaker Dummy Interface for OVS Integration
After=network.target
Before=netmaker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '
    # Remove interface if it exists
    ip link delete $INTERFACE_NAME 2>/dev/null || true
    # Create dummy interface
    ip link add $INTERFACE_NAME type dummy
    # Set IP address
    ip addr add $DUMMY_IP dev $INTERFACE_NAME
    # Bring interface up
    ip link set $INTERFACE_NAME up
    echo "Dummy interface $INTERFACE_NAME created with IP $DUMMY_IP"
'
ExecStop=/bin/bash -c '
    ip link delete $INTERFACE_NAME 2>/dev/null || true
    echo "Dummy interface $INTERFACE_NAME removed"
'

[Install]
WantedBy=multi-user.target
EOF

    # Enable the service
    systemctl daemon-reload
    systemctl enable netmaker-dummy-interface.service
    
    print_status "Created persistent interface service: netmaker-dummy-interface.service"
}

# Validate dummy installation
validate_dummy_installation() {
    print_header "Validating Dummy Installation"
    echo "────────────────────────────────────────────────────────────────────────"
    
    local validation_passed=true
    
    # Check dummy interface
    if ip link show "$INTERFACE_NAME" >/dev/null 2>&1; then
        print_status "✓ Dummy interface $INTERFACE_NAME exists"
        
        # Check if it matches the pattern the OVS script expects
        local detected_interfaces=$(ip link show | grep -o 'nm-[^:@]*' 2>/dev/null || echo "")
        if [[ -n "$detected_interfaces" ]]; then
            print_status "✓ Interface matches netmaker detection pattern: $detected_interfaces"
        else
            print_warning "⚠ Interface may not match expected pattern for OVS integration"
        fi
    else
        print_error "✗ Dummy interface $INTERFACE_NAME not found"
        validation_passed=false
    fi
    
    # Check configuration files
    if [[ -f /etc/netmaker/config.yaml ]]; then
        print_status "✓ Netmaker configuration exists"
    else
        print_error "✗ Netmaker configuration missing"
        validation_passed=false
    fi
    
    if [[ -f /etc/netmaker/ovs-config ]]; then
        print_status "✓ OVS configuration exists"
    else
        print_error "✗ OVS configuration missing"
        validation_passed=false
    fi
    
    # Check systemd services
    if systemctl list-unit-files | grep -q "netmaker.service"; then
        print_status "✓ Netmaker service registered"
    else
        print_error "✗ Netmaker service not found"
        validation_passed=false
    fi
    
    # Check OVS availability
    if command -v ovs-vsctl >/dev/null 2>&1; then
        print_status "✓ OpenVSwitch tools available"
    else
        print_error "✗ OpenVSwitch not installed"
        validation_passed=false
    fi
    
    echo
    if [[ "$validation_passed" == "true" ]]; then
        print_status "✅ Dummy installation validation passed!"
    else
        print_warning "⚠️ Some validation checks failed"
    fi
    
    return 0
}

# Display completion summary
show_completion_summary() {
    print_header "Dummy Installation Complete!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    print_status "🎭 Dummy Netmaker setup completed successfully!"
    echo
    
    echo -e "${CYAN}📋 What was created:${NC}"
    echo "  • Dummy interface: $INTERFACE_NAME ($DUMMY_IP)"
    echo "  • Netmaker config: /etc/netmaker/config.yaml"
    echo "  • OVS config: /etc/netmaker/ovs-config"
    echo "  • SystemD services: netmaker.service, netclient.service"
    echo "  • Persistent interface service: netmaker-dummy-interface.service"
    echo
    
    echo -e "${CYAN}🔧 Ready for OVS Integration:${NC}"
    echo "  • Interface pattern: $(grep NM_INTERFACE_PATTERN /etc/netmaker/ovs-config | cut -d'=' -f2)"
    echo "  • Bridge name: $(grep BRIDGE_NAME /etc/netmaker/ovs-config | cut -d'=' -f2)"
    echo "  • Detected interfaces: $(ip link show | grep -o 'nm-[^:@]*' || echo 'none')"
    echo
    
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo "  1. Navigate to netmaker-ovs-integration directory"
    echo "  2. Run: sudo ./install-interactive.sh"
    echo "  3. The OVS integration should now detect the dummy interface"
    echo "  4. After testing OVS integration, remove dummy setup:"
    echo "     sudo ./remove-dummy.sh (if created) or manual cleanup"
    echo "  5. Run real Netmaker installation: sudo ./install-interactive.sh"
    echo
    
    echo -e "${CYAN}⚠️ Important Notes:${NC}"
    echo "  • This is a DUMMY installation - not functional Netmaker"
    echo "  • Only use for testing OVS integration scripts"
    echo "  • Remove dummy setup before real installation"
    echo "  • Dummy interface persists across reboots"
    echo
    
    echo -e "${CYAN}🔍 Verification Commands:${NC}"
    echo "  • Check interface: ip addr show $INTERFACE_NAME"
    echo "  • Check services: systemctl status netmaker netclient"
    echo "  • Check OVS detection: ip link show | grep -o 'nm-[^:@]*'"
    echo "  • View OVS config: cat /etc/netmaker/ovs-config"
    echo
    
    echo "════════════════════════════════════════════════════════════════════════"
}

# Create removal script
create_removal_script() {
    print_info "Creating dummy removal script..."
    
    cat > "$PWD/remove-dummy.sh" << EOF
#!/bin/bash

# Remove GhostBridge Netmaker Dummy Installation
echo "Removing dummy Netmaker installation..."

# Stop and disable services
systemctl stop netmaker netclient netmaker-dummy-interface 2>/dev/null || true
systemctl disable netmaker netclient netmaker-dummy-interface 2>/dev/null || true

# Remove dummy interface
ip link delete $INTERFACE_NAME 2>/dev/null || true

# Remove systemd services
rm -f /etc/systemd/system/netmaker.service
rm -f /etc/systemd/system/netclient.service  
rm -f /etc/systemd/system/netmaker-dummy-interface.service

# Remove configuration files
rm -f /etc/netmaker/config.yaml
rm -f /etc/netmaker/ovs-config

# Reload systemd
systemctl daemon-reload

echo "Dummy installation removed successfully!"
echo "You can now run a real Netmaker installation."
EOF

    chmod +x "$PWD/remove-dummy.sh"
    print_status "Created removal script: $PWD/remove-dummy.sh"
}

# Main execution function
main() {
    show_banner
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting dummy installer v$SCRIPT_VERSION" >> "$LOG_FILE"
    
    check_root
    explain_purpose
    get_configuration
    
    print_header "Beginning Dummy Installation Process"
    echo "════════════════════════════════════════════════════════════════════════"
    
    install_dependencies
    create_directories
    create_dummy_interface
    create_netmaker_config
    create_ovs_config
    create_dummy_services
    create_persistent_interface
    validate_dummy_installation
    create_removal_script
    show_completion_summary
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Dummy installation completed successfully" >> "$LOG_FILE"
}

# Execute main function
main "$@"