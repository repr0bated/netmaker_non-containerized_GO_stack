#!/bin/bash
# GhostBridge - Reconfigure Container Networking for OVS
# Run this script on the Proxmox host after OVS configuration and reboot

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Configuration
CONTAINER_ID="100"
CONTAINER_NAME="ghostbridge"

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root on the Proxmox host"
   exit 1
fi

echo "=== GhostBridge: Reconfigure Container Networking ==="
log "Updating container $CONTAINER_ID networking for OVS bridges"

# Check if container exists
if ! pct list | grep -q "^$CONTAINER_ID"; then
    error "Container $CONTAINER_ID not found"
    exit 1
fi

# Stop container if running
if pct status $CONTAINER_ID | grep -q "running"; then
    log "Stopping container $CONTAINER_ID..."
    pct stop $CONTAINER_ID
    sleep 5
fi

# Backup container configuration
log "Backing up container configuration..."
cp /etc/pve/lxc/${CONTAINER_ID}.conf /etc/pve/lxc/${CONTAINER_ID}.conf.backup.$(date +%s)

# Update container network configuration
log "Updating container network configuration..."

# Remove old network configuration
sed -i '/^net[0-9]/d' /etc/pve/lxc/${CONTAINER_ID}.conf

# Add new network configuration
cat >> /etc/pve/lxc/${CONTAINER_ID}.conf << EOF

# GhostBridge OVS Network Configuration
# Management interface (external access)
net0: name=eth0,bridge=ovsbr0,ip=dhcp

# Private interface (internal container communication)  
net1: name=eth1,bridge=ovsbr1,ip=192.168.100.101/24
EOF

# Start container
log "Starting container $CONTAINER_ID..."
pct start $CONTAINER_ID

# Wait for container to start
sleep 10

# Configure networking inside container
log "Configuring networking inside container..."

# Create network configuration script for container
cat > /tmp/container-network-config.sh << 'EOF'
#!/bin/bash
# Configure networking inside container

# Update /etc/network/interfaces
cat > /etc/network/interfaces << 'NETEOF'
# GhostBridge Container Network Configuration

auto lo
iface lo inet loopback

# Management interface (external access via DHCP)
auto eth0
iface eth0 inet dhcp

# Private interface (internal container network)
auto eth1  
iface eth1 inet static
    address 192.168.100.101
    netmask 255.255.255.0
    # No gateway on private interface
NETEOF

# Restart networking
systemctl restart networking

# Show interface status
echo "Container network interfaces:"
ip addr show

# Test connectivity
echo "Testing connectivity..."
ping -c 3 8.8.8.8 || echo "External connectivity test failed"
ping -c 3 192.168.100.1 || echo "Private gateway connectivity test failed"
EOF

# Copy and execute network configuration in container
pct push $CONTAINER_ID /tmp/container-network-config.sh /tmp/network-config.sh
pct exec $CONTAINER_ID -- chmod +x /tmp/network-config.sh
pct exec $CONTAINER_ID -- /tmp/network-config.sh

# Clean up temporary file
rm /tmp/container-network-config.sh

# Update Netmaker configuration for new IP
log "Updating Netmaker configuration for new network..."
NETMAKER_CONFIG="/etc/netmaker/config.yaml"

if pct exec $CONTAINER_ID -- test -f "$NETMAKER_CONFIG"; then
    # Backup existing config
    pct exec $CONTAINER_ID -- cp "$NETMAKER_CONFIG" "${NETMAKER_CONFIG}.backup.$(date +%s)"
    
    # Get the new external IP (from DHCP)
    sleep 5  # Wait for DHCP
    EXTERNAL_IP=$(pct exec $CONTAINER_ID -- ip route get 8.8.8.8 | grep -oP 'src \K\S+')
    
    if [[ -n "$EXTERNAL_IP" ]]; then
        log "Container external IP: $EXTERNAL_IP"
        
        # Update Netmaker config with new IPs
        pct exec $CONTAINER_ID -- sed -i "s/server_host:.*/server_host: $EXTERNAL_IP/" "$NETMAKER_CONFIG"
        pct exec $CONTAINER_ID -- sed -i "s/api_host:.*/api_host: $EXTERNAL_IP/" "$NETMAKER_CONFIG"
        
        # Set broker to use private IP for internal communication
        pct exec $CONTAINER_ID -- sed -i 's|broker_endpoint:.*|broker_endpoint: ws://192.168.100.101:9001/mqtt|g' "$NETMAKER_CONFIG"
        
        success "Netmaker configuration updated"
    else
        warning "Could not determine container external IP"
    fi
else
    warning "Netmaker config not found"
fi

# Show final configuration
log "Final container configuration:"
echo "Container ID: $CONTAINER_ID"
echo "Management Interface (eth0): DHCP on ovsbr0"
echo "Private Interface (eth1): 192.168.100.101/24 on ovsbr1"
echo ""
echo "Container network interfaces:"
pct exec $CONTAINER_ID -- ip addr show

echo ""
echo "OVS Bridge Status:"
ovs-vsctl show

success "Container networking reconfiguration complete!"

echo ""
echo "=== Network Configuration Summary ==="
echo "Proxmox Host:"
echo "  - ovsbr0 (OVS): Management bridge with external access"  
echo "  - ovsbr1 (OVS): Private bridge (192.168.100.0/24)"
echo ""
echo "Container $CONTAINER_ID:"
echo "  - eth0: DHCP on ovsbr0 (external access)"
echo "  - eth1: 192.168.100.101/24 on ovsbr1 (private)"
echo ""
echo "Next: Update CLAUDE.md with new network configuration"