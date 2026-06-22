# Proxmox — Virtual Machine Deployment

Scripts for deploying full virtual machines on Proxmox VE.

## Scripts

| Script | What it does |
|--------|-------------|
| `deploy-ubuntu-2404.sh` | Creates an Ubuntu 24.04 LTS VM using cloud-init. No installation wizard — the VM configures itself automatically on first boot. |
| `deploy-windows-server-2025.sh` | Creates a Windows Server 2025 VM, attaches the OS and VirtIO ISOs ready for installation. |
| `clone-vm-from-template.sh` | Clones an existing template to a new VM. The fastest way to get a new server running. |

## Usage Examples

```bash
# Ubuntu — basic (VM 100, 2GB RAM, 20GB disk, DHCP)
./deploy-ubuntu-2404.sh

# Ubuntu — web server
./deploy-ubuntu-2404.sh -i 110 -n "web01" -m 4096 -c 2 -d 40

# Windows — domain controller
./deploy-windows-server-2025.sh -i 200 -n "dc01" -m 8192 -c 4 -d 80

# Clone from template
./clone-vm-from-template.sh -t 9000 -i 101 -n "app01"
```

## All Options

```
./deploy-ubuntu-2404.sh --help
./deploy-windows-server-2025.sh --help
./clone-vm-from-template.sh --help
```
