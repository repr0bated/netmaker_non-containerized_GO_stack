#!/bin/bash
set -euo pipefail

# This script must be run as root/sudo
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo." >&2
    exit 1
fi

# Check if pre-install was run
if [ ! -d "/tmp/netmaker-ovs-backup-"* ] 2>/dev/null; then
    echo "WARNING: Pre-installation script has not been run."
    echo "It is strongly recommended to run './pre-install.sh' first to:"
    echo "  - Check for conflicts"
    echo "  - Backup existing configuration"
    echo "  - Ensure system readiness"
    echo ""
    echo "Alternatively, use './install-interactive.sh' for guided setup with auto-detection."
    echo ""
    read -p "Do you want to continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled. Please run './pre-install.sh' or './install-interactive.sh' first."
        exit 1
    fi
fi

echo "=== Netmaker OpenVSwitch Integration Setup ==="

# Configuration
# Determine the directory where this install.sh script is located
# Fallback to current directory if readlink -f fails (e.g. on macOS without coreutils)
INSTALL_SCRIPT_PATH=$(readlink -f "$0" || realpath "$0" || echo "$0")
INSTALL_BASE_DIR=$(dirname "$INSTALL_SCRIPT_PATH")

SCRIPTS_DIR="$INSTALL_BASE_DIR/scripts"
CONFIG_DIR="$INSTALL_BASE_DIR/config"
SYSTEMD_DIR="$INSTALL_BASE_DIR/systemd"

DEST_BIN_DIR="/usr/local/bin"
DEST_CONFIG_DIR="/etc/netmaker"
DEST_SYSTEMD_DIR="/etc/systemd/system"
DOC_DIR="/usr/share/doc/netmaker-ovs-integration"


OVS_CONFIG_FILE_NAME="ovs-config"
ADD_SCRIPT_NAME="netmaker-ovs-bridge-add.sh"
REMOVE_SCRIPT_NAME="netmaker-ovs-bridge-remove.sh"
OBFS_SCRIPT_NAME="obfuscation-manager.sh"
SERVICE_NAME="netmaker-ovs-bridge.service"
OBFS_SERVICE_NAME="netmaker-obfuscation-daemon.service"
README_NAME="README.md"

# First, stop and disable any existing services to ensure a clean install
echo "Stopping and disabling any existing services..."
systemctl stop "$SERVICE_NAME" 2>/dev/null || true # Ignore error if service doesn't exist
systemctl disable "$SERVICE_NAME" 2>/dev/null || true # Ignore error
systemctl stop "$OBFS_SERVICE_NAME" 2>/dev/null || true # Ignore error if service doesn't exist
systemctl disable "$OBFS_SERVICE_NAME" 2>/dev/null || true # Ignore error

# Remove any existing files to prevent conflicts
echo "Removing any old installed files..."
rm -f "$DEST_BIN_DIR/$ADD_SCRIPT_NAME"
rm -f "$DEST_BIN_DIR/$REMOVE_SCRIPT_NAME"
rm -f "$DEST_BIN_DIR/$OBFS_SCRIPT_NAME"
rm -f "$DEST_SYSTEMD_DIR/$SERVICE_NAME"
rm -f "$DEST_SYSTEMD_DIR/$OBFS_SERVICE_NAME"
rm -f "$DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME"
rm -f "$DOC_DIR/$README_NAME"
rmdir "$DOC_DIR" 2>/dev/null || true


# Create directories if they don't exist
echo "Creating target directories..."
mkdir -p "$DEST_CONFIG_DIR"
mkdir -p "$DEST_BIN_DIR"
mkdir -p "$DEST_SYSTEMD_DIR" # Though systemd dir usually exists
mkdir -p "$DOC_DIR"

# Check if source files exist
if [ ! -f "$CONFIG_DIR/$OVS_CONFIG_FILE_NAME" ] || \
   [ ! -f "$SCRIPTS_DIR/$ADD_SCRIPT_NAME" ] || \
   [ ! -f "$SCRIPTS_DIR/$REMOVE_SCRIPT_NAME" ] || \
   [ ! -f "$SCRIPTS_DIR/$OBFS_SCRIPT_NAME" ] || \
   [ ! -f "$SYSTEMD_DIR/$SERVICE_NAME" ] || \
   [ ! -f "$SYSTEMD_DIR/$OBFS_SERVICE_NAME" ] || \
   [ ! -f "$INSTALL_BASE_DIR/$README_NAME" ]; then
    echo "Error: One or more source files are missing from the repository structure." >&2
    echo "Please ensure the following files exist relative to install.sh:" >&2
    echo "  config/$OVS_CONFIG_FILE_NAME" >&2
    echo "  scripts/$ADD_SCRIPT_NAME" >&2
    echo "  scripts/$REMOVE_SCRIPT_NAME" >&2
    echo "  scripts/$OBFS_SCRIPT_NAME" >&2
    echo "  systemd/$SERVICE_NAME" >&2
    echo "  systemd/$OBFS_SERVICE_NAME" >&2
    echo "  $README_NAME (in the root of the repository)" >&2
    exit 1
fi


# Copy configuration file
echo "Copying configuration file to $DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME..."
cp "$CONFIG_DIR/$OVS_CONFIG_FILE_NAME" "$DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME"

# Copy scripts
echo "Copying scripts to $DEST_BIN_DIR..."
cp "$SCRIPTS_DIR/$ADD_SCRIPT_NAME" "$DEST_BIN_DIR/$ADD_SCRIPT_NAME"
cp "$SCRIPTS_DIR/$REMOVE_SCRIPT_NAME" "$DEST_BIN_DIR/$REMOVE_SCRIPT_NAME"
cp "$SCRIPTS_DIR/$OBFS_SCRIPT_NAME" "$DEST_BIN_DIR/$OBFS_SCRIPT_NAME"

# Copy systemd service files
echo "Copying systemd service files to $DEST_SYSTEMD_DIR..."
cp "$SYSTEMD_DIR/$SERVICE_NAME" "$DEST_SYSTEMD_DIR/$SERVICE_NAME"
cp "$SYSTEMD_DIR/$OBFS_SERVICE_NAME" "$DEST_SYSTEMD_DIR/$OBFS_SERVICE_NAME"

# Copy README for documentation
echo "Copying README.md to $DOC_DIR..."
cp "$INSTALL_BASE_DIR/$README_NAME" "$DOC_DIR/$README_NAME"


# Set permissions
echo "Setting permissions..."
chmod 755 "$DEST_BIN_DIR/$ADD_SCRIPT_NAME"
chmod 755 "$DEST_BIN_DIR/$REMOVE_SCRIPT_NAME"
chmod 755 "$DEST_BIN_DIR/$OBFS_SCRIPT_NAME"
chmod 644 "$DEST_SYSTEMD_DIR/$SERVICE_NAME"
chmod 644 "$DEST_SYSTEMD_DIR/$OBFS_SERVICE_NAME"
chmod 644 "$DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME" # Config should be readable by root
chmod 644 "$DOC_DIR/$README_NAME"


# Create OVS bridge if it doesn't exist (using BRIDGE_NAME from the copied config)
# Load the config to get BRIDGE_NAME
if [ -f "$DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME" ]; then
    # Source the config in a subshell to avoid polluting current environment if variables clash
    (
        source "$DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME"
        if [ -n "$BRIDGE_NAME" ]; then
            echo "Checking OVS bridge '$BRIDGE_NAME'..."
            if ! ovs-vsctl br-exists "$BRIDGE_NAME"; then
                echo "Creating OVS bridge '$BRIDGE_NAME'..."
                if ovs-vsctl add-br "$BRIDGE_NAME"; then
                    echo "OVS bridge '$BRIDGE_NAME' created."
                else
                    echo "Warning: Failed to create OVS bridge '$BRIDGE_NAME'. Please create it manually." >&2
                fi
            else
                echo "OVS bridge '$BRIDGE_NAME' already exists."
            fi
        else
            echo "Warning: BRIDGE_NAME not found in $DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME. Skipping bridge check/creation." >&2
        fi
    )
else
    echo "Warning: Configuration file $DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME not found. Skipping bridge check/creation." >&2
fi

# Create obfuscation state directory
echo "Creating obfuscation state directory..."
mkdir -p /var/lib/netmaker
chown root:root /var/lib/netmaker
chmod 755 /var/lib/netmaker

# Reload systemd daemon, enable and start the services
echo "Reloading systemd daemon, enabling and starting services..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# Check if obfuscation is enabled before starting daemon
source "$DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME"
if [ "${ENABLE_OBFUSCATION:-false}" = "true" ]; then
    echo "Obfuscation enabled, starting obfuscation daemon..."
    systemctl enable "$OBFS_SERVICE_NAME"
    systemctl start "$OBFS_SERVICE_NAME"
else
    echo "Obfuscation disabled in configuration"
fi

echo ""
echo "=== Installation Complete ==="
echo "Netmaker OpenVSwitch Integration with mild obfuscation has been installed and started."
echo "Configuration file: $DEST_CONFIG_DIR/$OVS_CONFIG_FILE_NAME"
echo "Scripts installed in: $DEST_BIN_DIR"
echo "Documentation: $DOC_DIR/$README_NAME"
echo ""
echo "Services status:"
echo "  Main service: systemctl status $SERVICE_NAME"
if [ "${ENABLE_OBFUSCATION:-false}" = "true" ]; then
    echo "  Obfuscation daemon: systemctl status $OBFS_SERVICE_NAME"
fi
echo ""
echo "To see logs, run:"
echo "  journalctl -u $SERVICE_NAME"
if [ "${ENABLE_OBFUSCATION:-false}" = "true" ]; then
    echo "  journalctl -u $OBFS_SERVICE_NAME"
fi
echo ""
echo "Obfuscation features enabled:"
if [ "${ENABLE_OBFUSCATION:-false}" = "true" ]; then
    echo "  ✓ VLAN rotation every ${VLAN_ROTATION_INTERVAL:-300} seconds"
    echo "  ✓ MAC randomization every ${MAC_ROTATION_INTERVAL:-1800} seconds"
    echo "  ✓ Basic timing obfuscation (max ${MAX_DELAY_MS:-50}ms delay)"
    echo "  ✓ Traffic shaping at ${SHAPING_RATE_MBPS:-100}Mbps"
else
    echo "  ✗ Obfuscation disabled (set ENABLE_OBFUSCATION=true to enable)"
fi
echo ""
echo "Please ensure your Netmaker client service (e.g., netmaker or netclient) is running."
echo "The integration service will add Netmaker interfaces to OVS bridge with mild obfuscation."
