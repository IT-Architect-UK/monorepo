# Packer — Automated Machine Image Builds

[![Validate](https://github.com/IT-Architect-UK/monorepo/actions/workflows/validate.yml/badge.svg)](https://github.com/IT-Architect-UK/monorepo/actions/workflows/validate.yml)

[HashiCorp Packer](https://www.packer.io/) automates the creation of identical machine images across multiple platforms from a single configuration file. Instead of manually building and configuring a VM, Packer does the entire pipeline — OS install, patching, tool installation, hardening, and image sealing — in a single repeatable command.

## Why Packer?

| Manual approach | With Packer |
|---|---|
| Launch VM, SSH in, configure manually | `packer build ubuntu-2604-proxmox.pkr.hcl` |
| Steps live in someone's head | Everything version-controlled in HCL |
| Different process per platform | One template structure, consistent output |
| Easy to miss a step | Reproducible, auditable, CI-validated |
| Drift between environments | Identical image on every platform |

## How It Fits the Repo

```
Packer (this directory)
    │
    ├── calls ──► scripts/provision.sh              (OS baseline, hardening)
    ├── calls ──► scripts/provision-automation-toolbox.sh  (tools: Ansible, Terraform, Docker …)
    ├── calls ──► ../ansible/playbooks/server-baseline.yml
    ├── calls ──► scripts/cleanup.sh                (image sealing)
    │
    └── outputs──► Proxmox Template / VMware Template / AMI / Managed Image / GCP Image
```

The same Ansible `server-baseline` role that hardens a running server also hardens the golden image — no duplication.

## Folder Structure

```
automation/packer/
├── variables.pkr.hcl                              # All shared variable definitions
│
├── ubuntu-2604-proxmox.pkr.hcl                   # Ubuntu 26.04 — Proxmox template (ISO + HTTP server)
├── ubuntu-2604-automation-toolbox-proxmox.pkr.hcl # Ubuntu 26.04 — Automation host (Ansible, Packer, Terraform …)
├── ubuntu-2604-ansible-server-proxmox.pkr.hcl    # Ubuntu 26.04 — Dedicated Ansible control node
├── ubuntu-2604-vmware.pkr.hcl                    # Ubuntu 26.04 — VMware vSphere template
├── ubuntu-2604-aws.pkr.hcl                       # Ubuntu 26.04 — AWS AMI
├── ubuntu-2604-azure.pkr.hcl                     # Ubuntu 26.04 — Azure Managed Image
├── ubuntu-2604-gcp.pkr.hcl                       # Ubuntu 26.04 — GCP Custom Image
├── win2025-proxmox.pkr.hcl                       # Windows Server 2025 — Proxmox template
├── win2025-vmware.pkr.hcl                        # Windows Server 2025 — VMware vSphere template
│
├── scripts/
│   ├── provision.sh                               # OS baseline: updates, hardening, branding
│   ├── provision-automation-toolbox.sh            # Installs automation tools (Ansible, Packer, Terraform …)
│   └── cleanup.sh                                 # Image sealing: removes SSH keys, machine-id, logs
│
├── http/
│   ├── user-data                                  # Ubuntu autoinstall (unattended OS install via HTTP)
│   └── meta-data                                  # Required by cloud-init NoCloud datasource
│
└── environments/
    ├── homelab.pkrvars.hcl                        # Your Proxmox/VMware addresses and storage names
    ├── automation-toolbox.pkrvars.hcl             # Overrides for the automation toolbox image
    ├── ansible-server.pkrvars.hcl                 # Overrides for the Ansible server image
    ├── win2025.pkrvars.hcl                        # Windows-specific overrides
    └── production.pkrvars.hcl                     # Production environment values
```

## Quick Start

### 1. Prerequisites

- [Packer](https://developer.hashicorp.com/packer/install) ≥ 1.10.0
- For Proxmox builds: Proxmox VE 7+ with API access
- For VMware builds: vCenter or ESXi with vSphere API access
- For cloud builds: AWS CLI / Azure CLI / gcloud configured

```bash
# Verify Packer is installed
packer version
```

### 2. Clone and initialise

```bash
git clone https://github.com/IT-Architect-UK/monorepo.git
cd monorepo/automation/packer

# Download the required Packer plugins (run once per template)
packer init .
```

### 3. Configure your environment

Copy `environments/homelab.pkrvars.hcl` and edit it to match your infrastructure:

```bash
cp environments/homelab.pkrvars.hcl environments/mylab.pkrvars.hcl
```

Key values to change:

| Variable | What to set |
|---|---|
| `proxmox_url` | Your Proxmox API URL, e.g. `https://192.168.1.10:8006/api2/json` |
| `proxmox_node` | Your Proxmox node name |
| `proxmox_storage_pool` | Where to store the template disk |
| `proxmox_iso_storage` | Where your ISOs are stored |
| `ubuntu_iso_file` | Path to Ubuntu ISO already on Proxmox storage |

See [`environments/README.md`](environments/README.md) for the full variable reference.

### 4. Set credentials as environment variables

Never put passwords in var files. Use environment variables:

```bash
# Proxmox
export PKR_VAR_proxmox_password="your-proxmox-root-password"
export PKR_VAR_ssh_password="temp-build-password"

# VMware
export PKR_VAR_vsphere_password="your-vcenter-password"

# AWS (or use aws configure)
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."

# Azure (or use az login)
export PKR_VAR_azure_subscription_id="your-sub-id"
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_TENANT_ID="..."

# GCP (or use gcloud auth application-default login)
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
```

### 5. Build

```bash
# Validate first (catches errors without building anything)
packer validate -var-file="environments/homelab.pkrvars.hcl" ubuntu-2604-proxmox.pkr.hcl

# Build a Proxmox template
packer build -var-file="environments/homelab.pkrvars.hcl" ubuntu-2604-proxmox.pkr.hcl

# Build the automation toolbox (uses two var files)
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  -var-file="environments/automation-toolbox.pkrvars.hcl" \
  ubuntu-2604-automation-toolbox-proxmox.pkr.hcl

# Build an AWS AMI
packer build ubuntu-2604-aws.pkr.hcl

# Enable verbose logging
PACKER_LOG=1 packer build -var-file="environments/homelab.pkrvars.hcl" ubuntu-2604-proxmox.pkr.hcl
```

## Template Reference

| Template | Platform | Output | Notes |
|---|---|---|---|
| `ubuntu-2604-proxmox.pkr.hcl` | Proxmox | VM Template | General-purpose Ubuntu 26.04 base |
| `ubuntu-2604-automation-toolbox-proxmox.pkr.hcl` | Proxmox | VM Template | Ansible, Packer, Terraform, Docker, AWS/Azure/GCP CLIs |
| `ubuntu-2604-ansible-server-proxmox.pkr.hcl` | Proxmox | VM Template | Dedicated Ansible control node with Semaphore UI |
| `ubuntu-2604-vmware.pkr.hcl` | VMware vSphere | VM Template | Ubuntu 26.04 base for vSphere |
| `ubuntu-2604-aws.pkr.hcl` | AWS | AMI | Ubuntu 26.04, eu-west-2 by default |
| `ubuntu-2604-azure.pkr.hcl` | Azure | Managed Image | Ubuntu 26.04, uksouth by default |
| `ubuntu-2604-gcp.pkr.hcl` | GCP | Custom Image | Ubuntu 26.04, europe-west2 by default |
| `win2025-proxmox.pkr.hcl` | Proxmox | VM Template | Windows Server 2025, unattended install |
| `win2025-vmware.pkr.hcl` | VMware vSphere | VM Template | Windows Server 2025, unattended install |

## Proxmox Builds — cidata ISO

The Proxmox templates use Ubuntu autoinstall via a **cidata ISO** instead of Packer's built-in HTTP server. This is more reliable in homelab environments where the build VM may not be able to reach the Packer host.

The cidata ISO contains two files:
- `user-data` — the Ubuntu autoinstall configuration (from `http/user-data`)
- `meta-data` — required empty file for cloud-init NoCloud

**Build and upload the cidata ISO before running any Proxmox template:**

```bash
# On your Packer host (Linux)
pip install pycdlib
python3 scripts/build-cidata-iso.py

# Upload to Proxmox storage
scp ubuntu-2604-cidata.iso root@proxmox:/var/lib/vz/template/iso/
```

Or upload via the Proxmox web UI to your ISO storage pool.

The ISO path is set by `cidata_iso_file` in your var file (default: `NFS-10GB-PROXMOX-1:iso/ubuntu-2604-cidata.iso`).

## Build Pipeline

What happens during `packer build`:

```
packer build ubuntu-2604-proxmox.pkr.hcl
      │
      ├─ [1] Connect to Proxmox API
      ├─ [2] Create VM, attach Ubuntu ISO + cidata ISO
      ├─ [3] Boot VM — Ubuntu autoinstall reads user-data from cidata ISO
      ├─ [4] OS installs unattended (~10 min)
      ├─ [5] Packer connects via SSH
      │
      ├─ [6] Provisioner: scripts/provision.sh
      │         ├── apt-get update && upgrade
      │         ├── Install common tools (curl, git, jq, vim …)
      │         ├── Apply company branding (MOTD, login banner, PS1)
      │         ├── Harden SSH (disable root login, set AllowUsers)
      │         ├── Configure UFW firewall
      │         └── Disable IPv6, cloud-init persistence
      │
      ├─ [7] Provisioner: Ansible server-baseline playbook
      │         ├── Apply roles/common tasks
      │         ├── Configure fail2ban
      │         └── Set timezone / NTP
      │
      ├─ [8] Provisioner: scripts/cleanup.sh
      │         ├── Remove SSH host keys (regenerated on first boot)
      │         ├── Reset machine-id
      │         ├── Clean cloud-init cache
      │         └── Clear logs and temp files
      │
      └─ [9] Convert VM to Proxmox template
             Write packer-manifest.json
```

Total build time: ~20–40 min (Proxmox/VMware, includes OS install). ~10–15 min (AWS/Azure/GCP, starts from existing base image).

## Windows Builds

Windows Server 2025 templates use an `autounattend.xml` for unattended install and WinRM for provisioning (instead of SSH).

**Before running a Windows build:**
1. Download the [Windows Server 2025 evaluation ISO](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025)
2. Download the [virtio-win drivers ISO](https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso)
3. Upload both to your Proxmox ISO storage
4. Set `win_iso_file` and `virtio_iso_file` in your var file

```bash
export PKR_VAR_winrm_password="your-winrm-password"
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  -var-file="environments/win2025.pkrvars.hcl" \
  win2025-proxmox.pkr.hcl
```

## Running the Build (Windows PowerShell)

A PowerShell build script is included for running Packer on Windows without typing credentials each time.

### 1. Create your local credentials file

```powershell
cd D:\GitHub\monorepo\automation\packer
Copy-Item build-automation-toolbox.vars.ps1.example build-automation-toolbox.vars.ps1
```

Open `build-automation-toolbox.vars.ps1` and fill in your three passwords:

```powershell
$ProxmoxPassword        = "your-proxmox-root-password"
$PackerSshPassword      = "your-packer-temp-password"
$SemaphoreAdminPassword = "your-semaphore-admin-password"
```

This file is listed in `.gitignore` — it will never be committed to GitHub.

### 2. Allow PowerShell scripts to run (one-time)

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 3. Run the script

```powershell
# Validate only — no build, confirms template and credentials are correct
.\build-automation-toolbox.ps1 -DryRun

# Full build (~20-40 minutes)
.\build-automation-toolbox.ps1

# Full build with verbose Packer debug output
.\build-automation-toolbox.ps1 -Verbose
```

The script automatically runs `git pull` before building, sets credentials as session-only environment variables (never written to disk), and clears them on exit. Watch build progress in the Proxmox console.

---

## CI/CD Validation

Every push to this repo runs `packer validate` against all templates automatically via GitHub Actions. The badge at the top of this file shows current status.

The validation uses dummy credentials — it checks HCL syntax and variable completeness without connecting to any infrastructure. See [`.github/workflows/validate.yml`](../../.github/workflows/validate.yml).

## Troubleshooting

**`packer init` fails**
→ Check internet access. Requires Packer ≥ 1.10.0: `packer version`

**SSH timeout on Proxmox/VMware build**
→ The OS autoinstall takes 10–20 min. The default `ssh_timeout` is 90 min.
→ Watch the VM console in Proxmox UI to see if the install is progressing.
→ Check the cidata ISO is mounted and readable: `pvesm list <storage> --content iso`

**`nomodeset` and framebuffer errors on boot**
→ The boot command includes `nomodeset` — required for Ubuntu 26.04 in VMs without a display adapter. Do not remove it.

**Build VM IP not found (Proxmox)**
→ Ensure `qemu-guest-agent` is installed and the QEMU agent is enabled on the VM.

**AWS: "no valid credential sources"**
→ Run `aws configure` or set `AWS_ACCESS_KEY_ID` + `AWS_SECRET_ACCESS_KEY`.

**VMware: insecure_connection error**
→ Set `insecure_skip_tls_verify = true` (lab only) or trust your vCenter certificate.

**`packer-manifest.json` not found**
→ Written to the directory where you ran `packer build`.

## Further Reading

- [Packer Documentation](https://developer.hashicorp.com/packer/docs)
- [Proxmox Plugin](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox)
- [vSphere Plugin](https://developer.hashicorp.com/packer/integrations/hashicorp/vsphere)
- [Amazon EBS Builder](https://developer.hashicorp.com/packer/integrations/hashicorp/amazon/latest/components/builder/ebs)
- [Ubuntu Autoinstall Reference](https://ubuntu.com/server/docs/install/autoinstall-reference)
- [Packer + Ansible](https://developer.hashicorp.com/packer/integrations/hashicorp/ansible)
