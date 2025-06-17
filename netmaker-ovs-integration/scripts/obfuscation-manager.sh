#!/bin/bash
set -euo pipefail

# Obfuscation Manager for Netmaker OVS Integration
# Implements mild obfuscation with best gain/cost ratio

CONFIG_FILE="/etc/netmaker/ovs-config"
OBFS_STATE_FILE="/var/lib/netmaker/obfuscation-state"
LOCK_FILE="/var/run/netmaker-obfuscation.lock"

# Create state directory
mkdir -p "$(dirname "$OBFS_STATE_FILE")"

# Source configuration
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found!" >&2
    exit 1
fi
source "$CONFIG_FILE"

# Check if obfuscation is enabled
if [ "${ENABLE_OBFUSCATION:-false}" != "true" ]; then
    echo "Obfuscation disabled in configuration"
    exit 0
fi

# Lock file management
acquire_lock() {
    if ! mkdir "$LOCK_FILE" 2>/dev/null; then
        echo "Another obfuscation process is running (lock file exists)" >&2
        exit 1
    fi
    trap 'rm -rf "$LOCK_FILE"' EXIT
}

# Generate random MAC address (keeping OUI for realism)
generate_random_mac() {
    # Use a common OUI prefix to look like real hardware
    local oui_prefixes=("02:00:00" "06:00:00" "0a:00:00" "0e:00:00")
    local oui=${oui_prefixes[$RANDOM % ${#oui_prefixes[@]}]}
    
    # Generate random last 3 octets
    printf "%s:%02x:%02x:%02x" "$oui" $((RANDOM % 256)) $((RANDOM % 256)) $((RANDOM % 256))
}

# Get random VLAN from pool
get_random_vlan() {
    local vlan_array=(${VLAN_POOL//,/ })
    echo ${vlan_array[$RANDOM % ${#vlan_array[@]}]}
}

# Apply VLAN obfuscation
apply_vlan_obfuscation() {
    local interface="$1"
    local bridge="$2"
    
    if [ "${VLAN_OBFUSCATION:-false}" != "true" ]; then
        return 0
    fi
    
    local current_vlan=$(get_random_vlan)
    echo "Applying VLAN $current_vlan to interface $interface"
    
    # Set VLAN tag on the port
    if ovs-vsctl set port "$interface" tag="$current_vlan" 2>/dev/null; then
        echo "VLAN $current_vlan applied to $interface"
        echo "vlan_$interface=$current_vlan" >> "$OBFS_STATE_FILE"
    else
        echo "Warning: Failed to apply VLAN to $interface" >&2
    fi
}

# Apply MAC randomization
apply_mac_randomization() {
    local interface="$1"
    
    if [ "${MAC_RANDOMIZATION:-false}" != "true" ]; then
        return 0
    fi
    
    local new_mac=$(generate_random_mac)
    echo "Applying MAC $new_mac to interface $interface"
    
    # Change MAC address
    if ip link set dev "$interface" address "$new_mac" 2>/dev/null; then
        echo "MAC address changed to $new_mac for $interface"
        echo "mac_$interface=$new_mac" >> "$OBFS_STATE_FILE"
    else
        echo "Warning: Failed to change MAC address for $interface" >&2
    fi
}

# Apply basic timing obfuscation via QoS
apply_timing_obfuscation() {
    local interface="$1"
    local bridge="$2"
    
    if [ "${TIMING_OBFUSCATION:-false}" != "true" ]; then
        return 0
    fi
    
    local max_delay=${MAX_DELAY_MS:-50}
    local random_delay=$((RANDOM % max_delay + 10))  # 10-60ms range
    
    echo "Applying timing obfuscation (${random_delay}ms max delay) to $interface"
    
    # Create QoS rule with variable rate to introduce timing variation
    local base_rate=$((RANDOM % 50000000 + 50000000))  # 50-100 Mbps random base
    
    ovs-vsctl set interface "$interface" \
        ingress_policing_rate="$base_rate" \
        ingress_policing_burst="$((base_rate / 10))" 2>/dev/null || \
        echo "Warning: Failed to apply timing obfuscation to $interface" >&2
}

# Apply traffic shaping
apply_traffic_shaping() {
    local interface="$1"
    local bridge="$2"
    
    if [ "${TRAFFIC_SHAPING:-false}" != "true" ]; then
        return 0
    fi
    
    local rate_mbps=${SHAPING_RATE_MBPS:-100}
    local rate_bps=$((rate_mbps * 1000000))
    
    echo "Applying traffic shaping (${rate_mbps}Mbps) to $interface"
    
    # Apply rate limiting
    ovs-vsctl set interface "$interface" \
        ingress_policing_rate="$rate_bps" \
        ingress_policing_burst="$((rate_bps / 8))" 2>/dev/null || \
        echo "Warning: Failed to apply traffic shaping to $interface" >&2
}

# Main obfuscation function
apply_obfuscation() {
    local interface="$1"
    local bridge="$2"
    
    echo "Applying mild obfuscation to interface $interface on bridge $bridge"
    
    # Clear previous state for this interface
    if [ -f "$OBFS_STATE_FILE" ]; then
        grep -v "^[a-z]*_$interface=" "$OBFS_STATE_FILE" > "${OBFS_STATE_FILE}.tmp" || true
        mv "${OBFS_STATE_FILE}.tmp" "$OBFS_STATE_FILE" 2>/dev/null || true
    fi
    
    # Apply obfuscation techniques
    apply_vlan_obfuscation "$interface" "$bridge"
    apply_mac_randomization "$interface"
    apply_timing_obfuscation "$interface" "$bridge"
    apply_traffic_shaping "$interface" "$bridge"
    
    # Record timestamp
    echo "last_update_$interface=$(date +%s)" >> "$OBFS_STATE_FILE"
    
    echo "Obfuscation applied to $interface successfully"
}

# Rotation function for periodic updates
rotate_obfuscation() {
    local interface="$1"
    local bridge="$2"
    
    if [ ! -f "$OBFS_STATE_FILE" ]; then
        echo "No state file found, applying initial obfuscation"
        apply_obfuscation "$interface" "$bridge"
        return
    fi
    
    # Check if VLAN rotation is needed
    local vlan_interval=${VLAN_ROTATION_INTERVAL:-300}
    local mac_interval=${MAC_ROTATION_INTERVAL:-1800}
    local current_time=$(date +%s)
    
    # Get last update time
    local last_update=$(grep "^last_update_$interface=" "$OBFS_STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo "0")
    local time_since_update=$((current_time - last_update))
    
    # Rotate VLAN if interval exceeded
    if [ "$time_since_update" -gt "$vlan_interval" ] && [ "${VLAN_OBFUSCATION:-false}" = "true" ]; then
        echo "Rotating VLAN for $interface (${time_since_update}s since last update)"
        apply_vlan_obfuscation "$interface" "$bridge"
    fi
    
    # Rotate MAC if interval exceeded
    if [ "$time_since_update" -gt "$mac_interval" ] && [ "${MAC_RANDOMIZATION:-false}" = "true" ]; then
        echo "Rotating MAC for $interface (${time_since_update}s since last update)"
        apply_mac_randomization "$interface"
    fi
    
    # Update timestamp if any rotation occurred
    if [ "$time_since_update" -gt "$vlan_interval" ] || [ "$time_since_update" -gt "$mac_interval" ]; then
        sed -i "s/^last_update_$interface=.*/last_update_$interface=$current_time/" "$OBFS_STATE_FILE"
    fi
}

# Remove obfuscation from interface
remove_obfuscation() {
    local interface="$1"
    local bridge="$2"
    
    echo "Removing obfuscation from interface $interface"
    
    # Clear VLAN tag
    ovs-vsctl remove port "$interface" tag 2>/dev/null || true
    
    # Clear QoS settings
    ovs-vsctl clear interface "$interface" ingress_policing_rate 2>/dev/null || true
    ovs-vsctl clear interface "$interface" ingress_policing_burst 2>/dev/null || true
    
    # Clean up state file
    if [ -f "$OBFS_STATE_FILE" ]; then
        grep -v "_$interface=" "$OBFS_STATE_FILE" > "${OBFS_STATE_FILE}.tmp" || true
        mv "${OBFS_STATE_FILE}.tmp" "$OBFS_STATE_FILE" 2>/dev/null || true
    fi
    
    echo "Obfuscation removed from $interface"
}

# Command handling
case "${1:-}" in
    "apply")
        if [ $# -lt 3 ]; then
            echo "Usage: $0 apply <interface> <bridge>" >&2
            exit 1
        fi
        acquire_lock
        apply_obfuscation "$2" "$3"
        ;;
    "rotate")
        if [ $# -lt 3 ]; then
            echo "Usage: $0 rotate <interface> <bridge>" >&2
            exit 1
        fi
        acquire_lock
        rotate_obfuscation "$2" "$3"
        ;;
    "remove")
        if [ $# -lt 3 ]; then
            echo "Usage: $0 remove <interface> <bridge>" >&2
            exit 1
        fi
        acquire_lock
        remove_obfuscation "$2" "$3"
        ;;
    "daemon")
        # Daemon mode for continuous rotation
        echo "Starting obfuscation daemon..."
        while true; do
            # Find all netmaker interfaces and rotate obfuscation
            if [ -n "${BRIDGE_NAME:-}" ] && ovs-vsctl br-exists "$BRIDGE_NAME" 2>/dev/null; then
                ovs-vsctl list-ports "$BRIDGE_NAME" 2>/dev/null | while read -r port; do
                    if [[ "$port" =~ ${NM_INTERFACE_PATTERN:-nm-} ]]; then
                        acquire_lock
                        rotate_obfuscation "$port" "$BRIDGE_NAME"
                        rm -rf "$LOCK_FILE"
                    fi
                done
            fi
            
            # Sleep for minimum rotation interval
            local min_interval=${VLAN_ROTATION_INTERVAL:-300}
            local mac_interval=${MAC_ROTATION_INTERVAL:-1800}
            local sleep_time=$((min_interval < mac_interval ? min_interval : mac_interval))
            sleep "$((sleep_time / 4))"  # Check 4x more frequently than rotation
        done
        ;;
    *)
        echo "Usage: $0 {apply|rotate|remove|daemon} <interface> <bridge>"
        echo "       $0 daemon  # Run in daemon mode for automatic rotation"
        exit 1
        ;;
esac