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
| **Cloud Infrastructure** | AWS (fully built out) · Azure & GCP (identity, monitoring, image maintenance) |
| **Containers** | Docker · Docker Swarm · Kubernetes bootstrap · Portainer |
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
│   ├── packer/                   # Golden image pipelines — one subdirectory per template
│   │   ├── builds/
│   │   │   ├── ubuntu-2604-automation-toolbox/  # Ansible+Packer+Terraform+Docker all-in-one VM
│   │   │   ├── ubuntu-2604-proxmox/             # Generic Ubuntu 26.04 → Proxmox
│   │   │   ├── ubuntu-2604-vmware/              # Generic Ubuntu 26.04 → vSphere
│   │   │   ├── ubuntu-2604-aws/                 # Ubuntu 26.04 → AWS AMI
│   │   │   ├── ubuntu-2604-azure/               # Ubuntu 26.04 → Azure Managed Image
│   │   │   ├── ubuntu-2604-gcp/                 # Ubuntu 26.04 → GCP Custom Image
│   │   │   ├── win2025-proxmox/                 # Windows Server 2025 → Proxmox
│   │   │   └── win2025-vmware/                  # Windows Server 2025 → vSphere
│   │   ├── environments/         # Var files shared across more than one template
│   │   ├── scripts/              # Shell + PowerShell provisioners (shared)
│   │   └── http/                 # cloud-init user-data + Windows autounattend.xml
│   └── python/                   # Azure inventory, infrastructure health checks, Prometheus queries
│
├── infrastructure/
│   ├── hypervisors/
│   │   ├── proxmox/              # VM + LXC deployment scripts
│   │   └── vmware/               # vSphere templates and provisioning scripts
│   ├── identity/                 # Active Directory forest, OUs, groups, GPO baselines
│   ├── servers/
│   │   ├── linux/configuration/  # Baseline hardening, users, TLS, branding, IPv6
│   │   └── windows/               # PowerShell: local admin, rename, update, disk setup
│   ├── networking/               # iptables firewall rules, DNS, NTP configuration
│   └── storage/                  # Disk extension, NFS mounts (Linux + Windows)
│
├── cloud/
│   ├── aws/                      # Account baseline, EC2 inventory, VPC deployment, CloudWatch
│   ├── azure/                    # Identity migration tooling (on-prem → cloud-only)
│   └── gcp/                      # Scaffolded — account/compute/networking structure in place
│
├── containers/
│   ├── docker/                   # Install + Docker Swarm cluster setup
│   ├── kubernetes/               # Master/worker/management node bootstrap, Minikube
│   └── portainer/                # Portainer server + agent install
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
│   ├── uptime-kuma/               # Docker-based uptime monitoring
│   └── cloud/                    # CloudWatch, Azure Monitor, GCP Ops agents
│
├── backup/
│   ├── on-premises/restic/       # Local and S3-backed Restic backups
│   ├── on-premises/veeam-agent/  # Veeam Agent for Linux
│   └── cloud/aws/                # AWS Backup configuration
│
├── image-maintenance/            # Golden image refresh: AWS AMI, Azure/GCP images, Proxmox templates, sysprep
├── applications/                 # AWX, Bacula, Webmin, WordPress deployment scripts
├── projects/blockchain/          # Cardano, COTI, World Mobile node deployment
├── scripts/ & utilities/         # Standalone helper scripts (repo sync, RDS certs, etc.)
└── CONFIGURATION.md              # Full credentials/setup guide for every platform above
```

---

## Highlighted Capabilities

### Packer Golden Image Pipeline

A complete multi-platform image factory. One set of Ansible playbooks and shell provisioners, eight build targets — each template lives in its own self-contained `builds/<template>/` directory:

```bash
cd automation/packer/builds/ubuntu-2604-proxmox

# Build a hardened Ubuntu 26.04 template on Proxmox
packer init .
export PKR_VAR_proxmox_password="your-password"
packer build \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  .

# Build a Windows Server 2025 template on Proxmox
cd ../win2025-proxmox
export PKR_VAR_proxmox_password="..."
export PKR_VAR_winrm_password="..."
packer build \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  -var-file="../../environments/win2025.pkrvars.hcl" \
  .
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

Every push triggers four validation jobs in parallel:

```
✔ Shell script syntax    (bash -n on all .sh files)
✔ Ansible syntax         (ansible-playbook --syntax-check on all playbooks)
✔ Packer validate        (all 8 templates validated independently)
✔ PowerShell syntax      (parser-based check on all .ps1 files)
```

Each template lives in its own subdirectory (`automation/packer/builds/<template>/`), so `packer init`/`packer validate` run against a single, isolated `.pkr.hcl` file per template — no shared-directory HCL merge conflicts to work around.

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
nano inventory/hosts.yml   # edit with your hosts (already a working example — replace the IPs)
ansible-playbook playbooks/server-baseline.yml -i inventory/hosts.yml
```

### Build a VM template

```bash
cd automation/packer/builds/ubuntu-2604-proxmox
packer init .
export PKR_VAR_proxmox_password="your-password"
packer build \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  .
```

Full credential setup for every platform (Proxmox, VMware, AWS, Azure, GCP, GitHub Actions) is in [`CONFIGURATION.md`](CONFIGURATION.md).

---

## Design Principles

**Real, not demo.** Scripts are written to production standards — error handling, idempotency, and comments that explain *why*, not just *what*.

**Multi-platform parity where it matters.** AWS is the most fully built-out cloud target; Azure and GCP have identity, monitoring, and image-maintenance tooling with the same structure ready to extend. On-premises and cloud are treated as equal targets, not cloud-first with on-prem as an afterthought.

**CI-gated.** No untested code on main. The GitHub Actions workflow validates every shell script, every Ansible playbook, and every Packer template on every push.

**Separation of secrets.** Credentials are never committed. Sensitive values use environment variables (`PKR_VAR_*`, `.env` files excluded by `.gitignore`) with `.env.example` files showing required keys.

---

## Author

**Darren Pilkington** — Senior IT Infrastructure & Security Architect  
[it-architect.uk](https://it-architect.uk) · [LinkedIn](https://www.linkedin.com/in/darrenpilkington) · darren.pilkington@it-architect.uk

Specialisms: Enterprise infrastructure design · Hypervisor platforms · Cloud migration · Infrastructure as Code · Security architecture
