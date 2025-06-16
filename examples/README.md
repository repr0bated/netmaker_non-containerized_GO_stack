# Configuration Examples

This directory contains production-ready configuration examples based on the GhostBridge project deployment experience.

## Files Overview

### `ghostbridge-production-config.yaml`
- **Purpose**: Production Netmaker configuration for GhostBridge deployment
- **Key Features**: 
  - Correct MQTT endpoint configuration (addresses timeout issues)
  - Security settings optimized for production
  - Based on hobsonschoice.net domain structure
- **Usage**: Copy to `/etc/netmaker/config.yaml` and customize

### `mosquitto-secure.conf`
- **Purpose**: Secure Mosquitto MQTT broker configuration
- **Key Features**:
  - Binds to `0.0.0.0` instead of `127.0.0.1` (critical fix)
  - Disables anonymous access for security
  - Includes both TCP and WebSocket listeners
- **Usage**: Copy to `/etc/mosquitto/mosquitto.conf`

### `nginx-ghostbridge.conf`
- **Purpose**: Complete nginx configuration with stream module
- **Key Features**:
  - Stream module configuration for MQTT TCP proxy
  - SSL termination for all subdomains
  - Proper proxy headers and WebSocket support
- **Usage**: Copy to `/etc/nginx/nginx.conf`

## Configuration Notes

### Critical Settings

#### MQTT Broker Endpoint
```yaml
# WRONG - will cause "token timeout" errors
endpoint: "http://broker.hobsonschoice.net:1883"

# CORRECT - proper MQTT protocol
endpoint: "mqtt://netmaker:password@127.0.0.1:1883"
```

#### Mosquitto Binding
```conf
# WRONG - only accessible locally
listener 1883
bind_address 127.0.0.1

# CORRECT - accessible from network
listener 1883
bind_address 0.0.0.0
```

#### Nginx Stream Module
```nginx
# CRITICAL - must have stream module for MQTT TCP proxy
stream {
    upstream mqtt_backend {
        server 10.0.0.101:1883;
    }
    
    server {
        listen 1883;
        proxy_pass mqtt_backend;
    }
}
```

### Security Considerations

1. **Change Default Passwords**: Update all example passwords
2. **Generate Secure Keys**: Replace `REPLACE_WITH_SECURE_MASTER_KEY`
3. **SSL Certificates**: Ensure proper Let's Encrypt setup
4. **Firewall Rules**: Restrict access to required ports only

### Customization for Your Environment

#### Update Domain Names
Replace `hobsonschoice.net` with your domain:
```bash
sed -i 's/hobsonschoice\.net/yourdomain.com/g' *.conf *.yaml
```

#### Update IP Addresses
Replace container IP `10.0.0.101` with your setup:
```bash
sed -i 's/10\.0\.0\.101/your.container.ip/g' *.conf *.yaml
```

#### Update Credentials
1. Generate secure MQTT password:
   ```bash
   openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
   ```

2. Generate master key:
   ```bash
   openssl rand -hex 32
   ```

## Testing Configurations

### Validate Nginx Configuration
```bash
nginx -t -c /path/to/nginx-ghostbridge.conf
```

### Test Mosquitto Configuration
```bash
mosquitto -c /path/to/mosquitto-secure.conf -v
```

### Validate Netmaker Configuration
```bash
/usr/local/bin/netmaker --config /path/to/ghostbridge-production-config.yaml --version
```

## Common Issues

### Stream Module Not Available
**Error**: `"stream" directive is not allowed here`
**Solution**: Install `nginx-full` instead of `nginx-light`

### MQTT Connection Timeout
**Error**: `Fatal: could not connect to broker, token timeout`
**Solution**: Check MQTT endpoint uses `mqtt://` protocol and Mosquitto binds to `0.0.0.0`

### SSL Certificate Issues
**Error**: Certificate validation fails
**Solution**: Ensure DNS points to correct IP and ports 80/443 are accessible

## Production Deployment Checklist

- [ ] Update all domain names to your domain
- [ ] Update all IP addresses to match your network
- [ ] Generate and update all passwords and keys
- [ ] Test nginx configuration syntax
- [ ] Test mosquitto configuration syntax
- [ ] Verify DNS resolution for all subdomains
- [ ] Ensure SSL certificates are properly configured
- [ ] Test MQTT connectivity locally and remotely
- [ ] Verify Netmaker API accessibility
- [ ] Test complete mesh network functionality

## Support

These configurations are based on real-world troubleshooting from the GhostBridge project. For issues:

1. Check the main [TROUBLESHOOTING.md](../TROUBLESHOOTING.md)
2. Review the [INSTALLATION-GUIDE.md](../INSTALLATION-GUIDE.md)
3. Report issues via GitHub with configuration details