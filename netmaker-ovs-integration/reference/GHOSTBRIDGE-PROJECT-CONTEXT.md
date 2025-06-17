# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview: GhostBridge
GhostBridge is a Netmaker-based WireGuard mesh network controller deployment on Proxmox VE with LXC containers.

### Architecture
- **Proxmox Host**: 80.209.240.244 (public) / 10.0.0.1 (private bridge vmbr0)
- **Netmaker LXC Container**: 10.0.0.101 (ghostbridge container ID 100)
- **Domain**: hobsonschoice.net with subdomains (netmaker., api., broker., proxmox., ghostbridge.)
- **Services**: 
  - Nginx reverse proxy (Proxmox host)
  - Mosquitto MQTT broker (LXC container)
  - Netmaker server (LXC container)

### Current Status & Critical Issues
1. **MQTT Broker Connection Failure**: Netmaker fails with "Fatal: could not connect to broker, token timeout, exiting"
2. **Mosquitto Binding**: Must listen on 0.0.0.0:1883 (TCP) and 0.0.0.0:9001 (WebSocket), not just 127.0.0.1
3. **Netmaker Config**: Should connect to local Mosquitto via `ws://127.0.0.1:9001/mqtt`, not public IP
4. **Nginx Stream**: Requires nginx-full package and stream module for raw MQTT TCP proxy on port 1883

### Network Configuration
- Proxmox uses standard Linux bridges (vmbr0 for public, vmbr1 for private)
- LXC container networking: `bridge=vmbr0,ip=10.0.0.101/24,gw=10.0.0.1`
- Avoid VLAN 505 references (handled upstream by ISP)
- DNS: 8.8.8.8, 8.8.4.4

### Key Files & Locations
- Mosquitto config: `/etc/mosquitto/mosquitto.conf`
- Netmaker config: `/etc/netmaker/config.yaml`
- Nginx config: `/etc/nginx/sites-available/netmaker-proxy.conf`
- Systemd services: `netmaker.service`, `mosquitto.service`

### SSL Configuration
- Let's Encrypt certificates for hobsonschoice.net domains
- Nginx handles HTTPS termination and proxying to HTTP backends

### Todo Tasks in Progress
1. Fix Mosquitto configuration in LXC container (IN PROGRESS)
2. Fix Netmaker broker endpoint configuration
3. Fix nginx stream configuration on Proxmox host
4. Create comprehensive troubleshooting script
5. Create master deployment script

### Common Commands
- Check Netmaker status: `systemctl status netmaker.service`
- Check Mosquitto status: `systemctl status mosquitto`
- View Netmaker logs: `journalctl -u netmaker.service -f`
- Check listening ports: `ss -tlnp | grep -E '1883|9001|8081'`
- Test MQTT: `mosquitto_pub -h 127.0.0.1 -p 1883 -t test -m hello`

### Deployment Notes
- Scripts should be run in sequence: Mosquitto fix → Netmaker config fix → Nginx stream fix
- Always backup configs before modification
- Reboot Proxmox host after network interface changes
- LXC container recreation may be needed for network changes

### Previous Troubleshooting History
- Extensive chat log in `chatgpt_session (1).txt` contains detailed troubleshooting steps
- Multiple failed attempts with OVS configuration - use standard Linux bridges instead
- Nginx stream module was missing initially, required nginx-full package
- Container IP was initially mismatched between expected (192.168.10.x) and actual (10.0.0.101)

## Development Workflow
1. Create fix scripts locally in this directory
2. Transfer to appropriate systems (Proxmox host or LXC container)
3. Execute in correct sequence
4. Monitor logs and test connectivity
5. Iterate based on results

This project requires careful coordination between host and container networking, MQTT broker connectivity, and reverse proxy configuration.