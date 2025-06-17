#!/bin/bash

# Install SystemD Services Script
# Creates and installs proper systemd service files for EMQX and Netmaker in the container

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

# Find container
CONTAINER_ID=""
if [[ $# -eq 1 ]]; then
    CONTAINER_ID="$1"
else
    # Auto-detect latest container
    CONTAINER_ID=$(pct list | tail -n +2 | sort -k1 -n | tail -1 | awk '{print $1}' || echo "")
    if [[ -z "$CONTAINER_ID" ]]; then
        print_error "No container found. Please specify container ID as argument."
        exit 1
    fi
fi

print_info "Installing systemd services in container ID: $CONTAINER_ID"

# 1. Create EMQX systemd service file
print_info "Creating EMQX systemd service..."
pct exec "$CONTAINER_ID" -- bash -c 'cat > /etc/systemd/system/emqx.service << "EOF"
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
EOF'

# 2. Create Netmaker systemd service file  
print_info "Creating Netmaker systemd service..."
pct exec "$CONTAINER_ID" -- bash -c 'cat > /etc/systemd/system/netmaker.service << "EOF"
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
EOF'

# 3. Create necessary directories and set permissions
print_info "Creating directories and setting permissions..."
pct exec "$CONTAINER_ID" -- mkdir -p /var/lib/emqx /var/log/emqx /etc/emqx
pct exec "$CONTAINER_ID" -- mkdir -p /etc/netmaker /var/log/netmaker

# Ensure emqx user exists
if ! pct exec "$CONTAINER_ID" -- id emqx >/dev/null 2>&1; then
    print_info "Creating emqx user..."
    pct exec "$CONTAINER_ID" -- useradd -r -s /bin/false -d /var/lib/emqx emqx
fi

# Set proper ownership
pct exec "$CONTAINER_ID" -- chown -R emqx:emqx /var/lib/emqx /var/log/emqx /etc/emqx
pct exec "$CONTAINER_ID" -- chown -R root:root /etc/netmaker /var/log/netmaker

# 4. Reload systemd and enable services
print_info "Reloading systemd daemon..."
pct exec "$CONTAINER_ID" -- systemctl daemon-reload

print_info "Enabling services..."
pct exec "$CONTAINER_ID" -- systemctl enable emqx.service
pct exec "$CONTAINER_ID" -- systemctl enable netmaker.service

# 5. Stop any existing broken services
print_info "Stopping any existing broken services..."
pct exec "$CONTAINER_ID" -- systemctl stop emqx.service || true
pct exec "$CONTAINER_ID" -- systemctl stop netmaker.service || true

# Reset failed state
pct exec "$CONTAINER_ID" -- systemctl reset-failed emqx.service || true
pct exec "$CONTAINER_ID" -- systemctl reset-failed netmaker.service || true

print_status "✅ SystemD services installed successfully!"
print_info "Services created:"
print_info "  • /etc/systemd/system/emqx.service"
print_info "  • /etc/systemd/system/netmaker.service"
print_info ""
print_info "Next steps:"
print_info "  1. Run ./configure-emqx.sh to create EMQX config"
print_info "  2. Create Netmaker config file"
print_info "  3. Run ./start-services.sh to start services"
print_info ""
print_info "Service status:"
pct exec "$CONTAINER_ID" -- systemctl is-enabled emqx.service || true
pct exec "$CONTAINER_ID" -- systemctl is-enabled netmaker.service || true