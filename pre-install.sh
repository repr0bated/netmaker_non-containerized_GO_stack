#!/bin/bash
set -euo pipefail

# Pre-Installation Network Reset Script
# Resets network to clean state and installs dependencies before Netmaker OVS Integration

SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/netmaker-ovs-preinstall-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Colored output functions
error() {
    echo -e "${RED}ERROR: $1${NC}" | tee -a "$LOG_FILE"
}

warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

info() {
    echo -e "${BLUE}INFO: $1${NC}" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}" | tee -a "$LOG_FILE"
}

# Check if running as root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root. Please use sudo."
        exit 1
    fi
}

# Install required dependencies
install_dependencies() {
    info "Installing required dependencies..."
    
    # Update package cache
    info "Updating package cache..."
    apt-get update -qq || warning "Package cache update failed"
    
    # Required packages
    local required_packages=(
        "openvswitch-switch"
        "bridge-utils"
        "iproute2"
        "systemd"
        "net-tools"
        "dhcpcd5"
    )
    
    for package in "${required_packages[@]}"; do
        if ! dpkg -l | grep -q "^ii.*$package"; then
            info "Installing $package..."
            apt-get install -y "$package" || warning "Failed to install $package"
        else
            info "$package is already installed"
        fi
    done
    
    success "Dependencies installation completed"
}

# Check prerequisites are now available
check_prerequisites() {
    info "Verifying prerequisites..."
    
    local missing_deps=()
    
    # Check for required commands
    local required_commands=(
        "ovs-vsctl"
        "ovs-ofctl" 
        "ip"
        "brctl"
        "systemctl"
    )
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("command: $cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing prerequisites after installation:"
        for dep in "${missing_deps[@]}"; do
            error "  - $dep"
        done
        return 1
    else
        success "All prerequisites satisfied"
        return 0
    fi
}

# Check OpenVSwitch status
check_ovs_status() {
    info "Checking OpenVSwitch status..."
    
    # Check if OVS is running
    if ! systemctl is-active --quiet openvswitch-switch; then
        warning "OpenVSwitch service is not running"
        info "Attempting to start OpenVSwitch..."
        if systemctl start openvswitch-switch; then
            success "OpenVSwitch started successfully"
        else
            error "Failed to start OpenVSwitch"
            return 1
        fi
    else
        success "OpenVSwitch is running"
    fi
    
    # Check OVS database
    if ! ovs-vsctl show >/dev/null 2>&1; then
        error "Cannot connect to OVS database"
        return 1
    fi
    
    # List existing bridges
    local bridges=$(ovs-vsctl list-br 2>/dev/null || true)
    if [ -n "$bridges" ]; then
        info "Existing OVS bridges found:"
        echo "$bridges" | while read -r bridge; do
            info "  - $bridge"
        done
    else
        info "No existing OVS bridges found"
    fi
    
    return 0
}

# Check network configuration conflicts
check_network_conflicts() {
    info "Checking for network configuration conflicts..."
    
    local conflicts_found=false
    
    # Check for conflicting bridge names
    if ovs-vsctl br-exists ovsbr0 2>/dev/null; then
        warning "OVS bridge 'ovsbr0' already exists"
        
        # Check what's connected to it
        local ports=$(ovs-vsctl list-ports ovsbr0 2>/dev/null || true)
        if [ -n "$ports" ]; then
            warning "Bridge ovsbr0 has existing ports:"
            echo "$ports" | while read -r port; do
                warning "  - $port"
            done
            conflicts_found=true
        fi
    fi
    
    # Check for Netmaker interfaces
    local netmaker_interfaces=$(ip link show | grep -o 'nm-[^:]*' || true)
    if [ -n "$netmaker_interfaces" ]; then
        warning "Existing Netmaker interfaces found:"
        echo "$netmaker_interfaces" | while read -r iface; do
            warning "  - $iface"
        done
        conflicts_found=true
    fi
    
    # Check for VLAN conflicts in target pool
    local vlan_pool=(100 200 300 400 500)
    for vlan in "${vlan_pool[@]}"; do
        if ip link show | grep -q "\.${vlan}@"; then
            warning "VLAN $vlan is already in use"
            conflicts_found=true
        fi
    done
    
    # Check interface naming conflicts
    if ip link show | grep -qE "(ovsbr|nm-|netmaker)"; then
        warning "Interfaces with conflicting names detected"
        conflicts_found=true
    fi
    
    if [ "$conflicts_found" = true ]; then
        warning "Network conflicts detected - will resolve during cleanup"
        return 1
    else
        success "No network conflicts found"
        return 0
    fi
}

# Backup existing configuration
backup_existing_config() {
    info "Backing up existing configuration..."
    
    # Backup network configuration
    if [ -f "/etc/network/interfaces" ]; then
        cp "/etc/network/interfaces" "$BACKUP_DIR/network/interfaces.backup"
        info "Backed up /etc/network/interfaces"
    fi
    
    if [ -d "/etc/network/interfaces.d" ]; then
        cp -r "/etc/network/interfaces.d" "$BACKUP_DIR/network/"
        info "Backed up /etc/network/interfaces.d/"
    fi
    
    # Backup OVS configuration
    if [ -f "/etc/openvswitch/conf.db" ]; then
        cp "/etc/openvswitch/conf.db" "$BACKUP_DIR/config/ovs-conf.db.backup"
        info "Backed up OVS configuration database"
    fi
    
    # Backup existing Netmaker configuration
    if [ -d "/etc/netmaker" ]; then
        cp -r "/etc/netmaker" "$BACKUP_DIR/config/"
        info "Backed up existing Netmaker configuration"
    fi
    
    # Backup systemd services
    for service_file in /etc/systemd/system/netmaker*.service; do
        if [ -f "$service_file" ]; then
            cp "$service_file" "$BACKUP_DIR/systemd/"
            info "Backed up $(basename "$service_file")"
        fi
    done
    
    # Backup state directories
    if [ -d "/var/lib/netmaker" ]; then
        cp -r "/var/lib/netmaker" "$BACKUP_DIR/config/"
        info "Backed up Netmaker state directory"
    fi
    
    success "Configuration backup completed"
}

# Clean up existing installation
cleanup_existing_installation() {
    info "Cleaning up existing installation..."
    
    # Stop and disable services
    local services=(
        "netmaker-ovs-bridge.service"
        "netmaker-obfuscation-daemon.service"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            info "Stopping service: $service"
            systemctl stop "$service" || warning "Failed to stop $service"
        fi
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            info "Disabling service: $service"
            systemctl disable "$service" || warning "Failed to disable $service"
        fi
    done
    
    # Remove existing files
    local files_to_remove=(
        "/usr/local/bin/netmaker-ovs-bridge-add.sh"
        "/usr/local/bin/netmaker-ovs-bridge-remove.sh"
        "/usr/local/bin/obfuscation-manager.sh"
        "/etc/systemd/system/netmaker-ovs-bridge.service"
        "/etc/systemd/system/netmaker-obfuscation-daemon.service"
        "/var/run/netmaker-obfuscation.lock"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            info "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    # Clean up state directories
    if [ -f "/var/lib/netmaker/obfuscation-state" ]; then
        info "Removing obfuscation state file"
        rm -f "/var/lib/netmaker/obfuscation-state"
    fi
    
    # Reload systemd
    systemctl daemon-reload
    
    success "Cleanup completed"
}

# Clean network state
clean_network_state() {
    info "Cleaning network state..."
    
    # Remove Netmaker interfaces from OVS bridges
    local bridges=$(ovs-vsctl list-br 2>/dev/null || true)
    if [ -n "$bridges" ]; then
        while read -r bridge; do
            local ports=$(ovs-vsctl list-ports "$bridge" 2>/dev/null | grep -E "^nm-" || true)
            if [ -n "$ports" ]; then
                while read -r port; do
                    info "Removing Netmaker interface $port from bridge $bridge"
                    ovs-vsctl --if-exists del-port "$bridge" "$port"
                done <<< "$ports"
            fi
        done <<< "$bridges"
    fi
    
    # Clean up VLAN configurations on target VLANs
    local vlan_pool=(100 200 300 400 500)
    for vlan in "${vlan_pool[@]}"; do
        local vlan_interfaces=$(ip link show | grep "\.${vlan}@" | cut -d':' -f2 | tr -d ' ' || true)
        if [ -n "$vlan_interfaces" ]; then
            while read -r vlan_iface; do
                info "Removing VLAN interface: $vlan_iface"
                ip link delete "$vlan_iface" 2>/dev/null || warning "Failed to remove $vlan_iface"
            done <<< "$vlan_interfaces"
        fi
    done
    
    # Reset any existing obfuscation on remaining interfaces
    local netmaker_interfaces=$(ip link show | grep -o 'nm-[^:@]*' || true)
    if [ -n "$netmaker_interfaces" ]; then
        while read -r iface; do
            info "Resetting interface $iface to default state"
            
            # Clear any QoS settings
            ovs-vsctl --if-exists clear interface "$iface" ingress_policing_rate 2>/dev/null || true
            ovs-vsctl --if-exists clear interface "$iface" ingress_policing_burst 2>/dev/null || true
            
            # Clear VLAN tags
            ovs-vsctl --if-exists remove port "$iface" tag 2>/dev/null || true
            
        done <<< "$netmaker_interfaces"
    fi
    
    success "Network state cleaned"
}

# Validate system readiness
validate_system_readiness() {
    info "Validating system readiness for installation..."
    
    local validation_failed=false
    
    # Check OpenVSwitch is operational
    if ! ovs-vsctl show >/dev/null 2>&1; then
        error "OpenVSwitch is not operational"
        validation_failed=true
    fi
    
    # Check network connectivity
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        warning "External network connectivity test failed"
        # This is a warning, not a fatal error
    fi
    
    # Check available disk space
    local available_space=$(df /tmp | awk 'NR==2 {print $4}')
    if [ "$available_space" -lt 102400 ]; then # 100MB in KB
        error "Insufficient disk space in /tmp (need at least 100MB)"
        validation_failed=true
    fi
    
    # Check memory availability
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    if [ "$available_memory" -lt 256 ]; then
        warning "Low available memory ($available_memory MB) - installation may be slow"
    fi
    
    # Check systemd is functional
    if ! systemctl --version >/dev/null 2>&1; then
        error "systemd is not functional"
        validation_failed=true
    fi
    
    # Validate directory permissions
    local required_dirs=("/etc" "/usr/local/bin" "/var/lib")
    for dir in "${required_dirs[@]}"; do
        if [ ! -w "$dir" ]; then
            error "No write permission to $dir"
            validation_failed=true
        fi
    done
    
    if [ "$validation_failed" = true ]; then
        error "System validation failed"
        return 1
    else
        success "System validation passed"
        return 0
    fi
}

# Generate installation report
generate_report() {
    local report_file="$BACKUP_DIR/pre-install-report.txt"
    
    {
        echo "========================================"
        echo "Netmaker OVS Pre-Installation Report"
        echo "========================================"
        echo "Date: $(date)"
        echo "Script Version: $SCRIPT_VERSION"
        echo "Log File: $LOG_FILE"
        echo "Backup Directory: $BACKUP_DIR"
        echo ""
        echo "System Status:"
        echo "- OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'=' -f2 | tr -d '"')"
        echo "- Kernel: $(uname -r)"
        echo "- OpenVSwitch: $(ovs-vsctl --version | head -n1 2>/dev/null || echo 'Not available')"
        echo ""
        echo "Network Configuration:"
        echo "- OVS Bridges: $(ovs-vsctl list-br 2>/dev/null | wc -l)"
        echo "- Network Interfaces: $(ip link show | grep -c '^[0-9]')"
        echo "- Netmaker Interfaces: $(ip link show | grep -c 'nm-' || echo '0')"
        echo ""
        echo "System Readiness: $([ $? -eq 0 ] && echo 'READY' || echo 'NEEDS ATTENTION')"
        echo ""
        echo "Next Steps:"
        echo "1. Review this report and the full log: $LOG_FILE"
        echo "2. If system is ready, proceed with: sudo ./install.sh"
        echo "3. If issues found, resolve them before installation"
        echo ""
        echo "Backup Information:"
        echo "- Configuration backed up to: $BACKUP_DIR"
        echo "- To restore previous state if needed:"
        echo "  sudo cp $BACKUP_DIR/network/interfaces.backup /etc/network/interfaces"
        echo "  sudo systemctl restart networking"
        echo ""
        
    } > "$report_file"
    
    info "Pre-installation report generated: $report_file"
}

# Main execution function
main() {
    echo "========================================"
    echo "Netmaker OVS Pre-Installation Script"
    echo "Version: $SCRIPT_VERSION"
    echo "========================================"
    echo ""
    
    log "Starting pre-installation process"
    
    # Check prerequisites first
    check_root
    
    # Install dependencies
    install_dependencies
    
    # Verify installation worked
    if ! check_prerequisites; then
        error "Prerequisites installation failed. Please check the logs."
        exit 1
    fi
    
    # Run network reset
    info "Running network reset..."
    if [ -x "./network-reset.sh" ]; then
        ./network-reset.sh
        if [ $? -ne 0 ]; then
            warning "Network reset completed with warnings"
        else
            success "Network reset completed successfully"
        fi
    else
        error "network-reset.sh not found or not executable"
        exit 1
    fi
    
    success "Pre-installation completed successfully!"
    echo ""
    echo "========================================"
    echo "SYSTEM IS READY FOR INSTALLATION"
    echo "========================================"
    echo ""
    echo "Network has been reset to:"
    echo "- eth0: DHCP configuration"
    echo "- br0: Simple empty bridge"
    echo "- All conflicting configurations removed"
    echo "- Required dependencies installed"
    echo ""
    echo "Next step: Run sudo ./install.sh"
    echo "Log file: $LOG_FILE"
    echo ""
}

# Execute main function
main "$@"