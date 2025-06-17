#!/bin/bash

# Localhost Setup Script (Inside Container)
# Sets up EMQX and Netmaker with localhost-only configs to break circular dependency

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

echo "=== GhostBridge Localhost Setup (Inside Container) ==="
echo

# Check if running inside container
if [[ "$(systemd-detect-virt)" != "lxc" ]] && [[ ! -d /proc/vz ]]; then
    print_warning "This script should be run inside the LXC container"
    print_info "Copy this script to the container and run it there"
fi

print_status "Setting up localhost-only services..."

# 1. Stop any existing services
print_info "Stopping existing services..."
systemctl stop emqx.service || true
systemctl stop netmaker.service || true
systemctl reset-failed emqx.service || true
systemctl reset-failed netmaker.service || true

# Kill any stuck processes
pkill -f emqx || true
pkill -f netmaker || true

# 2. Create minimal localhost EMQX config
print_info "Creating minimal EMQX config (localhost only)..."
mkdir -p /etc/emqx /var/lib/emqx /var/log/emqx

cat > /etc/emqx/emqx.conf << 'EOF'
## Minimal localhost EMQX config for GhostBridge
node.name = "emqx@127.0.0.1"
node.cookie = "secret-cookie"
node.data_dir = "/var/lib/emqx"

## Localhost-only listeners
listener.tcp = 1883
listener.dashboard = 18083

## Allow everything for initial setup
allow_anonymous = true
acl_nomatch = allow

## Simple logging
log.console = console
log.file = emqx.log
EOF

print_status "EMQX localhost config created"

# 3. Create minimal localhost Netmaker config
print_info "Creating minimal Netmaker config (localhost only)..."
mkdir -p /etc/netmaker /var/lib/netmaker /var/log/netmaker

cat > /etc/netmaker/config.yaml << 'EOF'
server:
  host: "127.0.0.1"
  apiport: 8081
  grpcport: 50051
  masterkey: ""

database:
  type: "sqlite"
  path: "/var/lib/netmaker/netmaker.db"

mqtt:
  host: "127.0.0.1"
  port: 1883
  username: ""
  password: ""

logging:
  level: "info"

verbosity: 1
platform: "linux"
EOF

print_status "Netmaker localhost config created"

# 4. Ensure users and permissions
print_info "Setting up users and permissions..."
if ! id emqx >/dev/null 2>&1; then
    useradd -r -s /bin/false -d /var/lib/emqx emqx
    print_status "Created emqx user"
fi

chown -R emqx:emqx /var/lib/emqx /var/log/emqx /etc/emqx
chown -R root:root /etc/netmaker /var/lib/netmaker /var/log/netmaker
chmod 755 /var/lib/emqx /var/lib/netmaker
chmod 644 /etc/emqx/emqx.conf /etc/netmaker/config.yaml

# 5. Create simple systemd services
print_info "Creating simple systemd services..."

# Simple EMQX service
cat > /etc/systemd/system/emqx.service << 'EOF'
[Unit]
Description=EMQX MQTT Broker (Localhost)
After=network.target

[Service]
Type=simple
User=emqx
Group=emqx
WorkingDirectory=/var/lib/emqx
ExecStart=/usr/bin/emqx foreground
Restart=on-failure
RestartSec=5
Environment=EMQX_NODE__DATA_DIR=/var/lib/emqx

[Install]
WantedBy=multi-user.target
EOF

# Simple Netmaker service
cat > /etc/systemd/system/netmaker.service << 'EOF'
[Unit]
Description=Netmaker Server (Localhost)
After=network.target emqx.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/etc/netmaker
ExecStart=/usr/local/bin/netmaker -c /etc/netmaker/config.yaml
Restart=on-failure
RestartSec=5
Environment=NETMAKER_CONFIG_PATH=/etc/netmaker/config.yaml

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
print_status "Simple systemd services created"

# 6. Test EMQX config
print_info "Testing EMQX configuration..."
if /usr/bin/emqx chkconfig >/dev/null 2>&1; then
    print_status "✅ EMQX config validation passed"
else
    print_warning "⚠ EMQX config validation failed but proceeding"
fi

# 7. Start EMQX first
print_info "Starting EMQX (localhost only)..."
systemctl enable emqx.service
if systemctl start emqx.service; then
    sleep 5
    if systemctl is-active --quiet emqx.service; then
        print_status "✅ EMQX started successfully on localhost"
        
        # Check if EMQX is listening
        if ss -tlnp | grep -q ":1883 "; then
            print_status "✅ EMQX listening on port 1883"
        else
            print_warning "⚠ EMQX not listening on port 1883 yet"
        fi
        
        if ss -tlnp | grep -q ":18083 "; then
            print_status "✅ EMQX dashboard listening on port 18083"
        else
            print_warning "⚠ EMQX dashboard not listening on port 18083 yet"
        fi
    else
        print_error "❌ EMQX failed to start"
        systemctl status emqx.service --no-pager -l
        exit 1
    fi
else
    print_error "❌ Failed to start EMQX service"
    systemctl status emqx.service --no-pager -l
    exit 1
fi

# 8. Start Netmaker
print_info "Starting Netmaker (localhost only)..."
systemctl enable netmaker.service
if systemctl start netmaker.service; then
    sleep 5
    if systemctl is-active --quiet netmaker.service; then
        print_status "✅ Netmaker started successfully on localhost"
        
        # Check if Netmaker is listening
        if ss -tlnp | grep -q ":8081 "; then
            print_status "✅ Netmaker API listening on port 8081"
        else
            print_warning "⚠ Netmaker API not listening on port 8081 yet"
        fi
    else
        print_error "❌ Netmaker failed to start"
        systemctl status netmaker.service --no-pager -l
        print_info "Checking Netmaker logs..."
        journalctl -u netmaker.service --no-pager -n 20
    fi
else
    print_error "❌ Failed to start Netmaker service"
    systemctl status netmaker.service --no-pager -l
fi

# 9. Final status
echo
print_info "=== Final Localhost Status ==="
print_info "Services:"
systemctl is-active emqx.service && print_status "  ✅ EMQX: Active" || print_error "  ❌ EMQX: Failed"
systemctl is-active netmaker.service && print_status "  ✅ Netmaker: Active" || print_error "  ❌ Netmaker: Failed"

print_info "Listening ports:"
ss -tlnp | grep -E ":(1883|8081|18083)" || print_warning "No expected ports listening"

echo
print_info "=== Testing Connectivity ==="
print_info "Testing EMQX dashboard..."
if curl -s http://127.0.0.1:18083 >/dev/null 2>&1; then
    print_status "✅ EMQX dashboard responding"
else
    print_warning "⚠ EMQX dashboard not responding"
fi

print_info "Testing Netmaker API..."
if curl -s http://127.0.0.1:8081/api/server/health >/dev/null 2>&1; then
    print_status "✅ Netmaker API responding"
else
    print_warning "⚠ Netmaker API not responding yet"
fi

echo
print_status "🎉 Localhost setup completed!"
print_info "Next steps:"
print_info "  • Test EMQX: curl http://127.0.0.1:18083"
print_info "  • Test Netmaker: curl http://127.0.0.1:8081/api/server/health"
print_info "  • Check logs: journalctl -u emqx.service -f"
print_info "  • Check logs: journalctl -u netmaker.service -f"
print_info "  • Once working, run network setup script on Proxmox host"