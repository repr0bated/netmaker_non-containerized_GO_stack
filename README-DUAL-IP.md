# GhostBridge Dual IP Deployment

## 🚀 **Quick Start**

### **Single IP Deployment (Current)**
```bash
sudo ./deploy-ghostbridge.sh
# Choose "N" for dual IP when prompted
```

### **Dual IP Deployment (Commercial)**
```bash
sudo ./deploy-ghostbridge.sh  
# Choose "Y" for dual IP when prompted
# Enter second public IP address
```

## 🏗️ **Architecture**

### **Single IP Mode**
- All services behind nginx proxy on 80.209.240.244
- GhostBridge + Netmaker on same IP
- Good for testing/basic setup

### **Dual IP Mode (Recommended for Production)**
- **IP 1**: GhostBridge control panel + Proxmox management
- **IP 2**: Direct Netmaker API + MQTT services  
- Better performance, isolation, commercial scalability

## 📋 **Service Endpoints**

### **Single IP**
- `https://ghostbridge.hobsonschoice.net` → nginx → proxy
- `https://netmaker.hobsonschoice.net` → nginx → container

### **Dual IP**  
- `https://ghostbridge.hobsonschoice.net` → IP1 direct
- `https://netmaker.hobsonschoice.net` → IP2 container direct

## 🔑 **API Access**

```bash
# Get master key
MASTER_KEY=$(pct exec 100 -- /etc/netmaker/get-master-key.sh)

# Test API
curl -H "Authorization: Bearer $MASTER_KEY" \
     https://netmaker.hobsonschoice.net/api/server/health
```

## 📁 **Key Files**
- `deploy-ghostbridge.sh` - Master deployment script
- `DUAL_IP_ARCHITECTURE.md` - Detailed architecture docs
- `CONTEXT_HANDOFF.md` - Development context and next steps