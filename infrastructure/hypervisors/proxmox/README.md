# Proxmox VE — VM & Container Deployment

This section covers deploying virtual machines and containers on [Proxmox VE](https://www.proxmox.com/), a free and open-source hypervisor platform. Proxmox is the most popular choice for home labs and small-to-medium businesses looking for a VMware alternative without licensing costs.

## 📋 What is Proxmox VE?

Proxmox VE (Virtual Environment) is an open-source server virtualisation platform based on Debian Linux. It supports two virtualisation technologies:

| Technology | Description | Best For |
|------------|-------------|----------|
| **KVM (full VM)** | Full hardware virtualisation — runs any OS | Windows, VMs needing custom kernels, Docker hosts |
| **LXC (container)** | Lightweight Linux containers sharing the host kernel | Linux-only services, maximum density, fast boot |

## 📁 Folder Structure

```
proxmox/
├── vms/                  # Full virtual machine deployment scripts
│   ├── deploy-windows-server-2025.sh   # Deploy Windows Server 2025
│   ├── deploy-ubuntu-2404.sh           # Deploy Ubuntu 24.04 LTS (cloud-init)
│   └── clone-vm-from-template.sh       # Clone any existing template to a new VM
└── lxc/                  # Lightweight Linux container scripts
    ├── deploy-ubuntu-lxc.sh            # Deploy Ubuntu 24.04 LXC container
    └── lxc-baseline.sh                 # Apply baseline hardening to an LXC container
```

## 🚀 Quick Start

### First Time Setup

1. **Install Proxmox VE** — download the ISO from [proxmox.com/downloads](https://www.proxmox.com/en/downloads) and install on bare metal.

2. **Access the web UI** — open a browser and navigate to:
   ```
   https://<proxmox-host-ip>:8006
   ```
   Login with root and the password you set during installation.

3. **Upload ISOs** — go to **Datacenter → Storage → local → ISO Images → Upload** and upload your Windows and VirtIO ISOs.

4. **Run the deployment scripts** — SSH into your Proxmox host as root and run the scripts below.

### Deploy Ubuntu 24.04 VM (recommended starting point)

```bash
# Download the script to your Proxmox host
wget https://raw.githubusercontent.com/IT-Architect-UK/monorepo/main/infrastructure/hypervisors/proxmox/vms/deploy-ubuntu-2404.sh
chmod +x deploy-ubuntu-2404.sh

# Deploy with defaults (VM ID 100, 2GB RAM, 20GB disk)
./deploy-ubuntu-2404.sh

# Or customise it
./deploy-ubuntu-2404.sh --vmid 101 --name "web01" --memory 4096 --disk 40
```

### Deploy Windows Server 2025 VM

```bash
wget https://raw.githubusercontent.com/IT-Architect-UK/monorepo/main/infrastructure/hypervisors/proxmox/vms/deploy-windows-server-2025.sh
chmod +x deploy-windows-server-2025.sh
./deploy-windows-server-2025.sh --vmid 200 --name "dc01" --memory 8192 --cores 4
```

### Clone a Template to a New VM

```bash
# Convert an existing VM to a template first (in the Proxmox UI or via CLI)
qm template 100

# Then clone it as many times as you need
./clone-vm-from-template.sh --template-id 100 --vmid 101 --name "web01"
./clone-vm-from-template.sh --template-id 100 --vmid 102 --name "db01"
```

### Deploy an LXC Container (lightweight Linux service)

```bash
./lxc/deploy-ubuntu-lxc.sh --ctid 300 --name "pihole" --memory 256 --disk 4
```

## 💡 Recommended VM Sizes (Home Lab)

| Role | RAM | CPU | Disk |
|------|-----|-----|------|
| Ubuntu general server | 2 GB | 2 | 20 GB |
| Ubuntu Docker host | 4 GB | 4 | 40 GB |
| Windows Server 2025 (member) | 4 GB | 2 | 60 GB |
| Windows Server 2025 (DC) | 8 GB | 4 | 80 GB |
| Monitoring stack | 4 GB | 2 | 50 GB |
| LXC lightweight service | 256–512 MB | 1 | 4–8 GB |

## 🔗 Cloud Equivalents

Understanding how Proxmox concepts map to cloud services helps you move between environments:

| Proxmox Concept | AWS Equivalent | Azure Equivalent | GCP Equivalent |
|----------------|----------------|-----------------|----------------|
| KVM Virtual Machine | EC2 Instance | Azure VM | Compute Engine VM |
| LXC Container | ECS Container / Fargate | ACI (Container Instance) | Cloud Run / GKE |
| VM Template | AMI (Amazon Machine Image) | Managed Image | Machine Image |
| Cloud-Init | EC2 User Data | Custom Script Extension | Startup Script |
| Storage Pool | EBS Volume | Managed Disk | Persistent Disk |
| Network Bridge | VPC / Subnet | VNet / Subnet | VPC / Subnet |

## ❓ Troubleshooting

**VM won't boot from ISO?**
→ Check the boot order in VM Options → Boot Order. The IDE device (ISO) should be first.

**Windows install can't find the disk?**
→ You need to load the VirtIO storage driver. Click "Load driver" during setup and browse to the VirtIO CD → viostor folder.

**Cloud-init VM not getting an IP?**
→ Ensure your DHCP server is reachable on the bridge interface. Check with: `qm config <vmid>` and verify `net0` is set correctly.

**Permission denied running the scripts?**
→ Make the script executable: `chmod +x script.sh` and run as root.

## 📚 Further Reading

- [Proxmox VE Documentation](https://pve.proxmox.com/pve-docs/)
- [Proxmox Community Forum](https://forum.proxmox.com/)
- [VirtIO Drivers Download](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/)
- [Ubuntu Cloud Images](https://cloud-images.ubuntu.com/)
