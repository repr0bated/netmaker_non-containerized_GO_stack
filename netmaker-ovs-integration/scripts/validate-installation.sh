#!/bin/bash

# GhostBridge Netmaker Installation Validation Script
# Validates that installation was successful and all components are working

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Validation results
VALIDATION_PASSED=true
VALIDATION_LOG="/tmp/netmaker-validation-$(date +%Y%m%d-%H%M%S).log"

print_status() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "$VALIDATION_LOG"
}

print_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$VALIDATION_LOG"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "$VALIDATION_LOG"
    VALIDATION_PASSED=false
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1" | tee -a "$VALIDATION_LOG"
}

print_header() {
    echo -e "${CYAN}=== $1 ===${NC}" | tee -a "$VALIDATION_LOG"
}

show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║        GhostBridge Netmaker Installation Validator          ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
}

# Initialize validation log
{
    echo "GhostBridge Netmaker Installation Validation"
    echo "Generated: $(date)"
    echo "Host: $(hostname)"
    echo ""
} > "$VALIDATION_LOG"

show_banner

print_header "SERVICE STATUS VALIDATION"

# Check critical services
services=("netmaker" "mosquitto" "nginx")

for service in "${services[@]}"; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
        print_status "$service service is running"
        
        # Additional service-specific checks
        case $service in
            "netmaker")
                if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                    print_status "$service is enabled (will start on boot)"
                else
                    print_warning "$service is not enabled for auto-start"
                fi
                ;;
            "mosquitto")
                if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                    print_status "$service is enabled (will start on boot)"
                else
                    print_warning "$service is not enabled for auto-start"
                fi
                ;;
            "nginx")
                if systemctl is-enabled --quiet "$service" 2>/dev/null; then
                    print_status "$service is enabled (will start on boot)"
                else
                    print_warning "$service is not enabled for auto-start"
                fi
                ;;
        esac
    else
        print_error "$service service is not running"
    fi
done

echo

print_header "PORT BINDING VALIDATION"

# Check critical ports
critical_ports=(
    "80:HTTP"
    "443:HTTPS"
    "1883:MQTT_TCP"
    "8081:Netmaker_API"
    "9001:MQTT_WebSocket"
)

for port_info in "${critical_ports[@]}"; do
    port=$(echo "$port_info" | cut -d':' -f1)
    description=$(echo "$port_info" | cut -d':' -f2)
    
    if ss -tlnp | grep -q ":$port "; then
        service_info=$(ss -tlnp | grep ":$port " | head -1 | awk '{print $7}' | cut -d'"' -f2)
        print_status "Port $port ($description) is listening [$service_info]"
    else
        print_error "Port $port ($description) is not listening"
    fi
done

echo

print_header "CONFIGURATION FILE VALIDATION"

# Check Netmaker configuration
if [[ -f /etc/netmaker/config.yaml ]]; then
    print_status "Netmaker configuration file exists"
    
    # Validate YAML syntax
    if python3 -c "import yaml; yaml.safe_load(open('/etc/netmaker/config.yaml'))" 2>/dev/null; then
        print_status "Netmaker configuration has valid YAML syntax"
    else
        print_error "Netmaker configuration has invalid YAML syntax"
    fi
    
    # Check critical configuration values
    if grep -q "mqtt://.*:1883" /etc/netmaker/config.yaml; then
        print_status "MQTT endpoint uses correct protocol (mqtt://)"
    elif grep -q "http://.*:1883" /etc/netmaker/config.yaml; then
        print_error "MQTT endpoint uses incorrect protocol (http://) - should be mqtt://"
    else
        print_warning "Could not verify MQTT endpoint protocol"
    fi
    
    # Check if master key is set
    if grep -q "masterkey:.*[a-f0-9]\{32\}" /etc/netmaker/config.yaml; then
        print_status "Master key appears to be properly configured"
    else
        print_warning "Master key may not be properly configured"
    fi
else
    print_error "Netmaker configuration file not found at /etc/netmaker/config.yaml"
fi

# Check Mosquitto configuration
if [[ -f /etc/mosquitto/mosquitto.conf ]]; then
    print_status "Mosquitto configuration file exists"
    
    # Test configuration syntax
    if mosquitto -c /etc/mosquitto/mosquitto.conf -t 2>/dev/null; then
        print_status "Mosquitto configuration is syntactically valid"
    else
        print_error "Mosquitto configuration has syntax errors"
    fi
    
    # Check binding configuration
    if grep -q "bind_address 0.0.0.0" /etc/mosquitto/mosquitto.conf; then
        print_status "Mosquitto binds to all interfaces (0.0.0.0)"
    elif grep -q "bind_address 127.0.0.1" /etc/mosquitto/mosquitto.conf; then
        print_error "Mosquitto binds only to localhost (127.0.0.1) - should be 0.0.0.0"
    else
        print_warning "Could not determine Mosquitto bind address"
    fi
    
    # Check authentication
    if grep -q "allow_anonymous false" /etc/mosquitto/mosquitto.conf; then
        print_status "Anonymous access is disabled (secure)"
        
        # Check for password file
        if grep -q "password_file" /etc/mosquitto/mosquitto.conf; then
            password_file=$(grep "password_file" /etc/mosquitto/mosquitto.conf | awk '{print $2}')
            if [[ -f "$password_file" ]]; then
                print_status "MQTT password file exists: $password_file"
            else
                print_error "MQTT password file not found: $password_file"
            fi
        else
            print_warning "Password file not configured but anonymous access is disabled"
        fi
    elif grep -q "allow_anonymous true" /etc/mosquitto/mosquitto.conf; then
        print_warning "Anonymous access is enabled (security risk)"
    fi
else
    print_error "Mosquitto configuration file not found at /etc/mosquitto/mosquitto.conf"
fi

# Check Nginx configuration
if command -v nginx >/dev/null 2>&1; then
    if nginx -t 2>/dev/null; then
        print_status "Nginx configuration is syntactically valid"
    else
        print_error "Nginx configuration has syntax errors"
    fi
    
    # Check for stream module
    if nginx -V 2>&1 | grep -q 'stream'; then
        print_status "Nginx stream module is available"
    else
        print_error "Nginx stream module is missing (install nginx-full)"
    fi
    
    # Check for Netmaker site configuration
    if [[ -f /etc/nginx/sites-enabled/netmaker ]]; then
        print_status "Netmaker nginx site is enabled"
    elif [[ -f /etc/nginx/sites-available/netmaker ]]; then
        print_warning "Netmaker nginx site exists but is not enabled"
    else
        print_warning "Netmaker nginx site configuration not found"
    fi
else
    print_error "Nginx is not installed"
fi

echo

print_header "CONNECTIVITY VALIDATION"

# Test MQTT connectivity
if command -v mosquitto_pub >/dev/null 2>&1; then
    print_info "Testing MQTT broker connectivity..."
    
    # Test local connection
    if timeout 5 mosquitto_pub -h 127.0.0.1 -p 1883 -t test/validation -m "local_test" 2>/dev/null; then
        print_status "MQTT broker accepts local connections"
    else
        # Try with authentication if anonymous is disabled
        if [[ -f /etc/mosquitto/passwd ]]; then
            print_info "Testing MQTT with authentication (if configured)..."
            # This will fail without proper credentials, but that's expected
            print_warning "MQTT authentication required - manual testing needed"
        else
            print_error "MQTT broker local connection failed"
        fi
    fi
    
    # Test external connectivity (if not in container)
    if [[ ! -f /.dockerenv ]] && [[ ! -d /proc/vz ]]; then
        local_ip=$(ip route get 8.8.8.8 | grep -oP 'src \K[^ ]+')
        if timeout 5 mosquitto_pub -h "$local_ip" -p 1883 -t test/validation -m "external_test" 2>/dev/null; then
            print_status "MQTT broker accepts external connections"
        else
            print_warning "MQTT broker external connection failed (may require authentication)"
        fi
    fi
else
    print_warning "mosquitto_pub not available - cannot test MQTT connectivity"
fi

# Test Netmaker API
if command -v curl >/dev/null 2>&1; then
    print_info "Testing Netmaker API connectivity..."
    
    api_response=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8081/api/server/health 2>/dev/null || echo "000")
    
    case $api_response in
        "200")
            print_status "Netmaker API is responding (HTTP 200)"
            ;;
        "401")
            print_status "Netmaker API is responding (HTTP 401 - authentication required)"
            ;;
        "404")
            print_warning "Netmaker API endpoint not found (HTTP 404)"
            ;;
        "000")
            print_error "Netmaker API is not responding (connection failed)"
            ;;
        *)
            print_warning "Netmaker API responded with HTTP $api_response"
            ;;
    esac
else
    print_warning "curl not available - cannot test API connectivity"
fi

echo

print_header "NETWORK INTERFACE VALIDATION"

# Check for Netmaker interfaces
netmaker_interfaces=$(ip link show | grep -o 'nm-[^:@]*' 2>/dev/null || echo "")

if [[ -n "$netmaker_interfaces" ]]; then
    print_status "Netmaker network interfaces found:"
    for iface in $netmaker_interfaces; do
        ip_addr=$(ip addr show "$iface" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)
        if [[ -n "$ip_addr" ]]; then
            print_info "  • $iface: $ip_addr"
        else
            print_warning "  • $iface: no IP address assigned"
        fi
    done
else
    print_info "No Netmaker interfaces found yet (nm-*)"
    print_info "This is normal for a fresh installation - interfaces are created when networks are added"
fi

echo

print_header "SSL CERTIFICATE VALIDATION"

# Check SSL certificates
ssl_domains=()

# Try to detect configured domains from nginx config
if [[ -f /etc/nginx/sites-available/netmaker ]]; then
    ssl_domains+=($(grep "server_name" /etc/nginx/sites-available/netmaker | awk '{print $2}' | tr -d ';' | grep -v "localhost"))
fi

# Default domains if none found
if [[ ${#ssl_domains[@]} -eq 0 ]]; then
    ssl_domains=("netmaker.hobsonschoice.net" "broker.hobsonschoice.net" "dashboard.hobsonschoice.net")
fi

for domain in "${ssl_domains[@]}"; do
    cert_path="/etc/letsencrypt/live/$domain/fullchain.pem"
    if [[ -f "$cert_path" ]]; then
        print_status "SSL certificate exists for $domain"
        
        # Check expiry
        expiry_date=$(openssl x509 -enddate -noout -in "$cert_path" 2>/dev/null | cut -d= -f2)
        expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || echo "0")
        current_epoch=$(date +%s)
        days_until_expiry=$(( (expiry_epoch - current_epoch) / 86400 ))
        
        if [[ $days_until_expiry -gt 30 ]]; then
            print_status "  Certificate expires in $days_until_expiry days"
        elif [[ $days_until_expiry -gt 7 ]]; then
            print_warning "  Certificate expires in $days_until_expiry days (consider renewal soon)"
        else
            print_error "  Certificate expires in $days_until_expiry days (urgent renewal needed)"
        fi
    else
        print_warning "SSL certificate not found for $domain"
        print_info "  Run: certbot --nginx -d $domain"
    fi
done

echo

print_header "VALIDATION SUMMARY"

if [[ "$VALIDATION_PASSED" == "true" ]]; then
    print_status "✅ All critical validation checks passed!"
    echo
    print_info "Your Netmaker installation appears to be working correctly."
    print_info "You can now:"
    echo "  • Access the web interface (if configured)"
    echo "  • Create your first network"
    echo "  • Install netclient on devices"
    echo "  • Run OVS integration (if planned)"
else
    print_error "⚠️  Some validation checks failed"
    echo
    print_info "Please review the errors above and:"
    echo "  • Check service logs: journalctl -u netmaker -f"
    echo "  • Review configuration files"
    echo "  • Run diagnostics: ./scripts/netmaker-diagnostics.sh"
    echo "  • Consult TROUBLESHOOTING.md"
fi

echo
print_info "Validation report saved to: $VALIDATION_LOG"

# Exit with appropriate code
if [[ "$VALIDATION_PASSED" == "true" ]]; then
    exit 0
else
    exit 1
fi