# Interactive Installation Features

## Overview

The interactive installer (`install-interactive.sh`) provides a guided setup experience with automatic system detection and intelligent configuration recommendations. It eliminates guesswork and ensures optimal configuration for your specific environment.

## Key Features

### 🔍 Automatic System Detection

#### System Information
- **Hardware Resources**: CPU cores, memory, disk space
- **Virtualization Platform**: Bare metal, VM, Docker, OpenVZ, Xen
- **Proxmox Integration**: Automatic Proxmox version detection
- **Container Runtime**: Docker, Podman, Proxmox LXC support

#### Network Analysis
- **Existing OVS Bridges**: Detection and port analysis
- **Netmaker Interfaces**: Active interface discovery and pattern analysis
- **VLAN Usage**: Conflict detection for obfuscation VLANs
- **Network Namespaces**: Container networking awareness

#### Service Discovery
- **Netmaker Services**: Automatic detection of netmaker/netclient
- **Service Status**: Running, enabled, and configuration states
- **Dependency Validation**: Ensures all prerequisites are met

### 🎯 Intelligent Configuration

#### Bridge Configuration
- **Smart Naming**: Suggests bridge names based on existing infrastructure
- **Conflict Avoidance**: Detects naming conflicts and offers alternatives
- **Reuse Detection**: Identifies existing bridges for reuse

#### Interface Pattern Detection
- **Automatic Pattern Recognition**: Analyzes existing interfaces to suggest patterns
- **Multiple Pattern Support**: Handles various Netmaker naming conventions
- **Validation**: Ensures patterns match actual interface naming

#### Resource-Based Recommendations
- **Performance Tuning**: Adjusts settings based on available resources
- **Overhead Optimization**: Recommends obfuscation levels for system capacity
- **Scalability Planning**: Considers growth and resource constraints

### ⚙️ Obfuscation Configuration

#### Preset Levels
1. **Disabled**: No obfuscation (0% overhead)
2. **Conservative**: Minimal impact (5% overhead, 20% protection)
3. **Balanced**: Good protection (15% overhead, 30% protection) [DEFAULT]
4. **Aggressive**: Maximum protection (25% overhead, 40% protection)
5. **Custom**: Full manual configuration

#### Smart VLAN Management
- **Conflict Detection**: Identifies VLANs already in use
- **Pool Optimization**: Suggests available VLANs for rotation
- **Automatic Exclusion**: Removes conflicting VLANs from pool

#### Performance Impact Estimation
- **Real-time Calculation**: Shows estimated overhead based on selections
- **Resource Validation**: Warns if settings exceed system capacity
- **Optimization Suggestions**: Recommends adjustments for better performance

### 🖥️ User Experience

#### Visual Interface
- **Color-coded Output**: Clear distinction between information types
- **Progress Indicators**: Shows current step and overall progress
- **Formatted Displays**: Professional presentation of system information

#### Interactive Menus
- **Intuitive Navigation**: Numbered choices with clear descriptions
- **Validation**: Input validation with helpful error messages
- **Flexibility**: Ability to modify configuration before installation

#### Configuration Management
- **Summary Display**: Complete configuration overview before installation
- **Save/Load**: Option to save configurations for future use
- **Backup Integration**: Automatic backup before any changes

## Auto-Detection Examples

### Proxmox Environment Detection
```bash
System Information:
  • CPU Cores: 8
  • Memory: 32768 MB
  • Available Disk Space: 500 GB
  • Virtualization: bare-metal
  • Proxmox Version: 8.0.4

Network Configuration:
  • Network Interfaces: 4
  • Network Namespaces: 12
  • Container Runtime: proxmox-lxc

OpenVSwitch Status:
  • Existing OVS Bridges:
    - ovsbr0 (3 ports)
    - vmbr0 (2 ports)

Netmaker Status:
  • Detected Services: netclient.service
  • Active Interfaces:
    - nm-ghostbridge (UP)
    - nm-management (UP)
```

### Docker Environment Detection
```bash
System Information:
  • CPU Cores: 4
  • Memory: 8192 MB
  • Available Disk Space: 100 GB
  • Virtualization: docker
  • Container Runtime: docker

Network Configuration:
  • Network Interfaces: 3
  • Network Namespaces: 8

OpenVSwitch Status:
  • No existing OVS bridges found

Netmaker Status:
  • Detected Services: netmaker.service
  • No active Netmaker interfaces found

VLANs currently in use: 100 200
```

## Configuration Workflow

### 1. System Analysis Phase
```
╔═══ DETECTED SYSTEM CONFIGURATION ═══╗

[Automatic detection results displayed]
[Resource analysis and recommendations]
[Conflict identification and warnings]
```

### 2. Bridge Configuration
```
╔═══ BRIDGE CONFIGURATION ═══╗

Current OVS bridges: ovsbr0, vmbr0
Suggested name: ovsbr1

Enter bridge name [ovsbr1]: _
```

### 3. Interface Pattern Setup
```
╔═══ NETMAKER INTERFACE CONFIGURATION ═══╗

Currently detected interfaces:
  - nm-ghostbridge
  - nm-management
Suggested pattern: nm-*

Enter interface pattern [nm-*]: _
```

### 4. Obfuscation Selection
```
╔═══ OBFUSCATION CONFIGURATION ═══╗

Select obfuscation level:
  1) Disabled - No obfuscation (0% overhead)
  2) Conservative - Minimal impact (5% overhead, 20% protection)
  3) Balanced - Good protection (15% overhead, 30% protection) [DEFAULT]
  4) Aggressive - Maximum protection (25% overhead, 40% protection)
  5) Custom - Configure manually

Recommended for your system: balanced

Enter choice (1-5) [3]: _
```

### 5. Configuration Summary
```
╔═══════════════════════════════════════════════════════════════╗
║                    CONFIGURATION SUMMARY                     ║
╚═══════════════════════════════════════════════════════════════╝

Bridge Configuration:
  • Bridge Name: ovsbr1
  • Create Bridge: true

Netmaker Configuration:
  • Interface Pattern: nm-*

Obfuscation Configuration:
  • Enabled: true
  • VLAN Rotation: true (every 300s)
  • MAC Randomization: true (every 1800s)
  • Timing Obfuscation: true (max 50ms)
  • Traffic Shaping: true (100 Mbps)
  • VLAN Pool: 300,400,500

Estimated Performance Impact: ~15%
```

## Advanced Features

### Custom Obfuscation Configuration
When selecting "Custom" obfuscation, the installer provides granular control:

```bash
Custom Obfuscation Configuration:

Enable VLAN rotation? (Disrupts traffic flow analysis)
Enable VLAN obfuscation? (y/N): y
VLAN rotation interval in seconds [300]: 180

Enable MAC address randomization? (Prevents device fingerprinting)
Enable MAC randomization? (y/N): y
MAC rotation interval in seconds [1800]: 900

Enable timing obfuscation? (Disrupts timing correlation attacks)
Enable timing obfuscation? (y/N): y
Maximum delay in milliseconds [50]: 75

Enable traffic shaping? (Normalizes traffic patterns)
Enable traffic shaping? (y/N): y
Traffic shaping rate in Mbps [100]: 50
```

### VLAN Pool Management
Intelligent VLAN pool configuration:

```bash
VLAN Pool Configuration:

VLANs currently in use: 100 200
Available VLANs: 300 400 500 600 700
Default pool: 100,200,300,400,500

Enter VLAN pool (comma-separated) [300,400,500]: 300,400,500,600,700
VLAN pool configured: 300,400,500,600,700
```

### Configuration Persistence
Options for saving and reusing configurations:

```bash
Ready to proceed with installation?
  1) Install with current configuration
  2) Modify configuration
  3) Save configuration and exit
  4) Exit without installing

Enter choice (1-4): 3

Configuration saved to: netmaker-ovs-config-20240101-120000.conf
You can use this file for future installations or reference.
```

## Integration with Existing Scripts

The interactive installer seamlessly integrates with the existing installation framework:

1. **Pre-install Integration**: Can automatically run pre-install.sh if needed
2. **Configuration Generation**: Creates compatible config files for install.sh
3. **Backup Compatibility**: Works with existing backup and restore mechanisms
4. **Service Integration**: Maintains compatibility with all systemd services

## Error Handling and Validation

### Input Validation
- **Bridge Names**: Validates naming conventions and character restrictions
- **VLAN Numbers**: Ensures valid VLAN ranges (1-4094)
- **Interval Timing**: Validates reasonable rotation intervals
- **Resource Limits**: Warns about resource-intensive configurations

### Conflict Resolution
- **Automatic Cleanup**: Suggests resolution for detected conflicts
- **Alternative Suggestions**: Provides alternatives when conflicts exist
- **Graceful Degradation**: Continues with warnings when possible

### Recovery Options
- **Configuration Retry**: Allows reconfiguration without restart
- **Safe Exit**: Clean exit without system changes
- **Backup Integration**: Automatic restoration if installation fails

## Performance Considerations

### Resource Optimization
The interactive installer considers system resources when making recommendations:

- **Low Resource Systems** (< 2GB RAM, < 2 cores): Conservative settings recommended
- **Standard Systems** (2-8GB RAM, 2-4 cores): Balanced settings (default)
- **High Resource Systems** (> 8GB RAM, > 4 cores): Aggressive settings available

### Impact Estimation
Real-time performance impact calculation based on:
- Selected obfuscation features
- System resource availability
- Existing network load
- Container/VM overhead

## Troubleshooting Integration

The interactive installer includes built-in troubleshooting:

### Common Issue Detection
- **Missing Prerequisites**: Automatic detection and installation suggestions
- **Service Conflicts**: Identification and resolution recommendations
- **Network Conflicts**: VLAN and interface conflict resolution

### Diagnostic Information
- **Comprehensive Logging**: Detailed logs for support purposes
- **System State Capture**: Pre and post-installation system state
- **Configuration Validation**: Syntax and compatibility checks

This interactive installation approach significantly reduces deployment complexity while ensuring optimal configuration for the specific environment.