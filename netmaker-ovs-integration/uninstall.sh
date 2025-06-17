#!/bin/bash
set -euo pipefail

# Netmaker OVS Integration Uninstaller
# Completely removes the installation and optionally restores backed up configuration

SCRIPT_VERSION="1.0.0"
LOG_FILE="/tmp/netmaker-ovs-uninstall-$(date +%Y%m%d-%H%M%S).log"

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

# Find backup directories
find_backup_dirs() {
    local backup_dirs=($(find /tmp -maxdepth 1 -type d -name "netmaker-ovs-backup-*" 2>/dev/null | sort -r))
    if [ ${#backup_dirs[@]} -gt 0 ]; then
        echo "${backup_dirs[0]}"  # Return most recent
    else
        echo ""
    fi
}

# Stop and disable services
stop_services() {
    info "Stopping and disabling Netmaker OVS services..."
    
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
    
    success "Services stopped and disabled"
}

# Remove obfuscation from active interfaces
remove_active_obfuscation() {
    info "Removing obfuscation from active interfaces..."
    
    # Find Netmaker interfaces
    local netmaker_interfaces=$(ip link show | grep -o 'nm-[^:@]*' || true)
    
    if [ -n "$netmaker_interfaces" ]; then
        while read -r iface; do
            info "Cleaning obfuscation from interface: $iface"
            
            # Clear QoS settings
            ovs-vsctl --if-exists clear interface "$iface" ingress_policing_rate 2>/dev/null || true
            ovs-vsctl --if-exists clear interface "$iface" ingress_policing_burst 2>/dev/null || true
            
            # Clear VLAN tags
            ovs-vsctl --if-exists remove port "$iface" tag 2>/dev/null || true
            
            success "Cleaned interface: $iface"
        done <<< "$netmaker_interfaces"
    else
        info "No active Netmaker interfaces found"
    fi
}

# Remove installed files
remove_files() {
    info "Removing installed files..."
    
    local files_to_remove=(
        "/usr/local/bin/netmaker-ovs-bridge-add.sh"
        "/usr/local/bin/netmaker-ovs-bridge-remove.sh"
        "/usr/local/bin/obfuscation-manager.sh"
        "/etc/systemd/system/netmaker-ovs-bridge.service"
        "/etc/systemd/system/netmaker-obfuscation-daemon.service"
        "/etc/netmaker/ovs-config"
        "/usr/share/doc/netmaker-ovs-integration/README.md"
        "/var/lib/netmaker/obfuscation-state"
        "/var/run/netmaker-obfuscation.lock"
    )
    
    for file in "${files_to_remove[@]}"; do
        if [ -f "$file" ]; then
            info "Removing file: $file"
            rm -f "$file"
        fi
    done
    
    # Remove empty directories
    local dirs_to_remove=(
        "/usr/share/doc/netmaker-ovs-integration"
        "/etc/netmaker"  # Only if empty
        "/var/lib/netmaker"  # Only if empty
    )
    
    for dir in "${dirs_to_remove[@]}"; do
        if [ -d "$dir" ] && [ -z "$(ls -A "$dir")" ]; then
            info "Removing empty directory: $dir"
            rmdir "$dir"
        elif [ -d "$dir" ]; then
            warning "Directory $dir not empty, leaving in place"
        fi
    done
    
    # Reload systemd
    systemctl daemon-reload
    
    success "Files removed successfully"
}

# Remove Netmaker interfaces from OVS bridges
cleanup_ovs_integration() {
    info "Cleaning up OVS integration..."
    
    # Get all OVS bridges
    local bridges=$(ovs-vsctl list-br 2>/dev/null || true)
    
    if [ -n "$bridges" ]; then
        while read -r bridge; do
            # Find Netmaker interfaces in this bridge
            local netmaker_ports=$(ovs-vsctl list-ports "$bridge" 2>/dev/null | grep -E "^nm-" || true)
            
            if [ -n "$netmaker_ports" ]; then
                info "Removing Netmaker interfaces from bridge: $bridge"
                while read -r port; do
                    info "  Removing port: $port"
                    ovs-vsctl --if-exists del-port "$bridge" "$port"
                done <<< "$netmaker_ports"
            fi
        done <<< "$bridges"
    fi
    
    success "OVS integration cleaned up"
}

# Restore configuration from backup
restore_configuration() {
    local backup_dir="$1"
    
    if [ -z "$backup_dir" ] || [ ! -d "$backup_dir" ]; then
        warning "No backup directory found or provided. Skipping restore."
        return 0
    fi
    
    info "Restoring configuration from backup: $backup_dir"
    
    # Restore network configuration
    if [ -f "$backup_dir/network/interfaces.backup" ]; then
        info "Restoring /etc/network/interfaces"
        cp "$backup_dir/network/interfaces.backup" "/etc/network/interfaces"
    fi
    
    if [ -d "$backup_dir/network/interfaces.d" ]; then
        info "Restoring /etc/network/interfaces.d/"
        rm -rf "/etc/network/interfaces.d"
        cp -r "$backup_dir/network/interfaces.d" "/etc/network/"
    fi
    
    # Restore OVS configuration
    if [ -f "$backup_dir/config/ovs-conf.db.backup" ]; then
        info "Restoring OVS configuration database"
        systemctl stop openvswitch-switch
        cp "$backup_dir/config/ovs-conf.db.backup" "/etc/openvswitch/conf.db"
        systemctl start openvswitch-switch
    fi
    
    # Restore Netmaker configuration (if it was backed up and no current installation)
    if [ -d "$backup_dir/config/netmaker" ] && [ ! -d "/etc/netmaker" ]; then
        info "Restoring Netmaker configuration"
        cp -r "$backup_dir/config/netmaker" "/etc/"
    fi
    
    # Restore systemd services (if they were backed up and are not Netmaker-OVS services)
    if [ -d "$backup_dir/systemd" ]; then
        for service_file in "$backup_dir/systemd"/*.service; do
            if [ -f "$service_file" ]; then
                local service_name=$(basename "$service_file")
                if [[ ! "$service_name" =~ netmaker-ovs ]]; then
                    info "Restoring systemd service: $service_name"
                    cp "$service_file" "/etc/systemd/system/"
                fi
            fi
        done
    fi
    
    # Reload systemd and restart networking
    systemctl daemon-reload
    
    success "Configuration restored from backup"
}

# Generate uninstall report
generate_report() {
    local backup_dir="$1"
    local report_file="/tmp/netmaker-ovs-uninstall-report-$(date +%Y%m%d-%H%M%S).txt"
    
    {
        echo "========================================"
        echo "Netmaker OVS Uninstallation Report"
        echo "========================================"
        echo "Date: $(date)"
        echo "Script Version: $SCRIPT_VERSION"
        echo "Log File: $LOG_FILE"
        echo ""
        echo "Uninstallation Status: COMPLETED"
        echo ""
        echo "Removed Components:"
        echo "- Netmaker OVS bridge integration service"
        echo "- Obfuscation daemon service"
        echo "- Configuration files"
        echo "- Script files"
        echo "- State files"
        echo ""
        echo "System Status After Uninstall:"
        echo "- OpenVSwitch: $(systemctl is-active openvswitch-switch)"
        echo "- OVS Bridges: $(ovs-vsctl list-br 2>/dev/null | wc -l)"
        echo "- Network Interfaces: $(ip link show | grep -c '^[0-9]')"
        echo "- Remaining Netmaker Interfaces: $(ip link show | grep -c 'nm-' || echo '0')"
        echo ""
        if [ -n "$backup_dir" ]; then
            echo "Backup Information:"
            echo "- Original backup used: $backup_dir"
            echo "- Configuration restored from backup"
        else
            echo "No backup restoration performed"
        fi
        echo ""
        echo "Notes:"
        echo "- OpenVSwitch remains installed and configured"
        echo "- Core Netmaker installation (if present) remains untouched"
        echo "- OVS bridges and other network configuration preserved"
        echo ""
        echo "To completely remove OpenVSwitch (if desired):"
        echo "  sudo apt remove --purge openvswitch-switch openvswitch-common"
        echo ""
        echo "To remove core Netmaker (if desired):"
        echo "  sudo systemctl stop netmaker netclient"
        echo "  sudo apt remove netmaker netclient"
        echo ""
        
    } > "$report_file"
    
    info "Uninstallation report generated: $report_file"
    echo "$report_file"
}

# Main execution function
main() {
    echo "========================================"
    echo "Netmaker OVS Integration Uninstaller"
    echo "Version: $SCRIPT_VERSION"
    echo "========================================"
    echo ""
    
    log "Starting uninstallation process"
    
    check_root
    
    # Check if installation exists
    local has_installation=false
    
    if systemctl list-unit-files | grep -q "netmaker-ovs-bridge.service"; then
        has_installation=true
    fi
    
    if [ -f "/usr/local/bin/obfuscation-manager.sh" ]; then
        has_installation=true
    fi
    
    if [ "$has_installation" = false ]; then
        warning "No Netmaker OVS installation found. Nothing to uninstall."
        exit 0
    fi
    
    # Ask for confirmation
    echo "This will completely remove the Netmaker OVS Integration with obfuscation."
    echo "The following will be removed:"
    echo "  - All service files and scripts"
    echo "  - Configuration files"
    echo "  - Obfuscation state"
    echo ""
    echo "The following will NOT be affected:"
    echo "  - Core Netmaker installation"
    echo "  - OpenVSwitch installation"
    echo "  - Existing OVS bridges and network configuration"
    echo ""
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Uninstallation cancelled."
        exit 0
    fi
    
    # Find backup directory
    local backup_dir=$(find_backup_dirs)
    local restore_config=false
    
    if [ -n "$backup_dir" ]; then
        echo ""
        echo "Found backup directory: $backup_dir"
        read -p "Do you want to restore the original configuration from backup? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            restore_config=true
        fi
    fi
    
    echo ""
    info "Starting uninstallation..."
    
    # Execute uninstallation steps
    stop_services
    remove_active_obfuscation
    cleanup_ovs_integration
    remove_files
    
    # Restore configuration if requested
    if [ "$restore_config" = true ]; then
        restore_configuration "$backup_dir"
    fi
    
    # Generate report
    local report_file=$(generate_report "$backup_dir")
    
    success "Uninstallation completed successfully!"
    echo ""
    echo "========================================"
    echo "UNINSTALLATION COMPLETED"
    echo "========================================"
    echo ""
    echo "Summary:"
    echo "- All Netmaker OVS integration components removed"
    echo "- Obfuscation cleaned from active interfaces"
    echo "- System restored to pre-installation state"
    echo ""
    if [ "$restore_config" = true ]; then
        echo "- Original configuration restored from backup"
    fi
    echo ""
    echo "Report available at: $report_file"
    echo "Log available at: $LOG_FILE"
    echo ""
    echo "System is ready for fresh installation if desired."
    echo ""
}

# Execute main function
main "$@"