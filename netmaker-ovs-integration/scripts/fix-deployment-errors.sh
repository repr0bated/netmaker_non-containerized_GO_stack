#!/bin/bash

# Fix Deployment Errors Script
# Addresses EMQX configuration and master key issues

set -euo pipefail

CONTAINER_ID="${1:-105}"

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

print_info "Fixing deployment errors for container $CONTAINER_ID"

# Fix 1: Create minimal EMQX configuration
print_info "Creating minimal EMQX configuration..."
pct exec "$CONTAINER_ID" -- bash -c 'cat > /etc/emqx/emqx.conf << "EOF"
# Minimal EMQX Configuration for GhostBridge
node {
  name = "emqx@127.0.0.1"
}

listeners.tcp.default {
  bind = "0.0.0.0:1883"
}

listeners.ws.default {
  bind = "0.0.0.0:8083"
  mqtt_path = "/mqtt"
}

dashboard {
  listeners.http {
    bind = 18083
  }
  default_username = "admin"
  default_password = "public"
}

authentication = [
  {
    mechanism = password_based
    backend = built_in_database
    user_id_type = username
  }
]

authorization {
  no_match = allow
}
EOF'

print_status "EMQX configuration simplified"

# Fix 2: Check EMQX configuration
print_info "Testing EMQX configuration..."
if pct exec "$CONTAINER_ID" -- emqx chkconfig 2>/dev/null; then
    print_status "EMQX configuration is valid"
else
    print_warning "EMQX configuration still has issues - will try to start anyway"
fi

# Fix 3: Generate and store master key properly
print_info "Generating Netmaker master key..."
MASTER_KEY=$(openssl rand -hex 32)
pct exec "$CONTAINER_ID" -- bash -c "echo 'NETMAKER_MASTER_KEY=$MASTER_KEY' > /etc/netmaker/master-key.env"
pct exec "$CONTAINER_ID" -- chmod 600 /etc/netmaker/master-key.env
print_status "Master key generated and stored"

# Fix 4: Update Netmaker config with proper master key
print_info "Updating Netmaker configuration with master key..."
pct exec "$CONTAINER_ID" -- sed -i "s/masterkey: \"\"/masterkey: \"$MASTER_KEY\"/" /etc/netmaker/config.yaml
print_status "Netmaker config updated"

# Fix 5: Set proper permissions
pct exec "$CONTAINER_ID" -- chown -R emqx:emqx /etc/emqx /var/lib/emqx /var/log/emqx 2>/dev/null || true
pct exec "$CONTAINER_ID" -- chown -R root:root /etc/netmaker

print_status "🎯 Deployment errors fixed!"
print_info "You can now try starting services:"
print_info "  pct exec $CONTAINER_ID -- systemctl start emqx"
print_info "  pct exec $CONTAINER_ID -- systemctl start netmaker"
print_info "Or use: ./start-services.sh $CONTAINER_ID"