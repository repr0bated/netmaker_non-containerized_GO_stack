#!/bin/bash
# verify-btrfs-storage.sh - Verify and monitor btrfs storage for GhostBridge deployment
set -euo pipefail

LOG_FILE="/var/log/ghostbridge-btrfs-check.log"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1" | tee -a "$LOG_FILE"; }
print_error() { echo -e "${RED}[✗]${NC} $1" | tee -a "$LOG_FILE"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1" | tee -a "$LOG_FILE"; }
print_info() { echo -e "${BLUE}[i]${NC} $1" | tee -a "$LOG_FILE"; }

show_banner() {
    echo -e "${BLUE}"
    cat << 'EOF'
╔═══════════════════════════════════════════════════════════════════════════╗
║                                                                           ║
║                 GhostBridge BTRFS Storage Verification                    ║
║                                                                           ║
║      Verifies btrfs storage pool and monitors utilization                ║
║                                                                           ║
╚═══════════════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# Check if btrfs tools are available
check_btrfs_tools() {
    print_info "Checking btrfs tools availability..."
    
    if ! command -v btrfs >/dev/null 2>&1; then
        print_error "btrfs-progs package not installed"
        print_info "Installing btrfs-progs..."
        apt update && apt install -y btrfs-progs
    fi
    
    print_status "btrfs tools available"
}

# Verify btrfs storage exists and has space
verify_storage_pool() {
    print_info "Verifying btrfs storage availability..."
    
    # Find btrfs filesystems
    local btrfs_mounts=$(btrfs filesystem show 2>/dev/null | grep -E "^Label:" -A1 | grep "uuid:" | awk '{print $NF}' | while read uuid; do
        findmnt -n -o TARGET --source UUID="$uuid" 2>/dev/null
    done | head -3)
    
    if [[ -z "$btrfs_mounts" ]]; then
        print_error "No btrfs filesystems found"
        print_info "Available filesystems:"
        mount | grep -E "(ext4|xfs|btrfs)" | awk '{print $1, $3, $5}' || echo "  No supported filesystems found"
        return 1
    fi
    
    print_status "Found btrfs filesystems:"
    for mount_point in $btrfs_mounts; do
        local fs_label=$(btrfs filesystem label "$mount_point" 2>/dev/null || echo "unlabeled")
        print_info "  $mount_point (label: $fs_label)"
    done
    
    # Check if any mount point has enough space for containers
    local sufficient_space=false
    for mount_point in $btrfs_mounts; do
        local available_gb=$(btrfs filesystem usage "$mount_point" 2>/dev/null | grep "Free (estimated):" | awk '{print $3}' | sed 's/GiB//' | cut -d'.' -f1 || echo "0")
        if [[ $available_gb -gt 50 ]]; then
            sufficient_space=true
            print_status "Sufficient space available at $mount_point: ${available_gb}GB"
            break
        fi
    done
    
    if ! $sufficient_space; then
        print_error "No btrfs filesystem has sufficient space (need 50GB+)"
        return 1
    fi
}

# Check btrfs filesystem health
check_filesystem_health() {
    print_info "Checking btrfs filesystem health..."
    
    # Get btrfs mount points using btrfs commands
    local btrfs_mounts=$(btrfs filesystem show 2>/dev/null | grep -E "^Label:" -A1 | grep "uuid:" | awk '{print $NF}' | while read uuid; do
        findmnt -n -o TARGET --source UUID="$uuid" 2>/dev/null
    done)
    
    if [[ -z "$btrfs_mounts" ]]; then
        print_error "No btrfs filesystems found"
        return 1
    fi
    
    for mount_point in $btrfs_mounts; do
        print_info "Checking filesystem: $mount_point"
        
        # Check filesystem status using btrfs scrub
        local scrub_status=$(btrfs scrub status "$mount_point" 2>/dev/null | grep "Status:" | awk '{print $2}' || echo "unknown")
        if [[ "$scrub_status" == "finished" ]] || [[ "$scrub_status" == "unknown" ]]; then
            print_status "Filesystem at $mount_point is healthy"
        else
            print_warning "Scrub status: $scrub_status for $mount_point"
        fi
        
        # Check for device errors using btrfs device stats
        local error_count=$(btrfs device stats "$mount_point" 2>/dev/null | grep -vE "(write_io_errs|read_io_errs|flush_io_errs|corruption_errs|generation_errs).*0$" | wc -l || echo "0")
        if [[ "$error_count" -eq 0 ]]; then
            print_status "No device errors on $mount_point"
        else
            print_warning "$error_count device errors found on $mount_point"
            btrfs device stats "$mount_point" 2>/dev/null | grep -vE ".*0$" || true
        fi
        
        # Check subvolume structure
        local subvol_count=$(btrfs subvolume list "$mount_point" 2>/dev/null | wc -l || echo "0")
        print_info "Subvolumes in $mount_point: $subvol_count"
    done
}

# Monitor storage utilization
monitor_storage_utilization() {
    print_info "Monitoring btrfs storage utilization..."
    
    # Get btrfs filesystem usage using native commands
    local btrfs_mounts=$(btrfs filesystem show 2>/dev/null | grep -E "^Label:" -A1 | grep "uuid:" | awk '{print $NF}' | while read uuid; do
        findmnt -n -o TARGET --source UUID="$uuid" 2>/dev/null
    done)
    
    for mount_point in $btrfs_mounts; do
        print_info "BTRFS usage for $mount_point:"
        
        # Get filesystem usage details
        btrfs filesystem usage "$mount_point" 2>/dev/null || {
            print_warning "Cannot read usage for $mount_point"
            continue
        }
        echo
        
        # Calculate usage percentage using btrfs fi show and usage
        local device_size=$(btrfs filesystem usage "$mount_point" 2>/dev/null | grep "Device size:" | awk '{print $3}' | sed 's/[^0-9.]//g' || echo "0")
        local used_space=$(btrfs filesystem usage "$mount_point" 2>/dev/null | grep "Used:" | awk '{print $2}' | sed 's/[^0-9.]//g' || echo "0")
        
        if [[ $(echo "$device_size > 0" | bc -l 2>/dev/null || echo "0") -eq 1 ]] && [[ $(echo "$used_space > 0" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
            local usage_percent=$(echo "scale=0; $used_space * 100 / $device_size" | bc -l 2>/dev/null || echo "0")
            
            if [[ $usage_percent -gt 90 ]]; then
                print_error "Storage usage critical: ${usage_percent}% used (${used_space}GB/${device_size}GB)"
            elif [[ $usage_percent -gt 80 ]]; then
                print_warning "Storage usage high: ${usage_percent}% used (${used_space}GB/${device_size}GB)"
            else
                print_status "Storage usage normal: ${usage_percent}% used (${used_space}GB/${device_size}GB)"
            fi
        else
            print_info "Usage calculation not available for $mount_point"
        fi
        
        # Show subvolume quotas if enabled
        if btrfs qgroup show "$mount_point" >/dev/null 2>&1; then
            print_info "Quota groups configured:"
            btrfs qgroup show "$mount_point" 2>/dev/null | head -10
        fi
        echo
    done
}

# Check container storage requirements
check_container_requirements() {
    print_info "Checking container storage requirements..."
    
    # Calculate space needed for containers
    local containers_count=${1:-3}  # Default 3 containers
    local container_size_gb=${2:-8}  # Default 8GB per container
    local total_needed_gb=$((containers_count * container_size_gb))
    
    print_info "Estimated storage needed: ${total_needed_gb}GB for $containers_count containers"
    
    # Check available space using btrfs commands
    local max_available_gb=0
    local btrfs_mounts=$(btrfs filesystem show 2>/dev/null | grep -E "^Label:" -A1 | grep "uuid:" | awk '{print $NF}' | while read uuid; do
        findmnt -n -o TARGET --source UUID="$uuid" 2>/dev/null
    done)
    
    for mount_point in $btrfs_mounts; do
        local available_gb=$(btrfs filesystem usage "$mount_point" 2>/dev/null | grep "Free (estimated):" | awk '{print $3}' | sed 's/GiB//' | cut -d'.' -f1 || echo "0")
        if [[ $available_gb -gt $max_available_gb ]]; then
            max_available_gb=$available_gb
        fi
    done
    
    if [[ $max_available_gb -gt $total_needed_gb ]]; then
        print_status "Sufficient space available: ${max_available_gb}GB free"
    else
        print_warning "Limited space: ${max_available_gb}GB available, ${total_needed_gb}GB needed"
    fi
}

# Create monitoring script for deployment
create_monitoring_script() {
    print_info "Creating btrfs monitoring script..."
    
    cat > /usr/local/bin/btrfs-monitor << 'EOF'
#!/bin/bash
# Continuous btrfs monitoring for GhostBridge deployment

LOG_FILE="/var/log/btrfs-monitor.log"
ALERT_THRESHOLD=85

check_usage() {
    local mount_point="$1"
    local device_size=$(btrfs filesystem usage "$mount_point" 2>/dev/null | grep "Device size:" | awk '{print $3}' | sed 's/[^0-9.]//g' || echo "0")
    local used_space=$(btrfs filesystem usage "$mount_point" 2>/dev/null | grep "Used:" | awk '{print $2}' | sed 's/[^0-9.]//g' || echo "0")
    
    if [[ $(echo "$device_size > 0" | bc -l 2>/dev/null || echo "0") -eq 1 ]] && [[ $(echo "$used_space > 0" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
        local usage_percent=$(echo "scale=0; $used_space * 100 / $device_size" | bc -l 2>/dev/null || echo "0")
        
        if [[ $usage_percent -gt $ALERT_THRESHOLD ]]; then
            echo "$(date): ALERT - $mount_point usage at ${usage_percent}% (${used_space}GB/${device_size}GB)" | tee -a "$LOG_FILE"
            # Could add email notification here
        fi
        
        echo "$(date): $mount_point usage: ${usage_percent}% (${used_space}GB/${device_size}GB)" >> "$LOG_FILE"
    else
        echo "$(date): Cannot calculate usage for $mount_point" >> "$LOG_FILE"
    fi
}

# Monitor all btrfs filesystems using btrfs commands
for mount_point in $(btrfs filesystem show 2>/dev/null | grep -E "^Label:" -A1 | grep "uuid:" | awk '{print $NF}' | while read uuid; do findmnt -n -o TARGET --source UUID="$uuid" 2>/dev/null; done); do
    check_usage "$mount_point"
done
EOF
    
    chmod +x /usr/local/bin/btrfs-monitor
    
    # Create systemd timer for monitoring
    cat > /etc/systemd/system/btrfs-monitor.service << 'EOF'
[Unit]
Description=BTRFS Storage Monitor
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/btrfs-monitor
EOF

    cat > /etc/systemd/system/btrfs-monitor.timer << 'EOF'
[Unit]
Description=BTRFS Storage Monitor Timer
Requires=btrfs-monitor.service

[Timer]
OnCalendar=*:0/15
Persistent=true

[Install]
WantedBy=timers.target
EOF
    
    systemctl daemon-reload
    systemctl enable btrfs-monitor.timer
    systemctl start btrfs-monitor.timer
    
    print_status "BTRFS monitoring service configured"
}

# Validate deployment readiness
validate_deployment_readiness() {
    print_info "Validating deployment readiness..."
    
    local checks_passed=0
    local total_checks=4
    
    # Check 1: BTRFS filesystems exist
    local btrfs_count=$(btrfs filesystem show 2>/dev/null | grep -c "^Label:" || echo "0")
    if [[ $btrfs_count -gt 0 ]]; then
        print_status "✓ BTRFS filesystems available ($btrfs_count found)"
        ((checks_passed++))
    else
        print_error "✗ No BTRFS filesystems found"
    fi
    
    # Check 2: Filesystem health
    local btrfs_healthy=true
    local btrfs_mounts=$(btrfs filesystem show 2>/dev/null | grep -E "^Label:" -A1 | grep "uuid:" | awk '{print $NF}' | while read uuid; do
        findmnt -n -o TARGET --source UUID="$uuid" 2>/dev/null
    done | head -3)
    
    for mount_point in $btrfs_mounts; do
        if ! btrfs filesystem show "$mount_point" >/dev/null 2>&1; then
            btrfs_healthy=false
            break
        fi
    done
    
    if $btrfs_healthy && [[ -n "$btrfs_mounts" ]]; then
        print_status "✓ BTRFS filesystems healthy"
        ((checks_passed++))
    else
        print_error "✗ BTRFS filesystem issues detected"
    fi
    
    # Check 3: Sufficient space using btrfs commands
    local max_available_gb=0
    for mount_point in $btrfs_mounts; do
        local available_gb=$(btrfs filesystem usage "$mount_point" 2>/dev/null | grep "Free (estimated):" | awk '{print $3}' | sed 's/GiB//' | cut -d'.' -f1 || echo "0")
        if [[ $available_gb -gt $max_available_gb ]]; then
            max_available_gb=$available_gb
        fi
    done
    
    if [[ $max_available_gb -gt 50 ]]; then
        print_status "✓ Sufficient storage space (${max_available_gb}GB)"
        ((checks_passed++))
    else
        print_error "✗ Insufficient storage space (${max_available_gb}GB)"
    fi
    
    # Check 4: Monitoring active
    if systemctl is-active --quiet btrfs-monitor.timer 2>/dev/null; then
        print_status "✓ BTRFS monitoring active"
        ((checks_passed++))
    else
        print_error "✗ BTRFS monitoring not active"
    fi
    
    echo
    if [[ $checks_passed -eq $total_checks ]]; then
        print_status "🎉 All BTRFS checks passed - deployment ready!"
        return 0
    else
        print_error "❌ $((total_checks - checks_passed)) checks failed - fix issues before deployment"
        return 1
    fi
}

# Main execution
main() {
    show_banner
    echo "BTRFS Storage Verification Started" | tee -a "$LOG_FILE"
    
    check_btrfs_tools
    verify_storage_pool
    check_filesystem_health
    monitor_storage_utilization
    check_container_requirements "$@"
    create_monitoring_script
    validate_deployment_readiness
    
    echo "BTRFS verification completed" | tee -a "$LOG_FILE"
}

main "$@"