#!/bin/bash

# GhostBridge Container Network Setup Script
# Creates dummy OVS interfaces for Netmaker mesh integration
# Based on NETWORK_TOPOLOGY_MAPPING.md

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
CONTAINER_PRIVATE_IP="10.0.0.151"
CONTAINER_PUBLIC_IP="80.209.242.196"
PUBLIC_GATEWAY="80.209.242.129"
PRIVATE_GATEWAY="10.0.0.1"
DNS_SERVERS="8.8.8.8 8.8.4.4"
NETMAKER_MESH_IP="100.104.70.1"
NETMAKER_MGMT_IP="10.88.88.151"

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root"
    fi
}

# Check if running in container
check_container() {
    if [[ ! -f /.dockerenv && ! -f /run/.containerenv ]]; then
        # Check for LXC container
        if [[ ! -d /proc/1/root/.lxc-boot ]]; then
            warn "This script is designed to run inside an LXC container"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    fi
}

# Skip package installation - no network connectivity in container
install_packages() {
    log "Skipping package installation (no network connectivity)"
    return 0
}

# Configure network interfaces
setup_network_interfaces() {
    log "Configuring network interfaces..."
    
    # Configure DNS
    cat > /etc/resolv.conf << EOF
nameserver ${DNS_SERVERS%% *}
nameserver ${DNS_SERVERS##* }
EOF
    
    # Check if we have dual interface setup from Proxmox
    if ip addr show eth1 &>/dev/null; then
        log "Dual interface setup detected (eth0 + eth1)"
        
        # Configure private interface (eth0)
        ip addr flush dev eth0 || true
        ip addr add ${CONTAINER_PRIVATE_IP}/24 dev eth0
        ip link set eth0 up
        
        # Configure public interface (eth1) - 80.209.242.196/25
        ip addr flush dev eth1 || true
        ip addr add ${CONTAINER_PUBLIC_IP}/25 dev eth1
        ip link set eth1 up
        
        # Set up routing for dual interface
        ip route del default || true
        ip route add default via ${PUBLIC_GATEWAY} dev eth1
        ip route add 10.0.0.0/24 via ${PRIVATE_GATEWAY} dev eth0
        
    else
        log "Single interface setup detected (eth0 only)"
        
        # Configure single interface with private IP
        ip addr flush dev eth0 || true
        ip addr add ${CONTAINER_PRIVATE_IP}/24 dev eth0
        ip link set eth0 up
        
        # Set default gateway
        ip route del default || true
        ip route add default via ${PRIVATE_GATEWAY} dev eth0
    fi
}

# Create dummy interfaces for Netmaker integration (no OVS in container)
setup_dummy_ovs_interfaces() {
    log "Creating dummy interfaces for Netmaker integration (container mode)..."
    setup_dummy_interfaces
}

# Create dummy interfaces if OVS not available
setup_dummy_interfaces() {
    log "Creating dummy interfaces for Netmaker integration..."
    
    # Create dummy interfaces
    ip link add nm-mesh type dummy || true
    ip link add nm-mgmt type dummy || true
    
    # Configure Netmaker mesh interface
    ip addr flush dev nm-mesh || true
    ip addr add ${NETMAKER_MESH_IP}/24 dev nm-mesh
    ip link set nm-mesh up
    
    # Configure Netmaker management interface  
    ip addr flush dev nm-mgmt || true
    ip addr add ${NETMAKER_MGMT_IP}/24 dev nm-mgmt
    ip link set nm-mgmt up
    
    log "Dummy Netmaker integration interfaces created"
}

# Configure Netmaker integration
setup_netmaker_config() {
    log "Configuring Netmaker integration..."
    
    # Create Netmaker config directory
    mkdir -p /etc/netmaker
    
    # Create basic Netmaker configuration
    cat > /etc/netmaker/config.yaml << EOF
server:
  host: "${CONTAINER_PUBLIC_IP:-$CONTAINER_PRIVATE_IP}"
  apiport: 8081
  publichost: "${CONTAINER_PUBLIC_IP:-$CONTAINER_PRIVATE_IP}"
  grpcport: 50051
  masterkey: "secretkey"
  
broker:
  host: "127.0.0.1"
  port: 1883
  
database:
  host: "127.0.0.1"
  port: 5432
  
network:
  mesh_interface: "nm-mesh"
  management_interface: "nm-mgmt"
  mesh_subnet: "100.104.70.0/24"
  management_subnet: "10.88.88.0/24"
  
integration:
  ovs_bridge: "nm-local"
  dummy_mode: true
EOF
    
    log "Netmaker configuration created"
}

# Create persistent network configuration
create_persistent_config() {
    log "Creating persistent network configuration..."
    
    # Create systemd network configuration for container
    mkdir -p /etc/systemd/network
    
    # Configure eth0 (private interface)
    cat > /etc/systemd/network/eth0.network << EOF
[Match]
Name=eth0

[Network]
Address=${CONTAINER_PRIVATE_IP}/24
Gateway=${PRIVATE_GATEWAY}
DNS=${DNS_SERVERS}
EOF
    
    # Configure eth1 if dual interface
    if ip addr show eth1 &>/dev/null; then
        cat > /etc/systemd/network/eth1.network << EOF
[Match]
Name=eth1

[Network]
Address=${CONTAINER_PUBLIC_IP}/25
Gateway=${PUBLIC_GATEWAY}
DNS=${DNS_SERVERS}
EOF
    fi
    
    # Configure Netmaker mesh interface
    cat > /etc/systemd/network/nm-mesh.network << EOF
[Match]
Name=nm-mesh

[Network]
Address=${NETMAKER_MESH_IP}/24
EOF
    
    # Configure Netmaker management interface
    cat > /etc/systemd/network/nm-mgmt.network << EOF
[Match]
Name=nm-mgmt

[Network]
Address=${NETMAKER_MGMT_IP}/24
EOF
    
    # Create startup script for dummy interfaces
    cat > /etc/systemd/system/netmaker-interfaces.service << EOF
[Unit]
Description=Netmaker Dummy Interfaces
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c '
    # Create dummy interfaces if they don't exist
    ip link add nm-mesh type dummy 2>/dev/null || true
    ip link add nm-mgmt type dummy 2>/dev/null || true
    
    # Configure interfaces
    ip addr flush dev nm-mesh 2>/dev/null || true
    ip addr add ${NETMAKER_MESH_IP}/24 dev nm-mesh
    ip link set nm-mesh up
    
    ip addr flush dev nm-mgmt 2>/dev/null || true  
    ip addr add ${NETMAKER_MGMT_IP}/24 dev nm-mgmt
    ip link set nm-mgmt up
'
ExecStop=/bin/bash -c '
    ip link del nm-mesh 2>/dev/null || true
    ip link del nm-mgmt 2>/dev/null || true
'

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the service
    systemctl daemon-reload
    systemctl enable netmaker-interfaces.service
    
    log "Persistent configuration created"
}

# Show interface status (no connectivity testing)
show_interface_status() {
    log "Showing interface configuration..."
    
    echo -e "${BLUE}=== Interface Status ===${NC}"
    ip addr show | grep -E "(eth[0-9]|nm-)"
    
    echo -e "${BLUE}=== Routing Table ===${NC}"
    ip route show
}

# Show final status
show_status() {
    log "Container network setup complete!"
    echo
    echo -e "${BLUE}=== Network Configuration Summary ===${NC}"
    echo "Private Interface: ${CONTAINER_PRIVATE_IP}/24 via ${PRIVATE_GATEWAY}"
    [[ -n "${CONTAINER_PUBLIC_IP:-}" ]] && echo "Public Interface: ${CONTAINER_PUBLIC_IP}/25 via ${PUBLIC_GATEWAY}"
    echo "Netmaker Mesh: ${NETMAKER_MESH_IP}/24 (nm-mesh)"
    echo "Netmaker Management: ${NETMAKER_MGMT_IP}/24 (nm-mgmt)"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Install and configure Netmaker server"
    echo "2. Configure Mosquitto MQTT broker" 
    echo "3. Set up SSL certificates"
    echo "4. Configure reverse proxy on host"
}

# Cleanup function
cleanup() {
    if [[ $? -ne 0 ]]; then
        error "Script failed! Check logs for details."
    fi
}

# Main execution
main() {
    log "Starting GhostBridge Container Network Setup..."
    
    check_root
    check_container
    
    # Set trap for cleanup
    trap cleanup EXIT
    
    install_packages
    setup_network_interfaces
    setup_dummy_ovs_interfaces
    setup_netmaker_config
    create_persistent_config
    show_interface_status
    show_status
    
    log "Container network setup completed successfully!"
}

# Run main function
main "$@"