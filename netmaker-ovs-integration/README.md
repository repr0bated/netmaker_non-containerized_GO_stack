# Netmaker Non-Containerized GO Stack Installation

Complete installation and configuration suite for deploying Netmaker as a native GO binary stack on Debian/Ubuntu systems, without containers.

## Features

- **Native Binary Installation**: Direct GO binary deployment, no Docker/containers required
- **Complete Service Stack**: Netmaker server, Mosquitto MQTT, nginx reverse proxy  
- **Automated Configuration**: Database setup, SSL certificates, service dependencies
- **Interactive Installation**: Guided setup with intelligent system detection
- **Production Ready**: SystemD integration, monitoring, backup/restore
- **Troubleshooting Tools**: Comprehensive diagnostic and repair utilities

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Netmaker GO Stack                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Public Internet                          │
│                80.209.240.244:443 (HTTPS)                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Nginx Reverse Proxy                        │
│          • SSL Termination (Let's Encrypt)                 │
│          • Domain routing (*.hobsonschoice.net)            │
│          • API/UI/Broker proxying                          │
└─────────────────────────────────────────────────────────────┘
                              │
                 ┌────────────┼────────────┐
                 ▼            ▼            ▼
┌─────────────┐ ┌─────────────┐ ┌─────────────┐
│  Netmaker   │ │  Mosquitto  │ │   Static    │
│   Server    │ │    MQTT     │ │  Web UI     │
│             │ │   Broker    │ │             │
│ :8081 (API) │ │ :1883 (TCP) │ │   :80       │
│             │ │ :9001 (WS)  │ │             │
└─────────────┘ └─────────────┘ └─────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   SQLite Database                          │
│              /opt/netmaker/data/                            │
└─────────────────────────────────────────────────────────────┘
```

## Repository Structure

```
netmaker_non-containerized_GO_stack/
├── 📄 README.md                              # This file
├── 📄 INSTALLATION-GUIDE.md                  # Step-by-step installation
├── 📄 TROUBLESHOOTING.md                     # Common issues and solutions
├── 📄 ARCHITECTURE.md                        # Technical architecture guide
├── 📄 .gitignore                             # Git ignore patterns
│
├── 🔧 Installation Scripts
│   ├── 📄 install-interactive.sh             # Interactive installer (RECOMMENDED)
│   ├── 📄 install-dummy.sh                   # Dummy installer for OVS integration testing
│   ├── 📄 remove-dummy.sh                    # Remove dummy installation (auto-generated)
│   ├── 📄 install.sh                         # Standard automated installer  
│   ├── 📄 pre-install.sh                     # Pre-installation validation
│   └── 📄 uninstall.sh                       # Complete removal
│
├── ⚙️ config/
│   ├── 📄 netmaker.yaml.template             # Netmaker configuration template
│   ├── 📄 mosquitto.conf.template            # Mosquitto MQTT configuration
│   ├── 📄 nginx-netmaker.conf.template       # Nginx reverse proxy config
│   └── 📄 systemd-templates/                 # SystemD service templates
│       ├── 📄 netmaker.service.template
│       ├── 📄 mosquitto.service.template
│       └── 📄 netmaker-ui.service.template
│
├── 🔨 scripts/
│   ├── 📄 download-netmaker.sh               # Netmaker binary downloader
│   ├── 📄 setup-database.sh                  # Database initialization  
│   ├── 📄 configure-nginx.sh                 # Nginx configuration setup
│   ├── 📄 setup-ssl.sh                       # SSL certificate management
│   ├── 📄 setup-mosquitto.sh                 # MQTT broker setup
│   └── 📄 validate-installation.sh           # Post-install validation
│
├── 🛠️ tools/
│   ├── 📄 netmaker-diagnostics.sh            # Comprehensive system diagnostics
│   ├── 📄 service-monitor.sh                 # Service health monitoring
│   ├── 📄 backup-restore.sh                  # Backup and restore utility
│   ├── 📄 update-netmaker.sh                 # Update Netmaker binary
│   └── 📄 network-troubleshoot.sh            # Network connectivity testing
│
├── 📚 docs/
│   ├── 📄 DEPLOYMENT-SCENARIOS.md            # Common deployment patterns
│   ├── 📄 SECURITY-HARDENING.md              # Security best practices
│   ├── 📄 PERFORMANCE-TUNING.md              # Performance optimization
│   ├── 📄 SSL-CERTIFICATE-GUIDE.md           # SSL setup and management
│   └── 📄 MIGRATION-FROM-CONTAINERS.md       # Migrating from Docker setup
│
├── 💡 examples/
│   ├── 📄 production-config.yaml             # Production-ready configuration
│   ├── 📄 development-config.yaml            # Development setup
│   ├── 📄 high-availability-config.yaml      # HA deployment configuration  
│   └── 📄 nginx-configs/                     # Various nginx configurations
│       ├── 📄 basic-proxy.conf
│       ├── 📄 ssl-hardened.conf
│       └── 📄 load-balanced.conf
│
└── 📖 reference/
    ├── 📄 BINARY-INSTALLATION-METHODS.md     # Different installation approaches
    ├── 📄 SYSTEMD-INTEGRATION.md             # SystemD service management
    ├── 📄 DATABASE-MANAGEMENT.md             # Database operations and maintenance
    └── 📄 MQTT-BROKER-INTEGRATION.md         # MQTT broker setup and integration
```

## Quick Start

### Method 1: Interactive Installation (RECOMMENDED)
```bash
# Clone the repository
git clone https://github.com/your-username/netmaker_non-containerized_GO_stack
cd netmaker_non-containerized_GO_stack

# Make scripts executable
chmod +x install-interactive.sh

# Run interactive installer
sudo ./install-interactive.sh
```

### Method 1a: Dummy Installation (For OVS Integration Testing)
If you need to test netmaker-ovs-integration before doing a real installation:
```bash
# Run dummy installer first
sudo ./install-dummy.sh

# Navigate to netmaker-ovs-integration and test
cd ../netmaker-ovs-integration
sudo ./install-interactive.sh

# Remove dummy setup and do real installation
cd ../netmaker_non-containerized_GO_stack
sudo ./remove-dummy.sh
sudo ./install-interactive.sh
```

### Method 2: Automated Installation
```bash
# Run pre-installation checks
sudo ./pre-install.sh

# Run automated installer
sudo ./install.sh
```

### Method 3: Manual Step-by-Step
See [INSTALLATION-GUIDE.md](INSTALLATION-GUIDE.md) for detailed manual installation instructions.

## System Requirements

### Minimum Requirements
- **OS**: Ubuntu 20.04+ / Debian 11+
- **CPU**: 1 core, 1.5 GHz
- **RAM**: 1 GB
- **Storage**: 5 GB free space
- **Network**: Public IP or proper port forwarding

### Recommended Requirements  
- **OS**: Ubuntu 22.04 LTS / Debian 12
- **CPU**: 2+ cores, 2.0+ GHz
- **RAM**: 2+ GB
- **Storage**: 20+ GB free space (for logs, backups)
- **Network**: Dedicated public IP, proper DNS setup

### Network Requirements
- **Ports**: 80, 443, 8081, 1883, 9001
- **DNS**: Valid domain with A records for subdomains
- **SSL**: Let's Encrypt or valid SSL certificates

## Installation Process

The installation follows these phases:

### Phase 1: Pre-Installation Validation
- System compatibility check
- Dependency verification  
- Port availability validation
- DNS resolution testing
- Existing installation detection

### Phase 2: Core Component Installation
- GO binary download and installation
- Mosquitto MQTT broker setup
- Nginx reverse proxy configuration
- SSL certificate generation/installation

### Phase 3: Service Configuration
- Netmaker configuration generation
- Database initialization
- SystemD service setup
- Service dependency configuration

### Phase 4: Post-Installation Validation
- Service startup verification
- Network connectivity testing
- SSL certificate validation
- API endpoint testing

## Key Features

### 🚀 **Native Performance**
- Direct GO binary execution (no container overhead)
- Optimized for bare metal and VM deployments
- Minimal resource footprint

### 🔧 **Production Ready**
- SystemD integration with proper dependencies
- Automatic service recovery and monitoring
- Comprehensive logging and diagnostics

### 🔒 **Security Focused**
- SSL/TLS encryption by default
- Secure service isolation
- Regular security updates and patches

### 📊 **Monitoring & Diagnostics**
- Built-in health checks and monitoring
- Comprehensive diagnostic tools
- Performance metrics and logging

### 🔄 **Maintenance Tools**
- Automated backup and restore
- Update management
- Configuration validation

## Supported Deployment Scenarios

### 1. **Single Server Deployment**
Complete Netmaker stack on one server with all services co-located.

### 2. **Multi-Server Deployment**  
Netmaker server, MQTT broker, and database on separate servers.

### 3. **High Availability Setup**
Load balanced Netmaker servers with shared database and MQTT cluster.

### 4. **Development Environment**
Lightweight setup for development and testing.

## Migration from Container Deployments

This repository includes tools for migrating from existing container-based Netmaker deployments:

- **Data Migration**: Export/import of existing networks and configurations
- **SSL Certificate Transfer**: Migration of existing certificates
- **Network Preservation**: Maintain existing network topologies
- **Downtime Minimization**: Rolling migration strategies

See [MIGRATION-FROM-CONTAINERS.md](docs/MIGRATION-FROM-CONTAINERS.md) for detailed migration procedures.

## Documentation

### Quick References
- [Installation Guide](INSTALLATION-GUIDE.md) - Complete installation instructions
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues and solutions
- [Architecture Guide](ARCHITECTURE.md) - Technical architecture details

### Advanced Topics
- [Security Hardening](docs/SECURITY-HARDENING.md) - Security best practices
- [Performance Tuning](docs/PERFORMANCE-TUNING.md) - Optimization strategies
- [SSL Certificate Guide](docs/SSL-CERTIFICATE-GUIDE.md) - SSL setup and management

## Contributing

Contributions are welcome! Please read the contributing guidelines before submitting pull requests.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: Report bugs and feature requests via GitHub issues
- **Documentation**: Comprehensive documentation in the `docs/` directory
- **Diagnostics**: Use built-in diagnostic tools for troubleshooting

## Acknowledgments

- **Netmaker Project** - Core mesh networking platform
- **GhostBridge Project** - Real-world deployment testing and validation
- **Community Contributors** - Bug reports, feature requests, and improvements

---

**Note**: This is a community-maintained installation suite. While thoroughly tested, please review configurations and security settings for your specific environment before production deployment.