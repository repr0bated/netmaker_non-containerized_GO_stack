#!/bin/bash

# Fix Services Inside Container Script
# Run this script INSIDE the LXC container to fix EMQX and Netmaker services

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

echo "=== GhostBridge Service Fix (Inside Container) ==="
echo

# Check if running inside container
if [[ ! -f /.dockerenv ]] && [[ ! -f /run/.containerenv ]] && [[ ! -d /proc/vz ]] && [[ "$(systemd-detect-virt)" != "lxc" ]]; then
    print_warning "This script should be run inside the LXC container"
    print_info "Copy this script to the container and run it there"
    exit 1
fi

print_status "Running inside container, proceeding..."

# 1. Stop broken services
print_info "Stopping broken services..."
systemctl stop emqx.service || true
systemctl stop netmaker.service || true
systemctl reset-failed emqx.service || true
systemctl reset-failed netmaker.service || true

# 2. Create proper EMQX configuration
print_info "Creating EMQX configuration..."
mkdir -p /etc/emqx /var/lib/emqx /var/log/emqx

cat > /etc/emqx/emqx.conf << 'EOF'
### EMQX Configuration for GhostBridge

## Node settings
node.name = "emqx@127.0.0.1"
node.cookie = "secret-cookie" 
node.data_dir = "/var/lib/emqx"

## Dashboard settings
listener.dashboard = 18083
listener.dashboard_external = 8081

## MQTT listeners  
listener.tcp = 1883
listener.ssl = 8883

## Allow anonymous clients
allow_anonymous = true

## Access control
acl_nomatch = allow
acl_file = "etc/acl.conf"

## Logging
log.file = emqx.log
log.console = console

## Broker sys topics
broker.sys_interval = 1m
EOF

print_status "EMQX config created at /etc/emqx/emqx.conf"

# 3. Create proper Netmaker systemd service
print_info "Fixing Netmaker systemd service..."
cat > /etc/systemd/system/netmaker.service << 'EOF'
[Unit]
Description=Netmaker Server
Documentation=https://docs.netmaker.org/
After=network.target

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/etc/netmaker
ExecStart=/usr/local/bin/netmaker -c /etc/netmaker/config.yaml
Restart=on-failure
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3
Environment=NETMAKER_CONFIG_PATH=/etc/netmaker/config.yaml
Environment=NETMAKER_LOG_LEVEL=info

[Install]
WantedBy=multi-user.target
EOF

print_status "Netmaker service fixed with correct -c flag"

# 4. Create proper EMQX systemd service
print_info "Creating EMQX systemd service..."
cat > /etc/systemd/system/emqx.service << 'EOF'
[Unit]
Description=EMQX MQTT Broker
Documentation=https://www.emqx.io/
After=network.target

[Service]
Type=forking
User=emqx
Group=emqx
Environment=HOME=/var/lib/emqx
WorkingDirectory=/var/lib/emqx
ExecStart=/usr/bin/emqx start
ExecStop=/usr/bin/emqx stop
ExecReload=/usr/bin/emqx restart
Restart=on-failure
RestartSec=5
StartLimitInterval=60
StartLimitBurst=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

print_status "EMQX service created"

# 5. Create Netmaker config directory and basic config
print_info "Creating Netmaker configuration..."
mkdir -p /etc/netmaker /var/log/netmaker

if [[ ! -f /etc/netmaker/config.yaml ]]; then
    cat > /etc/netmaker/config.yaml << 'EOF'
# Netmaker Configuration
server:
  host: "127.0.0.1"
  apiport: 8081
  grpcport: 50051

database:
  type: "sqlite"
  path: "/var/lib/netmaker/netmaker.db"

mqtt:
  host: "127.0.0.1"
  port: 1883
  username: "netmaker"
  password: ""

logging:
  level: "info"
  file: "/var/log/netmaker/netmaker.log"
EOF
    print_status "Basic Netmaker config created"
else
    print_info "Netmaker config already exists"
fi

# 6. Set proper permissions
print_info "Setting permissions..."
# Ensure emqx user exists
if ! id emqx >/dev/null 2>&1; then
    useradd -r -s /bin/false -d /var/lib/emqx emqx
    print_status "Created emqx user"
fi

chown -R emqx:emqx /var/lib/emqx /var/log/emqx /etc/emqx
chown -R root:root /etc/netmaker /var/log/netmaker
chmod 755 /etc/emqx /var/lib/emqx
chmod 644 /etc/emqx/emqx.conf

# 7. Reload systemd and enable services
print_info "Reloading systemd..."
systemctl daemon-reload
systemctl enable emqx.service
systemctl enable netmaker.service

print_status "Services enabled"

# 8. Test EMQX configuration
print_info "Testing EMQX configuration..."
if emqx chkconfig >/dev/null 2>&1; then
    print_status "✅ EMQX config validation passed"
else
    print_warning "⚠ EMQX config validation failed but proceeding anyway"
fi

# 9. Start services
print_info "Starting EMQX..."
if systemctl start emqx.service; then
    sleep 3
    if systemctl is-active --quiet emqx.service; then
        print_status "✅ EMQX started successfully"
    else
        print_error "❌ EMQX failed to start"
        systemctl status emqx.service --no-pager -l
    fi
else
    print_error "❌ Failed to start EMQX service"
fi

print_info "Starting Netmaker..."
if systemctl start netmaker.service; then
    sleep 3
    if systemctl is-active --quiet netmaker.service; then
        print_status "✅ Netmaker started successfully"
    else
        print_error "❌ Netmaker failed to start"
        systemctl status netmaker.service --no-pager -l
    fi
else
    print_error "❌ Failed to start Netmaker service"
fi

# 10. Final status check
echo
print_info "=== Final Service Status ==="
systemctl status emqx.service --no-pager -l || true
echo
systemctl status netmaker.service --no-pager -l || true
echo

print_info "=== Port Check ==="
ss -tlnp | grep -E ":(1883|8081|18083)" || print_warning "No expected ports listening yet"

echo
print_status "🎉 Service fix completed!"
print_info "Next steps:"
print_info "  • Check service logs: journalctl -u emqx.service -f"
print_info "  • Check service logs: journalctl -u netmaker.service -f"
print_info "  • Test EMQX: curl http://127.0.0.1:18083"
print_info "  • Test Netmaker: curl http://127.0.0.1:8081/api/server/health"