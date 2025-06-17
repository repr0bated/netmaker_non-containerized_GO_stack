#!/bin/bash
# GhostBridge - Configure OVS Bridges on Proxmox
# Run this script on the Proxmox host as root

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

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root on the Proxmox host"
   exit 1
fi


echo "=== GhostBridge: Configure OVS Bridges on Proxmox ==="
log "Starting OVS bridge configuration"

# Backup current network configuration
log "Backing up current network configuration..."
cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%s)

# Get current network interface (assuming it's the one with the default route)
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
MAIN_IP=$(ip addr show $MAIN_INTERFACE | grep 'inet ' | awk '{print $2}' | head -n1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)

log "Detected main interface: $MAIN_INTERFACE"
log "Current IP: $MAIN_IP"
log "Gateway: $GATEWAY"

# Install Open vSwitch
log "Installing Open vSwitch..."
apt-get update
apt-get install -y openvswitch-switch

# Enable and start OVS service
systemctl enable openvswitch-switch
systemctl start openvswitch-switch

# Wait for OVS to be ready
sleep 3

# Create OVS bridges
log "Creating OVS bridges..."

# Management bridge (OVS) - use --may-exist for idempotency
ovs-vsctl --may-exist add-br ovsbr0
ovs-vsctl --may-exist add-port ovsbr0 $MAIN_INTERFACE

# Private container bridge (OVS)
ovs-vsctl --may-exist add-br ovsbr1

# Configure network interfaces
log "Creating new network configuration..."
cat > /etc/network/interfaces << EOF
# GhostBridge OVS Network Configuration
# Generated on $(date)

# Loopback interface
auto lo
iface lo inet loopback

# Management bridge (public/WAN access) - OVS Bridge
allow-ovs ovsbr0
iface ovsbr0 inet manual
    ovs_type OVSBridge
    ovs_ports $MAIN_INTERFACE vlan1

# Main interface (enslaved to OVS bridge)
allow-ovsbr0 $MAIN_INTERFACE
iface $MAIN_INTERFACE inet manual
    ovs_bridge ovsbr0
    ovs_type OVSPort

# Management IP via OVS internal port (best practice)
allow-ovsbr0 vlan1
iface vlan1 inet static
    ovs_type OVSIntPort
    ovs_bridge ovsbr0
    ovs_options tag=1
    address ${MAIN_IP%/*}
    netmask $(ipcalc -m $MAIN_IP | cut -d= -f2)
    gateway $GATEWAY
    dns-nameservers 8.8.8.8 8.8.4.4

# Private container bridge (internal only) - OVS Bridge
allow-ovs ovsbr1
iface ovsbr1 inet manual
    ovs_type OVSBridge
    ovs_ports vlan100

# Private network IP via OVS internal port
allow-ovsbr1 vlan100
iface vlan100 inet static
    ovs_type OVSIntPort
    ovs_bridge ovsbr1
    ovs_options tag=100
    address 192.168.100.1
    netmask 255.255.255.0
    # Enable IP forwarding for this bridge
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o vlan1 -j MASQUERADE
    post-up iptables -A FORWARD -i vlan100 -o vlan1 -j ACCEPT
    post-up iptables -A FORWARD -i vlan1 -o vlan100 -m state --state RELATED,ESTABLISHED -j ACCEPT
    post-down iptables -t nat -D POSTROUTING -s 192.168.100.0/24 -o vlan1 -j MASQUERADE
    post-down iptables -D FORWARD -i vlan100 -o vlan1 -j ACCEPT
    post-down iptables -D FORWARD -i vlan1 -o vlan100 -m state --state RELATED,ESTABLISHED -j ACCEPT

EOF

# Install systemd service to create bridges at boot
log "Installing systemd service for OVS bridges..."
cp "$SCRIPT_DIR/create-ovs-bridges.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable create-ovs-bridges.service
systemctl start create-ovs-bridges.service

# Show OVS configuration
log "Current OVS configuration:"
ovs-vsctl show

# Show bridge configuration
log "OVS bridges:"
ovs-vsctl list-br

success "OVS bridges configured successfully!"

echo ""
echo "=== Configuration Summary ==="
echo "Management Bridge: ovsbr0 (OVS) - Connected to $MAIN_INTERFACE"
echo "  - IP: $MAIN_IP"
echo "  - Gateway: $GATEWAY"
echo "  - Purpose: VM/Container management and WAN access"
echo ""
echo "Private Bridge: ovsbr1 (OVS) - Internal only"
echo "  - IP: 192.168.100.1/24"
echo "  - DHCP Range: 192.168.100.10-250 (if DHCP configured)"
echo "  - Purpose: Private container networking with NAT"
echo ""
echo "=== Next Steps ==="
echo "1. REBOOT the Proxmox host to apply network changes"
echo "2. Update container network configuration to use:"
echo "   - Management: ovsbr0 (for external access)"
echo "   - Private: ovsbr1 (for internal container communication)"
echo "3. Example container network config:"
echo "   net0: bridge=ovsbr0,ip=dhcp"
echo "   net1: bridge=ovsbr1,ip=192.168.100.101/24"
echo ""
warning "IMPORTANT: Network connectivity will be lost until reboot!"
warning "Make sure you have console access before rebooting!"
echo ""
echo "Reboot command: shutdown -r now"