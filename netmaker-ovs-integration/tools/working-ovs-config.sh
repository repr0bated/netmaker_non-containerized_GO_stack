#!/bin/bash
# Working OVS Configuration for Proxmox (Based on Community Examples)
# This configuration is based on proven working examples from Proxmox community

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
   error "This script must be run as root"
   exit 1
fi

echo "=== Working OVS Configuration for Proxmox ==="
log "Based on proven community examples"

# Get current network interface
MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
MAIN_IP=$(ip addr show $MAIN_INTERFACE | grep 'inet ' | awk '{print $2}' | head -n1)
GATEWAY=$(ip route | grep default | awk '{print $3}' | head -n1)

log "Detected main interface: $MAIN_INTERFACE"
log "Current IP: $MAIN_IP"
log "Gateway: $GATEWAY"

# Backup current configuration
log "Backing up current network configuration..."
cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%s)

# Install Open vSwitch
log "Installing Open vSwitch..."
apt-get update
apt-get install -y openvswitch-switch

# Enable and start OVS service
systemctl enable openvswitch-switch
systemctl start openvswitch-switch
sleep 3

# Create network interfaces file based on working community examples
log "Creating working OVS configuration..."
cat > /etc/network/interfaces << EOF
# Working OVS Configuration - Based on Community Examples
# Generated on $(date)

# Loopback interface
auto lo
iface lo inet loopback

# Physical interface (enslaved to OVS bridge)
auto $MAIN_INTERFACE
iface $MAIN_INTERFACE inet manual
    ovs_type OVSPort
    ovs_bridge vmbr0

# Management VLAN interface (for host access)
auto vlan1
iface vlan1 inet static
    address ${MAIN_IP%/*}
    netmask $(ipcalc -m $MAIN_IP | cut -d= -f2)
    gateway $GATEWAY
    dns-nameservers 8.8.8.8 8.8.4.4
    ovs_type OVSIntPort
    ovs_bridge vmbr0
    ovs_options tag=1

# Private network interface (for container isolation)
auto vlan100
iface vlan100 inet static
    address 192.168.100.1
    netmask 255.255.255.0
    ovs_type OVSIntPort
    ovs_bridge vmbr1
    ovs_options tag=100
    # NAT configuration for private network
    post-up echo 1 > /proc/sys/net/ipv4/ip_forward
    post-up iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -o vlan1 -j MASQUERADE
    post-up iptables -A FORWARD -i vlan100 -o vlan1 -j ACCEPT
    post-up iptables -A FORWARD -i vlan1 -o vlan100 -m state --state RELATED,ESTABLISHED -j ACCEPT
    post-down iptables -t nat -D POSTROUTING -s 192.168.100.0/24 -o vlan1 -j MASQUERADE
    post-down iptables -D FORWARD -i vlan100 -o vlan1 -j ACCEPT
    post-down iptables -D FORWARD -i vlan1 -o vlan100 -m state --state RELATED,ESTABLISHED -j ACCEPT

# Management OVS Bridge (external access)
auto vmbr0
iface vmbr0 inet manual
    ovs_type OVSBridge
    ovs_ports $MAIN_INTERFACE vlan1

# Private OVS Bridge (container isolation)
auto vmbr1
iface vmbr1 inet manual
    ovs_type OVSBridge
    ovs_ports vlan100

EOF

success "OVS network configuration created!"

echo ""
echo "=== Configuration Summary ==="
echo "Management Bridge: vmbr0 (OVS)"
echo "  - Physical port: $MAIN_INTERFACE"
echo "  - Management IP: vlan1 (${MAIN_IP%/*}) on VLAN 1"
echo ""
echo "Private Bridge: vmbr1 (OVS)" 
echo "  - Internal only with NAT"
echo "  - Private IP: vlan100 (192.168.100.1) on VLAN 100"
echo ""
echo "=== Next Steps ==="
echo "1. REBOOT the host to apply network changes"
echo "2. After reboot, update container configs to use:"
echo "   - Management: vmbr0 (external access)"
echo "   - Private: vmbr1 (internal communication)"
echo "3. Container network config example:"
echo "   net0: name=eth0,bridge=vmbr0,ip=dhcp"
echo "   net1: name=eth1,bridge=vmbr1,ip=192.168.100.101/24"
echo ""
warning "IMPORTANT: You will lose network connectivity until reboot!"
warning "Make sure you have console access!"
echo ""
echo "To reboot: shutdown -r now"