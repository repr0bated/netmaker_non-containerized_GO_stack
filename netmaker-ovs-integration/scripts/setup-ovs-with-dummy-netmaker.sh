#!/bin/bash

# Setup OVS with Dummy Netmaker Interfaces
# Creates OVS bridges with placeholder Netmaker network until API calls configure real ones

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }
print_header() { echo -e "${CYAN}[OVS-SETUP]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root"
    exit 1
fi

print_header "Setting up OVS with Dummy Netmaker Interfaces"
echo

# Network configuration from CLAUDE.md
GHOSTBRIDGE_NETWORK="10.0.0.0/24"
PROXMOX_IP="10.0.0.1"
CONTAINER_IP="10.0.0.151"
BRIDGE_NAME="ovsbr0"

print_info "Network configuration:"
echo "  • Bridge: $BRIDGE_NAME"
echo "  • Network: $GHOSTBRIDGE_NETWORK" 
echo "  • Proxmox: $PROXMOX_IP"
echo "  • Container: $CONTAINER_IP"
echo

# Install OVS if not installed
print_info "Installing OpenVSwitch..."
if ! command -v ovs-vsctl >/dev/null 2>&1; then
    apt update -qq
    apt install -y openvswitch-switch
    print_status "OpenVSwitch installed"
else
    print_status "OpenVSwitch already installed"
fi

# Start OVS services
print_info "Starting OVS services..."
systemctl enable openvswitch-switch
systemctl start openvswitch-switch
print_status "OVS services started"

# Create main OVS bridge
print_info "Creating OVS bridge: $BRIDGE_NAME"
if ! ovs-vsctl br-exists "$BRIDGE_NAME"; then
    ovs-vsctl add-br "$BRIDGE_NAME"
    print_status "OVS bridge $BRIDGE_NAME created"
else
    print_status "OVS bridge $BRIDGE_NAME already exists"
fi

# Configure bridge IP (Proxmox node IP)
print_info "Configuring bridge IP: $PROXMOX_IP"
ip addr flush dev "$BRIDGE_NAME" 2>/dev/null || true
ip addr add "$PROXMOX_IP/24" dev "$BRIDGE_NAME"
ip link set "$BRIDGE_NAME" up
print_status "Bridge IP configured"

# Create dummy Netmaker interfaces (placeholders until API calls)
print_info "Creating dummy Netmaker network interfaces..."

# Dummy ghostbridge-net interface (represents the Netmaker network)
if ! ip link show ghostbridge-net >/dev/null 2>&1; then
    ip link add ghostbridge-net type dummy
    ip link set ghostbridge-net up
    ovs-vsctl add-port "$BRIDGE_NAME" ghostbridge-net
    print_status "Created dummy ghostbridge-net interface"
else
    print_status "Dummy ghostbridge-net interface already exists"
fi

# Dummy interfaces for Netmaker nodes (will be replaced by API calls)
# Proxmox node interface
if ! ip link show nm-proxmox >/dev/null 2>&1; then
    ip link add nm-proxmox type dummy
    ip link set nm-proxmox up
    ovs-vsctl add-port "$BRIDGE_NAME" nm-proxmox
    print_status "Created dummy nm-proxmox interface"
else
    print_status "Dummy nm-proxmox interface already exists"
fi

# Container node interface  
if ! ip link show nm-container >/dev/null 2>&1; then
    ip link add nm-container type dummy
    ip link set nm-container up
    ovs-vsctl add-port "$BRIDGE_NAME" nm-container
    print_status "Created dummy nm-container interface"
else
    print_status "Dummy nm-container interface already exists"
fi

# Set up basic forwarding
print_info "Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ovs-forward.conf
print_status "IP forwarding enabled"

# Show OVS configuration
print_info "Current OVS configuration:"
ovs-vsctl show

print_status "✅ OVS setup with dummy Netmaker interfaces completed!"
echo
print_info "Next steps:"
print_info "  1. Move container to OVS bridge: pct set <id> -net0 name=eth0,bridge=$BRIDGE_NAME,ip=$CONTAINER_IP/24,gw=$PROXMOX_IP"
print_info "  2. Start services: ./start-services.sh <container-id>"
print_info "  3. API calls will replace dummy interfaces with real Netmaker networks"
echo
print_warning "Dummy interfaces are placeholders - real Netmaker networks will be configured via API"