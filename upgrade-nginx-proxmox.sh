#!/bin/bash

# GhostBridge Nginx Upgrade Script for Proxmox Host
# Upgrades nginx to nginx-full package and configures stream module
# This script runs on the Proxmox host, not in the container

set -euo pipefail

SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/ghostbridge-nginx-upgrade.log"
BACKUP_DIR="/var/backups/nginx-ghostbridge"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default values from CLAUDE.md - Updated for OVS setup
DEFAULT_CONTAINER_IP="10.0.0.151"  # Updated for container DHCP range
DEFAULT_DOMAIN="hobsonschoice.net"
DEFAULT_PUBLIC_IP="80.209.240.244"  # Proxmox public IP
DEFAULT_MQTT_PORT="1883"
DEFAULT_MQTT_WS_PORT="9001"
DEFAULT_API_PORT="8081"

# Configuration storage
declare -A CONFIG

# Utility functions
print_status() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "${CYAN}[NGINX]${NC} $1" | tee -a "$LOG_FILE"
}

print_question() {
    echo -e "${PURPLE}[?]${NC} $1"
}

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔════════════════════════════════════════════════════════════════════════╗
║                                                                        ║
║          GhostBridge Nginx Upgrade Script for Proxmox Host            ║
║                                                                        ║
║     Upgrades to nginx-full and configures stream module for MQTT      ║
║                                                                        ║
╚════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
    print_info "Version: $SCRIPT_VERSION"
    print_info "Purpose: Upgrade nginx with stream module support"
    print_info "Log File: $LOG_FILE"
    echo
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root on the Proxmox host"
        exit 1
    fi
}

# Check if running on Proxmox host
check_proxmox() {
    if [[ ! -f /etc/pve/local/pve-ssl.pem ]]; then
        print_error "This script must be run on the Proxmox host, not in a container"
        exit 1
    fi
    
    local pve_version=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "unknown")
    print_status "Running on Proxmox VE: $pve_version"
}

# Analyze current nginx installation
analyze_nginx() {
    print_header "Analyzing Current Nginx Installation"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if nginx is installed
    if command -v nginx >/dev/null 2>&1; then
        local nginx_version=$(nginx -v 2>&1 | cut -d' ' -f3)
        print_info "Current nginx version: $nginx_version"
        
        # Check package type
        local nginx_package=""
        if dpkg -l | grep -q "nginx-full"; then
            nginx_package="nginx-full"
            print_status "nginx-full is already installed"
        elif dpkg -l | grep -q "nginx-light"; then
            nginx_package="nginx-light"
            print_warning "nginx-light is installed (lacks stream module)"
        elif dpkg -l | grep -q "nginx-core"; then
            nginx_package="nginx-core"
            print_warning "nginx-core is installed (lacks stream module)"
        elif dpkg -l | grep -q "nginx "; then
            nginx_package="nginx"
            print_info "Generic nginx package is installed"
        else
            nginx_package="unknown"
            print_warning "Cannot determine nginx package type"
        fi
        
        CONFIG[current_nginx_package]="$nginx_package"
        
        # Check stream module availability
        if nginx -V 2>&1 | grep -q 'stream'; then
            print_status "✓ Stream module is available"
            CONFIG[has_stream_module]="true"
        else
            print_error "✗ Stream module is NOT available"
            CONFIG[has_stream_module]="false"
        fi
        
        # Check if nginx is running
        if systemctl is-active --quiet nginx; then
            print_status "Nginx service is running"
            CONFIG[nginx_running]="true"
        else
            print_info "Nginx service is not running"
            CONFIG[nginx_running]="false"
        fi
        
        # List current sites
        if [[ -d /etc/nginx/sites-enabled ]]; then
            local enabled_sites=$(ls /etc/nginx/sites-enabled/ 2>/dev/null | wc -l)
            print_info "Current enabled sites: $enabled_sites"
            if [[ $enabled_sites -gt 0 ]]; then
                ls /etc/nginx/sites-enabled/ | sed 's/^/    /'
            fi
        fi
        
    else
        print_info "Nginx is not installed"
        CONFIG[current_nginx_package]="none"
        CONFIG[has_stream_module]="false"
        CONFIG[nginx_running]="false"
    fi
}

# Get configuration from user
get_configuration() {
    print_header "Nginx Configuration Setup"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_question "Enter LXC container IP address:"
    print_info "IP ranges: Services 1-50, Reserved 51-149, Containers 150-245"
    read -p "Container IP [$DEFAULT_CONTAINER_IP]: " container_ip
    CONFIG[container_ip]="${container_ip:-$DEFAULT_CONTAINER_IP}"
    
    print_question "Enter Proxmox public IP address:"
    read -p "Public IP [$DEFAULT_PUBLIC_IP]: " public_ip
    CONFIG[public_ip]="${public_ip:-$DEFAULT_PUBLIC_IP}"
    
    print_question "Enter domain name:"
    read -p "Domain [$DEFAULT_DOMAIN]: " domain
    CONFIG[domain]="${domain:-$DEFAULT_DOMAIN}"
    
    print_question "Enter MQTT TCP port:"
    read -p "MQTT Port [$DEFAULT_MQTT_PORT]: " mqtt_port
    CONFIG[mqtt_port]="${mqtt_port:-$DEFAULT_MQTT_PORT}"
    
    print_question "Enter MQTT WebSocket port:"
    read -p "MQTT WS Port [$DEFAULT_MQTT_WS_PORT]: " mqtt_ws_port
    CONFIG[mqtt_ws_port]="${mqtt_ws_port:-$DEFAULT_MQTT_WS_PORT}"
    
    print_question "Enter Netmaker API port:"
    read -p "API Port [$DEFAULT_API_PORT]: " api_port
    CONFIG[api_port]="${api_port:-$DEFAULT_API_PORT}"
    
    echo
    print_info "Configuration:"
    echo "  • Container IP: ${CONFIG[container_ip]}"
    echo "  • Public IP: ${CONFIG[public_ip]}"
    echo "  • Domain: ${CONFIG[domain]}"
    echo "  • MQTT TCP: ${CONFIG[mqtt_port]}"
    echo "  • MQTT WebSocket: ${CONFIG[mqtt_ws_port]}"
    echo "  • API Port: ${CONFIG[api_port]}"
    echo
}

# Create backup of current configuration
backup_nginx_config() {
    print_header "Creating Nginx Configuration Backup"
    echo "────────────────────────────────────────────────────────────────────────"
    
    mkdir -p "$BACKUP_DIR"
    
    # Files to backup
    local files_to_backup=(
        "/etc/nginx/nginx.conf"
        "/etc/nginx/sites-available"
        "/etc/nginx/sites-enabled"
        "/etc/nginx/conf.d"
    )
    
    for item in "${files_to_backup[@]}"; do
        if [[ -e "$item" ]]; then
            if [[ -d "$item" ]]; then
                cp -r "$item" "$BACKUP_DIR/$(basename "$item")-$TIMESTAMP/" 2>/dev/null || true
                print_status "Backed up directory: $item"
            else
                cp "$item" "$BACKUP_DIR/$(basename "$item")-$TIMESTAMP" 2>/dev/null || true
                print_status "Backed up file: $item"
            fi
        fi
    done
    
    print_status "Backup created in: $BACKUP_DIR"
}

# Upgrade nginx to nginx-full
upgrade_nginx() {
    print_header "Upgrading Nginx to nginx-full"
    echo "────────────────────────────────────────────────────────────────────────"
    
    if [[ "${CONFIG[current_nginx_package]}" == "nginx-full" ]] && [[ "${CONFIG[has_stream_module]}" == "true" ]]; then
        print_status "nginx-full with stream module is already installed"
        return 0
    fi
    
    # Stop nginx if running
    if [[ "${CONFIG[nginx_running]}" == "true" ]]; then
        print_info "Stopping nginx service..."
        systemctl stop nginx
    fi
    
    # Update package list
    print_info "Updating package lists..."
    apt update
    
    # Remove current nginx packages if they lack stream module
    if [[ "${CONFIG[current_nginx_package]}" == "nginx-light" ]] || [[ "${CONFIG[current_nginx_package]}" == "nginx-core" ]]; then
        print_info "Removing ${CONFIG[current_nginx_package]} (lacks stream module)..."
        apt remove -y "${CONFIG[current_nginx_package]}" || true
    fi
    
    # Install nginx-full
    print_info "Installing nginx-full with stream module support..."
    apt install -y nginx-full
    
    # Verify stream module is available
    if nginx -V 2>&1 | grep -q 'stream'; then
        print_status "✓ nginx-full installed with stream module support"
    else
        print_error "✗ Stream module still not available after upgrade"
        exit 1
    fi
    
    # Enable nginx service
    systemctl enable nginx
}

# Configure nginx with stream module
configure_nginx_stream() {
    print_header "Configuring Nginx with Stream Module"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Create main nginx.conf with stream module
    print_info "Creating nginx.conf with stream module..."
    
    cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
    multi_accept on;
    use epoll;
}

# HTTP Configuration
http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    server_tokens off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Logging
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log /var/log/nginx/access.log main;
    error_log /var/log/nginx/error.log;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript
               application/javascript application/xml+rss application/json;

    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}

# Stream Configuration (Critical for MQTT TCP proxy)
stream {
    log_format basic '$remote_addr [$time_local] '
                     '$protocol $status $bytes_sent $bytes_received '
                     '$session_time';

    access_log /var/log/nginx/stream.log basic;
    error_log /var/log/nginx/stream_error.log;

    include /etc/nginx/stream-conf.d/*.conf;
}
EOF

    # Create stream configuration directory
    mkdir -p /etc/nginx/stream-conf.d
    
    # Configure MQTT TCP stream proxy
    print_info "Creating MQTT stream proxy configuration..."
    cat > /etc/nginx/stream-conf.d/mqtt.conf << EOF
# MQTT TCP Stream Proxy for GhostBridge
# Proxies MQTT traffic to LXC container

upstream mqtt_backend {
    server ${CONFIG[container_ip]}:${CONFIG[mqtt_port]};
}

server {
    listen ${CONFIG[public_ip]}:${CONFIG[mqtt_port]};
    proxy_pass mqtt_backend;
    proxy_timeout 1s;
    proxy_responses 1;
    error_log /var/log/nginx/mqtt_stream.log;
}
EOF

    print_status "MQTT stream proxy configured"
}

# Configure HTTP sites for Netmaker
configure_nginx_sites() {
    print_header "Configuring Nginx HTTP Sites"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Create Netmaker site configuration
    cat > /etc/nginx/sites-available/ghostbridge << EOF
# GhostBridge Netmaker Nginx Configuration
# HTTP reverse proxy for Netmaker services in LXC container

# Netmaker API Server
server {
    listen ${CONFIG[public_ip]}:80;
    server_name netmaker.${CONFIG[domain]};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen ${CONFIG[public_ip]}:443 ssl http2;
    server_name netmaker.${CONFIG[domain]};
    
    # SSL configuration (will be populated by certbot)
    # ssl_certificate /etc/letsencrypt/live/netmaker.${CONFIG[domain]}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/netmaker.${CONFIG[domain]}/privkey.pem;
    
    location / {
        proxy_pass http://${CONFIG[container_ip]}:${CONFIG[api_port]};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# MQTT Broker WebSocket
server {
    listen ${CONFIG[public_ip]}:80;
    server_name broker.${CONFIG[domain]};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen ${CONFIG[public_ip]}:443 ssl http2;
    server_name broker.${CONFIG[domain]};
    
    # SSL configuration (will be populated by certbot)
    # ssl_certificate /etc/letsencrypt/live/broker.${CONFIG[domain]}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/broker.${CONFIG[domain]}/privkey.pem;
    
    location / {
        proxy_pass http://${CONFIG[container_ip]}:${CONFIG[mqtt_ws_port]};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support for MQTT
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Timeout settings
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}

# GhostBridge Control Panel (placeholder for future GUI/control panel)
server {
    listen ${CONFIG[public_ip]}:80;
    server_name ghostbridge.${CONFIG[domain]};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen ${CONFIG[public_ip]}:443 ssl http2;
    server_name ghostbridge.${CONFIG[domain]};
    
    # SSL configuration (will be populated by certbot)
    # ssl_certificate /etc/letsencrypt/live/ghostbridge.${CONFIG[domain]}/fullchain.pem;
    # ssl_certificate_key /etc/letsencrypt/live/ghostbridge.${CONFIG[domain]}/privkey.pem;
    
    # Placeholder for GhostBridge control panel
    location / {
        # Future: proxy_pass to GhostBridge control panel service
        # For now, return maintenance page or redirect to API docs
        return 503 "GhostBridge Control Panel - Coming Soon";
        add_header Content-Type text/plain;
    }
    
    # API proxy endpoint for control panel to access Netmaker
    location /api/netmaker/ {
        proxy_pass http://${CONFIG[container_ip]}:${CONFIG[api_port]}/api/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket support for real-time updates
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # CORS headers for frontend access
        add_header 'Access-Control-Allow-Origin' '*' always;
        add_header 'Access-Control-Allow-Methods' 'GET, POST, PUT, DELETE, OPTIONS' always;
        add_header 'Access-Control-Allow-Headers' 'DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization' always;
        
        if (\$request_method = 'OPTIONS') {
            add_header 'Access-Control-Max-Age' 1728000;
            add_header 'Content-Type' 'text/plain; charset=utf-8';
            add_header 'Content-Length' 0;
            return 204;
        }
    }
}

# Proxmox management interface (optional redirect)
server {
    listen ${CONFIG[public_ip]}:80;
    server_name proxmox.${CONFIG[domain]};
    return 301 https://\$server_name:8006/;
}
EOF

    # Enable the site
    ln -sf /etc/nginx/sites-available/ghostbridge /etc/nginx/sites-enabled/ghostbridge
    
    # Remove default site if it exists
    rm -f /etc/nginx/sites-enabled/default
    
    print_status "GhostBridge site configuration created and enabled"
}

# Test nginx configuration
test_nginx_config() {
    print_header "Testing Nginx Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Testing nginx configuration syntax..."
    if nginx -t; then
        print_status "✓ Nginx configuration syntax is valid"
    else
        print_error "✗ Nginx configuration syntax errors detected"
        print_error "Please check the configuration and run nginx -t manually"
        exit 1
    fi
}

# Start nginx service
start_nginx() {
    print_header "Starting Nginx Service"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Starting nginx service..."
    systemctl start nginx
    
    if systemctl is-active --quiet nginx; then
        print_status "✓ Nginx service is running"
    else
        print_error "✗ Nginx service failed to start"
        journalctl -u nginx --no-pager -n 10
        exit 1
    fi
    
    # Verify ports are listening
    print_info "Checking listening ports..."
    
    if ss -tlnp | grep -q ":80 "; then
        print_status "✓ HTTP port 80 is listening"
    else
        print_warning "⚠ HTTP port 80 is not listening"
    fi
    
    if ss -tlnp | grep -q ":443 "; then
        print_status "✓ HTTPS port 443 is listening"
    else
        print_info "HTTPS port 443 not listening (normal without SSL certificates)"
    fi
    
    if ss -tlnp | grep -q ":${CONFIG[mqtt_port]} "; then
        print_status "✓ MQTT stream port ${CONFIG[mqtt_port]} is listening"
    else
        print_error "✗ MQTT stream port ${CONFIG[mqtt_port]} is not listening"
    fi
}

# Install SSL certificate tools
install_ssl_tools() {
    print_header "Installing SSL Certificate Tools"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "Installing certbot..."
    apt install -y certbot python3-certbot-nginx
    
    print_status "SSL certificate tools installed"
    print_info "To obtain SSL certificates, run:"
    print_info "certbot --nginx -d netmaker.${CONFIG[domain]} -d broker.${CONFIG[domain]} -d dashboard.${CONFIG[domain]} -d ${CONFIG[domain]}"
}

# Validate the complete setup
validate_setup() {
    print_header "Validating Nginx Setup"
    echo "────────────────────────────────────────────────────────────────────────"
    
    local validation_passed=true
    
    # Check nginx status
    if systemctl is-active --quiet nginx; then
        print_status "✓ Nginx service is running"
    else
        print_error "✗ Nginx service is not running"
        validation_passed=false
    fi
    
    # Check stream module
    if nginx -V 2>&1 | grep -q 'stream'; then
        print_status "✓ Stream module is available"
    else
        print_error "✗ Stream module is not available"
        validation_passed=false
    fi
    
    # Check listening ports
    local expected_ports=("80" "443" "${CONFIG[mqtt_port]}")
    for port in "${expected_ports[@]}"; do
        if ss -tlnp | grep -q ":$port "; then
            print_status "✓ Port $port is listening"
        else
            if [[ "$port" == "443" ]]; then
                print_info "Port 443 not listening (SSL certificates needed)"
            else
                print_error "✗ Port $port is not listening"
                validation_passed=false
            fi
        fi
    done
    
    # Check configuration files
    if [[ -f /etc/nginx/sites-enabled/ghostbridge ]]; then
        print_status "✓ GhostBridge site is enabled"
    else
        print_error "✗ GhostBridge site is not enabled"
        validation_passed=false
    fi
    
    if [[ -f /etc/nginx/stream-conf.d/mqtt.conf ]]; then
        print_status "✓ MQTT stream configuration exists"
    else
        print_error "✗ MQTT stream configuration missing"
        validation_passed=false
    fi
    
    echo
    if [[ "$validation_passed" == "true" ]]; then
        print_status "✅ Nginx setup validation passed!"
    else
        print_warning "⚠️ Some validation checks failed"
    fi
}

# Display completion summary
show_completion() {
    print_header "Nginx Upgrade Complete!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    print_status "🎉 Nginx upgrade and configuration completed!"
    echo
    
    echo -e "${CYAN}📋 What was configured:${NC}"
    echo "  • Upgraded to nginx-full with stream module"
    echo "  • MQTT TCP stream proxy on port ${CONFIG[mqtt_port]}"
    echo "  • HTTP reverse proxy for Netmaker API"
    echo "  • WebSocket proxy for MQTT broker"
    echo "  • Site configurations for all subdomains"
    echo
    
    echo -e "${CYAN}🌐 Service Endpoints:${NC}"
    echo "  • Netmaker API: https://netmaker.${CONFIG[domain]}"
    echo "  • MQTT Broker: mqtt://broker.${CONFIG[domain]}:${CONFIG[mqtt_port]}"
    echo "  • MQTT WebSocket: wss://broker.${CONFIG[domain]}:${CONFIG[mqtt_ws_port]}"
    echo "  • Dashboard: https://dashboard.${CONFIG[domain]}"
    echo "  • Main domain: https://${CONFIG[domain]}"
    echo
    
    echo -e "${CYAN}🔧 Proxies to Container:${NC}"
    echo "  • Container IP: ${CONFIG[container_ip]}"
    echo "  • API Port: ${CONFIG[api_port]}"
    echo "  • MQTT TCP: ${CONFIG[mqtt_port]}"
    echo "  • MQTT WebSocket: ${CONFIG[mqtt_ws_port]}"
    echo
    
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo "  1. Ensure container services are running"
    echo "  2. Test MQTT connectivity: telnet ${CONFIG[container_ip]} ${CONFIG[mqtt_port]}"
    echo "  3. Test API connectivity: curl http://${CONFIG[container_ip]}:${CONFIG[api_port]}/api/server/health"
    echo "  4. Obtain SSL certificates:"
    echo "     certbot --nginx -d netmaker.${CONFIG[domain]} -d broker.${CONFIG[domain]} -d dashboard.${CONFIG[domain]} -d ${CONFIG[domain]}"
    echo "  5. Configure DNS records to point to this Proxmox host"
    echo
    
    echo -e "${CYAN}📁 Important Files:${NC}"
    echo "  • Main config: /etc/nginx/nginx.conf"
    echo "  • Site config: /etc/nginx/sites-available/ghostbridge"
    echo "  • Stream config: /etc/nginx/stream-conf.d/mqtt.conf"
    echo "  • Backup directory: $BACKUP_DIR"
    echo "  • Installation log: $LOG_FILE"
    echo
    
    echo -e "${CYAN}🔍 Troubleshooting:${NC}"
    echo "  • Test nginx config: nginx -t"
    echo "  • Check nginx status: systemctl status nginx"
    echo "  • View nginx logs: journalctl -u nginx -f"
    echo "  • Check listening ports: ss -tlnp | grep nginx"
    echo "  • Test MQTT stream: nc -v localhost ${CONFIG[mqtt_port]}"
    echo
    
    echo "════════════════════════════════════════════════════════════════════════"
}

# Main execution
main() {
    show_banner
    check_root
    check_proxmox
    analyze_nginx
    get_configuration
    
    print_header "Starting Nginx Upgrade Process"
    echo "════════════════════════════════════════════════════════════════════════"
    
    backup_nginx_config
    upgrade_nginx
    configure_nginx_stream
    configure_nginx_sites
    test_nginx_config
    start_nginx
    install_ssl_tools
    validate_setup
    show_completion
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Nginx upgrade completed successfully" >> "$LOG_FILE"
}

main "$@"