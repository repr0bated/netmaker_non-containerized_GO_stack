# Helper Tools and Utilities

This directory contains specialized tools and utilities to support Netmaker OVS integration deployment, particularly for Proxmox VE environments and troubleshooting scenarios.

## Available Tools

### 🏢 **configure-ovs-proxmox.sh**
**Proxmox VE OpenVSwitch Configuration Tool**

Automated script for setting up OpenVSwitch networking on Proxmox VE hosts with proper bridge configuration and container integration.

**Features:**
- Automatic Proxmox VE detection and configuration
- OVS bridge creation with proper naming conventions
- Container network interface configuration
- VLAN setup and management
- Integration with Proxmox web interface

**Usage:**
```bash
sudo ./tools/configure-ovs-proxmox.sh
```

**Prerequisites:**
- Proxmox VE 7.0 or later
- OpenVSwitch packages installed
- Root access to Proxmox host

**Configuration Options:**
- Bridge naming (ovsbr0, ovsbr1, etc.)
- VLAN configuration for tenant isolation
- Container network assignment
- Gateway and DNS configuration

---

### 🛠️ **working-ovs-config.sh**
**OVS Configuration Validation and Setup Helper**

Comprehensive tool for validating and configuring OpenVSwitch setups with support for various network topologies and configurations.

**Features:**
- OVS installation verification
- Bridge configuration validation
- Port assignment and VLAN setup
- Network connectivity testing
- Configuration backup and restore

**Usage:**
```bash
sudo ./tools/working-ovs-config.sh [options]
```

**Options:**
- `--validate` - Check existing OVS configuration
- `--setup` - Create new OVS bridges and ports
- `--backup` - Backup current configuration
- `--restore` - Restore from backup

**Integration:**
- Compatible with Netmaker OVS integration
- Supports obfuscation VLAN pools
- Validates network reachability

---

### 📦 **reconfigure-container-networking.sh**
**Container Network Reconfiguration Tool**

Specialized tool for reconfiguring LXC container networking in Proxmox VE environments, particularly useful for updating container network assignments.

**Features:**
- LXC container network interface reconfiguration
- Automatic container service management
- Network bridge migration
- IP address reassignment
- Container restart coordination

**Usage:**
```bash
sudo ./tools/reconfigure-container-networking.sh <container-id> [options]
```

**Options:**
- `--bridge <bridge-name>` - Target bridge for migration
- `--ip <ip-address>` - New IP address assignment
- `--vlan <vlan-id>` - VLAN tag assignment
- `--dry-run` - Preview changes without applying

**Example:**
```bash
# Migrate container 100 to ovsbr0 with new IP
sudo ./tools/reconfigure-container-networking.sh 100 --bridge ovsbr0 --ip 10.0.0.101/24
```

---

### 📡 **fix-mosquitto-lxc.sh**
**Mosquitto MQTT Broker LXC Configuration Fix**

Specialized tool for fixing Mosquitto MQTT broker connectivity issues in LXC containers, addressing the common binding and connectivity problems identified in the GhostBridge project.

**Features:**
- Mosquitto configuration file correction
- Binding address fixes (0.0.0.0 vs 127.0.0.1)
- Port configuration for TCP (1883) and WebSocket (9001)
- Service restart and validation
- Connection testing

**Usage:**
```bash
sudo ./tools/fix-mosquitto-lxc.sh [container-id]
```

**Fixes Applied:**
- Updates mosquitto.conf for proper binding
- Configures both TCP and WebSocket listeners
- Sets appropriate logging levels
- Validates service startup

**Integration with GhostBridge:**
- Resolves "Fatal: could not connect to broker, token timeout" errors
- Enables proper Netmaker-Mosquitto communication
- Supports both containerized and host deployments

## Tool Integration Matrix

| Tool | Proxmox | OVS | LXC | Netmaker | Obfuscation |
|------|---------|-----|-----|----------|-------------|
| **configure-ovs-proxmox.sh** | ✅ Primary | ✅ Setup | ✅ Integration | ⚠️ Compatible | ✅ VLAN Support |
| **working-ovs-config.sh** | ⚠️ Compatible | ✅ Primary | ❌ N/A | ✅ Integration | ✅ Full Support |
| **reconfigure-container-networking.sh** | ✅ Primary | ✅ Bridge Migration | ✅ Primary | ⚠️ Compatible | ⚠️ Basic |
| **fix-mosquitto-lxc.sh** | ✅ LXC Support | ❌ N/A | ✅ Primary | ✅ MQTT Fix | ❌ N/A |

## Usage Scenarios

### 🚀 **Initial Proxmox VE Setup**
```bash
# 1. Configure OVS on Proxmox host
sudo ./tools/configure-ovs-proxmox.sh

# 2. Validate OVS configuration
sudo ./tools/working-ovs-config.sh --validate

# 3. Set up container networking
sudo ./tools/reconfigure-container-networking.sh 100 --bridge ovsbr0

# 4. Fix Mosquitto if needed
sudo ./tools/fix-mosquitto-lxc.sh 100
```

### 🔧 **Migration and Updates**
```bash
# 1. Backup current configuration
sudo ./tools/working-ovs-config.sh --backup

# 2. Reconfigure container networking
sudo ./tools/reconfigure-container-networking.sh 100 --bridge new-bridge

# 3. Validate new setup
sudo ./tools/working-ovs-config.sh --validate
```

### 🛠️ **Troubleshooting**
```bash
# 1. Check OVS configuration
sudo ./tools/working-ovs-config.sh --validate

# 2. Fix MQTT connectivity
sudo ./tools/fix-mosquitto-lxc.sh

# 3. Reconfigure networking if needed
sudo ./tools/reconfigure-container-networking.sh 100 --dry-run
```

## Integration with Main Installation

### 🔗 **Pre-Installation Use**
These tools can be used before running the main installation to prepare the environment:

```bash
# Prepare Proxmox environment
sudo ./tools/configure-ovs-proxmox.sh

# Run main installation
sudo ./install-interactive.sh
```

### 🔄 **Post-Installation Maintenance**
Tools can be used for ongoing maintenance and troubleshooting:

```bash
# After installation, if issues arise
sudo ./tools/fix-mosquitto-lxc.sh
sudo ./tools/working-ovs-config.sh --validate
```

## Tool Dependencies

### 📋 **System Requirements**
- **Linux Distribution**: Ubuntu 20.04+, Debian 11+, Proxmox VE 7.0+
- **Root Access**: All tools require sudo/root privileges
- **Network Tools**: iproute2, bridge-utils installed

### 📦 **Package Dependencies**
```bash
# Common dependencies
apt install iproute2 bridge-utils net-tools

# For Proxmox tools
apt install pve-manager openvswitch-switch

# For container tools
apt install lxc-utils

# For MQTT tools
apt install mosquitto mosquitto-clients
```

## Configuration Examples

### 🏢 **Proxmox VE Integration**
```bash
# Example: Set up dual-bridge configuration
sudo ./tools/configure-ovs-proxmox.sh \
  --primary-bridge ovsbr0 \
  --secondary-bridge ovsbr1 \
  --vlan-range 100-500
```

### 📦 **Container Migration**
```bash
# Example: Migrate container to obfuscation-ready bridge
sudo ./tools/reconfigure-container-networking.sh 100 \
  --bridge ovsbr0 \
  --ip 10.0.0.101/24 \
  --vlan 100 \
  --gateway 10.0.0.1
```

### 📡 **MQTT Configuration**
```bash
# Example: Fix Mosquitto for both TCP and WebSocket
sudo ./tools/fix-mosquitto-lxc.sh 100 \
  --tcp-port 1883 \
  --websocket-port 9001 \
  --bind-all-interfaces
```

## Security Considerations

### 🔐 **Access Control**
- All tools require root/sudo access
- Scripts validate permissions before execution
- Configuration changes are logged

### 🛡️ **Network Security**
- Tools respect existing firewall configurations
- VLAN isolation maintained during reconfiguration
- Secure defaults applied to new configurations

### 📝 **Audit Trail**
- All configuration changes are logged
- Backup files created before modifications
- Rollback capability provided where possible

## Troubleshooting Tool Issues

### 🔍 **Common Problems**

#### **Permission Errors**
```bash
# Ensure proper permissions
sudo chmod +x tools/*.sh
sudo chown root:root tools/*.sh
```

#### **Missing Dependencies**
```bash
# Install required packages
sudo apt update
sudo apt install openvswitch-switch bridge-utils lxc-utils
```

#### **Configuration Conflicts**
```bash
# Check for conflicting configurations
sudo ./tools/working-ovs-config.sh --validate
```

### 📊 **Validation and Testing**
```bash
# Test tool functionality
sudo ./tools/working-ovs-config.sh --test
sudo ./tools/configure-ovs-proxmox.sh --dry-run
```

## Best Practices

### 📋 **Pre-Execution**
1. **Backup configurations** before running tools
2. **Test in lab environment** before production use
3. **Review tool options** and understand impact
4. **Ensure console access** for recovery

### 🔄 **During Execution**
1. **Monitor tool output** for errors or warnings
2. **Validate each step** before proceeding
3. **Document changes** made by tools
4. **Test connectivity** after modifications

### ✅ **Post-Execution**
1. **Verify tool results** meet expectations
2. **Test system functionality** thoroughly
3. **Update documentation** with any changes
4. **Create recovery plan** if needed

These tools provide comprehensive support for deploying and maintaining Netmaker OVS integration across various infrastructure scenarios, with particular strength in Proxmox VE environments and troubleshooting complex networking issues.