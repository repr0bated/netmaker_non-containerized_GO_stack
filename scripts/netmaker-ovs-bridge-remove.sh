#!/bin/bash
set -euo pipefail

# Source configuration
CONFIG_FILE="/etc/netmaker/ovs-config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found!" >&2
    # Don't exit 1 here, as this script might be called during uninstall
    # when the config is already removed.
    # Try to proceed if BRIDGE_NAME and NM_INTERFACE_PATTERN are passed as arguments or defaults.
fi
source "$CONFIG_FILE" 2>/dev/null || true # Source if exists, ignore errors

# Use environment variables if set (e.g. by systemd), otherwise from config
BRIDGE_NAME="${BRIDGE_NAME:-ovsbr0}" # Default if not set
NM_INTERFACE_PATTERN="${NM_INTERFACE_PATTERN:-nm-*}" # Default if not set


# Check if OVS bridge name is available
if [ -z "$BRIDGE_NAME" ]; then
    echo "BRIDGE_NAME is not set (checked $CONFIG_FILE and environment)!" >&2
    exit 1
fi

# Check if Netmaker interface pattern is available
if [ -z "$NM_INTERFACE_PATTERN" ]; then
    echo "NM_INTERFACE_PATTERN is not set (checked $CONFIG_FILE and environment)!" >&2
    exit 1
fi

# Find Netmaker interfaces currently in the bridge
# This is safer on shutdown, as the interface might already be down or gone.
echo "Checking for Netmaker interfaces in bridge $BRIDGE_NAME matching pattern $NM_INTERFACE_PATTERN..."
INTERFACES_TO_REMOVE=""
if ovs-vsctl br-exists "$BRIDGE_NAME"; then
    INTERFACES_TO_REMOVE=$(ovs-vsctl list-ports "$BRIDGE_NAME" | grep "$NM_INTERFACE_PATTERN" || true)
fi

if [ -z "$INTERFACES_TO_REMOVE" ]; then
    echo "No Netmaker interfaces found in bridge $BRIDGE_NAME matching the pattern."
else
    for NM_IFACE_REMOVE in $INTERFACES_TO_REMOVE; do
        echo "Removing interface $NM_IFACE_REMOVE from OVS bridge $BRIDGE_NAME..."
        if sudo ovs-vsctl --if-exists del-port "$BRIDGE_NAME" "$NM_IFACE_REMOVE"; then
            echo "Interface $NM_IFACE_REMOVE removed from $BRIDGE_NAME."
            
            # Remove obfuscation if enabled
            OBFS_SCRIPT="/usr/local/bin/obfuscation-manager.sh"
            if [ -x "$OBFS_SCRIPT" ] && [ "${ENABLE_OBFUSCATION:-false}" = "true" ]; then
                echo "Removing obfuscation from $NM_IFACE_REMOVE..."
                if "$OBFS_SCRIPT" remove "$NM_IFACE_REMOVE" "$BRIDGE_NAME"; then
                    echo "Obfuscation removed from $NM_IFACE_REMOVE"
                else
                    echo "Warning: Failed to remove obfuscation from $NM_IFACE_REMOVE" >&2
                fi
            fi
        else
            echo "Failed to remove interface $NM_IFACE_REMOVE from $BRIDGE_NAME (it might have already been removed)." >&2
        fi
    done
fi

echo "Netmaker OVS bridge remove script completed."
exit 0
