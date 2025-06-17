#!/bin/bash

# Network Setup Script (Proxmox Host)
# Sets up final OVS networking after services are running in localhost mode

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }

echo "=== GhostBridge Network Setup (Proxmox Host) ==="
echo

# Find container
CONTAINER_ID=""
if [[ $# -eq 1 ]]; then
    CONTAINER_ID="$1"
else
    print_info "Auto-detecting container..."
    if command -v pct >/dev/null 2>&1; then
        CONTAINER_ID=$(pct list | tail -n +2 | sort -k1 -n | tail -1 | awk '{print $1}' || echo "")
    elif command -v lxc-ls >/dev/null 2>&1; then
        CONTAINER_ID=$(lxc-ls | head -1 || echo "")
    fi
    
    if [[ -z "$CONTAINER_ID" ]]; then
        print_error "No container found. Please specify container ID as argument."
        print_info "Usage: $0 <container-id>"
        exit 1
    fi
fi

print_info "Using container ID: $CONTAINER_ID"

# Check if we're on Proxmox host
if [[ ! -f /etc/pve/local/pve-ssl.pem ]]; then
    print_error "This script must be run on the Proxmox host"
    exit 1
fi

# Network configuration
CONTAINER_IP="10.0.0.101"
BRIDGE_NAME="ovsbr0"
PUBLIC_IP_1="80.209.240.244"
PUBLIC_IP_2="80.209.240.243"
PRIVATE_GATEWAY="10.0.0.1"

print_info "Network configuration:"
echo "  • Container IP: $CONTAINER_IP"
echo "  • OVS Bridge: $BRIDGE_NAME"
echo "  • Public IPs: $PUBLIC_IP_1, $PUBLIC_IP_2"
echo "  • Private Gateway: $PRIVATE_GATEWAY"
echo

# 1. Verify services are running in container
print_info "Checking if services are running in container..."
container_exec() {
    if command -v pct >/dev/null 2>&1; then
        pct exec "$CONTAINER_ID" -- "$@"
    else
        lxc-attach -n "$CONTAINER_ID" -- "$@"
    fi
}

# Check EMQX
if container_exec systemctl is-active --quiet emqx.service; then
    print_status "✅ EMQX is running in container"
else
    print_error "❌ EMQX is not running in container"
    print_info "Run localhost-setup-container.sh first"
    exit 1
fi

# Check Netmaker
if container_exec systemctl is-active --quiet netmaker.service; then
    print_status "✅ Netmaker is running in container"
else
    print_error "❌ Netmaker is not running in container"
    print_info "Run localhost-setup-container.sh first"
    exit 1
fi

# 2. Install OVS if needed
print_info "Installing OpenVSwitch..."
if ! command -v ovs-vsctl >/dev/null 2>&1; then
    apt update
    apt install -y openvswitch-switch bridge-utils
    print_status "OpenVSwitch installed"
else
    print_status "OpenVSwitch already installed"
fi

systemctl enable openvswitch-switch
systemctl start openvswitch-switch

# 3. Create OVS bridge
print_info "Creating OVS bridge: $BRIDGE_NAME"
if ! ovs-vsctl br-exists "$BRIDGE_NAME"; then
    ovs-vsctl add-br "$BRIDGE_NAME"
    print_status "OVS bridge $BRIDGE_NAME created"
else
    print_status "OVS bridge $BRIDGE_NAME already exists"
fi

# 4. Add physical interface to bridge
print_info "Adding physical interface to bridge..."
PHYSICAL_IFACE="eth0"
if ip link show "$PHYSICAL_IFACE" >/dev/null 2>&1; then
    if ! ovs-vsctl list-ports "$BRIDGE_NAME" | grep -q "^${PHYSICAL_IFACE}$"; then
        ovs-vsctl add-port "$BRIDGE_NAME" "$PHYSICAL_IFACE"
        print_status "Physical interface $PHYSICAL_IFACE added to bridge"
    else
        print_status "Physical interface already in bridge"
    fi
else
    print_warning "Physical interface $PHYSICAL_IFACE not found"
fi

# 5. Configure bridge networking
print_info "Configuring bridge networking..."

# Create internal ports for public and private networks
if ! ovs-vsctl list-ports "$BRIDGE_NAME" | grep -q "^${BRIDGE_NAME}-public$"; then
    ovs-vsctl add-port "$BRIDGE_NAME" "${BRIDGE_NAME}-public" -- set interface "${BRIDGE_NAME}-public" type=internal
    print_status "Created public internal port"
fi

if ! ovs-vsctl list-ports "$BRIDGE_NAME" | grep -q "^${BRIDGE_NAME}-private$"; then
    ovs-vsctl add-port "$BRIDGE_NAME" "${BRIDGE_NAME}-private" -- set interface "${BRIDGE_NAME}-private" type=internal
    print_status "Created private internal port"
fi

# Configure IP addresses
ip link set "${BRIDGE_NAME}-public" up
ip link set "${BRIDGE_NAME}-private" up

# Add IP addresses (remove existing first)
ip addr flush dev "${BRIDGE_NAME}-public" || true
ip addr flush dev "${BRIDGE_NAME}-private" || true

ip addr add "$PUBLIC_IP_1/25" dev "${BRIDGE_NAME}-public"
ip addr add "$PUBLIC_IP_2/25" dev "${BRIDGE_NAME}-public"
ip addr add "$PRIVATE_GATEWAY/24" dev "${BRIDGE_NAME}-private"

print_status "Bridge IP addresses configured"

# 6. Update container network configuration
print_info "Updating container network configuration..."

# Stop container briefly to change network config
print_info "Stopping container to update network..."
if command -v pct >/dev/null 2>&1; then
    pct stop "$CONTAINER_ID"
    
    # Update container network config
    pct set "$CONTAINER_ID" -net0 name=eth0,bridge="$BRIDGE_NAME",ip="$CONTAINER_IP/24",gw="$PRIVATE_GATEWAY"
    
    # Start container
    pct start "$CONTAINER_ID"
    
    # Wait for container to be ready
    sleep 10
    
    print_status "Container network updated and restarted"
else
    print_warning "Using LXC commands - manual network reconfiguration needed"
fi

# 7. Update container configs for new network
print_info "Updating container service configs for new network..."

# Update EMQX config to listen on container IP
container_exec bash -c 'cat > /etc/emqx/emqx.conf << "EOF"
## EMQX config for final network
node.name = "emqx@10.0.0.101"
node.cookie = "secret-cookie"
node.data_dir = "/var/lib/emqx"

## Network listeners
listener.tcp = 1883
listener.dashboard = 18083

## Allow everything
allow_anonymous = true
acl_nomatch = allow

## Logging
log.console = console
log.file = emqx.log
EOF'

# Update Netmaker config for new network
container_exec bash -c 'cat > /etc/netmaker/config.yaml << "EOF"
server:
  host: "10.0.0.101"
  apiport: 8081
  grpcport: 50051

database:
  type: "sqlite"
  path: "/var/lib/netmaker/netmaker.db"

mqtt:
  host: "10.0.0.101"
  port: 1883
  username: ""
  password: ""

logging:
  level: "info"

verbosity: 1
platform: "linux"
EOF'

print_status "Container service configs updated for new network"

# 8. Restart services in container
print_info "Restarting services in container..."
container_exec systemctl daemon-reload
container_exec systemctl restart emqx.service
sleep 5
container_exec systemctl restart netmaker.service
sleep 5

# 9. Final validation
print_info "=== Final Network Validation ==="

# Check services
if container_exec systemctl is-active --quiet emqx.service; then
    print_status "✅ EMQX running on new network"
else
    print_error "❌ EMQX failed on new network"
fi

if container_exec systemctl is-active --quiet netmaker.service; then
    print_status "✅ Netmaker running on new network"
else
    print_error "❌ Netmaker failed on new network"
fi

# Check connectivity from host to container
print_info "Testing connectivity from host to container..."
if ping -c 2 "$CONTAINER_IP" >/dev/null 2>&1; then
    print_status "✅ Container reachable from host"
else
    print_warning "⚠ Container not reachable from host"
fi

# Check ports
print_info "Checking exposed ports..."
if curl -s "http://$CONTAINER_IP:18083" >/dev/null 2>&1; then
    print_status "✅ EMQX dashboard accessible"
else
    print_warning "⚠ EMQX dashboard not accessible"
fi

if curl -s "http://$CONTAINER_IP:8081/api/server/health" >/dev/null 2>&1; then
    print_status "✅ Netmaker API accessible"
else
    print_warning "⚠ Netmaker API not accessible yet"
fi

echo
print_status "🎉 Network setup completed!"
print_info "Services available at:"
print_info "  • EMQX Dashboard: http://$PUBLIC_IP_1:18083"
print_info "  • Netmaker API: http://$PUBLIC_IP_1:8081"
print_info "  • MQTT TCP: $PUBLIC_IP_1:1883"
print_info ""
print_info "Next steps:"
print_info "  • Configure nginx proxy for SSL termination"
print_info "  • Set up domain names and certificates"
print_info "  • Configure Netmaker networks and nodes via API"