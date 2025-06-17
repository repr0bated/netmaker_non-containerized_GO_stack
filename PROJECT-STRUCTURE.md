# Netmaker OVS Integration - Project Structure

## Overview

This project provides a comprehensive solution for integrating Netmaker mesh networking with OpenVSwitch, enhanced with mild obfuscation features for privacy protection. The codebase includes automated installation, configuration management, and extensive documentation.

## Directory Structure

```
netmaker-ovs-integration/
├── 📄 README.md                              # Main project documentation
├── 📄 DEPLOYMENT-GUIDE.md                    # Comprehensive deployment guide
├── 📄 INTERACTIVE-FEATURES.md                # Interactive installer documentation
├── 📄 README-OBFUSCATION.md                  # Technical obfuscation details
├── 📄 PROJECT-STRUCTURE.md                   # This file
├── 📄 .gitignore                             # Git ignore patterns
│
├── 🔧 Installation Scripts
│   ├── 📄 install-interactive.sh             # Interactive guided installer (RECOMMENDED)
│   ├── 📄 install.sh                         # Standard installer
│   ├── 📄 pre-install.sh                     # Pre-installation cleanup & validation
│   └── 📄 uninstall.sh                       # Complete uninstaller with rollback
│
├── ⚙️ config/
│   └── 📄 ovs-config                         # Main configuration file with obfuscation settings
│
├── 🔨 scripts/
│   ├── 📄 netmaker-ovs-bridge-add.sh         # Add Netmaker interfaces to OVS bridge
│   ├── 📄 netmaker-ovs-bridge-remove.sh      # Remove interfaces and cleanup
│   └── 📄 obfuscation-manager.sh             # Core obfuscation management logic
│
├── 🏃 systemd/
│   ├── 📄 netmaker-ovs-bridge.service        # Main integration service
│   └── 📄 netmaker-obfuscation-daemon.service # Obfuscation rotation daemon
│
├── 📚 docs/                                  # Technical documentation
│   ├── 📄 DETECTION-RESISTANCE-DEEP-DIVE.md  # Advanced detection resistance techniques
│   ├── 📄 OVERHEAD-COST-ANALYSIS.md          # Performance impact analysis
│   ├── 📄 OVS-OBFUSCATION-ANALYSIS.md        # Comprehensive obfuscation analysis
│   └── 📄 PROXMOX-SPECIFIC-ANALYSIS.md       # Proxmox VE integration specifics
│
├── 💡 examples/                              # Configuration examples
│   ├── 📄 interfaces-ovs-corrected           # Corrected OVS interfaces file
│   └── 📄 interfaces-standard                # Standard network interfaces example
│
├── 🛠️ tools/                                 # Helper tools and utilities
│   ├── 📄 configure-ovs-proxmox.sh           # Proxmox OVS configuration tool
│   ├── 📄 fix-mosquitto-lxc.sh               # Mosquitto MQTT broker fix for LXC
│   ├── 📄 reconfigure-container-networking.sh # Container network reconfiguration
│   └── 📄 working-ovs-config.sh              # Working OVS configuration helper
│
└── 📖 reference/                             # Background and reference materials
    ├── 📄 GHOSTBRIDGE-PROJECT-CONTEXT.md     # Original project context and requirements
    └── 📄 enhanced-integration-analysis.md   # Integration analysis and recommendations
```

## Component Overview

### 🚀 Installation Components

#### **install-interactive.sh** (RECOMMENDED)
- **Purpose**: Guided interactive installation with auto-detection
- **Features**: 
  - Automatic system configuration detection
  - Intelligent recommendations based on resources
  - Step-by-step configuration with validation
  - Visual interface with color-coded output
- **Use Case**: Primary installation method for all users

#### **pre-install.sh**
- **Purpose**: Pre-installation validation and cleanup
- **Features**:
  - Conflict detection and resolution
  - System readiness validation
  - Configuration backup creation
  - Network state cleanup
- **Use Case**: Ensures clean installation environment

#### **install.sh**
- **Purpose**: Standard non-interactive installer
- **Features**:
  - Uses existing configuration files
  - Batch installation capability
  - Service deployment and configuration
- **Use Case**: Automated deployments, CI/CD pipelines

#### **uninstall.sh**
- **Purpose**: Complete system removal and rollback
- **Features**:
  - Service shutdown and removal
  - Configuration cleanup
  - Optional backup restoration
  - System state verification
- **Use Case**: Clean removal or migration preparation

### ⚙️ Configuration Management

#### **config/ovs-config**
- **Purpose**: Central configuration file for all components
- **Contains**:
  - Bridge and interface settings
  - Obfuscation parameters
  - Performance tuning options
  - Feature enable/disable flags
- **Customization**: Modified by interactive installer or manually

### 🔨 Core Scripts

#### **obfuscation-manager.sh**
- **Purpose**: Core obfuscation logic and management
- **Features**:
  - VLAN rotation management
  - MAC address randomization
  - Timing obfuscation control
  - Traffic shaping configuration
  - Daemon mode for continuous operation
- **Modes**: apply, remove, rotate, daemon

#### **netmaker-ovs-bridge-add.sh**
- **Purpose**: Integrate Netmaker interfaces with OVS
- **Features**:
  - Interface detection and validation
  - OVS bridge integration
  - Automatic obfuscation application
  - Error handling and logging

#### **netmaker-ovs-bridge-remove.sh**
- **Purpose**: Clean removal of Netmaker integration
- **Features**:
  - Interface removal from bridges
  - Obfuscation cleanup
  - State file management
  - Graceful degradation

### 🏃 System Services

#### **netmaker-ovs-bridge.service**
- **Purpose**: Main integration service
- **Dependencies**: networking, openvswitch-switch, netmaker
- **Function**: Monitors for Netmaker interfaces and integrates them
- **Triggers**: Interface creation/removal events

#### **netmaker-obfuscation-daemon.service**
- **Purpose**: Continuous obfuscation management
- **Function**: Rotates obfuscation parameters on schedule
- **Resource Limits**: CPU and memory constrained for stability
- **Conditional**: Only runs when obfuscation is enabled

### 📚 Documentation

#### **Technical Documentation (docs/)**
- **DETECTION-RESISTANCE-DEEP-DIVE.md**: Advanced evasion techniques
- **OVERHEAD-COST-ANALYSIS.md**: Performance impact quantification  
- **OVS-OBFUSCATION-ANALYSIS.md**: Comprehensive obfuscation analysis
- **PROXMOX-SPECIFIC-ANALYSIS.md**: Proxmox VE integration details

#### **User Documentation**
- **DEPLOYMENT-GUIDE.md**: Step-by-step deployment instructions
- **INTERACTIVE-FEATURES.md**: Interactive installer feature overview
- **README-OBFUSCATION.md**: Obfuscation technical implementation

### 💡 Examples

#### **Network Configuration Examples**
- **interfaces-ovs-corrected**: Proper OVS interfaces configuration
- **interfaces-standard**: Standard Linux bridge configuration
- **Purpose**: Reference implementations and troubleshooting guides

### 🛠️ Helper Tools

#### **Proxmox-Specific Tools**
- **configure-ovs-proxmox.sh**: Proxmox OVS setup automation
- **reconfigure-container-networking.sh**: LXC container network management
- **fix-mosquitto-lxc.sh**: Mosquitto MQTT broker LXC fixes

#### **Configuration Tools**
- **working-ovs-config.sh**: OVS configuration validation and setup

### 📖 Reference Materials

#### **Project Context**
- **GHOSTBRIDGE-PROJECT-CONTEXT.md**: Original project requirements
- **enhanced-integration-analysis.md**: Design decisions and analysis

## Usage Patterns

### 🎯 Standard Deployment
```bash
# 1. Interactive installation (recommended)
sudo ./install-interactive.sh

# 2. Manual installation with pre-checks
sudo ./pre-install.sh
sudo ./install.sh

# 3. Quick installation (not recommended)
sudo ./install.sh
```

### 🔧 Configuration Management
```bash
# View current configuration
cat /etc/netmaker/ovs-config

# Manual obfuscation control
sudo ./scripts/obfuscation-manager.sh apply nm-interface ovsbr0
sudo ./scripts/obfuscation-manager.sh rotate nm-interface ovsbr0

# Service management
systemctl status netmaker-ovs-bridge
systemctl status netmaker-obfuscation-daemon
```

### 🛠️ Troubleshooting
```bash
# Check system readiness
sudo ./pre-install.sh

# View comprehensive logs
journalctl -u netmaker-ovs-bridge -u netmaker-obfuscation-daemon

# Use helper tools
sudo ./tools/configure-ovs-proxmox.sh
sudo ./tools/fix-mosquitto-lxc.sh
```

### 🗑️ Removal
```bash
# Complete removal with optional config restoration
sudo ./uninstall.sh
```

## Development Workflow

### 🔄 Adding New Features
1. **Update Configuration**: Modify `config/ovs-config` for new settings
2. **Enhance Scripts**: Update relevant scripts in `scripts/`
3. **Update Services**: Modify systemd services if needed
4. **Document Changes**: Update documentation in `docs/`
5. **Test Integration**: Use examples and tools for validation

### 📝 Documentation Updates
1. **Technical Details**: Add to appropriate files in `docs/`
2. **User Guides**: Update main README.md and guides
3. **Examples**: Provide configuration examples in `examples/`
4. **Reference**: Update project context in `reference/`

### 🧪 Testing
1. **Pre-Installation**: Test with various system configurations
2. **Installation**: Validate all installation methods
3. **Functionality**: Verify obfuscation and integration features
4. **Removal**: Ensure clean uninstallation and rollback

## Integration Points

### 🔗 External Dependencies
- **OpenVSwitch**: Core switching infrastructure
- **Netmaker**: Mesh networking platform  
- **systemd**: Service management and dependencies
- **Linux Networking**: Bridge, VLAN, and interface management

### 🏗️ Architecture Integration
- **Proxmox VE**: Specialized support and tooling
- **LXC Containers**: Container networking integration
- **MQTT Broker**: Netmaker communication infrastructure
- **Network Obfuscation**: Privacy and security enhancement

This structure provides a comprehensive, maintainable, and extensible foundation for Netmaker OVS integration with advanced obfuscation capabilities.