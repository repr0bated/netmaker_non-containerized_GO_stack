#!/bin/bash
# GhostBridge - Fix Mosquitto Configuration in LXC Container
# Run this script INSIDE the Netmaker LXC container (10.0.0.101)

set -e

echo "=== GhostBridge: Fixing Mosquitto Configuration in LXC ==="

# Check if we're running as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root inside the LXC container"
   exit 1
fi

# Backup existing mosquitto.conf
echo "Backing up existing mosquitto.conf..."
cp /etc/mosquitto/mosquitto.conf /etc/mosquitto/mosquitto.conf.backup.$(date +%s) 2>/dev/null || echo "No existing config to backup"

# Create correct mosquitto.conf
echo "Creating correct mosquitto.conf..."
cat > /etc/mosquitto/mosquitto.conf << 'EOF'
# GhostBridge Mosquitto Configuration for Netmaker
# This config ensures Mosquitto listens on all interfaces for both TCP and WebSocket connections

# Standard MQTT TCP listener on port 1883
listener 1883
bind_address 0.0.0.0
protocol mqtt
allow_anonymous true

# WebSocket listener on port 9001 for browser/UI connections
listener 9001
bind_address 0.0.0.0
protocol websockets
allow_anonymous true

# Persistence settings
persistence true
persistence_location /var/lib/mosquitto/

# Logging
log_dest stdout
log_type error
log_type warning
log_type notice
log_type information

# Connection settings
max_connections -1
max_keepalive 65535

# Retain settings (helps with Netmaker client reconnects)
retain_available true
max_queued_messages 1000
max_inflight_messages 20

# Security settings (disabled for initial setup)
#password_file /etc/mosquitto/passwd
#acl_file /etc/mosquitto/acl
EOF

# Ensure mosquitto data directory exists and has correct permissions
echo "Setting up mosquitto data directory..."
mkdir -p /var/lib/mosquitto/
chown mosquitto:mosquitto /var/lib/mosquitto/

# Stop mosquitto service if running
echo "Stopping mosquitto service..."
systemctl stop mosquitto 2>/dev/null || true

# Reload systemd and restart mosquitto
echo "Restarting mosquitto service..."
systemctl daemon-reload
systemctl enable mosquitto
systemctl start mosquitto

# Wait for service to start
sleep 3

# Verify mosquitto is running and listening on correct ports
echo "Verifying mosquitto service status..."
systemctl status mosquitto --no-pager -l || echo "Warning: mosquitto status check failed"

echo "Checking listening ports..."
ss -tlnp | grep -E '1883|9001' || echo "Warning: Expected ports not found"

# Test local connection
echo "Testing local MQTT connection..."
which mosquitto_pub >/dev/null 2>&1 && {
    echo "Testing MQTT publish..."
    mosquitto_pub -h 127.0.0.1 -p 1883 -t "test/ghostbridge" -m "mosquitto-fix-test" -q 0 -d 2>&1 || echo "MQTT test failed"
} || echo "mosquitto_pub not available for testing"

echo "=== Mosquitto Configuration Fix Complete ==="
echo "Mosquitto should now be listening on:"
echo "  - 0.0.0.0:1883 (MQTT TCP)"
echo "  - 0.0.0.0:9001 (MQTT WebSocket)"
echo ""
echo "Next: Run the Netmaker configuration fix script"