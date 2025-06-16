# GhostBridge Netmaker Interactive Installer - Usage Guide

## Overview

This interactive installer was created specifically for the GhostBridge project, incorporating lessons learned from extensive real-world troubleshooting documented in the chat transcripts. It addresses critical issues that commonly cause installation failures, particularly MQTT broker connection problems, nginx stream module issues, and network configuration problems.

## Key Features

### 🔧 **Problem-Focused Design**
- **MQTT Broker Connection Fixes**: Addresses the critical "Fatal: could not connect to broker, token timeout" issue
- **Nginx Stream Module**: Ensures nginx-full is installed with stream module support for MQTT TCP proxy
- **Protocol Validation**: Uses correct `mqtt://` protocol instead of problematic `http://` endpoints
- **Security by Default**: Disables anonymous MQTT access and generates secure credentials

### 🚀 **Real-World Validated**
- Based on extensive GhostBridge project troubleshooting
- Addresses network configuration issues specific to Proxmox + LXC container setups
- Includes DNS resolution validation for hobsonschoice.net domains
- Progressive validation at each installation step

### 📋 **Comprehensive Pre-flight Checks**
- Operating system compatibility validation
- System resource verification (memory, CPU, disk space)
- Critical port availability checking
- Nginx stream module detection and validation
- DNS resolution testing for all required domains
- Virtualization environment detection (Proxmox, LXC, etc.)

## Quick Start

### Prerequisites
- Ubuntu 20.04+ or Debian 11+
- Root access (use sudo)
- Internet connectivity
- Valid domain with DNS configured

### Installation

```bash
# Navigate to the installer directory
cd netmaker_non-containerized_GO_stack

# Run the interactive installer
sudo ./install-interactive.sh
```

### Deployment Scenarios

The installer supports several deployment types optimized for different use cases:

#### 1. **Proxmox Host + LXC Container (GhostBridge Standard)**
- Default configuration for GhostBridge project
- Services installed in LXC container
- Nginx proxy on Proxmox host with stream module
- Addresses container IP networking issues

#### 2. **Complete Single-Server Setup**
- All services on one system
- Simplified configuration
- Good for smaller deployments

#### 3. **Multi-Server Deployment**
- Distributed services across multiple servers
- Advanced configuration options
- Production-ready scalability

#### 4. **Development/Testing Setup**
- Minimal resource requirements
- Quick setup for testing

## Critical Configuration Items

### MQTT Broker Configuration
The installer specifically addresses the critical MQTT issues found in troubleshooting:

```bash
# Correct configuration (what the installer does):
listener 1883
bind_address 0.0.0.0          # Critical: NOT 127.0.0.1
protocol mqtt                 # Critical: Explicit protocol
allow_anonymous false         # Security: Disable anonymous access

# MQTT endpoint in Netmaker config:
endpoint: "mqtt://user:pass@broker.domain:1883"  # NOT http://
```

### Nginx Stream Module
Critical fix for MQTT TCP proxy functionality:

```bash
# The installer ensures nginx-full is installed:
apt install nginx-full  # NOT nginx-light

# Stream configuration for MQTT:
stream {
    upstream mqtt_backend {
        server 10.0.0.101:1883;  # Container IP
    }
    server {
        listen 1883;
        proxy_pass mqtt_backend;
    }
}
```

### Network Configuration
For Proxmox + LXC container setups:

- **Host Public IP**: 80.209.240.244 (default for GhostBridge)
- **Container IP**: 10.0.0.101 (LXC container network)
- **Bridge**: vmbr0 (standard Linux bridge, not OVS)
- **DNS**: All subdomains resolve to host public IP

## Installation Process

The installer follows a structured approach to prevent common failures:

### Phase 1: Pre-flight Validation
- System compatibility checks
- Resource availability verification
- Port conflict detection
- **Critical**: Nginx stream module validation
- DNS resolution testing

### Phase 2: Interactive Configuration
- Deployment type selection
- Network and domain configuration
- Component selection (Netmaker, Mosquitto, Nginx, SSL)
- **Security**: MQTT authentication setup

### Phase 3: Progressive Installation
- Dependency installation with **nginx-full**
- Netmaker binary download and verification
- **Secure Mosquitto configuration** (addresses binding issues)
- **Proper Netmaker MQTT endpoint configuration**
- Nginx reverse proxy with **stream module configuration**
- SSL certificate setup with Let's Encrypt

### Phase 4: Comprehensive Validation
- Service startup verification
- Port binding confirmation
- **MQTT connectivity testing**
- **API endpoint validation**
- SSL certificate verification

## Troubleshooting Integration

The installer includes built-in troubleshooting based on real-world issues:

### Common Issue Detection
- **Nginx stream module missing**: Automatically installs nginx-full
- **MQTT protocol errors**: Uses correct `mqtt://` endpoints
- **Port binding failures**: Validates each service starts correctly
- **DNS resolution problems**: Tests domain resolution before SSL setup

### Validation Commands
The installer tests each component with commands that were proven to work:

```bash
# MQTT connectivity test
mosquitto_pub -h 127.0.0.1 -p 1883 -t test -m hello -u user -P pass

# Nginx configuration validation
nginx -t

# Service status verification
systemctl status netmaker mosquitto nginx

# Port binding verification
ss -tlnp | grep -E '1883|9001|8081'
```

## Integration with netmaker-ovs-integration

This installer is designed to run **before** the netmaker-ovs-integration script:

1. **Run this installer first** to establish the base Netmaker stack
2. **Verify all services are working** using the built-in validation
3. **Then run netmaker-ovs-integration** for advanced networking features

The installer prepares the system properly so that the OVS integration can focus on its specialized networking tasks without having to deal with basic MQTT, nginx, or SSL configuration issues.

## Security Features

### MQTT Security
- **Disabled anonymous access** (addresses security vulnerability)
- **Generated secure credentials** (25-character random password)
- **Access control lists** for user permissions

### System Security
- **Secure file permissions** on configuration files
- **SystemD service isolation**
- **SSL/TLS encryption** by default
- **Backup creation** before any modifications

## Post-Installation

### Service Management
```bash
# Check service status
systemctl status netmaker mosquitto nginx

# View logs
journalctl -u netmaker -f
journalctl -u mosquitto -f

# Restart services
systemctl restart netmaker
```

### Configuration Files
- **Netmaker**: `/etc/netmaker/config.yaml`
- **Mosquitto**: `/etc/mosquitto/mosquitto.conf`
- **Nginx**: `/etc/nginx/sites-available/netmaker`
- **Installation Summary**: `/etc/netmaker/installation-summary.txt`

### Credentials and Keys
The installer generates and saves:
- **MQTT username/password** for secure broker access
- **Netmaker master key** for API administration
- **SSL certificates** for HTTPS access

⚠️ **Important**: Save these credentials securely as they are displayed only once during installation.

## Support and Troubleshooting

### Built-in Diagnostics
The installer includes comprehensive logging and validation that helps identify issues immediately rather than discovering them later.

### Common Issues Addressed
1. **"Fatal: could not connect to broker"** → Fixed with proper MQTT configuration
2. **"stream directive not allowed"** → Fixed with nginx-full installation
3. **Port binding failures** → Fixed with proper service sequencing
4. **DNS resolution problems** → Detected and handled gracefully

### Log Files
- **Installation Log**: `/var/log/ghostbridge-netmaker-install.log`
- **Service Logs**: Available via `journalctl`
- **Configuration Backups**: `/var/backups/ghostbridge-netmaker/`

This installer represents the distillation of extensive real-world troubleshooting into a reliable, automated deployment process that avoids the pitfalls commonly encountered when setting up Netmaker from scratch.