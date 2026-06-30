# Packer — Automated Machine Image Builds

[HashiCorp Packer](https://www.packer.io/) builds identical, version-controlled VM templates across multiple platforms from a single HCL configuration. Build once, deploy anywhere.

## Folder Structure

```
automation/packer/
├── builds/                          # One subdirectory per template
│   ├── ubuntu-2604-automation-toolbox/   # Ansible, Packer, Terraform, Docker, etc.
│   ├── ubuntu-2604-ansible-server/       # Dedicated Ansible control node
│   ├── ubuntu-2604-proxmox/              # Generic Ubuntu 26.04 — Proxmox
│   ├── ubuntu-2604-vmware/               # Generic Ubuntu 26.04 — VMware vSphere
│   ├── ubuntu-2604-aws/                  # Ubuntu 26.04 — AWS AMI
│   ├── ubuntu-2604-azure/                # Ubuntu 26.04 — Azure Managed Image
│   ├── ubuntu-2604-gcp/                  # Ubuntu 26.04 — GCP Custom Image
│   ├── win2025-proxmox/                  # Windows Server 2025 — Proxmox
│   └── win2025-vmware/                   # Windows Server 2025 — VMware vSphere
├── environments/                    # Shared variable files (referenced by all builds)
│   ├── homelab.pkrvars.hcl          # Proxmox host, storage, network settings
│   ├── automation-toolbox.pkrvars.hcl
│   └── README.md                    # Full variable reference
├── scripts/                         # Provisioner shell scripts (shared)
│   ├── provision.sh                 # Base OS setup, tools, hardening
│   ├── provision-automation-toolbox.sh
│   ├── provision-ansible-server.sh
│   ├── provision-semaphore.sh
│   ├── cleanup.sh
│   └── ...
└── http/                            # Cloud-init / autoinstall files (shared)
    ├── user-data
    ├── meta-data
    └── win2025-proxmox/
        └── autounattend.xml
```

Each `builds/<template>/` directory is self-contained — it has its own `variables.pkr.hcl` and can be validated or built independently:

```bash
cd automation/packer/builds/ubuntu-2604-automation-toolbox
packer init .
packer validate -var-file="../../environments/homelab.pkrvars.hcl" .
packer build   -var-file="../../environments/homelab.pkrvars.hcl" .
```

## Available Templates

| Template | Platform | Output | README |
|----------|----------|--------|--------|
| `ubuntu-2604-automation-toolbox` | Proxmox | VM Template (ID 9002) | [README](builds/ubuntu-2604-automation-toolbox/README.md) |
| `ubuntu-2604-ansible-server` | Proxmox | VM Template | [ANSIBLE-SERVER.md](ANSIBLE-SERVER.md) |
| `ubuntu-2604-proxmox` | Proxmox | VM Template | — |
| `ubuntu-2604-vmware` | VMware vSphere | vSphere Template | — |
| `ubuntu-2604-aws` | AWS | AMI | — |
| `ubuntu-2604-azure` | Azure | Managed Image | — |
| `ubuntu-2604-gcp` | GCP | Custom Image | — |
| `win2025-proxmox` | Proxmox | VM Template | — |
| `win2025-vmware` | VMware vSphere | vSphere Template | — |

## Prerequisites

| Tool | Minimum version | Install |
|------|-----------------|---------|
| Packer | 1.10.0 | [developer.hashicorp.com/packer/downloads](https://developer.hashicorp.com/packer/downloads) |
| Git | any | [git-scm.com](https://git-scm.com) |

## Credentials

Sensitive values are never stored in files. Set them as environment variables before running any build:

```powershell
# Windows — persist across sessions
[System.Environment]::SetEnvironmentVariable("PKR_VAR_proxmox_password",         "your-value", "User")
[System.Environment]::SetEnvironmentVariable("PKR_VAR_ssh_password",             "your-value", "User")
[System.Environment]::SetEnvironmentVariable("PKR_VAR_semaphore_admin_password", "your-value", "User")
```

```bash
# Linux / macOS — add to ~/.bashrc or ~/.zshrc
export PKR_VAR_proxmox_password="your-value"
export PKR_VAR_ssh_password="your-value"
export PKR_VAR_semaphore_admin_password="your-value"
```

See [`environments/README.md`](environments/README.md) for the full variable reference.

## CI/CD

Every push to `main` runs `packer validate` against all templates via GitHub Actions (`.github/workflows/validate.yml`). No credentials are needed — validation is syntax-only and uses dummy values for sensitive variables.
