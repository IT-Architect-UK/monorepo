# Monorepo Additions — Infrastructure Automation

This directory contains scripts, playbooks, and documentation for:
- Hypervisor VM/container deployment (Proxmox, VMware)
- Infrastructure automation (Ansible)
- TLS certificate management
- Server monitoring
- Backup and recovery
- Image/template maintenance

Every topic includes equivalent scripts for AWS, Azure, and GCP — making this ideal for learning how on-premises concepts map to cloud services.

## 📁 Structure

```
├── infrastructure/hypervisors/
│   ├── proxmox/          Proxmox VE VM and LXC deployment
│   └── vmware/           VMware ESXi/vCenter templates and provisioning
├── automation/ansible/   Ansible playbooks, roles, and inventory
├── security/tls/         TLS certificates (Let's Encrypt + cloud providers)
├── monitoring/           Uptime Kuma + AWS CloudWatch + Azure Monitor + GCP Ops
├── backup/               Restic + Veeam + AWS/Azure/GCP backup
└── image-maintenance/    Template patching and golden image builds
```

See the README in each directory for full usage instructions.
