#!/bin/bash

# GhostBridge Master Deployment Script
# Orchestrates the complete GhostBridge deployment:
# 1. Creates LXC container on Proxmox host
# 2. Installs Netmaker and Mosquitto in container
# 3. Upgrades nginx on Proxmox host with stream module
# 4. Configures complete networking stack

set -euo pipefail

SCRIPT_VERSION="1.0.0"
LOG_FILE="/var/log/ghostbridge-deployment.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

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
    echo -e "${CYAN}[DEPLOY]${NC} $1" | tee -a "$LOG_FILE"
}

print_question() {
    echo -e "${PURPLE}[?]${NC} $1"
}

# Display banner
show_banner() {
    clear
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║              GhostBridge Master Deployment Script                        ║
║                                                                           ║
║    Complete Netmaker deployment with LXC container architecture          ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo
    print_info "Version: $SCRIPT_VERSION"
    print_info "Purpose: Complete GhostBridge deployment orchestration"
    print_info "Log File: $LOG_FILE"
    echo
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"
    echo "────────────────────────────────────────────────────────────────────────"
    
    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root on the Proxmox host"
        exit 1
    fi
    
    # Check if running on Proxmox host
    if [[ ! -f /etc/pve/local/pve-ssl.pem ]]; then
        print_error "This script must be run on the Proxmox host"
        exit 1
    fi
    
    local pve_version=$(pveversion 2>/dev/null | cut -d'/' -f2 || echo "unknown")
    print_status "Running on Proxmox VE: $pve_version"
    
    # Check if deployment scripts exist
    local required_scripts=(
        "create-lxc-container.sh"
        "upgrade-nginx-proxmox.sh"
        "install-container-services.sh"
    )
    
    for script in "${required_scripts[@]}"; do
        if [[ ! -f "$SCRIPT_DIR/$script" ]]; then
            print_error "Required script not found: $script"
            exit 1
        else
            print_status "Found script: $script"
        fi
    done
    
    # Check required commands
    local required_commands=("pct" "curl" "wget" "jq")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            print_status "Command available: $cmd"
        else
            print_error "Required command not found: $cmd"
            exit 1
        fi
    done
}

# Get deployment configuration
get_deployment_config() {
    print_header "Deployment Configuration"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_info "This script will deploy GhostBridge with the following architecture:"
    echo "  • LXC container for Netmaker and Mosquitto services"
    echo "  • Nginx with stream module on Proxmox host for reverse proxy"
    echo "  • Proper network configuration for container communication"
    echo
    
    print_question "Do you want to proceed with the deployment? [y/N]: "
    read -r proceed
    if [[ ! "$proceed" =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled by user"
        exit 0
    fi
    
    print_question "Use interactive configuration for each component? [Y/n]: "
    read -r interactive
    if [[ "$interactive" =~ ^[Nn]$ ]]; then
        CONFIG[interactive]="false"
        print_info "Using default configuration values"
    else
        CONFIG[interactive]="true"
        print_info "Will prompt for configuration in each step"
    fi
    
    echo
}

# Step 1: Create LXC Container
deploy_lxc_container() {
    print_header "Step 1: Creating LXC Container"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Running LXC container creation script..."
    
    local create_cmd="$SCRIPT_DIR/create-lxc-container.sh"
    
    if [[ "${CONFIG[interactive]}" == "false" ]]; then
        # Run with default values (you could add non-interactive flags here)
        print_info "Creating container with default configuration..."
    fi
    
    if bash "$create_cmd"; then
        print_status "✅ LXC container creation completed successfully"
        
        # Extract container ID (assuming default 100)
        CONFIG[container_id]="100"
        CONFIG[container_ip]="10.0.0.151"  # Updated for container DHCP range
        
        print_info "Container created with ID: ${CONFIG[container_id]}"
        print_info "Container IP: ${CONFIG[container_ip]}"
        
    else
        print_error "❌ LXC container creation failed"
        exit 1
    fi
    
    echo
}

# Step 2: Install services in container
deploy_container_services() {
    print_header "Step 2: Installing Services in Container"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Copying installation script to container..."
    
    # Copy the container installation script
    if pct push "${CONFIG[container_id]}" "$SCRIPT_DIR/install-container-services.sh" /root/install-container-services.sh; then
        print_status "Installation script copied to container"
    else
        print_error "Failed to copy installation script to container"
        exit 1
    fi
    
    # Make it executable
    pct exec "${CONFIG[container_id]}" -- chmod +x /root/install-container-services.sh
    
    print_info "Running container services installation..."
    
    # Set environment variables for non-interactive mode
    if [[ "${CONFIG[interactive]}" == "false" ]]; then
        pct exec "${CONFIG[container_id]}" -- bash -c "
            export GHOSTBRIDGE_DOMAIN=hobsonschoice.net
            /root/install-container-services.sh
        "
    else
        pct exec "${CONFIG[container_id]}" -- /root/install-container-services.sh
    fi
    
    if [[ $? -eq 0 ]]; then
        print_status "✅ Container services installation completed successfully"
    else
        print_error "❌ Container services installation failed"
        exit 1
    fi
    
    echo
}

# Step 3: Upgrade nginx on Proxmox host
deploy_nginx_upgrade() {
    print_header "Step 3: Upgrading Nginx on Proxmox Host"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Running nginx upgrade script..."
    
    local nginx_cmd="$SCRIPT_DIR/upgrade-nginx-proxmox.sh"
    
    if bash "$nginx_cmd"; then
        print_status "✅ Nginx upgrade completed successfully"
    else
        print_error "❌ Nginx upgrade failed"
        exit 1
    fi
    
    echo
}

# Step 4: Test connectivity between components
test_deployment() {
    print_header "Step 4: Testing Deployment"
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_info "Testing container connectivity..."
    
    # Test basic connectivity to container
    if ping -c 2 "${CONFIG[container_ip]}" >/dev/null 2>&1; then
        print_status "✓ Container is reachable from Proxmox host"
    else
        print_warning "⚠ Container ping test failed (may be normal)"
    fi
    
    # Test container services
    print_info "Testing container services..."
    
    # Test MQTT port
    if pct exec "${CONFIG[container_id]}" -- ss -tlnp | grep -q ":1883 "; then
        print_status "✓ MQTT TCP port 1883 is listening in container"
    else
        print_error "✗ MQTT TCP port not listening in container"
    fi
    
    # Test MQTT WebSocket port
    if pct exec "${CONFIG[container_id]}" -- ss -tlnp | grep -q ":9001 "; then
        print_status "✓ MQTT WebSocket port 9001 is listening in container"
    else
        print_error "✗ MQTT WebSocket port not listening in container"
    fi
    
    # Test Netmaker API port
    if pct exec "${CONFIG[container_id]}" -- ss -tlnp | grep -q ":8081 "; then
        print_status "✓ Netmaker API port 8081 is listening in container"
    else
        print_error "✗ Netmaker API port not listening in container"
    fi
    
    # Test Proxmox host nginx
    print_info "Testing Proxmox host nginx..."
    
    if systemctl is-active --quiet nginx; then
        print_status "✓ Nginx service is running on Proxmox host"
    else
        print_error "✗ Nginx service not running on Proxmox host"
    fi
    
    if ss -tlnp | grep -q ":80 "; then
        print_status "✓ HTTP port 80 is listening on Proxmox host"
    else
        print_error "✗ HTTP port 80 not listening on Proxmox host"
    fi
    
    if ss -tlnp | grep -q ":1883 "; then
        print_status "✓ MQTT stream port 1883 is listening on Proxmox host"
    else
        print_error "✗ MQTT stream port 1883 not listening on Proxmox host"
    fi
    
    # Test connectivity from host to container services
    print_info "Testing host-to-container connectivity..."
    
    if timeout 3 nc -z "${CONFIG[container_ip]}" 1883 2>/dev/null; then
        print_status "✓ Can connect to container MQTT from host"
    else
        print_warning "⚠ Cannot connect to container MQTT from host"
    fi
    
    if timeout 3 nc -z "${CONFIG[container_ip]}" 8081 2>/dev/null; then
        print_status "✓ Can connect to container API from host"
    else
        print_warning "⚠ Cannot connect to container API from host"
    fi
    
    echo
}

# Step 5: Display deployment summary
show_deployment_summary() {
    print_header "Deployment Complete!"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    print_status "🎉 GhostBridge deployment completed successfully!"
    echo
    
    echo -e "${CYAN}📊 Deployment Summary:${NC}"
    echo "  • Architecture: LXC Container + Proxmox Host"
    echo "  • Container ID: ${CONFIG[container_id]}"
    echo "  • Container IP: ${CONFIG[container_ip]}"
    echo "  • Host Services: Nginx with stream module"
    echo "  • Container Services: Netmaker + Mosquitto"
    echo
    
    echo -e "${CYAN}🌐 Service Endpoints:${NC}"
    echo "  • Netmaker API: https://netmaker.hobsonschoice.net"
    echo "  • MQTT Broker: mqtt://broker.hobsonschoice.net:1883"
    echo "  • MQTT WebSocket: wss://broker.hobsonschoice.net:9001"
    echo "  • GhostBridge Control Panel: https://ghostbridge.hobsonschoice.net"
    echo
    
    echo -e "${CYAN}🔧 OVS Architecture Overview:${NC}"
    echo "  ┌─────────────────────────────┐     ┌──────────────────────┐"
    echo "  │      Proxmox Host           │────▶│   LXC Container      │"
    echo "  │  ovsbr0-public: 80.209.240.244  │     │   ${CONFIG[container_ip]}        │"
    echo "  │  ovsbr0-private: 10.0.0.1   │     │                      │"
    echo "  │                             │     │ • Netmaker (8081)    │"
    echo "  │ • Nginx (80.209.240.244)    │     │ • Mosquitto (1883)   │"
    echo "  │ • MQTT Proxy (1883)         │     │ • MQTT WS (9001)     │"
    echo "  │ • Stream Module             │     │ • Netmaker Overlay   │"
    echo "  │ • Proxmox UI (8006)         │     │                      │"
    echo "  └─────────────────────────────┘     └──────────────────────┘"
    echo
    
    echo -e "${CYAN}🚀 Next Steps:${NC}"
    echo "  1. Configure DNS records to point to Proxmox host public IP"
    echo "  2. Obtain SSL certificates:"
    echo "     certbot --nginx -d netmaker.hobsonschoice.net -d broker.hobsonschoice.net -d ghostbridge.hobsonschoice.net"
    echo "  3. Test Netmaker API at https://netmaker.hobsonschoice.net/api/server/health"
    echo "  4. Access master key: pct exec ${CONFIG[container_id]} -- /etc/netmaker/get-master-key.sh"
    echo "  5. Create your first admin user via API"
    echo "  6. Configure networks and nodes via API calls"
    echo "  7. Deploy GhostBridge control panel at https://ghostbridge.hobsonschoice.net"
    echo
    
    echo -e "${CYAN}📁 Important Files & Logs:${NC}"
    echo "  • Deployment log: $LOG_FILE"
    echo "  • Container config: pct config ${CONFIG[container_id]}"
    echo "  • Nginx config: /etc/nginx/sites-available/ghostbridge"
    echo "  • Netmaker config: /etc/netmaker/config.yaml (in container)"
    echo "  • MQTT config: /etc/mosquitto/mosquitto.conf (in container)"
    echo
    
    echo -e "${CYAN}🔍 Management Commands:${NC}"
    echo "  • Enter container: pct enter ${CONFIG[container_id]}"
    echo "  • Check container services: pct exec ${CONFIG[container_id]} -- systemctl status netmaker mosquitto"
    echo "  • Check host nginx: systemctl status nginx"
    echo "  • View container logs: pct exec ${CONFIG[container_id]} -- journalctl -u netmaker -f"
    echo "  • Test MQTT: pct exec ${CONFIG[container_id]} -- mosquitto_pub -h 127.0.0.1 -p 1883 -t test -m hello"
    echo
    
    echo -e "${CYAN}🛠️ Troubleshooting:${NC}"
    echo "  • Container not responding: pct stop ${CONFIG[container_id]} && pct start ${CONFIG[container_id]}"
    echo "  • Nginx issues: nginx -t && systemctl restart nginx"
    echo "  • Network issues: Check firewall rules and bridge configuration"
    echo "  • Service issues: Check logs in container with journalctl"
    echo
    
    # Extract and display credentials
    print_info "Extracting credentials from container..."
    if pct exec "${CONFIG[container_id]}" -- test -f /etc/netmaker/credentials.env; then
        echo -e "${CYAN}🔐 Generated Credentials & API Access:${NC}"
        pct exec "${CONFIG[container_id]}" -- cat /etc/netmaker/credentials.env | grep -E "(MASTER_KEY|USERNAME|PASSWORD|API_URL|CONTROL_PANEL)" | sed 's/^export /  • /'
        echo "  ⚠️  Save these credentials securely!"
        echo
        echo -e "${CYAN}💡 API Usage Examples:${NC}"
        echo "  • Get master key: pct exec ${CONFIG[container_id]} -- /etc/netmaker/get-master-key.sh"
        echo "  • Load variables: pct exec ${CONFIG[container_id]} -- source /etc/netmaker/credentials.env"
        echo "  • Test API: curl -H \"Authorization: Bearer \$NETMAKER_MASTER_KEY\" \$NETMAKER_API_URL/server/health"
        echo
    fi
    
    echo "════════════════════════════════════════════════════════════════════════"
    
    print_status "🎯 Deployment completed successfully!"
    print_info "Your GhostBridge Netmaker installation is ready to use."
}

# Cleanup on failure
cleanup_on_failure() {
    print_header "Cleaning Up After Failure"
    echo "────────────────────────────────────────────────────────────────────────"
    
    print_warning "Deployment failed - cleaning up partial installation..."
    
    # Stop and remove container if it exists
    if [[ -n "${CONFIG[container_id]:-}" ]]; then
        print_info "Cleaning up container ${CONFIG[container_id]}..."
        pct stop "${CONFIG[container_id]}" --force 2>/dev/null || true
        pct destroy "${CONFIG[container_id]}" --force 2>/dev/null || true
    fi
    
    print_info "Please review the log file for details: $LOG_FILE"
}

# Main execution function
main() {
    # Set up error handling
    trap cleanup_on_failure ERR
    
    show_banner
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting GhostBridge deployment v$SCRIPT_VERSION" >> "$LOG_FILE"
    
    check_prerequisites
    get_deployment_config
    
    print_header "Starting GhostBridge Deployment"
    echo "════════════════════════════════════════════════════════════════════════"
    echo
    
    # Execute deployment steps
    deploy_lxc_container
    deploy_container_services
    deploy_nginx_upgrade
    test_deployment
    show_deployment_summary
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - GhostBridge deployment completed successfully" >> "$LOG_FILE"
}

# Handle script interruption
trap 'print_error "Deployment interrupted by user"; cleanup_on_failure; exit 1' INT TERM

# Execute main function with all arguments
main "$@"