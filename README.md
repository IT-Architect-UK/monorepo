# IT Architect — Infrastructure as Code Monorepo

A centralised collection of production-grade infrastructure automation scripts covering on-premises infrastructure, cloud platforms, container orchestration, monitoring, security, and blockchain node operations.

![Bash](https://img.shields.io/badge/Bash-4EAA25?style=flat&logo=gnubash&logoColor=white)
![PowerShell](https://img.shields.io/badge/PowerShell-5391FE?style=flat&logo=powershell&logoColor=white)
![Python](https://img.shields.io/badge/Python-3776AB?style=flat&logo=python&logoColor=white)
![Azure](https://img.shields.io/badge/Azure-0078D4?style=flat&logo=microsoftazure&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-232F3E?style=flat&logo=amazonaws&logoColor=white)
![GCP](https://img.shields.io/badge/GCP-4285F4?style=flat&logo=googlecloud&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat&logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)

---

## Repository Structure

```
monorepo/
├── cloud/                    # Cloud provider automation
│   ├── aws/                  # Amazon Web Services
│   ├── azure/                # Microsoft Azure
│   └── gcp/                  # Google Cloud Platform
├── infrastructure/           # On-premises infrastructure
│   ├── servers/              # Server OS configuration
│   ├── hypervisors/          # Proxmox, VMware, Hyper-V
│   ├── networking/           # DNS, NTP, firewall
│   ├── storage/              # Disk, LVM, NFS
│   └── identity/             # Active Directory, GPO
├── containers/               # Container platforms
│   ├── docker/               # Docker CE + Swarm
│   ├── kubernetes/           # k8s cluster + Minikube
│   └── portainer/            # Portainer CE + Agent
├── monitoring/               # Observability
│   ├── prometheus-grafana/   # Metrics stack
│   └── zabbix/               # Agent deployment
├── security/                 # Security tooling
│   ├── pki/                  # Certificate authority
│   ├── vault/                # HashiCorp Vault
│   └── compliance/           # Compliance reporting
├── applications/             # Standalone application deployments
├── automation/               # Scripting and automation tools
│   ├── ansible/              # Ansible roles
│   └── python/               # Python utilities
├── projects/                 # Bespoke project deployments
│   └── blockchain/           # Blockchain node operations
├── utilities/                # Repo bootstrap and helper scripts
└── archive/                  # Deprecated / superseded scripts
```

---

## Skills Demonstrated

| Domain | Technologies |
|---|---|
| Operating Systems | **Linux:** Ubuntu 20.04 LTS, Ubuntu 22.04 LTS, Ubuntu 24.04 LTS, Debian 11 (Bullseye), Debian 12 (Bookworm), AlmaLinux 8, AlmaLinux 9 · **Windows Server:** 2016, 2019, 2022, 2025 |
| Hypervisors | Proxmox VE, VMware ESXi / vCenter |
| Containers | Docker, Docker Compose, Docker Swarm, Portainer |
| Orchestration | Kubernetes, Minikube, AWX (Ansible Tower) |
| Cloud — AWS | EC2, VPC, CloudTrail, GuardDuty, CloudWatch, IAM |
| Cloud — Azure | Entra ID, Virtual Machines |
| Cloud — GCP | *(in progress)* |
| Infrastructure Automation | Ansible, Bash, PowerShell, Python |
| Directory Services | Active Directory (ADDS), Group Policy, Entra ID |
| Monitoring | Prometheus, Grafana, Zabbix, Node Exporter |
| Security | OpenSSL / PKI, HashiCorp Vault, IPtables, GPO hardening |
| Backup | Bacula |
| Secrets Management | HashiCorp Vault |
| Blockchain | Cardano, COTI, World Mobile (AYA testnet) |
| Languages | Bash, PowerShell, Python |

---

## Cloud

### AWS — [`cloud/aws/`](cloud/aws/)

| Path | Script | Description |
|---|---|---|
| `account/` | `aws-account-baseline.sh` | New account hardening: CloudTrail, GuardDuty, S3 block-public-access, IAM password policy, default VPC removal |
| `compute/` | `install-cloudwatch-agent-ubuntu.sh` | CloudWatch unified agent with system metrics and log collection |
| `compute/` | `aws-ec2-inventory.py` | Multi-region EC2 inventory report via Boto3 (CSV + table output) |
| `networking/` | `deploy-vpc.sh` | VPC with public/private subnets, IGW, NAT gateway, and VPC Flow Logs |

### Azure — [`cloud/azure/`](cloud/azure/)

| Path | Script | Description |
|---|---|---|
| `identity/` | `convert-specific-onprem-users-to-cloud.ps1` | Migrate named users from on-premises AD to cloud-only Entra ID |
| `identity/` | `convert-all-onprem-users-to-cloud.ps1` | Bulk on-premises to Entra ID migration with error handling |

### GCP — [`cloud/gcp/`](cloud/gcp/)

*(Scripts in progress — directory structure ready)*

---

## Infrastructure

### Servers — Linux — [`infrastructure/servers/linux/`](infrastructure/servers/linux/)

| Script | Description |
|---|---|
| `server-baseline.sh` | Orchestrates full OS baseline: runs all configuration scripts, upgrades packages, reboots |
| `apt-get-upgrade.sh` | Full system package upgrade with logging |
| `apply-branding.sh` | MOTD and shell prompt customisation |
| `create-user.sh` | User account creation with sudo and SSH key setup |
| `disable-cloud-init.sh` | Prevent cloud-init re-runs on template VMs |
| `disable-ipv6.sh` | Disable IPv6 system-wide via sysctl |
| `install-tls-certificate.sh` | Install and configure a TLS certificate |

### Servers — Windows — [`infrastructure/servers/windows/`](infrastructure/servers/windows/)

| Path | Script | Description |
|---|---|---|
| `os/` | `rename-computer.ps1` | Computer rename with scheduled restart |
| `os/` | `create-local-admin.ps1` | Local administrator account creation |
| `os/` | `run-windows-update.ps1` | Automated Windows Update cycle |
| `os/` | `setup-hdds.ps1` | Disk initialisation, partitioning, and formatting |
| `os/` | `reset-local-policies.ps1` | Reset local security policy to defaults |
| `packages/` | `install-chocolatey-packages.ps1` | Chocolatey package manager + bulk software deployment |

### Hypervisors — [`infrastructure/hypervisors/`](infrastructure/hypervisors/)

#### Proxmox — [`infrastructure/hypervisors/proxmox/`](infrastructure/hypervisors/proxmox/)

| Script | Description |
|---|---|
| `templates/ubuntu-proxmox-template-prepare.sh` | Prepare an Ubuntu VM as a Proxmox cloud-init template |
| `templates/ubuntu-vm-template-prepare.sh` | Generic Ubuntu VM template preparation |
| `templates/ubuntu-default.sh` | Apply default Ubuntu template configuration |
| `templates/alma-vm-template-prepare.sh` | AlmaLinux VM template preparation |

#### VMware — [`infrastructure/hypervisors/vmware/`](infrastructure/hypervisors/vmware/)

| Script | Description |
|---|---|
| `enable-snmp-esxi.sh` | Configure SNMP v2c on ESXi hosts |
| `enable-snmp-vcenter.sh` | Configure SNMP on vCenter Server |

#### Hyper-V — [`infrastructure/hypervisors/hyper-v/`](infrastructure/hypervisors/hyper-v/)

*(Scripts in progress — directory structure ready)*

### Networking — [`infrastructure/networking/`](infrastructure/networking/)

| Path | Script | Description |
|---|---|---|
| `dns/` | `dns-default-gateway.sh` | Configure static DNS servers and default gateway via Netplan |
| `ntp/` | `setup-ntp.sh` | NTP client configuration (chrony / systemd-timesyncd) |
| `firewall/` | `setup-iptables.sh` | iptables baseline ruleset with persistent save |

### Storage — [`infrastructure/storage/`](infrastructure/storage/)

| Path | Script | Description |
|---|---|---|
| `linux/` | `extend-disks.sh` | LVM disk extension automation (PV, VG, LV resize) |
| `linux/` | `mount-nfs-volume.sh` | NFS share mount with fstab persistence |

### Identity — Active Directory — [`infrastructure/identity/active-directory/`](infrastructure/identity/active-directory/)

| Script | Description |
|---|---|
| `install-adds-new-forest.ps1` | Deploy a new AD forest with DNS, NTP (PDC), and DSRM configuration |
| `install-adds-rsat.ps1` | Install Remote Server Administration Tools |
| `add-adds-baseline-objects.ps1` | Create baseline AD users, groups, and OUs |
| `groups/create-ad-server-admins-group.ps1` | Create Server Admins security group |
| `ou/add-baseline-ou-objects.ps1` | Create baseline OU structure |
| `gpo/win-svr-2022/` | 4 x Windows Server 2022 GPO backups (security baseline, audit policy, registry hardening) — import via `Restore-GPO` |

---

## Containers

### Docker — [`containers/docker/`](containers/docker/)

| Script | Description |
|---|---|
| `install-docker.sh` | Docker CE installation using official keyring method |
| `install-docker-and-docker-compose.sh` | Docker CE + Compose plugin |
| `swarm/setup-docker-swarm.sh` | Docker Swarm cluster initialisation |
| `swarm/docker-swarm-node.sh` | Join a node to an existing swarm |
| `swarm/deploy-ds-portainer-agent.sh` | Deploy Portainer Agent across a Docker Swarm |

### Kubernetes — [`containers/kubernetes/`](containers/kubernetes/)

| Script | Description |
|---|---|
| `install-master-node.sh` | Kubernetes control plane initialisation |
| `install-worker-node.sh` | Worker node join |
| `install-management-node.sh` | kubectl management host setup |
| `install-minikube-kubectl-dashboard.sh` | Minikube + kubectl + Kubernetes Dashboard |

### Portainer — [`containers/portainer/`](containers/portainer/)

| Script | Description |
|---|---|
| `install-portainer.sh` | Portainer CE deployment |
| `install-portainer-agent.sh` | Portainer Agent for remote management |

---

## Monitoring

### Prometheus + Grafana — [`monitoring/prometheus-grafana/`](monitoring/prometheus-grafana/)

| Script | Description |
|---|---|
| `install-grafana-prometheus.sh` | Bare-metal install — auto-resolves latest Prometheus release |
| `install-grafana-prometheus-docker.sh` | Docker Compose deployment |
| `install-node-exporter-ubuntu.sh` | Node Exporter on Ubuntu |
| `install-node-exporter-windows.ps1` | Node Exporter on Windows |

### Zabbix — [`monitoring/zabbix/`](monitoring/zabbix/)

| Script | Description |
|---|---|
| `install-zabbix-agent-ubuntu.sh` | Zabbix agent on Ubuntu |
| `install-zabbix-agent-windows.ps1` | Zabbix agent on Windows |

---

## Security

### PKI — [`security/pki/`](security/pki/)

| Script | Description |
|---|---|
| `create-openssl-root-cert.sh` | Generate an OpenSSL root CA |
| `openssl-sign-sub-ca.sh` | Sign a subordinate CA request with the root CA |

### HashiCorp Vault — [`security/vault/`](security/vault/)

| Script | Description |
|---|---|
| `install-hashicorp-vault.sh` | Vault server installation and initialisation |
| `hashicorp-vault-server.sh` | Vault server role configuration |
| `useful-commands.txt` | Vault CLI reference commands |

### Compliance — [`security/compliance/`](security/compliance/)

| Script | Description |
|---|---|
| `PAM-TechSpecComplianceReport.ps1` | PAM technical specification compliance report generator |

---

## Applications

Standalone application deployments — [`applications/`](applications/)

| Directory | Script | Description |
|---|---|---|
| `awx/` | `install-awx.sh` | AWX (Ansible Tower) on Minikube with ingress and operator |
| `bacula/` | `install-bacula.sh` | Bacula backup server and client |
| `webmin/` | `install-webmin.sh` | Webmin web administration panel |
| `wordpress/` | `install-wordpress.sh` | WordPress on LAMP stack |

---

## Automation

### Python — [`automation/python/`](automation/python/)

| Script | Description |
|---|---|
| `azure-resource-inventory.py` | Azure subscription resource inventory via SDK — outputs CSV |
| `infrastructure-health-check.py` | Concurrent TCP/HTTP health checks with colour output and JSON report |
| `prometheus-query.py` | PromQL instant and range queries against any Prometheus endpoint |
| `test.py` | Environment check — Python version and DNS resolution |
| `requirements.txt` | Python dependency pinfile |

### Ansible — [`automation/ansible/`](automation/ansible/)

| Path | Description |
|---|---|
| `roles/microsoft/adds/` | Ansible Galaxy — Microsoft ADDS collection usage |
| `roles/microsoft/chocolatey/` | Ansible Galaxy — Chocolatey collection usage |

---

## Projects

### Blockchain — [`projects/blockchain/`](projects/blockchain/)

#### Cardano — [`projects/blockchain/cardano/`](projects/blockchain/cardano/)

| Script | Description |
|---|---|
| `install-cardano-node-baseline.sh` | Full node install with disk / resource pre-flight checks |
| `configure-cardano-node-iptables.sh` | Cardano-specific firewall rules |
| `deploy-docker-cardano-relay.sh` | Relay node via Docker |
| `download-cardano-cli.sh` | CLI binary download and verification |

#### COTI — [`projects/blockchain/coti/`](projects/blockchain/coti/)

| Script | Description |
|---|---|
| `install-coti-node-baseline.sh` | COTI network node baseline deployment |
| `configure-coti-iptables.sh` | COTI-specific firewall rules |

#### World Mobile — [`projects/blockchain/world-mobile/`](projects/blockchain/world-mobile/)

| Script | Description |
|---|---|
| `aya-testnet/1. aya-testnet-node-deploy.sh` | AYA testnet node deployment |
| `aya-testnet/2. aya-testnet-node-configuration.sh` | Node configuration |
| `aya-testnet/3. aya-testnet-node-keys.sh` | Key generation |
| `aya-testnet/aya-testnet-monitor-blocks.sh` | Block production monitoring |
| `wmc/docker-node.sh` | World Mobile Coin Docker node |

---

## Utilities

Bootstrap and helper scripts — [`utilities/`](utilities/)

| Script | Description |
|---|---|
| `github-monorepo-download.sh` | Clone this monorepo to a target Linux server |
| `make-sh-executable.sh` | Batch `chmod +x` on all downloaded scripts |
| `git-clone.ps1` | GitHub repository clone helper (PowerShell) |

---

## Usage

All scripts are standalone and self-documented with a header block describing purpose, prerequisites, and parameters.

**Bash scripts** — run as root or with sudo:
```bash
chmod +x script.sh
sudo ./script.sh
```

**PowerShell scripts** — run in an elevated session:
```powershell
Set-ExecutionPolicy RemoteSigned -Scope Process
.\script.ps1 -Parameter Value
```

**Python scripts** — requires Python 3.10+:
```bash
pip install -r automation/python/requirements.txt
python3 script.py --help
```

---

## License

Licensed under the [Apache License 2.0](LICENSE).
