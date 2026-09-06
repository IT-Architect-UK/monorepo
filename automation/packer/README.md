# Packer — Automated Machine Image Builds

[HashiCorp Packer](https://www.packer.io/) builds identical, version-controlled VM templates across multiple platforms from a single HCL configuration. Build once, deploy anywhere.

## Folder Structure

```
automation/packer/
├── builds/                          # One subdirectory per template
│   ├── ubuntu-2404-automation-toolbox/   # Ansible, Packer, Terraform, Docker, etc.
│   ├── ubuntu-2404-proxmox/              # Ubuntu 24.04 golden image — Proxmox
│   ├── ubuntu-2604-proxmox/              # Generic Ubuntu 26.04 — Proxmox
│   ├── ubuntu-2604-vmware/               # Generic Ubuntu 26.04 — VMware vSphere
│   ├── ubuntu-2604-aws/                  # Ubuntu 26.04 — AWS AMI
│   ├── ubuntu-2604-azure/                # Ubuntu 26.04 — Azure Managed Image
│   ├── ubuntu-2604-gcp/                  # Ubuntu 26.04 — GCP Custom Image
│   ├── win2025-proxmox/                  # Windows Server 2025 — Proxmox
│   └── win2025-vmware/                   # Windows Server 2025 — VMware vSphere
├── environments/                    # Variable files shared across more than one template
│   ├── homelab.pkrvars.hcl          # Proxmox / vSphere host, storage, network, ISO paths
│   ├── win2025.pkrvars.hcl          # Windows Server 2025 sizing, name and VM ID
│   ├── production.pkrvars.hcl       # Cloud (AWS / Azure / GCP) production values
│   └── README.md                    # Full variable reference
├── scripts/                         # Shared scripts — see scripts/README.md
│   ├── (in-guest provisioners)      # provision.sh, provision-windows.ps1, cleanup.sh, …
│   ├── (host-side Proxmox helpers)  # fetch-ubuntu-iso, select-or-upload-iso, remove-vm-if-exists, …
│   └── (diagnostics)                # task-probe.sh
├── http/                            # Unattended-install answer files — see http/README.md
│   ├── user-data / meta-data        # Ubuntu autoinstall (cloud-init NoCloud)
│   ├── win2025-proxmox/autounattend.xml
│   └── win2025-vmware/autounattend.xml
└── .env.example                     # Template for a local, git-ignored .env of PKR_VAR_* exports
```

Each `builds/<template>/` directory is self-contained — it has its own `variables.pkr.hcl` and can be validated or built independently. Always run Packer from inside the template directory, never from `builds/`.

## Building

The Proxmox templates each ship with a build wrapper (`build-*.sh` for Linux/macOS, `build-*.ps1` for Windows) and that is the normal entry point. The wrappers run `packer init`, `packer validate` and `packer build .` **without a var file**: site settings come from the `variables.pkr.hcl` defaults and any `PKR_VAR_*` environment variables, and the `.sh` wrappers additionally copy the site-general keys (URL, node, username, storage, bridge, VLAN) out of `environments/homelab.pkrvars.hcl` when nothing else has set them. Per-build values (VM ID, image name, sizing) stay with the template. The `.sh` wrappers also clear the fixed VM ID with `scripts/remove-vm-if-exists.sh` before building, so a re-run rebuilds in place.

The exception is the automation toolbox, whose wrapper passes two var files:

```bash
cd automation/packer/builds/ubuntu-2404-automation-toolbox
packer init .
packer validate -var-file="../../environments/homelab.pkrvars.hcl" -var-file="automation-toolbox.pkrvars.hcl" .
packer build    -var-file="../../environments/homelab.pkrvars.hcl" -var-file="automation-toolbox.pkrvars.hcl" .
```

Be aware of what `homelab.pkrvars.hcl` contains before passing it to any other template by hand: it sets `proxmox_vm_id = 106` and `image_name = "ubuntu-2604-homelab"`, which override the 9004/9006 IDs and `t-ubuntu-*` names shown in the table below. Only the toolbox restores its own values, because `automation-toolbox.pkrvars.hcl` is applied second. For the golden images either build through the wrapper, or pass the site file and then override with `-var`:

```bash
cd automation/packer/builds/ubuntu-2604-proxmox
packer build -var-file="../../environments/homelab.pkrvars.hcl" -var proxmox_vm_id=9006 -var image_name=t-ubuntu-2604 .
```

## Available Templates

| Template | Platform | Output | README |
|----------|----------|--------|--------|
| `ubuntu-2404-automation-toolbox` | Proxmox | VM Template (ID 9002, `T-UBUNTU-24-DEPLOY`) | [README](builds/ubuntu-2404-automation-toolbox/README.md) |
| `ubuntu-2404-proxmox` | Proxmox | VM Template (ID 9004, `t-ubuntu-2404-<timestamp>`) | [README](builds/ubuntu-2404-proxmox/README.md) |
| `ubuntu-2604-proxmox` | Proxmox | VM Template (ID 9006, `t-ubuntu-2604-<timestamp>`) | [README](builds/ubuntu-2604-proxmox/README.md) |
| `ubuntu-2604-vmware` | VMware vSphere | vSphere Template | [README](builds/ubuntu-2604-vmware/README.md) |
| `ubuntu-2604-aws` | AWS | AMI | [README](builds/ubuntu-2604-aws/README.md) |
| `ubuntu-2604-azure` | Azure | Managed Image | [README](builds/ubuntu-2604-azure/README.md) |
| `ubuntu-2604-gcp` | GCP | Custom Image | [README](builds/ubuntu-2604-gcp/README.md) |
| `win2025-proxmox` | Proxmox | VM Template (ID 9003, `t-win2025-<timestamp>`) | [README](builds/win2025-proxmox/README.md) |
| `win2025-vmware` | VMware vSphere | vSphere Template | [README](builds/win2025-vmware/README.md) |

## Prerequisites

| Tool | Needed by | Install |
|------|-----------|---------|
| Packer ≥ 1.10.0 | Everything | [developer.hashicorp.com/packer/downloads](https://developer.hashicorp.com/packer/downloads) |
| Git | Everything | [git-scm.com](https://git-scm.com) |
| xorriso | The Proxmox `.sh` wrappers (Packer needs it to build the cidata / autounattend CD) | `apt-get install xorriso` |
| curl, jq | The host-side Proxmox helpers in `scripts/` (automatic ISO staging, VM-slot clearing) | distro packages |
| Ansible | `ubuntu-2604-vmware`, `-aws`, `-azure`, `-gcp` only — their Ansible provisioner runs on the build host. The Proxmox templates run Ansible inside the guest | `pip install ansible` |
| Cloud CLI session | `aws configure`, `az login`, `gcloud auth application-default login` for the respective cloud template | vendor docs |

## Credentials

Sensitive values are never stored in files. Set them as `PKR_VAR_*` environment variables (or copy `.env.example` to `.env`, fill it in and `source .env`; `.env` is git-ignored). Which ones a build needs:

| Variable | Required by | Notes |
|----------|-------------|-------|
| `PKR_VAR_proxmox_password` | Proxmox templates | Or `PKR_VAR_proxmox_username="user@realm!tokenid"` + `PKR_VAR_proxmox_token` (token recommended; the toolbox template accepts password only) |
| `PKR_VAR_winrm_password` | `win2025-proxmox`, `win2025-vmware` | **Required, 12+ characters** — no default by design; injected into `autounattend.xml`. The Proxmox wrappers generate a random one if unset |
| `PKR_VAR_ssh_password` | `ubuntu-2604-vmware` only | The three Ubuntu Proxmox templates default it to `packer-temp-password`, the value whose hash is baked into `http/user-data` — do not set it unless you have regenerated `user-data` with a new hash |
| `PKR_VAR_semaphore_admin_password` | `ubuntu-2404-automation-toolbox` | Semaphore's initial admin password |
| `PKR_VAR_admin_password` | `ubuntu-2404-automation-toolbox` | Optional personal admin login password |
| `PKR_VAR_vsphere_password` | VMware templates | |
| `PKR_VAR_azure_subscription_id` | `ubuntu-2604-azure` | Plus an `az login` session |

```powershell
# Windows — persist across sessions
[System.Environment]::SetEnvironmentVariable("PKR_VAR_proxmox_password", "your-value", "User")
```

```bash
# Linux / macOS — add to ~/.bashrc or ~/.zshrc
export PKR_VAR_proxmox_password="your-value"
```

See [`environments/README.md`](environments/README.md) for the full variable reference.

**Known issue:** `.env.example` sets `PKR_VAR_ssh_password="Packer-Temp-P@ss1"`, which does not match the `packer-temp-password` hash in `http/user-data`. Sourcing an unedited copy makes the Ubuntu Proxmox builds fail SSH authentication until the timeout; remove or correct that line in your `.env`.

## CI/CD

Every push and pull request runs `packer init` and `packer validate` in each `builds/*` directory via GitHub Actions (`.github/workflows/validate.yml`), passing `environments/homelab.pkrvars.hcl` plus any template-local `.pkrvars.hcl`. No credentials are needed — validation is syntax-only and the workflow supplies dummy values for the sensitive variables.
