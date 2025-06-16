# GhostBridge Dual IP Architecture

## 🏗️ **Commercial-Ready Dual IP Setup**

This architecture is designed for **commercial deployment** with proper service isolation and modularity.

### **Network Architecture Overview**

```
┌─────────────────────────────────────────────────────────────────┐
│                       INTERNET                                 │
│                                                                 │
│   IP 1: 80.209.240.244    │    IP 2: 80.209.240.XXX          │
│   (GhostBridge Control)    │    (Netmaker Services)            │
└─────────────────┬─────────────────┬─────────────────────────────┘
                  │                 │
                  ▼                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                   PROXMOX HOST                                  │
│              (80.209.240.244)                                  │
│                                                                 │
│  ┌─────────────────────┐                                       │
│  │   Nginx (IP 1)      │                                       │
│  │ • GhostBridge UI    │                                       │
│  │ • Proxmox WebUI     │                                       │
│  │ • Control Panel     │                                       │
│  └─────────────────────┘                                       │
│                                                                 │
│               ovsbr0 Bridge                                     │
│           (10.0.0.1/24 gateway)                                │
└─────────────────┬─────────────────────────────────────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                LXC CONTAINER (ID: 100)                         │
│                                                                 │
│  ┌─────────────────────┐   ┌─────────────────────────────────┐  │
│  │  eth0 (Private)     │   │  eth1 (Public Direct)          │  │
│  │  10.0.0.151/24      │   │  80.209.240.XXX/25             │  │
│  │  (Internal comms)   │   │  (Direct Internet)             │  │
│  └─────────────────────┘   └─────────────────────────────────┘  │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │              NETMAKER SERVICES                          │    │
│  │  • API Server (8081) ──────────────► eth1 (direct)     │    │
│  │  • MQTT TCP (1883) ─────────────────► eth1 (direct)     │    │
│  │  │  MQTT WebSocket (9001) ──────────► eth1 (direct)     │    │
│  │  • WireGuard Mesh Management                            │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
```

## 🎯 **Service Endpoints**

### **IP 1 (80.209.240.244) - GhostBridge Management**
- `https://ghostbridge.hobsonschoice.net` - Control Panel UI
- `https://proxmox.hobsonschoice.net:8006` - Proxmox WebUI

### **IP 2 (80.209.240.XXX) - Netmaker Services** 
- `https://netmaker.hobsonschoice.net` - Netmaker API (direct)
- `mqtt://broker.hobsonschoice.net:1883` - MQTT TCP (direct)
- `wss://broker.hobsonschoice.net:9001` - MQTT WebSocket (direct)

## 🚀 **Commercial Benefits**

### **1. Service Isolation**
- **Management** and **Core Services** completely separated
- Independent scaling and maintenance
- Clear security boundaries

### **2. Performance** 
- **Zero proxy overhead** for Netmaker API calls
- Direct container access for MQTT traffic
- Reduced latency for VPN operations

### **3. Modularity**
- Services can be **packaged independently**
- Easy to deploy in different configurations
- Simple customer upgrades

### **4. Scaling**
- Can move Netmaker to dedicated server later
- Load balance multiple Netmaker instances
- Independent service monitoring

## 🔧 **Implementation Details**

### **Container Network Configuration**
```bash
# Private network (internal communications)
--net0 name=eth0,bridge=ovsbr0,ip=10.0.0.151/24,gw=10.0.0.1

# Public network (direct access)  
--net1 name=eth1,bridge=ovsbr0,ip=80.209.240.XXX/25,gw=80.209.240.1
```

### **DNS Configuration Required**
```bash
# Point to respective IPs
netmaker.hobsonschoice.net    → 80.209.240.XXX
broker.hobsonschoice.net      → 80.209.240.XXX
ghostbridge.hobsonschoice.net → 80.209.240.244
proxmox.hobsonschoice.net     → 80.209.240.244
```

### **SSL Certificates**
```bash
# Separate certificates for each service
certbot --nginx -d ghostbridge.hobsonschoice.net
certbot --standalone -d netmaker.hobsonschoice.net -d broker.hobsonschoice.net
```

## 📋 **Deployment Process**

1. **Get Second IP** from hosting provider
2. **Enable dual IP mode** in container creation
3. **Configure DNS** to point to respective IPs
4. **Deploy services** with direct access
5. **Obtain SSL certificates** for both IPs
6. **Test service isolation**

## 💡 **Migration Strategy**

### **From Single IP to Dual IP:**
1. **Deploy second IP** to container
2. **Update DNS records** gradually  
3. **Migrate SSL certificates**
4. **Remove nginx proxying** for Netmaker
5. **Test and validate** all services

This architecture provides a **clean, commercial-ready foundation** for GhostBridge deployment and future scaling.