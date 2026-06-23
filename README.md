# Infrastructure Automation Monorepo

[![Validate](https://github.com/IT-Architect-UK/monorepo/actions/workflows/validate.yml/badge.svg)](https://github.com/IT-Architect-UK/monorepo/actions/workflows/validate.yml)

A production-grade infrastructure automation library built by a Senior IT Infrastructure & Security Architect. This repository demonstrates end-to-end automation across on-premises hypervisors, public cloud, and everything in between — from bare-metal provisioning to golden image pipelines, configuration management, monitoring, and secure certificate management.

Everything here is written to be used in real environments, not just demonstrated.

---

## What This Repository Covers

| Domain | Technologies |
|--------|-------------|
| **VM Image Building** | Packer · Proxmox · VMware vSphere · AWS AMI · Azure Managed Image · GCP Image |
| **Configuration Management** | Ansible · Roles · Playbooks · Inventory |
| **Hypervisor Automation** | Proxmox VE · VMware ESXi/vCenter · LXC containers |
| **Cloud Infrastructure** | AWS · Azure · GCP · multi-cloud parity scripts |
| **Security & PKI** | TLS/SSL · Let's Encrypt · OpenSSL CA · HashiCorp Vault · Compliance reporting |
| **Monitoring** | Prometheus · Grafana · Zabbix · Uptime Kuma · CloudWatch · Azure Monitor · GCP Ops |
| **Backup & Recovery** | Restic · Veeam · AWS Backup |
| **Linux Administration** | Ubuntu · Debian · Bash · server hardening · storage · networking |
| **Windows Administration** | PowerShell · Windows Server 2025 · AD DS · RDS · Chocolatey |
| **CI/CD** | GitHub Actions · automated syntax validation on every push |

---

## Repository Structure

```
monorepo/
│
├── .github/workflows/
│   └── validate.yml              # CI: bash -n, ansible --syntax-check, packer validate
│
├── automation/
│   ├── ansible/                  # Ansible playbooks and roles
│   │   ├── playbooks/            # server-baseline, TLS, monitoring, backup, Docker, SSH keys
│   │   ├── roles/                # common, tls, monitoring-agent, backup-restic
│   │   └── inventory/            # hosts.yml + group_vars
│   ├── packer/                   # Golden image pipelines
│   │   ├── ubuntu-2404-proxmox.pkr.hcl        # Ubuntu 24.04 → Proxmox template
│   │   ├── ubuntu-2404-vmware.pkr.hcl         # Ubuntu 24.04 → vSphere template
│   │   ├── ubuntu-2404-aws.pkr.hcl            # Ubuntu 24.04 → AWS AMI
│   │   ├── ubuntu-2404-azure.pkr.hcl          # Ubuntu 24.04 → Azure managed image
│   │   ├── ubuntu-2404-gcp.pkr.hcl            # Ubuntu 24.04 → GCP image
│   │   ├── ubuntu-2404-ansible-server-proxmox.pkr.hcl   # Ansible control node
│   │   ├── ubuntu-2404-automation-toolbox-proxmox.pkr.hcl # All-in-one toolbox VM
│   │   ├── win2025-proxmox.pkr.hcl            # Windows Server 2025 → Proxmox template
│   │   ├── win2025-vmware.pkr.hcl             # Windows Server 2025 → vSphere template
│   │   ├── scripts/              # Shell + PowerShell provisioners
│   │   ├── http/                 # cloud-init user-data + Windows autounattend.xml
│   │   └── environments/         # Per-environment var files (homelab, production)
│   └── python/                   # Azure inventory, infrastructure health checks, Prometheus queries
│
├── infrastructure/
│   ├── hypervisors/
│   │   ├── proxmox/              # VM + LXC deployment scripts
│   │   └── vmware/               # vSphere templates and provisioning scripts
│   ├── servers/
│   │   ├── linux/configuration/  # Baseline hardening, users, TLS, branding, IPv6
│   │   └── windows/              # PowerShell: local admin, rename, update, disk setup
│   ├── networking/               # iptables firewall rules, NTP configuration
│   └── storage/                  # Disk extension, NFS mounts (Linux + Windows)
│
├── cloud/
│   └── aws/                      # Account baseline, EC2 inventory, VPC deployment, CloudWatch
│
├── security/
│   ├── tls/                      # Let's Encrypt (Certbot), NGINX/IIS deployment, AWS ACM, Azure KV, GCP CM
│   ├── pki/                      # OpenSSL root CA creation, sub-CA signing
│   ├── vault/                    # HashiCorp Vault installation and configuration
│   └── compliance/               # PAM compliance reporting (PowerShell)
│
├── monitoring/
│   ├── prometheus-grafana/       # Full stack install (bare metal + Docker), node exporter
│   ├── zabbix/                   # Agent install for Ubuntu and Windows
│   ├── uptime-kuma/              # Docker-based uptime monitoring
│   └── cloud/                    # CloudWatch, Azure Monitor, GCP Ops agents
│
├── backup/
│   ├── on-premises/restic/       # Local and S3-backed Restic backups
│   ├── on-premises/veeam-agent/  # Veeam Agent for Linux
│   └── cloud/aws/                # AWS Backup configuration
│
├── applications/                 # AWX, Bacula, Webmin, WordPress deployment scripts
├── image-maintenance/            # Template patching and golden image refresh automation
└── projects/blockchain/          # Cardano, COTI, World Mobile node deployment
```

---

## Highlighted Capabilities

### Packer Golden Image Pipeline

A complete multi-platform image factory. One set of Ansible playbooks and shell provisioners, eight build targets:

```bash
# Build a hardened Ubuntu 24.04 template on Proxmox
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  ubuntu-2404-proxmox.pkr.hcl

# Build a Windows Server 2025 template on Proxmox
export PKR_VAR_proxmox_password="..."
export PKR_VAR_winrm_password="..."
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  -var-file="environments/win2025.pkrvars.hcl" \
  win2025-proxmox.pkr.hcl
```

Every template:
- Runs automated OS installation (cloud-init autoinstall for Ubuntu, `autounattend.xml` for Windows)
- Applies a baseline Ansible role (updates, hardening, SSH, monitoring agent)
- Seals the image (sysprep / cloud-init clean) and converts to a template
- Validated by CI on every push — no broken templates reach the main branch

### Ansible Server Baseline Role

Applied automatically during Packer builds and available standalone:

```bash
ansible-playbook \
  -i inventory/hosts.yml \
  playbooks/server-baseline.yml
```

Covers: system updates · SSH hardening · fail2ban · unattended-upgrades · NTP · hostname · monitoring agent

### GitHub Actions CI

Every push triggers three validation jobs in parallel:

```
✔ Shell script syntax    (bash -n on all .sh files)
✔ Ansible syntax         (ansible-playbook --syntax-check on all playbooks)
✔ Packer validate        (all 9 templates validated in isolation)
```

Templates are validated one at a time using a rename-in-place strategy to avoid HCL merge conflicts — a non-obvious problem with multi-template Packer directories that this repo solves cleanly.

---

## Getting Started

### Prerequisites

- [Packer](https://developer.hashicorp.com/packer/install) ≥ 1.10
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) ≥ 2.14
- Access to Proxmox VE, VMware vCenter, or a cloud account

### Clone

```bash
git clone https://github.com/IT-Architect-UK/monorepo.git
cd monorepo
```

### Run Ansible against existing servers

```bash
cd automation/ansible
cp inventory/hosts.yml.example inventory/hosts.yml   # edit with your hosts
ansible-playbook playbooks/server-baseline.yml -i inventory/hosts.yml
```

### Build a VM template

```bash
cd automation/packer
packer init ubuntu-2404-proxmox.pkr.hcl
export PKR_VAR_proxmox_password="your-password"
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  ubuntu-2404-proxmox.pkr.hcl
```

---

## Design Principles

**Real, not demo.** Scripts are written to production standards — error handling, idempotency, and comments that explain *why*, not just *what*.

**Multi-platform parity.** Where a task applies to AWS, Azure, and GCP, there are equivalent scripts for all three. On-premises and cloud are treated as equal targets.

**CI-gated.** No untested code on main. The GitHub Actions workflow validates every shell script, Ansible playbook, and Packer template on every push.

**Separation of secrets.** Credentials are never committed. Sensitive values use environment variables (`PKR_VAR_*`, `.env` files excluded by `.gitignore`) with `.env.example` files showing required keys.

---

## Author

**Darren Pilkington** — Senior IT Infrastructure & Security Architect  
[it-architect.uk](https://it-architect.uk) · [LinkedIn](https://www.linkedin.com/in/darrenpilkington) · darren.pilkington@it-architect.uk

Specialisms: Enterprise infrastructure design · Hypervisor platforms · Cloud migration · Infrastructure as Code · Security architecture
