# Changelog

All notable changes to the GhostBridge Netmaker Non-Containerized GO Stack project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2024-12-19

### Added
- **Interactive Installation Script** (`install-interactive.sh`) - Complete rewrite based on GhostBridge troubleshooting
- **Dummy Installation Script** (`install-dummy.sh`) - For testing OVS integration before real installation
- **Comprehensive Pre-flight Validation** - Detects critical issues before installation
- **Real-world Problem Fixes** - Addresses MQTT broker connection failures, nginx stream issues
- **Progressive Installation Workflow** - Tests each component before proceeding
- **Detailed Installation Guide** - Step-by-step instructions for all deployment scenarios
- **Comprehensive Troubleshooting Guide** - Based on actual deployment issues and solutions
- **Security-first Configuration** - MQTT authentication, SSL certificates, secure defaults
- **Multi-deployment Support** - Single server, Proxmox+LXC, multi-server, development
- **Automatic Cleanup Scripts** - Backup creation and removal utilities

### Changed
- **MQTT Configuration** - Now binds to `0.0.0.0` instead of `127.0.0.1` (critical fix)
- **Nginx Installation** - Uses `nginx-full` instead of `nginx-light` for stream module support
- **Protocol Specification** - Uses correct `mqtt://` protocol instead of `http://` for broker endpoints
- **Service Dependencies** - Proper SystemD service ordering and dependency management
- **Configuration Validation** - Tests each service before proceeding to next step

### Fixed
- **Critical MQTT Broker Connection Timeout** - "Fatal: could not connect to broker, token timeout" error
- **Nginx Stream Module Missing** - Ensures stream module is available for MQTT TCP proxy
- **Anonymous MQTT Access** - Disables anonymous access by default for security
- **Container IP Mismatch** - Handles discrepancies between expected and actual container IPs
- **DNS Resolution Issues** - Validates domain resolution before SSL certificate generation
- **Service Startup Failures** - Proper service ordering and dependency management

### Security
- **MQTT Authentication** - Generated secure credentials with 25-character passwords
- **SSL Certificate Management** - Automated Let's Encrypt certificate generation
- **Access Control Lists** - MQTT user permissions and topic restrictions
- **Secure File Permissions** - Proper ownership and permissions on configuration files
- **Service Isolation** - SystemD security features and restricted service access

## [1.0.0] - 2024-12-18

### Added
- Initial repository structure
- Basic installation scripts
- Configuration templates
- Documentation framework

### Notes
- This version represents the baseline before the comprehensive rewrite
- Based on standard Netmaker installation procedures
- Limited real-world testing and validation

---

## Key Improvements in v2.0.0

### Problem-Focused Design
The v2.0.0 release is specifically designed to address the most common and critical issues encountered during Netmaker installations, particularly:

1. **MQTT Broker Connection Failures** - The #1 cause of installation failures
2. **Nginx Stream Module Issues** - Critical for MQTT TCP proxy functionality  
3. **Network Configuration Problems** - Especially in Proxmox/LXC environments
4. **Security Vulnerabilities** - Anonymous MQTT access and weak authentication
5. **Service Dependency Issues** - Improper startup ordering causing failures

### Real-World Validation
All fixes and improvements in v2.0.0 are based on:
- Extensive troubleshooting documentation from actual deployments
- Multiple failed installation attempts and their resolutions
- Testing in Proxmox/LXC environments matching GhostBridge architecture
- Integration testing with netmaker-ovs-integration scripts

### Backward Compatibility
- Configuration files from v1.0.0 should be backed up before upgrade
- Some configuration parameters have changed for security and reliability
- Existing installations may need to be reconfigured for optimal performance

### Migration from v1.0.0
```bash
# Backup existing configuration
sudo cp /etc/netmaker/config.yaml /etc/netmaker/config.yaml.v1.backup

# Remove old installation (if problematic)
sudo ./uninstall.sh

# Run new interactive installer
sudo ./install-interactive.sh
```

### Future Releases
- v2.1.0: Enhanced monitoring and diagnostics
- v2.2.0: High availability and clustering support
- v2.3.0: Advanced security features and hardening
- v3.0.0: Integration with additional mesh networking solutions