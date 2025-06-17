# Netmaker OVS Integration Deployment Guide

## Overview

This guide provides step-by-step instructions for deploying the Netmaker OpenVSwitch Integration with mild obfuscation features. The deployment process includes pre-installation validation, installation, and post-deployment verification.

## Pre-Deployment Checklist

### System Requirements
- **Operating System**: Linux with systemd support (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- **Memory**: Minimum 512MB RAM, Recommended 2GB+
- **CPU**: Minimum 1 core, Recommended 2+ cores
- **Storage**: 1GB free space for installation and logs
- **Network**: Active network interface with internet connectivity

### Prerequisites
- Root/sudo access
- OpenVSwitch installed and running (`openvswitch-switch` package)
- Netmaker client installed and configured
- Basic networking tools (`bridge-utils`, `iproute2`)

### Network Planning
- Identify target OVS bridge name (default: `ovsbr0`)
- Plan VLAN pool for obfuscation (default: 100,200,300,400,500)
- Ensure VLANs are not in use by other services
- Verify no conflicts with existing Netmaker interfaces

## Deployment Process

### Phase 1: Pre-Installation

#### 1.1 Download and Prepare
```bash
# Clone the repository
git clone <repository-url>
cd netmaker-ovs-integration

# Make scripts executable
chmod +x pre-install.sh install.sh uninstall.sh
```

#### 1.2 Run Pre-Installation Script
```bash
sudo ./pre-install.sh
```

**What this does:**
- Checks system prerequisites
- Detects conflicts with existing installations
- Backs up current configuration to `/tmp/netmaker-ovs-backup-<timestamp>/`
- Cleans up conflicting network state
- Validates OpenVSwitch functionality
- Generates pre-installation report

**Expected Output:**
```
========================================
Netmaker OVS Pre-Installation Script
Version: 1.0.0
========================================

INFO: Creating backup directory: /tmp/netmaker-ovs-backup-20240101-120000
SUCCESS: System information gathered
SUCCESS: All prerequisites satisfied
SUCCESS: No existing installations found
SUCCESS: No network conflicts found
SUCCESS: OpenVSwitch is running
SUCCESS: Configuration backup completed
SUCCESS: System validation passed
SUCCESS: Pre-installation completed successfully!

========================================
SYSTEM IS READY FOR INSTALLATION
========================================

Next steps:
1. Review the report: /tmp/netmaker-ovs-backup-20240101-120000/pre-install-report.txt
2. Run the installation: sudo ./install.sh
```

#### 1.3 Review Pre-Installation Report
```bash
# Review the generated report
cat /tmp/netmaker-ovs-backup-*/pre-install-report.txt
```

### Phase 2: Installation

#### 2.1 Configure Installation (Optional)
Edit the configuration file before installation if needed:
```bash
# Preview default configuration
cat config/ovs-config

# Customize if needed (optional)
nano config/ovs-config
```

**Key Configuration Options:**
```bash
# Basic settings
BRIDGE_NAME=ovsbr0                    # OVS bridge name
NM_INTERFACE_PATTERN="nm-*"          # Netmaker interface pattern

# Obfuscation settings
ENABLE_OBFUSCATION=true              # Enable/disable obfuscation
VLAN_POOL="100,200,300,400,500"      # Available VLAN tags
VLAN_ROTATION_INTERVAL=300           # VLAN rotation (seconds)
MAC_ROTATION_INTERVAL=1800           # MAC rotation (seconds)
MAX_DELAY_MS=50                      # Max timing delay
SHAPING_RATE_MBPS=100               # Traffic shaping rate
```

#### 2.2 Run Installation
```bash
sudo ./install.sh
```

**What this does:**
- Checks if pre-install was run (warns if not)
- Stops any existing services
- Removes conflicting files
- Copies new scripts and configurations
- Creates OVS bridge if needed
- Installs and starts systemd services
- Sets up obfuscation daemon (if enabled)

**Expected Output:**
```
=== Netmaker OpenVSwitch Integration Setup ===
Stopping and disabling any existing services...
Removing any old installed files...
Creating target directories...
Copying configuration file...
Copying scripts...
Copying systemd service files...
Setting permissions...
Creating obfuscation state directory...
Checking OVS bridge 'ovsbr0'...
Creating OVS bridge 'ovsbr0'...
Reloading systemd daemon, enabling and starting services...
Obfuscation enabled, starting obfuscation daemon...

=== Installation Complete ===
Netmaker OpenVSwitch Integration with mild obfuscation has been installed and started.

Services status:
  Main service: systemctl status netmaker-ovs-bridge
  Obfuscation daemon: systemctl status netmaker-obfuscation-daemon

Obfuscation features enabled:
  ✓ VLAN rotation every 300 seconds
  ✓ MAC randomization every 1800 seconds
  ✓ Basic timing obfuscation (max 50ms delay)
  ✓ Traffic shaping at 100Mbps
```

### Phase 3: Post-Installation Verification

#### 3.1 Verify Service Status
```bash
# Check main service
systemctl status netmaker-ovs-bridge

# Check obfuscation daemon
systemctl status netmaker-obfuscation-daemon

# View recent logs
journalctl -u netmaker-ovs-bridge -n 20
journalctl -u netmaker-obfuscation-daemon -n 20
```

#### 3.2 Verify OVS Configuration
```bash
# Check OVS bridges
ovs-vsctl show

# List bridge ports
ovs-vsctl list-ports ovsbr0

# Check for Netmaker interfaces
ip link show | grep nm-
```

#### 3.3 Test Netmaker Integration
```bash
# Start Netmaker client (if not running)
sudo systemctl start netclient

# Wait for interface creation and check integration
sleep 10
ovs-vsctl list-ports ovsbr0 | grep nm-

# Check obfuscation application
cat /var/lib/netmaker/obfuscation-state
```

#### 3.4 Verify Obfuscation Features
```bash
# Check VLAN configuration
ovs-vsctl list port | grep tag

# Check QoS settings
ovs-vsctl list interface | grep ingress_policing

# Monitor obfuscation rotation
journalctl -u netmaker-obfuscation-daemon -f
```

## Configuration Management

### Runtime Configuration Changes
```bash
# Edit configuration
sudo nano /etc/netmaker/ovs-config

# Restart services to apply changes
sudo systemctl restart netmaker-ovs-bridge
sudo systemctl restart netmaker-obfuscation-daemon
```

### Manual Obfuscation Control
```bash
# Apply obfuscation to specific interface
sudo /usr/local/bin/obfuscation-manager.sh apply nm-example ovsbr0

# Remove obfuscation from interface
sudo /usr/local/bin/obfuscation-manager.sh remove nm-example ovsbr0

# Force rotation of obfuscation parameters
sudo /usr/local/bin/obfuscation-manager.sh rotate nm-example ovsbr0
```

### Enabling/Disabling Obfuscation
```bash
# Disable obfuscation
sudo sed -i 's/ENABLE_OBFUSCATION=true/ENABLE_OBFUSCATION=false/' /etc/netmaker/ovs-config
sudo systemctl stop netmaker-obfuscation-daemon
sudo systemctl disable netmaker-obfuscation-daemon

# Re-enable obfuscation
sudo sed -i 's/ENABLE_OBFUSCATION=false/ENABLE_OBFUSCATION=true/' /etc/netmaker/ovs-config
sudo systemctl enable netmaker-obfuscation-daemon
sudo systemctl start netmaker-obfuscation-daemon
```

## Troubleshooting

### Common Issues

#### 1. Pre-Install Fails - Missing Prerequisites
```bash
# Install missing packages
sudo apt update
sudo apt install openvswitch-switch bridge-utils iproute2

# Restart OpenVSwitch
sudo systemctl restart openvswitch-switch
```

#### 2. Installation Fails - Bridge Creation Error
```bash
# Manually create bridge
sudo ovs-vsctl add-br ovsbr0

# Check OVS service
sudo systemctl status openvswitch-switch
```

#### 3. Service Won't Start - Configuration Error
```bash
# Check configuration syntax
sudo bash -n /etc/netmaker/ovs-config

# Check service logs
journalctl -u netmaker-ovs-bridge -n 50
```

#### 4. Obfuscation Not Working - Permission Issues
```bash
# Check obfuscation state file
sudo ls -la /var/lib/netmaker/

# Recreate state directory
sudo mkdir -p /var/lib/netmaker
sudo chown root:root /var/lib/netmaker
```

#### 5. Netmaker Interface Not Detected
```bash
# Check interface pattern
ip link show | grep nm-

# Verify Netmaker is running
sudo systemctl status netclient

# Check configuration pattern
grep NM_INTERFACE_PATTERN /etc/netmaker/ovs-config
```

### Performance Issues

#### High CPU Usage
```bash
# Check obfuscation daemon CPU usage
top -p $(pgrep -f obfuscation-manager)

# Reduce rotation frequency
sudo nano /etc/netmaker/ovs-config
# Increase VLAN_ROTATION_INTERVAL and MAC_ROTATION_INTERVAL
```

#### High Latency
```bash
# Reduce timing obfuscation
sudo nano /etc/netmaker/ovs-config
# Decrease MAX_DELAY_MS or disable TIMING_OBFUSCATION

# Check traffic shaping
ovs-vsctl list interface | grep ingress_policing
```

### Log Analysis
```bash
# Comprehensive log review
journalctl -u netmaker-ovs-bridge -u netmaker-obfuscation-daemon --since "1 hour ago"

# Monitor real-time
journalctl -u netmaker-ovs-bridge -u netmaker-obfuscation-daemon -f

# Check for errors
journalctl -u netmaker-ovs-bridge -p err
```

## Maintenance

### Regular Maintenance Tasks

#### Daily
- Monitor service status
- Check disk space for logs
- Verify network connectivity

#### Weekly
- Review obfuscation effectiveness
- Check for configuration drift
- Update system packages

#### Monthly
- Clean old log files
- Review performance metrics
- Test backup restoration

### Backup Management
```bash
# List available backups
ls -la /tmp/netmaker-ovs-backup-*

# Create manual backup
sudo cp -r /etc/netmaker /tmp/manual-backup-$(date +%Y%m%d)

# Clean old backups (keep last 5)
sudo find /tmp -name "netmaker-ovs-backup-*" -type d | sort | head -n -5 | xargs rm -rf
```

### Updates and Upgrades
```bash
# Before updating
sudo ./pre-install.sh  # Creates new backup

# After system updates
sudo systemctl restart openvswitch-switch
sudo systemctl restart netmaker-ovs-bridge
sudo systemctl restart netmaker-obfuscation-daemon
```

## Security Considerations

### Operational Security
- Regularly rotate obfuscation parameters
- Monitor for detection attempts
- Keep system updated
- Restrict access to configuration files

### Performance vs Security Trade-offs
- **Conservative**: Longer rotation intervals, minimal impact
- **Balanced**: Default settings, good protection with acceptable overhead
- **Aggressive**: Short intervals, maximum protection with higher overhead

### Compliance
- Ensure obfuscation use complies with local laws
- Document legitimate use cases
- Maintain audit logs

## Complete Removal

If you need to completely remove the installation:

```bash
# Run automated uninstaller
sudo ./uninstall.sh

# This will:
# - Stop all services
# - Remove obfuscation from interfaces
# - Clean up OVS integration
# - Remove all files
# - Optionally restore original configuration
```

## Support

### Log Collection for Support
```bash
# Collect all relevant logs
sudo tar -czf netmaker-ovs-logs-$(date +%Y%m%d).tar.gz \
  /var/log/syslog \
  /tmp/netmaker-ovs-*.log \
  /etc/netmaker/ \
  /var/lib/netmaker/ \
  <(journalctl -u netmaker-ovs-bridge -u netmaker-obfuscation-daemon --since "24 hours ago")
```

### Diagnostic Information
```bash
# System information
sudo /usr/local/bin/obfuscation-manager.sh --version 2>/dev/null || echo "Not installed"
systemctl --version
ovs-vsctl --version
uname -a
```

This deployment guide ensures a smooth installation process with proper validation, comprehensive troubleshooting, and maintenance procedures.