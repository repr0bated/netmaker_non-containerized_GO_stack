#!/bin/bash

# Manual Service Startup Script
# Use this to start services one by one and troubleshoot issues

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

print_info "Using container ID: $CONTAINER_ID"

# Function to check service status
check_service() {
    local service="$1"
    if pct exec "$CONTAINER_ID" -- systemctl is-active --quiet "$service"; then
        print_status "$service is running"
        return 0
    else
        print_warning "$service is not running"
        return 1
    fi
}

# Function to show logs
show_logs() {
    local service="$1"
    print_info "Last 10 log entries for $service:"
    pct exec "$CONTAINER_ID" -- journalctl -u "$service" --no-pager -n 10 || true
    echo
}

# Function to test EMQX config
test_emqx_config() {
    print_info "Testing EMQX configuration..."
    if pct exec "$CONTAINER_ID" -- emqx chkconfig; then
        print_status "EMQX configuration is valid"
        return 0
    else
        print_error "EMQX configuration has errors"
        print_info "Configuration file contents:"
        pct exec "$CONTAINER_ID" -- cat /etc/emqx/emqx.conf | head -20
        return 1
    fi
}

# Function to check listening ports
check_ports() {
    print_info "Checking listening ports in container:"
    pct exec "$CONTAINER_ID" -- ss -tlnp | grep -E ":(1883|8081|9001)" || print_warning "No expected ports listening"
}

echo "=== GhostBridge Service Startup ==="
echo

# Check current status
print_info "Current service status:"
check_service emqx || true
check_service netmaker || true
echo

# Step 1: Test and start EMQX
print_info "=== Step 1: Starting EMQX ==="
test_emqx_config

if ! check_service emqx; then
    print_info "Starting EMQX..."
    if pct exec "$CONTAINER_ID" -- systemctl start emqx; then
        sleep 3
        if check_service emqx; then
            print_status "✅ EMQX started successfully"
        else
            print_error "❌ EMQX failed to start"
            show_logs emqx
            exit 1
        fi
    else
        print_error "❌ Failed to start EMQX"
        show_logs emqx
        exit 1
    fi
fi

# Step 2: Configure EMQX via API
print_info "=== Step 2: Configuring EMQX via API ==="

# Wait for EMQX API to be available
print_info "Waiting for EMQX API to be available..."
local timeout=30
local count=0
while [[ $count -lt $timeout ]]; do
    if pct exec "$CONTAINER_ID" -- curl -s http://127.0.0.1:18083/status >/dev/null 2>&1; then
        break
    fi
    sleep 2
    ((count+=2))
done

if [[ $count -ge $timeout ]]; then
    print_warning "EMQX API not responding - skipping API configuration"
else
    print_status "EMQX API is responding"
    
    # Generate MQTT credentials
    local mqtt_username="netmaker"
    local mqtt_password=$(pct exec "$CONTAINER_ID" -- openssl rand -base64 32 | tr -d "/+" | cut -c1-25)
    
    print_info "Creating EMQX user: $mqtt_username"
    
    # Create MQTT user via API
    local user_response=$(pct exec "$CONTAINER_ID" -- curl -s -X POST http://127.0.0.1:18083/api/v5/authentication/password_based:built_in_database/users \
        -H "Content-Type: application/json" \
        -u "admin:public" \
        -d "{
            \"user_id\": \"$mqtt_username\",
            \"password\": \"$mqtt_password\"
        }" 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$user_response" | grep -q "user_id\|already_exists"; then
        print_status "MQTT user created or already exists"
        
        # Store credentials for Netmaker
        pct exec "$CONTAINER_ID" -- mkdir -p /etc/netmaker
        pct exec "$CONTAINER_ID" -- bash -c "echo 'MQTT_USERNAME=$mqtt_username' > /etc/netmaker/mqtt-credentials.env"
        pct exec "$CONTAINER_ID" -- bash -c "echo 'MQTT_PASSWORD=$mqtt_password' >> /etc/netmaker/mqtt-credentials.env"
        pct exec "$CONTAINER_ID" -- chmod 600 /etc/netmaker/mqtt-credentials.env
        
        print_info "MQTT credentials: $mqtt_username / $mqtt_password"
        print_status "MQTT credentials saved to /etc/netmaker/mqtt-credentials.env"
    else
        print_warning "MQTT user creation failed, will use anonymous access"
    fi
    
    # Test EMQX connectivity
    if pct exec "$CONTAINER_ID" -- which emqx_ctl >/dev/null 2>&1; then
        print_info "Testing EMQX cluster status..."
        if pct exec "$CONTAINER_ID" -- emqx_ctl status; then
            print_status "EMQX cluster status OK"
        else
            print_warning "EMQX cluster status check failed"
        fi
    fi
fi

# Step 3: Start Netmaker
print_info "=== Step 3: Starting Netmaker ==="
if ! check_service netmaker; then
    print_info "Starting Netmaker..."
    if pct exec "$CONTAINER_ID" -- systemctl start netmaker; then
        print_info "Waiting for Netmaker to initialize..."
        sleep 5
        if check_service netmaker; then
            print_status "✅ Netmaker started successfully"
        else
            print_error "❌ Netmaker failed to start"
            show_logs netmaker
            print_info "Checking Netmaker configuration:"
            pct exec "$CONTAINER_ID" -- cat /etc/netmaker/config.yaml | head -20
            exit 1
        fi
    else
        print_error "❌ Failed to start Netmaker"
        show_logs netmaker
        exit 1
    fi
fi

# Step 4: Configure Netmaker via API
print_info "=== Step 4: Configuring Netmaker via API ==="

# Wait for Netmaker API to be available
print_info "Waiting for Netmaker API to be available..."
local timeout=60
local count=0
local container_ip=$(pct exec "$CONTAINER_ID" -- hostname -I | tr -d ' ')

while [[ $count -lt $timeout ]]; do
    if pct exec "$CONTAINER_ID" -- curl -s http://127.0.0.1:8081/api/server/health >/dev/null 2>&1; then
        break
    fi
    sleep 2
    ((count+=2))
done

if [[ $count -ge $timeout ]]; then
    print_warning "Netmaker API not responding - skipping API configuration"
else
    print_status "Netmaker API is responding"
    
    # Get master key if available
    local master_key=""
    if pct exec "$CONTAINER_ID" -- test -f /etc/netmaker/master-key.env; then
        master_key=$(pct exec "$CONTAINER_ID" -- grep "NETMAKER_MASTER_KEY" /etc/netmaker/master-key.env | cut -d'=' -f2)
        print_info "Found existing master key"
    else
        master_key=$(pct exec "$CONTAINER_ID" -- openssl rand -base64 32 | tr -d "/+" | cut -c1-25)
        pct exec "$CONTAINER_ID" -- bash -c "echo 'NETMAKER_MASTER_KEY=$master_key' > /etc/netmaker/master-key.env"
        print_info "Generated new master key"
    fi
    
    # Create super admin user
    print_info "Creating Netmaker admin user..."
    local admin_response=$(pct exec "$CONTAINER_ID" -- curl -s -X POST http://127.0.0.1:8081/api/users/adm/create \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $master_key" \
        -d '{
            "username": "admin",
            "password": "GhostBridge2024!",
            "isadmin": true
        }' 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$admin_response" | grep -q "admin\|already exists"; then
        print_status "Admin user created or already exists"
        print_info "Username: admin / Password: GhostBridge2024!"
    else
        print_warning "Admin user creation failed"
    fi
    
    # Create GhostBridge network
    print_info "Creating GhostBridge network..."
    local network_response=$(pct exec "$CONTAINER_ID" -- curl -s -X POST http://127.0.0.1:8081/api/networks \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $master_key" \
        -d '{
            "netid": "ghostbridge",
            "addressrange": "10.0.0.0/24",
            "displayname": "GhostBridge Network",
            "defaultpostup": "iptables -A FORWARD -i %i -j ACCEPT; iptables -A FORWARD -o %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE",
            "defaultpostdown": "iptables -D FORWARD -i %i -j ACCEPT; iptables -D FORWARD -o %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE",
            "defaultkeepalive": 20,
            "defaultport": 51821,
            "islocal": false,
            "isdualstack": false,
            "isipv4": true,
            "isipv6": false
        }' 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$network_response" | grep -q "ghostbridge\|already exists"; then
        print_status "GhostBridge network created or already exists"
    else
        print_warning "Network creation failed"
    fi
    
    # Create enrollment key
    print_info "Creating enrollment key..."
    local key_response=$(pct exec "$CONTAINER_ID" -- curl -s -X POST http://127.0.0.1:8081/api/networks/ghostbridge/keys \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $master_key" \
        -d '{
            "uses": 100,
            "expiration": 86400
        }' 2>/dev/null || echo '{"error":"failed"}')
    
    if echo "$key_response" | grep -q "token"; then
        local enrollment_key=$(echo "$key_response" | pct exec "$CONTAINER_ID" -- jq -r '.token' 2>/dev/null || echo "unknown")
        print_status "Enrollment key created: $enrollment_key"
        pct exec "$CONTAINER_ID" -- bash -c "echo 'NETMAKER_ENROLLMENT_KEY=$enrollment_key' >> /etc/netmaker/master-key.env"
    else
        print_warning "Enrollment key creation failed"
    fi
fi

# Step 5: Final validation
print_info "=== Step 5: Final Validation ==="
check_ports
echo

print_info "Service status summary:"
check_service emqx && print_status "✅ EMQX: Running"
check_service netmaker && print_status "✅ Netmaker: Running"

print_info "Configuration summary:"
print_info "  • EMQX Dashboard: http://$container_ip:18083 (admin/public)"
print_info "  • Netmaker API: http://$container_ip:8081/api/server/health"
print_info "  • Netmaker Admin: admin / GhostBridge2024!"
print_info "  • MQTT TCP: $container_ip:1883"
print_info "  • MQTT SSL: $container_ip:8883"

print_info "Next steps:"
print_info "  • Configure networking and nginx proxy on Proxmox host"
print_info "  • Set up SSL certificates and domain configuration"
print_info "  • Join clients using enrollment key"

print_status "🎉 Service startup and configuration completed!"