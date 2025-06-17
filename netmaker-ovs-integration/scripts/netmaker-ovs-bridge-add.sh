#!/bin/bash
set -euo pipefail

# Source configuration
CONFIG_FILE="/etc/netmaker/ovs-config"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE not found!" >&2
    exit 1
fi
source "$CONFIG_FILE"

# Check if OVS bridge name is set
if [ -z "$BRIDGE_NAME" ]; then
    echo "BRIDGE_NAME is not set in $CONFIG_FILE!" >&2
    exit 1
fi

# Check if Netmaker interface pattern is set
if [ -z "$NM_INTERFACE_PATTERN" ]; then
    echo "NM_INTERFACE_PATTERN is not set in $CONFIG_FILE!" >&2
    exit 1
fi

# Check if bridge exists
if ! ovs-vsctl br-exists "$BRIDGE_NAME"; then
    echo "OVS Bridge $BRIDGE_NAME does not exist! Please create it first, or ensure the install script creates it." >&2
    # Attempt to create the bridge if it's missing (optional, uncomment if desired)
    # echo "Attempting to create OVS bridge $BRIDGE_NAME..."
    # if sudo ovs-vsctl add-br "$BRIDGE_NAME"; then
    #   echo "OVS bridge $BRIDGE_NAME created."
    # else
    #   echo "Failed to create OVS bridge $BRIDGE_NAME. Exiting." >&2
    #   exit 1
    # fi
    exit 1 # Exit if bridge doesn't exist and we are not auto-creating it.
fi

# Wait for netmaker interface to be available (with timeout)
TIMEOUT=60 # Increased timeout for slower interface bring-up
COUNTER=0
echo "Waiting for Netmaker interface matching pattern '$NM_INTERFACE_PATTERN'..."
NM_IFACE=""
while [ $COUNTER -lt $TIMEOUT ]; do
    # Using 'ip -o link' for more robust parsing if multiple interfaces match pattern (takes the first one)
    # Grep for pattern and ensure it's not already a bridge or part of OVS internal ports.
    NM_IFACE=$(ip -o link show | grep -Eo "$NM_INTERFACE_PATTERN[^:]*" | head -n 1)
    if [ -n "$NM_IFACE" ]; then
        echo "Found potential Netmaker interface: $NM_IFACE"
        break
    fi
    sleep 1
    COUNTER=$((COUNTER + 1))
done

if [ -z "$NM_IFACE" ]; then
    echo "No Netmaker interface found matching pattern '$NM_INTERFACE_PATTERN' after $TIMEOUT seconds."
    exit 0 # Exit gracefully, maybe Netmaker is not active or no such interface
fi

# Check if interface is already in bridge
if ovs-vsctl list-ports "$BRIDGE_NAME" | grep -q "^${NM_IFACE}$"; then
    echo "Interface $NM_IFACE is already part of bridge $BRIDGE_NAME."
else
    echo "Adding interface $NM_IFACE to OVS bridge $BRIDGE_NAME..."
    if sudo ovs-vsctl --may-exist add-port "$BRIDGE_NAME" "$NM_IFACE"; then
        echo "Interface $NM_IFACE added to $BRIDGE_NAME."
        # Common OVS port settings for VMs, adjust if needed
        # sudo ovs-vsctl set port "$NM_IFACE" vlan_mode=native-untagged # Example, adjust as per your network design
    else
        echo "Failed to add interface $NM_IFACE to $BRIDGE_NAME." >&2
        # Optionally, exit 1 here if adding the port is critical
    fi
fi

# Ensure interface is up
echo "Bringing up interface $NM_IFACE..."
if sudo ip link set "$NM_IFACE" up; then
    echo "$NM_IFACE is up."
else
    echo "Failed to bring up interface $NM_IFACE." >&2
fi

# Apply obfuscation if enabled
OBFS_SCRIPT="/usr/local/bin/obfuscation-manager.sh"
if [ -x "$OBFS_SCRIPT" ] && [ "${ENABLE_OBFUSCATION:-false}" = "true" ]; then
    echo "Applying mild obfuscation to $NM_IFACE..."
    if "$OBFS_SCRIPT" apply "$NM_IFACE" "$BRIDGE_NAME"; then
        echo "Obfuscation applied successfully to $NM_IFACE"
    else
        echo "Warning: Failed to apply obfuscation to $NM_IFACE" >&2
    fi
fi

echo "Netmaker OVS bridge add script completed for $NM_IFACE."
exit 0
