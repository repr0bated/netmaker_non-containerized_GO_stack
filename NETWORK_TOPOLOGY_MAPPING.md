# GhostBridge Network Topology - Complete Technical Mapping

## 🗺️ **Detailed Interface & IP Mapping**

### **Proxmox VE Host (The Iron Throne)**
| Interface | Type | IP Address | CIDR | Gateway | OVS Config | Purpose |
|-----------|------|------------|------|---------|------------|---------|
| `eth0` | Physical NIC | - | - | - | `ovs_bridge ovsbr0` | Physical uplink to ISP |
| `ovsbr0` | OVS Bridge | - | - | - | `ovs_type OVSBridge` | Main switching fabric |
| `ovsbr0-public` | OVS Internal | 80.209.240.244 | /25 | ISP Gateway | `ovs_type OVSIntPort` | Internet/Management |
| `ovsbr0-private` | OVS Internal | 10.0.0.1 | /24 | - | `ovs_type OVSIntPort` | Container gateway |

**Proxmox Network Config (`/etc/network/interfaces`):**
```bash
# Physical interface - no IP
auto eth0
iface eth0 inet manual
    ovs_bridge ovsbr0
    ovs_type OVSPort

# Main OVS Bridge
auto ovsbr0
iface ovsbr0 inet manual
    ovs_type OVSBridge
    ovs_ports eth0 ovsbr0-public ovsbr0-private

# Public/Management interface
auto ovsbr0-public
iface ovsbr0-public inet static
    address 80.209.240.244/25
    gateway 80.209.240.129  # ISP gateway
    dns-nameservers 8.8.8.8 8.8.4.4
    ovs_type OVSIntPort
    ovs_bridge ovsbr0

# Private/Container gateway
auto ovsbr0-private
iface ovsbr0-private inet static
    address 10.0.0.1/24
    ovs_type OVSIntPort
    ovs_bridge ovsbr0
```

### **Netmaker LXC Container (The Night's Watch)**
| Interface | Type | IP Address | CIDR | Gateway | Bridge | Purpose |
|-----------|------|------------|------|---------|--------|---------|
| `eth0` | Container veth | 10.0.0.151 | /24 | 10.0.0.1 | ovsbr0 | Private network |
| `eth1` | Container veth | 80.209.240.245 | /25 | 80.209.240.129 | ovsbr0 | Public direct (dual IP) |
| `nm-*` | WireGuard | Dynamic | /24 | - | - | Mesh overlay interfaces |

**Container Network Config:**
```bash
# LXC container configuration
net0: name=eth0,bridge=ovsbr0,ip=10.0.0.151/24,gw=10.0.0.1
net1: name=eth1,bridge=ovsbr0,ip=80.209.240.245/25,gw=80.209.240.129
```

### **Home Server (Winterfell)**
| Interface | Type | IP Address | CIDR | Gateway | OVS Config | Purpose |
|-----------|------|------------|------|---------|------------|---------|
| `eth0` | Physical NIC | - | - | - | `ovs_bridge ovsbr1` | Physical management uplink |
| `wlp2s0` | Wireless | DHCP | /24 | Router | - | Wireless backup |
| `ovsbr0` | OVS Bridge | - | - | - | `ovs_type OVSBridge` | Netmaker mesh bridge |
| `nm-int` | OVS Internal | 100.104.70.2 | /24 | - | `ovs_type OVSIntPort` | Netmaker mesh endpoint |
| `ovsbr1` | OVS Bridge | - | - | - | `ovs_type OVSBridge` | Management bridge |
| `mgmt-int` | OVS Internal | 10.88.88.2 | /24 | 10.88.88.1 | `ovs_type OVSIntPort` | Home management |

**Home Server Network Config (`/etc/network/interfaces`):**
```bash
# Physical management interface
auto eth0
iface eth0 inet manual
    ovs_bridge ovsbr1
    ovs_type OVSPort

# Management bridge
auto ovsbr1
iface ovsbr1 inet manual
    ovs_type OVSBridge
    ovs_ports eth0 mgmt-int

# Management interface
auto mgmt-int
iface mgmt-int inet static
    address 10.88.88.2/24
    gateway 10.88.88.1
    dns-nameservers 8.8.8.8 8.8.4.4
    ovs_type OVSIntPort
    ovs_bridge ovsbr1

# Netmaker mesh bridge
auto ovsbr0
iface ovsbr0 inet manual
    ovs_type OVSBridge
    ovs_ports nm-int

# Netmaker mesh interface
auto nm-int
iface nm-int inet static
    address 100.104.70.2/24
    ovs_type OVSIntPort
    ovs_bridge ovsbr0
```

### **Flint Router (King's Landing)**
| Interface | Type | IP Address | CIDR | Purpose |
|-----------|------|------------|------|---------|
| `internal` | Router Interface | 10.88.88.1 | /24 | Home network gateway & DHCP |
| `wan` | Router Interface | ISP DHCP | /24 | Internet uplink |

## 🌐 **Network Flows & Routing**

### **Single IP Mode (Current):**
```
Internet → 80.209.240.244 → Nginx Proxy → Services
    ↓
ovsbr0-public (80.209.240.244)
    ↓
ovsbr0-private (10.0.0.1) → Container (10.0.0.151)
```

### **Dual IP Mode (Production):**
```
Internet → 80.209.240.244 → GhostBridge Control
Internet → 80.209.240.245 → Container Direct

ovsbr0-public (80.209.240.244) → Proxmox Services
ovsbr0-public2 (80.209.240.245) → Container eth1 Direct
ovsbr0-private (10.0.0.1) → Container eth0 (Internal)
```

### **Mesh Overlay Network:**
```
Netmaker Container (10.0.0.151) ←→ WireGuard Mesh ←→ Home Server (100.104.70.2)
                                        ↕
                              Additional Mesh Clients
                              (Dynamic 100.104.70.x/24)
```

## 📋 **Service Port Mapping**

### **Proxmox Host Services:**
- **Port 8006**: Proxmox Web UI (https://proxmox.hobsonschoice.net:8006)
- **Port 80/443**: Nginx reverse proxy
- **Port 1883**: MQTT stream proxy (single IP mode)

### **Container Services:**
- **Port 8081**: Netmaker API
- **Port 1883**: Mosquitto MQTT TCP
- **Port 9001**: Mosquitto MQTT WebSocket

### **External Service Endpoints:**
- **GhostBridge Control**: https://ghostbridge.hobsonschoice.net
- **Netmaker API**: https://netmaker.hobsonschoice.net
- **MQTT Broker**: mqtt://broker.hobsonschoice.net:1883
- **MQTT WebSocket**: wss://broker.hobsonschoice.net:9001

## 🔧 **IP Allocation Strategy**

### **Public Subnet: 80.209.240.128/25**
- **Gateway**: 80.209.240.129
- **Proxmox Host**: 80.209.240.244
- **Container Direct**: 80.209.240.245 (dual IP mode)
- **Available**: 80.209.240.130-243, 246-254

### **Private Subnet: 10.0.0.0/24**
- **Gateway**: 10.0.0.1 (Proxmox)
- **Services**: 10.0.0.2-50
- **Reserved**: 10.0.0.51-149
- **Containers**: 10.0.0.150-245
- **Netmaker**: 10.0.0.151

### **Management Subnet: 10.88.88.0/24**
- **Router/Gateway**: 10.88.88.1
- **Home Server**: 10.88.88.2
- **DHCP Pool**: 10.88.88.100-200

### **Mesh Overlay: 100.104.70.0/24**
- **Netmaker Server**: 100.104.70.1 (auto-assigned)
- **Home Server**: 100.104.70.2
- **Client Pool**: 100.104.70.10-250

This mapping provides the exact technical specification for network implementation and troubleshooting.