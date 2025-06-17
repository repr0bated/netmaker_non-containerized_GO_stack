#!/bin/bash
set -euo pipefail

# Network Reset Script
# Removes all conflicting network configurations and resets to eth0 DHCP + simple bridge

SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/network-reset-$(date +%Y%m%d-%H%M%S).log"
BACKUP_DIR="/tmp/network-reset-backup-$(date +%Y%m%d-%H%M%S)"

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

# Create backup directory
create_backup_dir() {
    info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"/{network,systemd,ovs}
    log "Backup directory created at $BACKUP_DIR"
}

# Backup current network configuration
backup_network_config() {
    info "Backing up current network configuration..."
    
    # Backup network interfaces
    if [ -f "/etc/network/interfaces" ]; then
        cp "/etc/network/interfaces" "$BACKUP_DIR/network/interfaces.backup"
        info "Backed up /etc/network/interfaces"
    fi
    
    if [ -d "/etc/network/interfaces.d" ]; then
        cp -r "/etc/network/interfaces.d" "$BACKUP_DIR/network/"
        info "Backed up /etc/network/interfaces.d/"
    fi
    
    # Backup NetworkManager configs
    if [ -d "/etc/NetworkManager" ]; then
        cp -r "/etc/NetworkManager" "$BACKUP_DIR/network/"
        info "Backed up NetworkManager configuration"
    fi
    
    # Backup systemd-networkd configs
    if [ -d "/etc/systemd/network" ]; then
        cp -r "/etc/systemd/network" "$BACKUP_DIR/systemd/"
        info "Backed up systemd-networkd configuration"
    fi
    
    # Backup netplan configs
    if [ -d "/etc/netplan" ]; then
        cp -r "/etc/netplan" "$BACKUP_DIR/network/"
        info "Backed up netplan configuration"
    fi
    
    # Backup OVS configuration
    if [ -f "/etc/openvswitch/conf.db" ]; then
        cp "/etc/openvswitch/conf.db" "$BACKUP_DIR/ovs/conf.db.backup"
        info "Backed up OVS configuration database"
    fi
    
    # Save current network state
    {
        echo "=== PRE-RESET NETWORK STATE ==="
        echo "Date: $(date)"
        echo ""
        echo "=== IP ADDRESSES ==="
        ip addr show
        echo ""
        echo "=== ROUTES ==="
        ip route show
        echo ""
        echo "=== BRIDGES ==="
        brctl show 2>/dev/null || echo "bridge-utils not available"
        echo ""
        echo "=== OVS BRIDGES ==="
        ovs-vsctl show 2>/dev/null || echo "OpenVSwitch not available"
        echo ""
        echo "=== SYSTEMD SERVICES ==="
        systemctl list-units --type=service --state=running | grep -E "(network|ovs|bridge)" || echo "No network services found"
        echo ""
    } > "$BACKUP_DIR/pre-reset-state.txt"
    
    success "Network configuration backed up"
}

# Stop and disable conflicting systemd services
stop_network_services() {
    info "Stopping and disabling conflicting network services..."
    
    # List of network services to stop/disable
    local services=(
        "NetworkManager"
        "systemd-networkd" 
        "networking"
        "ifupdown-pre"
        "ifupdown-wait-online"
        "openvswitch-switch"
        "ovs-vswitchd"
        "ovsdb-server"
        "netmaker"
        "netclient"
        "netmaker-ovs-bridge"
        "netmaker-obfuscation-daemon"
    )
    
    for service in "${services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            info "Stopping service: $service"
            systemctl stop "$service" 2>/dev/null || warning "Failed to stop $service"
        fi
        
        if systemctl is-enabled --quiet "$service" 2>/dev/null; then
            info "Disabling service: $service"
            systemctl disable "$service" 2>/dev/null || warning "Failed to disable $service"
        fi
    done
    
    success "Network services stopped and disabled"
}

# Remove OVS configuration
cleanup_ovs() {
    info "Cleaning up OpenVSwitch configuration..."
    
    # Check if OVS is available
    if command -v ovs-vsctl >/dev/null 2>&1; then
        # Remove all OVS bridges
        local bridges=$(ovs-vsctl list-br 2>/dev/null || true)
        if [ -n "$bridges" ]; then
            while read -r bridge; do
                if [ -n "$bridge" ]; then
                    info "Removing OVS bridge: $bridge"
                    ovs-vsctl --if-exists del-br "$bridge"
                fi
            done <<< "$bridges"
        fi
        
        # Clear OVS database
        if [ -f "/etc/openvswitch/conf.db" ]; then
            info "Clearing OVS database"
            rm -f "/etc/openvswitch/conf.db"
        fi
    fi
    
    success "OVS configuration cleaned"
}

# Remove all network interfaces except eth0 and lo
cleanup_network_interfaces() {
    info "Cleaning up network interfaces..."
    
    # Get list of all interfaces except lo and eth0
    local interfaces=$(ip link show | grep -E '^[0-9]+:' | cut -d':' -f2 | tr -d ' ' | grep -v -E '^(lo|eth0)$' || true)
    
    if [ -n "$interfaces" ]; then
        while read -r iface; do
            if [ -n "$iface" ]; then
                info "Removing interface: $iface"
                ip link set "$iface" down 2>/dev/null || true
                ip link delete "$iface" 2>/dev/null || warning "Failed to remove $iface"
            fi
        done <<< "$interfaces"
    fi
    
    # Remove VLAN interfaces specifically
    local vlan_interfaces=$(ip link show | grep -E '\.[0-9]+@' | cut -d':' -f2 | tr -d ' ' || true)
    if [ -n "$vlan_interfaces" ]; then
        while read -r vlan_iface; do
            if [ -n "$vlan_iface" ]; then
                info "Removing VLAN interface: $vlan_iface"
                ip link delete "$vlan_iface" 2>/dev/null || warning "Failed to remove $vlan_iface"
            fi
        done <<< "$vlan_interfaces"
    fi
    
    # Remove bridge interfaces
    local bridges=$(brctl show 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -v '^$' || true)
    if [ -n "$bridges" ]; then
        while read -r bridge; do
            if [ -n "$bridge" ]; then
                info "Removing bridge: $bridge"
                ip link set "$bridge" down 2>/dev/null || true
                brctl delbr "$bridge" 2>/dev/null || warning "Failed to remove bridge $bridge"
            fi
        done <<< "$bridges"
    fi
    
    success "Network interfaces cleaned"
}

# Remove network configuration files
cleanup_network_configs() {
    info "Cleaning up network configuration files..."
    
    # Remove NetworkManager connections
    if [ -d "/etc/NetworkManager/system-connections" ]; then
        info "Removing NetworkManager connections"
        rm -f /etc/NetworkManager/system-connections/* 2>/dev/null || true
    fi
    
    # Remove systemd-networkd configs
    if [ -d "/etc/systemd/network" ]; then
        info "Removing systemd-networkd configurations"
        rm -f /etc/systemd/network/*.network 2>/dev/null || true
        rm -f /etc/systemd/network/*.netdev 2>/dev/null || true
        rm -f /etc/systemd/network/*.link 2>/dev/null || true
    fi
    
    # Remove netplan configs
    if [ -d "/etc/netplan" ]; then
        info "Removing netplan configurations"
        rm -f /etc/netplan/*.yaml 2>/dev/null || true
    fi
    
    # Remove interfaces.d configs
    if [ -d "/etc/network/interfaces.d" ]; then
        info "Removing interface-specific configurations"
        rm -f /etc/network/interfaces.d/* 2>/dev/null || true
    fi
    
    success "Network configuration files cleaned"
}

# Create simple eth0 DHCP + bridge configuration
create_simple_network_config() {
    info "Creating simple network configuration..."
    
    # Create basic /etc/network/interfaces
    cat > /etc/network/interfaces << 'EOF'
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface - DHCP
auto eth0
iface eth0 inet dhcp

# Simple bridge for containers/VMs
auto br0
iface br0 inet manual
    bridge_ports none
    bridge_stp off
    bridge_fd 0
    bridge_maxwait 0
EOF
    
    info "Created basic /etc/network/interfaces"
    
    # Ensure interfaces.d directory exists
    mkdir -p /etc/network/interfaces.d
    
    success "Simple network configuration created"
}

# Bring up eth0 and basic bridge
bring_up_network() {
    info "Bringing up network interfaces..."
    
    # Bring up loopback
    ip link set lo up 2>/dev/null || true
    
    # Bring up eth0 with DHCP
    if ip link show eth0 >/dev/null 2>&1; then
        info "Configuring eth0 with DHCP"
        ip link set eth0 up
        dhclient eth0 2>/dev/null || warning "DHCP configuration failed - may need manual configuration"
    else
        warning "eth0 interface not found - may need different interface name"
    fi
    
    # Create and bring up simple bridge
    if command -v brctl >/dev/null 2>&1; then
        info "Creating simple bridge br0"
        brctl addbr br0 2>/dev/null || warning "Failed to create br0"
        ip link set br0 up 2>/dev/null || warning "Failed to bring up br0"
    else
        warning "bridge-utils not available - bridge creation skipped"
    fi
    
    success "Network interfaces configured"
}

# Reload systemd and start essential services
restart_network_services() {
    info "Restarting essential network services..."
    
    # Reload systemd daemon
    systemctl daemon-reload
    
    # Start essential networking service (choose based on what's available)
    if systemctl list-unit-files | grep -q "networking.service"; then
        info "Starting networking service"
        systemctl enable networking 2>/dev/null || true
        systemctl start networking 2>/dev/null || warning "Failed to start networking service"
    elif systemctl list-unit-files | grep -q "systemd-networkd.service"; then
        info "Starting systemd-networkd"
        systemctl enable systemd-networkd 2>/dev/null || true
        systemctl start systemd-networkd 2>/dev/null || warning "Failed to start systemd-networkd"
    fi
    
    success "Network services restarted"
}

# Validate network reset
validate_network_reset() {
    info "Validating network reset..."
    
    local validation_failed=false
    
    # Check eth0 is up and has IP
    if ! ip addr show eth0 | grep -q "inet "; then
        warning "eth0 does not have an IP address"
        validation_failed=true
    fi
    
    # Check basic connectivity
    if ! ping -c 1 -W 5 8.8.8.8 >/dev/null 2>&1; then
        warning "External connectivity test failed"
        # Not fatal, but worth noting
    fi
    
    # Check no conflicting interfaces remain
    local conflicting_interfaces=$(ip link show | grep -E 'ovs|nm-|netmaker' || true)
    if [ -n "$conflicting_interfaces" ]; then
        warning "Some conflicting interfaces may still exist"
        echo "$conflicting_interfaces" | while read -r line; do
            warning "  $line"
        done
    fi
    
    # Check no OVS bridges remain
    if command -v ovs-vsctl >/dev/null 2>&1; then
        local remaining_bridges=$(ovs-vsctl list-br 2>/dev/null || true)
        if [ -n "$remaining_bridges" ]; then
            warning "OVS bridges still exist:"
            echo "$remaining_bridges" | while read -r bridge; do
                warning "  - $bridge"
            done
        fi
    fi
    
    if [ "$validation_failed" = true ]; then
        error "Network reset validation failed"
        return 1
    else
        success "Network reset validation passed"
        return 0
    fi
}

# Generate reset report
generate_reset_report() {
    local report_file="$BACKUP_DIR/network-reset-report.txt"
    
    {
        echo "========================================"
        echo "Network Reset Report"
        echo "========================================"
        echo "Date: $(date)"
        echo "Script Version: $SCRIPT_VERSION"
        echo "Log File: $LOG_FILE"
        echo "Backup Directory: $BACKUP_DIR"
        echo ""
        echo "=== POST-RESET NETWORK STATE ==="
        echo ""
        echo "IP Addresses:"
        ip addr show
        echo ""
        echo "Routes:"
        ip route show
        echo ""
        echo "Bridges:"
        brctl show 2>/dev/null || echo "bridge-utils not available"
        echo ""
        echo "OVS Status:"
        ovs-vsctl show 2>/dev/null || echo "OpenVSwitch not available/clean"
        echo ""
        echo "Active Network Services:"
        systemctl list-units --type=service --state=running | grep -E "(network|ovs|bridge)" || echo "No conflicting network services"
        echo ""
        echo "Network Reset Status: $([ $? -eq 0 ] && echo 'SUCCESS' || echo 'WITH WARNINGS')"
        echo ""
        echo "Restore Information:"
        echo "- Configuration backed up to: $BACKUP_DIR"
        echo "- To restore if needed: see backup files in $BACKUP_DIR"
        echo ""
        
    } > "$report_file"
    
    info "Network reset report generated: $report_file"
}

# Main execution function
main() {
    echo "========================================"
    echo "Network Reset Script"
    echo "Version: $SCRIPT_VERSION"
    echo "========================================"
    echo ""
    
    log "Starting network reset process"
    
    # Prerequisites
    check_root
    create_backup_dir
    backup_network_config
    
    # Reset process
    stop_network_services
    cleanup_ovs
    cleanup_network_interfaces
    cleanup_network_configs
    create_simple_network_config
    bring_up_network
    restart_network_services
    
    # Validation and reporting
    validate_network_reset
    generate_reset_report
    
    success "Network reset completed!"
    echo ""
    echo "========================================"
    echo "NETWORK RESET COMPLETE"
    echo "========================================"
    echo ""
    echo "Current network configuration:"
    echo "- eth0: DHCP (primary interface)"
    echo "- br0: Simple bridge (no ports)"
    echo "- All conflicting configurations removed"
    echo ""
    echo "Logs: $LOG_FILE"
    echo "Backups: $BACKUP_DIR"
    echo "Report: $BACKUP_DIR/network-reset-report.txt"
    echo ""
}

# Execute main function
main "$@"