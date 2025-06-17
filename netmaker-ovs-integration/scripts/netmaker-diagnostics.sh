#!/bin/bash

# GhostBridge Netmaker Comprehensive Diagnostic Script
# Based on real-world troubleshooting experience

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Report file
REPORT_FILE="/tmp/netmaker-diagnostic-$(date +%Y%m%d-%H%M%S).txt"

print_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
    echo "=== $1 ===" >> "$REPORT_FILE"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
    echo "[✓] $1" >> "$REPORT_FILE"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    echo "[⚠] $1" >> "$REPORT_FILE"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    echo "[✗] $1" >> "$REPORT_FILE"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
    echo "[i] $1" >> "$REPORT_FILE"
}

# Initialize report
{
    echo "GhostBridge Netmaker Diagnostic Report"
    echo "Generated: $(date)"
    echo "Host: $(hostname)"
    echo "User: $(whoami)"
    echo ""
} > "$REPORT_FILE"

print_header "SYSTEM INFORMATION"
{
    echo "Kernel: $(uname -a)"
    echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"')"
    echo "Architecture: $(dpkg --print-architecture 2>/dev/null || uname -m)"
    echo "Uptime: $(uptime)"
    echo ""
} | tee -a "$REPORT_FILE"

print_header "RESOURCE USAGE"
{
    echo "Memory Usage:"
    free -h
    echo ""
    echo "Disk Usage:"
    df -h /
    echo ""
    echo "CPU Information:"
    cat /proc/cpuinfo | grep -E "model name|processor" | head -2
    echo ""
    echo "Load Average:"
    uptime | awk -F'load average:' '{print $2}'
    echo ""
} | tee -a "$REPORT_FILE"

print_header "VIRTUALIZATION DETECTION"
{
    # Detect virtualization environment
    if [[ -f /.dockerenv ]]; then
        print_warning "Running in Docker container"
    elif [[ -d /proc/vz ]]; then
        print_warning "Running in OpenVZ container"
    elif grep -q "QEMU\|VMware\|VirtualBox" /proc/cpuinfo 2>/dev/null; then
        print_info "Running in virtual machine"
    elif [[ -f /proc/xen/version ]] 2>/dev/null; then
        print_warning "Running in Xen VM"
    elif [[ -f /proc/self/cgroup ]] && grep -q lxc /proc/self/cgroup; then
        print_info "Running in LXC container"
    else
        print_status "Running on bare metal"
    fi
    
    # Check for Proxmox
    if [[ -f /etc/pve/local/pve-ssl.pem ]]; then
        print_info "Proxmox host detected"
        pveversion 2>/dev/null || echo "Could not get Proxmox version"
    fi
    echo ""
} | tee -a "$REPORT_FILE"

print_header "SERVICE STATUS"
{
    # Check critical services
    services=("netmaker" "mosquitto" "nginx")
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            print_status "$service is running"
            systemctl status "$service" --no-pager -l | head -5
        elif systemctl list-unit-files | grep -q "$service"; then
            print_error "$service is installed but not running"
            systemctl status "$service" --no-pager -l | head -5
        else
            print_warning "$service is not installed"
        fi
        echo ""
    done
} | tee -a "$REPORT_FILE"

print_header "NETWORK CONFIGURATION"
{
    echo "Network Interfaces:"
    ip addr show | grep -E "^[0-9]+:|inet " 
    echo ""
    
    echo "Routing Table:"
    ip route show
    echo ""
    
    echo "DNS Configuration:"
    cat /etc/resolv.conf
    echo ""
} | tee -a "$REPORT_FILE"

print_header "PORT ANALYSIS"
{
    echo "Listening Ports (Critical for Netmaker):"
    critical_ports=("80" "443" "1883" "8081" "9001")
    
    for port in "${critical_ports[@]}"; do
        if ss -tlnp | grep -q ":$port "; then
            service_info=$(ss -tlnp | grep ":$port " | head -1)
            print_status "Port $port is listening: $service_info"
        else
            print_error "Port $port is not listening"
        fi
    done
    echo ""
    
    echo "All Listening Ports:"
    ss -tlnp | grep LISTEN
    echo ""
} | tee -a "$REPORT_FILE"

print_header "NETMAKER SPECIFIC CHECKS"
{
    # Check Netmaker binary
    if command -v netmaker >/dev/null 2>&1; then
        print_status "Netmaker binary found: $(which netmaker)"
        netmaker_version=$(netmaker --version 2>/dev/null | head -1 || echo "Could not get version")
        echo "Version: $netmaker_version"
    else
        print_error "Netmaker binary not found"
    fi
    echo ""
    
    # Check Netmaker configuration
    if [[ -f /etc/netmaker/config.yaml ]]; then
        print_status "Netmaker configuration found"
        echo "Configuration preview:"
        head -10 /etc/netmaker/config.yaml | sed 's/^/    /'
        
        # Check for common configuration issues
        if grep -q "http://.*:1883" /etc/netmaker/config.yaml; then
            print_error "CRITICAL: MQTT endpoint uses http:// instead of mqtt://"
        elif grep -q "mqtt://.*:1883" /etc/netmaker/config.yaml; then
            print_status "MQTT endpoint uses correct mqtt:// protocol"
        fi
    else
        print_error "Netmaker configuration not found at /etc/netmaker/config.yaml"
    fi
    echo ""
    
    # Check for Netmaker interfaces
    netmaker_interfaces=$(ip link show | grep -o 'nm-[^:@]*' 2>/dev/null || echo "")
    if [[ -n "$netmaker_interfaces" ]]; then
        print_status "Netmaker interfaces found:"
        for iface in $netmaker_interfaces; do
            echo "    - $iface: $(ip addr show "$iface" | grep inet | awk '{print $2}' | head -1)"
        done
    else
        print_warning "No Netmaker interfaces found (nm-*)"
    fi
    echo ""
} | tee -a "$REPORT_FILE"

print_header "MQTT BROKER ANALYSIS"
{
    # Check Mosquitto installation
    if command -v mosquitto >/dev/null 2>&1; then
        print_status "Mosquitto found: $(which mosquitto)"
        mosquitto_version=$(mosquitto -h 2>&1 | head -1 || echo "Could not get version")
        echo "Version: $mosquitto_version"
    else
        print_error "Mosquitto not found"
    fi
    echo ""
    
    # Check Mosquitto configuration
    if [[ -f /etc/mosquitto/mosquitto.conf ]]; then
        print_status "Mosquitto configuration found"
        
        # Test configuration
        if mosquitto -c /etc/mosquitto/mosquitto.conf -t 2>/dev/null; then
            print_status "Mosquitto configuration is valid"
        else
            print_error "Mosquitto configuration has errors"
        fi
        
        # Check for critical configuration issues
        if grep -q "bind_address 127.0.0.1" /etc/mosquitto/mosquitto.conf; then
            print_error "CRITICAL: Mosquitto binds to 127.0.0.1 (should be 0.0.0.0)"
        elif grep -q "bind_address 0.0.0.0" /etc/mosquitto/mosquitto.conf; then
            print_status "Mosquitto binds to 0.0.0.0 (correct)"
        fi
        
        if grep -q "allow_anonymous true" /etc/mosquitto/mosquitto.conf; then
            print_warning "Mosquitto allows anonymous access (security risk)"
        elif grep -q "allow_anonymous false" /etc/mosquitto/mosquitto.conf; then
            print_status "Mosquitto requires authentication (secure)"
        fi
        
        echo "Configuration preview:"
        head -15 /etc/mosquitto/mosquitto.conf | sed 's/^/    /'
    else
        print_error "Mosquitto configuration not found"
    fi
    echo ""
} | tee -a "$REPORT_FILE"

print_header "NGINX CONFIGURATION ANALYSIS"
{
    # Check nginx installation
    if command -v nginx >/dev/null 2>&1; then
        print_status "Nginx found: $(which nginx)"
        nginx_version=$(nginx -v 2>&1 | cut -d' ' -f3)
        echo "Version: $nginx_version"
        
        # Check for stream module (critical)
        if nginx -V 2>&1 | grep -q 'stream'; then
            print_status "Nginx stream module is available"
        else
            print_error "CRITICAL: Nginx stream module is missing (install nginx-full)"
        fi
        
        # Test configuration
        if nginx -t 2>/dev/null; then
            print_status "Nginx configuration is valid"
        else
            print_error "Nginx configuration has errors:"
            nginx -t 2>&1 | head -5 | sed 's/^/    /'
        fi
    else
        print_error "Nginx not found"
    fi
    echo ""
    
    # Check for Netmaker site configuration
    if [[ -f /etc/nginx/sites-available/netmaker ]]; then
        print_status "Netmaker nginx site configuration found"
        if [[ -f /etc/nginx/sites-enabled/netmaker ]]; then
            print_status "Netmaker site is enabled"
        else
            print_warning "Netmaker site exists but is not enabled"
        fi
    else
        print_warning "Netmaker nginx site configuration not found"
    fi
    echo ""
} | tee -a "$REPORT_FILE"

print_header "CONNECTIVITY TESTS"
{
    # Test MQTT connectivity
    if command -v mosquitto_pub >/dev/null 2>&1; then
        print_info "Testing MQTT connectivity..."
        if timeout 5 mosquitto_pub -h 127.0.0.1 -p 1883 -t test/diagnostic -m "connectivity_test" 2>/dev/null; then
            print_status "MQTT broker accepts connections"
        else
            print_error "MQTT broker connection failed"
        fi
    else
        print_warning "mosquitto_pub not available for testing"
    fi
    echo ""
    
    # Test API connectivity
    if command -v curl >/dev/null 2>&1; then
        print_info "Testing Netmaker API connectivity..."
        api_response=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8081/api/server/health 2>/dev/null || echo "000")
        
        if [[ "$api_response" == "200" ]]; then
            print_status "Netmaker API is responding (HTTP 200)"
        elif [[ "$api_response" == "401" ]]; then
            print_status "Netmaker API is responding (HTTP 401 - authentication required)"
        elif [[ "$api_response" == "000" ]]; then
            print_error "Netmaker API is not responding (connection failed)"
        else
            print_warning "Netmaker API responded with HTTP $api_response"
        fi
    else
        print_warning "curl not available for API testing"
    fi
    echo ""
    
    # Test DNS resolution
    print_info "Testing DNS resolution..."
    test_domains=("netmaker.hobsonschoice.net" "broker.hobsonschoice.net" "dashboard.hobsonschoice.net")
    
    for domain in "${test_domains[@]}"; do
        if command -v dig >/dev/null 2>&1; then
            resolved_ip=$(dig +short "$domain" 2>/dev/null | tail -n1)
            if [[ -n "$resolved_ip" ]]; then
                print_status "$domain resolves to: $resolved_ip"
            else
                print_warning "$domain DNS resolution failed"
            fi
        else
            print_warning "dig not available for DNS testing"
            break
        fi
    done
    echo ""
} | tee -a "$REPORT_FILE"

print_header "LOG ANALYSIS"
{
    echo "Recent Netmaker Logs:"
    if systemctl is-active --quiet netmaker 2>/dev/null; then
        journalctl -u netmaker --no-pager -n 10 --since "1 hour ago" 2>/dev/null | sed 's/^/    /' || echo "    No recent logs available"
    else
        echo "    Netmaker service is not running"
    fi
    echo ""
    
    echo "Recent Mosquitto Logs:"
    if systemctl is-active --quiet mosquitto 2>/dev/null; then
        journalctl -u mosquitto --no-pager -n 10 --since "1 hour ago" 2>/dev/null | sed 's/^/    /' || echo "    No recent logs available"
    else
        echo "    Mosquitto service is not running"
    fi
    echo ""
    
    echo "Recent Nginx Logs:"
    if systemctl is-active --quiet nginx 2>/dev/null; then
        if [[ -f /var/log/nginx/error.log ]]; then
            echo "    Last 5 nginx errors:"
            tail -5 /var/log/nginx/error.log 2>/dev/null | sed 's/^/    /' || echo "    No error logs available"
        fi
    else
        echo "    Nginx service is not running"
    fi
    echo ""
} | tee -a "$REPORT_FILE"

print_header "SSL CERTIFICATE STATUS"
{
    # Check SSL certificates
    ssl_domains=("netmaker.hobsonschoice.net" "broker.hobsonschoice.net" "dashboard.hobsonschoice.net")
    
    for domain in "${ssl_domains[@]}"; do
        cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
        if [[ -f "$cert_path" ]]; then
            print_status "SSL certificate exists for $domain"
            expiry=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
            echo "    Expires: $expiry"
        else
            print_warning "SSL certificate not found for $domain"
        fi
    done
    echo ""
    
    # Check certbot
    if command -v certbot >/dev/null 2>&1; then
        print_status "Certbot is available"
        echo "Certbot certificates:"
        certbot certificates 2>/dev/null | grep -E "Certificate Name|Expiry Date" | sed 's/^/    /' || echo "    No certificates managed by certbot"
    else
        print_warning "Certbot not found"
    fi
    echo ""
} | tee -a "$REPORT_FILE"

print_header "RECOMMENDATIONS"
{
    echo "Based on the diagnostic results, here are the recommendations:"
    echo ""
    
    # Generate recommendations based on findings
    if ! systemctl is-active --quiet netmaker 2>/dev/null; then
        print_error "Start Netmaker service: systemctl start netmaker"
    fi
    
    if ! systemctl is-active --quiet mosquitto 2>/dev/null; then
        print_error "Start Mosquitto service: systemctl start mosquitto"
    fi
    
    if ! systemctl is-active --quiet nginx 2>/dev/null; then
        print_error "Start Nginx service: systemctl start nginx"
    fi
    
    if [[ -f /etc/mosquitto/mosquitto.conf ]] && grep -q "bind_address 127.0.0.1" /etc/mosquitto/mosquitto.conf; then
        print_error "Fix Mosquitto binding: Change bind_address to 0.0.0.0"
    fi
    
    if command -v nginx >/dev/null 2>&1 && ! nginx -V 2>&1 | grep -q 'stream'; then
        print_error "Install nginx-full: apt remove nginx-light && apt install nginx-full"
    fi
    
    if [[ -f /etc/netmaker/config.yaml ]] && grep -q "http://.*:1883" /etc/netmaker/config.yaml; then
        print_error "Fix MQTT endpoint: Change http:// to mqtt:// in Netmaker config"
    fi
    
    echo ""
} | tee -a "$REPORT_FILE"

print_header "DIAGNOSTIC COMPLETE"
{
    echo "Diagnostic report saved to: $REPORT_FILE"
    echo ""
    echo "To share this report for support:"
    echo "  cat $REPORT_FILE"
    echo ""
    echo "To run specific tests:"
    echo "  mosquitto_pub -h 127.0.0.1 -p 1883 -t test -m hello"
    echo "  curl http://127.0.0.1:8081/api/server/health"
    echo "  systemctl status netmaker mosquitto nginx"
    echo ""
} | tee -a "$REPORT_FILE"

echo "Report saved to: $REPORT_FILE"