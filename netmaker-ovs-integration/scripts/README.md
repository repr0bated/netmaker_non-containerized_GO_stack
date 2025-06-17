# Utility Scripts

This directory contains utility scripts for managing and troubleshooting your Netmaker installation.

## Scripts Overview

### `netmaker-diagnostics.sh`
**Purpose**: Comprehensive diagnostic script that analyzes your entire Netmaker installation

**Features**:
- System information and resource usage
- Service status analysis
- Network configuration review
- Port binding verification
- Configuration file validation
- Connectivity testing
- Log analysis
- SSL certificate status
- Automated recommendations

**Usage**:
```bash
sudo ./scripts/netmaker-diagnostics.sh
```

**Output**: Generates a detailed diagnostic report saved to `/tmp/netmaker-diagnostic-TIMESTAMP.txt`

### `validate-installation.sh`
**Purpose**: Validates that your Netmaker installation is working correctly

**Features**:
- Service status validation
- Port binding checks
- Configuration file syntax validation
- Connectivity testing
- Network interface verification
- SSL certificate validation
- Pass/fail validation summary

**Usage**:
```bash
sudo ./scripts/validate-installation.sh
```

**Exit Codes**:
- `0`: All validation checks passed
- `1`: Some validation checks failed

## When to Use These Scripts

### After Installation
Run both scripts to verify your installation:
```bash
# Validate installation
sudo ./scripts/validate-installation.sh

# If validation fails, run diagnostics
sudo ./scripts/netmaker-diagnostics.sh
```

### Troubleshooting Issues
When experiencing problems:
```bash
# Get comprehensive diagnostic information
sudo ./scripts/netmaker-diagnostics.sh

# Check current status
sudo ./scripts/validate-installation.sh
```

### Before Upgrades
Validate current state before making changes:
```bash
sudo ./scripts/validate-installation.sh
```

### Regular Monitoring
Run periodically to ensure system health:
```bash
# Weekly health check
sudo ./scripts/validate-installation.sh
```

## Script Features

### Color-Coded Output
- 🟢 **Green [✓]**: Success/working correctly
- 🟡 **Yellow [⚠]**: Warning/needs attention
- 🔴 **Red [✗]**: Error/critical issue
- 🔵 **Blue [i]**: Information/status

### Detailed Logging
All scripts create detailed log files for:
- Sharing with support
- Historical tracking
- Automated analysis

### Automated Recommendations
Scripts provide specific recommendations based on findings:
- Service startup commands
- Configuration fixes
- Installation corrections

## Common Issues Detected

### MQTT Broker Problems
- Incorrect binding address (127.0.0.1 vs 0.0.0.0)
- Wrong protocol in endpoints (http:// vs mqtt://)
- Authentication configuration issues
- Port binding failures

### Nginx Configuration Issues
- Missing stream module
- Invalid configuration syntax
- SSL certificate problems
- Site configuration errors

### Netmaker Service Issues
- Service startup failures
- Configuration file errors
- API connectivity problems
- Database connection issues

### Network Configuration
- Interface creation problems
- IP address assignment issues
- Routing table problems
- DNS resolution failures

## Example Usage Scenarios

### Scenario 1: Fresh Installation Validation
```bash
# After running install-interactive.sh
sudo ./scripts/validate-installation.sh

# Expected output:
# ✓ netmaker service is running
# ✓ mosquitto service is running  
# ✓ nginx service is running
# ✓ All critical validation checks passed!
```

### Scenario 2: MQTT Connection Troubleshooting
```bash
# When seeing "Fatal: could not connect to broker"
sudo ./scripts/netmaker-diagnostics.sh

# Look for in the output:
# ✗ CRITICAL: MQTT endpoint uses http:// instead of mqtt://
# ✗ CRITICAL: Mosquitto binds to 127.0.0.1 (should be 0.0.0.0)
```

### Scenario 3: Stream Module Issue
```bash
sudo ./scripts/netmaker-diagnostics.sh

# Look for:
# ✗ CRITICAL: Nginx stream module is missing (install nginx-full)
# ✗ Fix: apt remove nginx-light && apt install nginx-full
```

### Scenario 4: Pre-OVS Integration Check
```bash
# Before running netmaker-ovs-integration
sudo ./scripts/validate-installation.sh

# Ensure all services are working before OVS integration
```

## Integration with Main Installers

### install-interactive.sh
The interactive installer automatically runs validation at the end:
```bash
# Installation process includes:
validate_installation  # Built-in validation function
```

### install-dummy.sh
The dummy installer includes validation to ensure OVS integration requirements are met:
```bash
# Dummy installation includes:
validate_dummy_installation  # Checks dummy setup
```

## Customization

### Adding Custom Checks
To add custom validation checks:

1. **Edit validate-installation.sh**:
```bash
print_header "CUSTOM VALIDATION"
# Add your custom checks here
if [[ your_condition ]]; then
    print_status "Custom check passed"
else
    print_error "Custom check failed"
fi
```

2. **Edit netmaker-diagnostics.sh**:
```bash
print_header "CUSTOM DIAGNOSTICS"
# Add your diagnostic information here
echo "Custom diagnostic info" | tee -a "$REPORT_FILE"
```

### Environment-Specific Configurations
Modify scripts for your environment:

```bash
# Update domain names
sed -i 's/hobsonschoice\.net/yourdomain.com/g' *.sh

# Update IP addresses
sed -i 's/10\.0\.0\.101/your.container.ip/g' *.sh
```

## Troubleshooting the Scripts

### Permission Issues
```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run with sudo for system access
sudo ./scripts/script-name.sh
```

### Missing Dependencies
Scripts check for required tools and provide alternatives:
- `curl` for API testing
- `mosquitto_pub` for MQTT testing
- `dig` for DNS testing
- `openssl` for certificate analysis

### Log File Access
Log files are created in `/tmp/` with timestamps:
- `/tmp/netmaker-diagnostic-YYYYMMDD-HHMMSS.txt`
- `/tmp/netmaker-validation-YYYYMMDD-HHMMSS.log`

## Support

When seeking help, run the diagnostic script and share the output:

```bash
# Generate diagnostic report
sudo ./scripts/netmaker-diagnostics.sh

# Share the generated report file
cat /tmp/netmaker-diagnostic-*.txt
```

The diagnostic output contains all necessary information for troubleshooting while protecting sensitive data like passwords and keys.