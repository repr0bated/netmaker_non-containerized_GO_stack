# Troubleshooting Guide

This guide addresses common issues encountered during Netmaker installation and deployment, based on real-world troubleshooting from the GhostBridge project.

## Table of Contents

- [Critical Issues (Deployment Blockers)](#critical-issues-deployment-blockers)
- [MQTT Broker Issues](#mqtt-broker-issues)
- [Nginx Configuration Issues](#nginx-configuration-issues)
- [Network Configuration Issues](#network-configuration-issues)
- [SSL/TLS Certificate Issues](#ssltls-certificate-issues)
- [Service Startup Issues](#service-startup-issues)
- [Container/LXC Specific Issues](#containerlxc-specific-issues)
- [Diagnostic Commands](#diagnostic-commands)
- [Configuration Validation](#configuration-validation)
- [Performance Issues](#performance-issues)

## Critical Issues (Deployment Blockers)

These issues will prevent Netmaker from functioning and must be resolved first.

### 1. MQTT Broker Connection Timeout

**Error**: 
```
Fatal: could not connect to broker, token timeout, exiting ...
```

**Root Causes**:
- Incorrect MQTT broker endpoint protocol
- Mosquitto not binding to correct interface
- Missing nginx stream module
- Authentication configuration errors

**Solutions**:

#### Fix 1: Correct MQTT Endpoint Protocol
```bash
# WRONG (will cause timeout)
endpoint: "http://80.209.240.244:1883"

# CORRECT 
endpoint: "mqtt://80.209.240.244:1883"
# or with authentication
endpoint: "mqtt://username:password@80.209.240.244:1883"
```

#### Fix 2: Mosquitto Binding Configuration
```bash
# Check current Mosquitto configuration
cat /etc/mosquitto/mosquitto.conf

# WRONG (only local access)
listener 1883
bind_address 127.0.0.1

# CORRECT (accessible from network)
listener 1883
bind_address 0.0.0.0
protocol mqtt
```

#### Fix 3: Verify Mosquitto is Listening
```bash
# Check if Mosquitto is listening on correct interface
ss -tlnp | grep 1883

# Should show:
# LISTEN 0 100 0.0.0.0:1883 0.0.0.0:*

# If showing 127.0.0.1:1883, reconfigure bind_address
```

#### Fix 4: Test MQTT Connectivity
```bash
# Test local connection
mosquitto_pub -h 127.0.0.1 -p 1883 -t test/topic -m "hello"

# Test with authentication
mosquitto_pub -h 127.0.0.1 -p 1883 -t test/topic -m "hello" -u username -P password

# Test external connection (from outside container/host)
mosquitto_pub -h your-server-ip -p 1883 -t test/topic -m "hello" -u username -P password
```

### 2. Nginx Stream Module Missing

**Error**:
```
nginx: [emerg] "stream" directive is not allowed here
```

**Root Cause**: nginx-light package doesn't include stream module

**Solution**:
```bash
# Remove nginx-light
apt remove nginx-light

# Install nginx-full with stream module
apt install nginx-full

# Verify stream module is available
nginx -V 2>&1 | grep stream

# Should show: --with-stream --with-stream_ssl_module
```

**Verification**:
```bash
# Test nginx configuration
nginx -t

# Should not show stream directive errors
```

## MQTT Broker Issues

### Anonymous Access Problems

**Issue**: Security vulnerability or authentication failures

**Mosquitto Configuration**:
```bash
# Secure configuration (RECOMMENDED)
listener 1883
bind_address 0.0.0.0
protocol mqtt
allow_anonymous false
password_file /etc/mosquitto/passwd

# Create password file
mosquitto_passwd -c -b /etc/mosquitto/passwd netmaker secure-password

# Set permissions
chown mosquitto:mosquitto /etc/mosquitto/passwd
chmod 600 /etc/mosquitto/passwd
```

### MQTT WebSocket Issues

**Error**: WebSocket connections failing

**Solution**:
```bash
# Add WebSocket listener to mosquitto.conf
listener 9001
bind_address 0.0.0.0
protocol websockets
allow_anonymous false
```

**Test WebSocket**:
```bash
# Check WebSocket port is listening
ss -tlnp | grep 9001

# Test with browser WebSocket client or curl
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
     -H "Sec-WebSocket-Version: 13" -H "Sec-WebSocket-Key: test" \
     http://your-server:9001/
```

### MQTT Connection Refused

**Error**: Connection refused on port 1883

**Diagnostic Steps**:
```bash
# Check if Mosquitto is running
systemctl status mosquitto

# Check if port is listening
ss -tlnp | grep 1883

# Check firewall rules
ufw status
iptables -L | grep 1883

# Test local connectivity
telnet 127.0.0.1 1883
```

**Common Fixes**:
```bash
# Restart Mosquitto service
systemctl restart mosquitto

# Check Mosquitto logs
journalctl -u mosquitto -f

# Ensure Mosquitto starts on boot
systemctl enable mosquitto
```

## Nginx Configuration Issues

### Stream Configuration Validation

**Test Stream Configuration**:
```bash
# Validate nginx configuration
nginx -t

# Check if stream module is loaded
nginx -V 2>&1 | grep -o with-stream

# Test stream configuration specifically
nginx -T | grep -A 10 "stream {"
```

### MQTT TCP Proxy Issues

**Problem**: MQTT TCP connections not being proxied correctly

**Solution**:
```bash
# Correct stream configuration
cat > /etc/nginx/conf.d/mqtt-stream.conf << 'EOF'
stream {
    upstream mqtt_backend {
        server 10.0.0.101:1883;  # Container IP
    }
    
    server {
        listen 1883;
        proxy_pass mqtt_backend;
        proxy_timeout 1s;
        proxy_responses 1;
        error_log /var/log/nginx/mqtt_stream.log;
    }
}
EOF

# Reload nginx
nginx -s reload
```

### Nginx Service Issues

**Problem**: Nginx fails to start after configuration changes

**Diagnostic**:
```bash
# Check nginx error logs
tail -f /var/log/nginx/error.log

# Test configuration syntax
nginx -t

# Check if nginx is running
systemctl status nginx

# Check port conflicts
ss -tlnp | grep -E ":80|:443"
```

**Common Issues**:
- Port conflicts with other services
- Syntax errors in configuration files
- Missing SSL certificate files
- Incorrect upstream server definitions

## Network Configuration Issues

### Container IP Mismatch

**Problem**: Expected container IP doesn't match actual IP

**Diagnostic**:
```bash
# Check actual container IP
ip addr show

# In LXC container, check assigned IP
cat /etc/systemd/network/*

# On Proxmox host, check container configuration
pct config 100  # Replace 100 with container ID
```

**Solution**:
```bash
# Update configuration to match actual IP
# Update nginx upstream configuration
# Update Netmaker broker endpoint if needed
```

### Bridge Configuration Issues

**Problem**: Network bridge not properly configured

**For Standard Linux Bridges** (Recommended):
```bash
# Check bridge configuration
ip link show vmbr0
brctl show vmbr0

# Verify container is attached to bridge
brctl show | grep vmbr0
```

**For OVS Bridges** (Advanced):
```bash
# Check OVS bridge status
ovs-vsctl show
ovs-vsctl list-br

# Check bridge ports
ovs-vsctl list-ports ovsbr0
```

### DNS Resolution Issues

**Problem**: Domain names not resolving correctly

**Diagnostic**:
```bash
# Test domain resolution
dig +short netmaker.hobsonschoice.net
nslookup broker.hobsonschoice.net

# Check /etc/hosts for local overrides
cat /etc/hosts

# Test from different locations
dig @8.8.8.8 netmaker.hobsonschoice.net
```

**Solutions**:
- Update DNS A records to point to correct IP
- Wait for DNS propagation (up to 48 hours)
- Use IP addresses temporarily for testing
- Check domain registrar DNS settings

## SSL/TLS Certificate Issues

### Let's Encrypt Certificate Generation Fails

**Error**: Certbot fails to generate certificates

**Common Causes**:
- Domain doesn't resolve to server IP
- Ports 80/443 not accessible
- Nginx configuration errors
- Rate limiting

**Solutions**:

#### Manual Certificate Generation
```bash
# Stop nginx temporarily
systemctl stop nginx

# Generate certificates using standalone mode
certbot certonly --standalone \
  -d netmaker.hobsonschoice.net \
  -d broker.hobsonschoice.net \
  -d dashboard.hobsonschoice.net \
  --email admin@hobsonschoice.net \
  --agree-tos --no-eff-email

# Start nginx
systemctl start nginx

# Configure nginx to use certificates
```

#### DNS Challenge Method
```bash
# Use DNS challenge if HTTP challenge fails
certbot certonly --manual --preferred-challenges dns \
  -d *.hobsonschoice.net \
  --email admin@hobsonschoice.net \
  --agree-tos
```

### Certificate Renewal Issues

**Setup Automatic Renewal**:
```bash
# Test renewal
certbot renew --dry-run

# Check renewal timer
systemctl status certbot.timer

# Enable if not active
systemctl enable certbot.timer
```

## Service Startup Issues

### SystemD Service Dependencies

**Problem**: Services starting in wrong order

**Solution**:
```bash
# Correct service dependencies in netmaker.service
[Unit]
Description=Netmaker Server
After=network-online.target mosquitto.service
Requires=mosquitto.service
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/local/bin/netmaker --config /etc/netmaker/config.yaml
Restart=always
RestartSec=5
```

### Service Configuration Validation

**Check Service Status**:
```bash
# Check all related services
systemctl status netmaker mosquitto nginx

# Check service logs
journalctl -u netmaker -f
journalctl -u mosquitto -f
journalctl -u nginx -f

# Check service startup order
systemctl list-dependencies netmaker
```

### Netmaker Binary Issues

**Problem**: Netmaker binary fails to start

**Diagnostic**:
```bash
# Test binary directly
/usr/local/bin/netmaker --version
/usr/local/bin/netmaker --config /etc/netmaker/config.yaml --help

# Check binary permissions
ls -la /usr/local/bin/netmaker

# Verify configuration file
cat /etc/netmaker/config.yaml
```

## Container/LXC Specific Issues

### LXC Container Networking

**Problem**: Container cannot reach external services

**Diagnostic**:
```bash
# From inside container
ping 8.8.8.8  # Test internet connectivity
ping 10.0.0.1  # Test gateway

# Check routing
ip route show
cat /etc/resolv.conf

# From host, test container connectivity
ping 10.0.0.101  # Container IP
```

### Container Resource Limits

**Problem**: Container hitting resource limits

**Check Container Limits**:
```bash
# On Proxmox host
pct config 100

# Inside container
free -h
df -h
cat /proc/cpuinfo | grep processor | wc -l
```

### Container Service Issues

**Problem**: Services behave differently in containers

**Common Issues**:
- SystemD not fully available
- Network namespace isolation
- File permission issues
- Resource constraints

**Solutions**:
```bash
# Ensure SystemD is working
systemctl --version
systemctl list-units

# Check container capabilities
cat /proc/self/status | grep Cap
```

## Diagnostic Commands

### Comprehensive System Check

```bash
#!/bin/bash
# Netmaker Diagnostic Script

echo "=== Netmaker Diagnostic Report ==="
echo "Generated: $(date)"
echo

echo "=== System Information ==="
uname -a
cat /etc/os-release | grep -E "NAME|VERSION"
free -h
df -h /

echo "=== Service Status ==="
systemctl status netmaker --no-pager
systemctl status mosquitto --no-pager  
systemctl status nginx --no-pager

echo "=== Network Configuration ==="
ip addr show
ip route show
ss -tlnp | grep -E ":80|:443|:1883|:8081|:9001"

echo "=== DNS Resolution ==="
dig +short netmaker.hobsonschoice.net
dig +short broker.hobsonschoice.net

echo "=== Configuration Files ==="
echo "--- Netmaker Config ---"
cat /etc/netmaker/config.yaml

echo "--- Mosquitto Config ---"
cat /etc/mosquitto/mosquitto.conf

echo "=== Recent Logs ==="
echo "--- Netmaker Logs ---"
journalctl -u netmaker --no-pager -n 10

echo "--- Mosquitto Logs ---"
journalctl -u mosquitto --no-pager -n 10

echo "=== Connectivity Tests ==="
echo "--- MQTT Test ---"
timeout 5 mosquitto_pub -h 127.0.0.1 -p 1883 -t test -m "diagnostic" || echo "MQTT test failed"

echo "--- API Test ---"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://127.0.0.1:8081/api/server/health

echo "=== End Diagnostic Report ==="
```

### Port Verification Script

```bash
#!/bin/bash
# Check all required ports

ports=(80 443 1883 8081 9001)

for port in "${ports[@]}"; do
    if ss -tlnp | grep -q ":$port "; then
        service=$(ss -tlnp | grep ":$port " | awk '{print $7}' | cut -d'"' -f2)
        echo "✓ Port $port is listening ($service)"
    else
        echo "✗ Port $port is not listening"
    fi
done
```

## Configuration Validation

### Mosquitto Configuration Validation

```bash
# Test configuration syntax
mosquitto -c /etc/mosquitto/mosquitto.conf -t

# Check effective configuration
mosquitto -c /etc/mosquitto/mosquitto.conf -v
```

### Nginx Configuration Validation

```bash
# Test main configuration
nginx -t

# Show complete configuration
nginx -T

# Test specific includes
nginx -t -c /etc/nginx/nginx.conf
```

### Netmaker Configuration Validation

```bash
# Validate YAML syntax
python3 -c "import yaml; yaml.safe_load(open('/etc/netmaker/config.yaml'))"

# Check configuration with Netmaker binary
/usr/local/bin/netmaker --config /etc/netmaker/config.yaml --version
```

## Performance Issues

### High CPU Usage

**Diagnostic**:
```bash
# Check process CPU usage
top -p $(pgrep netmaker)
htop

# Check system load
uptime
iostat 1

# Profile Netmaker process
strace -p $(pgrep netmaker)
```

### High Memory Usage

**Diagnostic**:
```bash
# Check memory usage
free -h
ps aux | grep netmaker
cat /proc/$(pgrep netmaker)/status | grep -E "VmRSS|VmSize"

# Check for memory leaks
valgrind /usr/local/bin/netmaker --config /etc/netmaker/config.yaml
```

### Network Performance Issues

**Diagnostic**:
```bash
# Test network bandwidth
iperf3 -s  # On server
iperf3 -c server-ip  # On client

# Check network latency
ping -c 10 netmaker-server

# Monitor network interfaces
iftop
nethogs
```

## Getting Help

### Log Collection

When seeking help, collect these logs:
```bash
# Service logs
journalctl -u netmaker --no-pager -n 100 > netmaker.log
journalctl -u mosquitto --no-pager -n 100 > mosquitto.log
journalctl -u nginx --no-pager -n 100 > nginx.log

# Configuration files
cp /etc/netmaker/config.yaml netmaker-config.yaml
cp /etc/mosquitto/mosquitto.conf mosquitto-config.conf

# System information
uname -a > system-info.txt
ip addr show > network-config.txt
ss -tlnp > listening-ports.txt
```

### Support Channels

- **GitHub Issues**: Report bugs with log files
- **Documentation**: Check installation guide for common solutions
- **Community**: Join Netmaker community for support

---

This troubleshooting guide is based on real-world deployment experience from the GhostBridge project. Most issues can be resolved by following the solutions provided above.