# GhostBridge Netmaker Installation Guide

Complete step-by-step installation guide for deploying Netmaker as a native GO binary stack on Debian/Ubuntu systems.

## Overview

This guide covers both the **Interactive Installation** (recommended) and **Dummy Installation** (for OVS integration testing) methods, based on real-world deployment experience from the GhostBridge project.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Pre-Installation Planning](#pre-installation-planning)
- [Installation Methods](#installation-methods)
  - [Method 1: Interactive Installation](#method-1-interactive-installation-recommended)
  - [Method 2: Dummy Installation](#method-2-dummy-installation-for-ovs-testing)
  - [Method 3: Manual Installation](#method-3-manual-installation)
- [Post-Installation](#post-installation)
- [Integration with OVS](#integration-with-ovs)
- [Troubleshooting](#troubleshooting)

## Prerequisites

### System Requirements

#### Minimum Requirements
- **Operating System**: Ubuntu 20.04+ / Debian 11+
- **CPU**: 1 core, 1.5 GHz
- **RAM**: 1 GB
- **Storage**: 5 GB free space
- **Network**: Public IP or proper port forwarding

#### Recommended Requirements
- **Operating System**: Ubuntu 22.04 LTS / Debian 12
- **CPU**: 2+ cores, 2.0+ GHz
- **RAM**: 2+ GB
- **Storage**: 20+ GB free space
- **Network**: Dedicated public IP, proper DNS setup

### Network Requirements

#### Required Ports
- **80**: HTTP (redirects to HTTPS)
- **443**: HTTPS (web interface and API)
- **1883**: MQTT TCP (broker communication)
- **8081**: Netmaker API (internal)
- **9001**: MQTT WebSocket (web-based connections)

#### DNS Configuration
For production deployments, you'll need:
- Valid domain name with A records for subdomains
- Example for `hobsonschoice.net`:
  - `netmaker.hobsonschoice.net` → Your server IP
  - `broker.hobsonschoice.net` → Your server IP
  - `dashboard.hobsonschoice.net` → Your server IP

### Access Requirements
- **Root/sudo access** for system configuration
- **Internet connectivity** for downloading packages and SSL certificates

## Pre-Installation Planning

### Deployment Architecture Decision

Choose your deployment type:

1. **Single Server** - All services on one system
2. **Proxmox + LXC** - GhostBridge standard configuration
3. **Multi-Server** - Distributed across multiple servers
4. **Development** - Minimal setup for testing

### Network Planning

For **GhostBridge/Proxmox + LXC** deployments:
- **Host Public IP**: Your server's public IP (e.g., 80.209.240.244)
- **Container IP**: LXC container private IP (e.g., 10.0.0.101)
- **Bridge**: Network bridge name (e.g., vmbr0)

### Security Planning

- **MQTT Authentication**: Always enable for production
- **SSL Certificates**: Required for secure web access
- **Firewall**: Ensure required ports are accessible

## Installation Methods

## Method 1: Interactive Installation (RECOMMENDED)

The interactive installer provides guided setup with automatic problem detection and resolution.

### Step 1: Download and Prepare

```bash
# Clone the repository
git clone https://github.com/your-username/netmaker_non-containerized_GO_stack
cd netmaker_non-containerized_GO_stack

# Make installer executable
chmod +x install-interactive.sh
```

### Step 2: Run Pre-flight Checks

The installer automatically runs comprehensive pre-flight validation:

```bash
sudo ./install-interactive.sh
```

The installer will check:
- ✅ Operating system compatibility
- ✅ System resources (memory, CPU, disk)
- ✅ Port availability
- ✅ Nginx stream module support
- ✅ DNS resolution
- ✅ Virtualization environment

### Step 3: Interactive Configuration

The installer will guide you through:

#### Deployment Type Selection
```
1) Complete Single-Server Setup
2) Proxmox Host + LXC Container Setup (GhostBridge standard)  ← Recommended for GhostBridge
3) Multi-Server Deployment
4) Development/Testing Setup
```

#### Domain and Network Configuration
```bash
Domain: hobsonschoice.net                    # Your domain
Host Public IP: 80.209.240.244             # For Proxmox deployments
Container IP: 10.0.0.101                   # For LXC container
Bridge: vmbr0                              # Network bridge
```

#### Component Selection
```bash
Install Netmaker server? [Y/n]: Y
Install Mosquitto MQTT broker? [Y/n]: Y
Install/configure Nginx reverse proxy? [Y/n]: Y
Setup SSL certificates with Let's Encrypt? [Y/n]: Y
```

#### Security Configuration
```bash
Generate secure MQTT credentials? [Y/n]: Y   # Recommended
```

### Step 4: Review Configuration Summary

The installer displays a complete summary:
```
Deployment Configuration:
  • Type: proxmox-lxc
  • Domain: hobsonschoice.net
  • Host Public IP: 80.209.240.244
  • Container IP: 10.0.0.101

Service Endpoints:
  • Netmaker API: https://netmaker.hobsonschoice.net:8081
  • MQTT Broker: mqtt://broker.hobsonschoice.net:1883
  • Dashboard: https://dashboard.hobsonschoice.net

Critical Installation Notes:
  • Nginx will be installed with stream module support (nginx-full)
  • MQTT broker will use proper protocol endpoints (mqtt://, not http://)
  • Anonymous MQTT access will be disabled for security
```

### Step 5: Installation Process

The installer proceeds through these phases:

#### Phase 1: System Dependencies
- Updates package lists
- Installs **nginx-full** (critical for stream module)
- Installs Mosquitto MQTT broker
- Installs SSL certificate tools

#### Phase 2: Netmaker Installation
- Downloads latest Netmaker binary
- Creates directory structure
- Sets up proper permissions

#### Phase 3: Service Configuration
- **Mosquitto**: Configured with proper security and binding
- **Netmaker**: Configured with correct MQTT endpoints
- **Nginx**: Configured with stream module for MQTT proxy
- **SystemD**: Service creation and dependency management

#### Phase 4: SSL Setup
- DNS validation for all subdomains
- Let's Encrypt certificate generation
- Nginx SSL configuration

#### Phase 5: Service Startup & Validation
- Progressive service startup
- Comprehensive connectivity testing
- MQTT broker validation
- API endpoint verification

### Step 6: Installation Completion

Upon successful completion, you'll receive:

```bash
🎉 GhostBridge Netmaker GO stack installation completed!

📋 Installation Summary:
  • Domain: hobsonschoice.net
  • Netmaker API: https://netmaker.hobsonschoice.net
  • MQTT Broker: mqtt://broker.hobsonschoice.net:1883
  • Dashboard: https://dashboard.hobsonschoice.net

🔐 MQTT Credentials:
  • Username: netmaker
  • Password: [Generated securely]

🔑 Netmaker Master Key:
  • Master Key: [Generated securely]
```

**Important**: Save the generated credentials securely!

## Method 2: Dummy Installation (For OVS Testing)

Use this method to test netmaker-ovs-integration before doing a real installation.

### When to Use Dummy Installation

- Testing OVS integration scripts
- Validating network configuration
- Development and testing workflows
- Learning the integration process

### Step 1: Run Dummy Installer

```bash
cd netmaker_non-containerized_GO_stack
sudo ./install-dummy.sh
```

### Step 2: Configure Dummy Setup

The dummy installer will ask for:
```bash
Interface name [nm-dummy]: nm-dummy
IP address [10.100.0.1/24]: 10.100.0.1/24
Bridge name [ovsbr0]: ovsbr0
Network range [10.100.0.0/24]: 10.100.0.0/24
```

### Step 3: What Gets Created

The dummy installer creates:
- **Dummy Interface**: `nm-dummy` with IP `10.100.0.1/24`
- **Configuration Files**: `/etc/netmaker/config.yaml` and `/etc/netmaker/ovs-config`
- **SystemD Services**: Placeholder `netmaker.service` and `netclient.service`
- **Persistent Setup**: Interface recreated on reboot
- **OVS Dependencies**: OpenVSwitch tools installed

### Step 4: Test OVS Integration

```bash
# Navigate to OVS integration
cd ../netmaker-ovs-integration

# Run OVS integration installer
sudo ./install-interactive.sh
```

The OVS installer should now detect:
- ✅ Netmaker interface: `nm-dummy`
- ✅ Netmaker services: `netmaker.service`, `netclient.service`
- ✅ Configuration files: `/etc/netmaker/ovs-config`

### Step 5: Clean Up and Real Installation

```bash
# Remove dummy setup
cd ../netmaker_non-containerized_GO_stack
sudo ./remove-dummy.sh

# Run real installation
sudo ./install-interactive.sh
```

## Method 3: Manual Installation

For advanced users who want full control over the installation process.

### Step 1: System Preparation

```bash
# Update system
apt update && apt upgrade -y

# Install dependencies
apt install -y curl wget unzip sqlite3 jq openssl dnsutils net-tools

# Install nginx-full (critical for stream module)
apt install -y nginx-full

# Verify stream module
nginx -V 2>&1 | grep stream
```

### Step 2: Install Mosquitto

```bash
# Install Mosquitto
apt install -y mosquitto mosquitto-clients

# Stop default service
systemctl stop mosquitto
systemctl disable mosquitto
```

### Step 3: Configure Mosquitto

```bash
# Create secure configuration
cat > /etc/mosquitto/mosquitto.conf << 'EOF'
# MQTT TCP Listener
listener 1883
bind_address 0.0.0.0
protocol mqtt
allow_anonymous false

# MQTT WebSocket Listener
listener 9001
bind_address 0.0.0.0
protocol websockets
allow_anonymous false

# Authentication
password_file /etc/mosquitto/passwd

# Persistence and Logging
persistence true
persistence_location /var/lib/mosquitto/
log_dest file /var/log/mosquitto/mosquitto.log
EOF

# Create user credentials
mosquitto_passwd -c -b /etc/mosquitto/passwd netmaker your-secure-password

# Set permissions
chown mosquitto:mosquitto /etc/mosquitto/passwd
chmod 600 /etc/mosquitto/passwd
```

### Step 4: Install Netmaker Binary

```bash
# Get latest version
NETMAKER_VERSION=$(curl -s https://api.github.com/repos/gravitl/netmaker/releases/latest | jq -r .tag_name)

# Download for your architecture
wget -O /tmp/netmaker "https://github.com/gravitl/netmaker/releases/download/${NETMAKER_VERSION}/netmaker-linux-amd64"

# Install binary
chmod +x /tmp/netmaker
mv /tmp/netmaker /usr/local/bin/netmaker

# Create directories
mkdir -p /etc/netmaker /opt/netmaker/{data,logs} /var/log/netmaker
```

### Step 5: Configure Netmaker

```bash
# Generate master key
MASTER_KEY=$(openssl rand -hex 32)

# Create configuration
cat > /etc/netmaker/config.yaml << EOF
version: v0.20.0

server:
  host: "0.0.0.0"
  apiport: 8081
  grpcport: 8082

# MQTT Configuration (CRITICAL: Use correct protocol)
messagequeue:
  host: "127.0.0.1"
  port: 1883
  endpoint: "mqtt://netmaker:your-secure-password@127.0.0.1:1883"
  username: "netmaker"
  password: "your-secure-password"

# API Configuration
api:
  endpoint: "https://netmaker.yourdomain.com"

masterkey: "${MASTER_KEY}"
EOF

# Set permissions
chmod 600 /etc/netmaker/config.yaml
```

### Step 6: Configure Nginx

```bash
# Main nginx configuration with stream module
cat > /etc/nginx/nginx.conf << 'EOF'
user www-data;
worker_processes auto;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

http {
    include /etc/nginx/mime.types;
    include /etc/nginx/sites-enabled/*;
}

# Stream configuration for MQTT TCP proxy
stream {
    upstream mqtt_backend {
        server 127.0.0.1:1883;
    }
    
    server {
        listen 1883;
        proxy_pass mqtt_backend;
    }
}
EOF

# Create site configuration
cat > /etc/nginx/sites-available/netmaker << 'EOF'
# Netmaker API
server {
    listen 443 ssl http2;
    server_name netmaker.yourdomain.com;
    
    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

# Enable site
ln -s /etc/nginx/sites-available/netmaker /etc/nginx/sites-enabled/
nginx -t
```

### Step 7: Create SystemD Services

```bash
# Netmaker service
cat > /etc/systemd/system/netmaker.service << 'EOF'
[Unit]
Description=Netmaker Server
After=network-online.target mosquitto.service
Requires=mosquitto.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/netmaker
ExecStart=/usr/local/bin/netmaker --config /etc/netmaker/config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# Enable services
systemctl daemon-reload
systemctl enable mosquitto netmaker nginx
```

### Step 8: Start Services

```bash
# Start in order
systemctl start mosquitto
systemctl start nginx
systemctl start netmaker

# Verify status
systemctl status mosquitto netmaker nginx
```

## Post-Installation

### Initial Setup

1. **Access Dashboard**: Navigate to `https://dashboard.yourdomain.com`
2. **Create Admin User**: Follow the setup wizard
3. **Create First Network**: Set up your mesh network
4. **Download Netclient**: Install on client devices

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

### Configuration Management

Important files and locations:
- **Netmaker Config**: `/etc/netmaker/config.yaml`
- **Mosquitto Config**: `/etc/mosquitto/mosquitto.conf`
- **Nginx Config**: `/etc/nginx/sites-available/netmaker`
- **Logs**: `/var/log/netmaker/`, `/var/log/mosquitto/`
- **Data**: `/opt/netmaker/data/`

### Security Considerations

1. **Change Default Passwords**: Update MQTT and master key
2. **Firewall Configuration**: Restrict access to required ports
3. **SSL Certificate Renewal**: Let's Encrypt auto-renewal
4. **Regular Updates**: Keep Netmaker binary updated

## Integration with OVS

### Pre-Integration Steps

If you plan to use netmaker-ovs-integration:

1. **Complete Base Installation**: Ensure Netmaker is fully working
2. **Verify Interface Creation**: Wait for Netmaker to create network interfaces
3. **Test Connectivity**: Confirm MQTT and API functionality

### OVS Integration Workflow

```bash
# After successful Netmaker installation
cd ../netmaker-ovs-integration

# Run OVS integration
sudo ./install-interactive.sh

# The integration script will detect:
# - Existing Netmaker interfaces (nm-*)
# - Running Netmaker services
# - Proper configuration files
```

### Post-Integration Verification

```bash
# Check OVS bridges
ovs-vsctl list-br

# Verify Netmaker interfaces in OVS
ovs-vsctl list-ports ovsbr0

# Test network connectivity
ping [remote-netmaker-node]
```

## Troubleshooting

### Common Issues

#### 1. MQTT Connection Failures
**Error**: `Fatal: could not connect to broker, token timeout, exiting`

**Solutions**:
- Check MQTT broker endpoint uses `mqtt://` not `http://`
- Verify Mosquitto is listening on `0.0.0.0:1883`, not `127.0.0.1:1883`
- Confirm MQTT credentials are correct
- Test MQTT connectivity: `mosquitto_pub -h 127.0.0.1 -p 1883 -t test -m hello`

#### 2. Nginx Stream Module Missing
**Error**: `"stream" directive is not allowed here`

**Solutions**:
- Install `nginx-full` instead of `nginx-light`
- Verify stream module: `nginx -V 2>&1 | grep stream`
- Reinstall nginx with stream support

#### 3. SSL Certificate Issues
**Error**: Certificate generation fails

**Solutions**:
- Verify DNS resolution: `dig +short netmaker.yourdomain.com`
- Check domain points to correct IP
- Ensure ports 80 and 443 are accessible
- Run certbot manually: `certbot --nginx -d yourdomain.com`

#### 4. Service Startup Failures
**Error**: Services fail to start

**Solutions**:
- Check service logs: `journalctl -u netmaker -n 50`
- Verify configuration files: `nginx -t`, `mosquitto -c /etc/mosquitto/mosquitto.conf -t`
- Check port conflicts: `ss -tlnp | grep -E '8081|1883|9001'`

### Diagnostic Commands

```bash
# System status
systemctl status netmaker mosquitto nginx

# Port verification
ss -tlnp | grep -E '80|443|1883|8081|9001'

# Network interfaces
ip addr show
ip link show | grep nm-

# Configuration validation
nginx -t
mosquitto -c /etc/mosquitto/mosquitto.conf -t

# API connectivity
curl -k https://localhost:8081/api/server/health

# MQTT connectivity  
mosquitto_pub -h 127.0.0.1 -p 1883 -t test -m hello -u netmaker -P password
```

### Log Locations

- **Installation Log**: `/var/log/ghostbridge-netmaker-install.log`
- **Netmaker Logs**: `journalctl -u netmaker`
- **Mosquitto Logs**: `/var/log/mosquitto/mosquitto.log`
- **Nginx Logs**: `/var/log/nginx/error.log`, `/var/log/nginx/access.log`

For additional troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

## Support

- **Documentation**: Check the `docs/` directory for additional guides
- **Issues**: Report problems via GitHub issues
- **Configuration Examples**: See `examples/` directory
- **Architecture Details**: Review `ARCHITECTURE.md`

---

This installation guide is based on real-world deployment experience from the GhostBridge project and addresses common pitfalls encountered during Netmaker installations.