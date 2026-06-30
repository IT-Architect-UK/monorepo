# Packer — Automated Machine Image Builds

[HashiCorp Packer](https://www.packer.io/) automates the creation of identical machine images across multiple platforms from a single configuration file. Instead of manually launching a VM, patching it, and converting it to a template, Packer does the entire pipeline in a single command.

## Why Packer?

| Manual approach | With Packer |
|----------------|-------------|
| Launch VM, SSH in, patch manually | `packer build ubuntu-2604-proxmox.pkr.hcl` |
| Steps aren't documented | Everything is in version-controlled HCL files |
| Different process per platform | One template structure, multiple platforms |
| Easy to forget a step | Reproducible, auditable, CI/CD ready |
| Rebuilt from scratch each time | Fast: starts from latest base image, adds only your changes |

Packer is the industry standard for immutable infrastructure — the image is built once, tested, and deployed many times. Nothing changes after deployment.

## How It Connects to the Rest of This Repo

```
Packer (this directory)
    │
    ├── calls ──► scripts/provision.sh   (OS updates, hardening)
    ├── calls ──► ../ansible/playbooks/server-baseline.yml
    ├── calls ──► scripts/cleanup.sh     (image sealing)
    │
    └── outputs──► Proxmox VM Template / AMI / Managed Image
                        │
                        └── deployed by ──► Terraform (next step)
```

## Folder Structure

```
packer/
├── variables.pkr.hcl                              # All variable definitions (shared by every template)
├── ubuntu-2604-automation-toolbox-proxmox.pkr.hcl # Automation Toolbox — Ansible, Packer, Terraform, Docker, etc.
├── ubuntu-2604-ansible-server-proxmox.pkr.hcl     # Dedicated Ansible control node
├── ubuntu-2404-proxmox.pkr.hcl                    # Generic Ubuntu 24.04 Proxmox template
├── ubuntu-2404-vmware.pkr.hcl                     # VMware vSphere template
├── ubuntu-2404-aws.pkr.hcl                        # AWS AMI
├── ubuntu-2404-azure.pkr.hcl                      # Azure Managed Image
├── ubuntu-2404-gcp.pkr.hcl                        # GCP Custom Image
├── build-automation-toolbox.ps1                   # Windows PowerShell build script (see below)
├── scripts/
│   ├── provision.sh                               # Updates, tools, hardening
│   └── cleanup.sh                                 # Seals the image (removes machine-unique data)
├── http/
│   ├── user-data                                  # Ubuntu autoinstall config (unattended install)
│   └── meta-data                                  # Required by cloud-init NoCloud datasource
└── environments/
    ├── homelab.pkrvars.hcl                        # Proxmox host, storage, network settings
    └── automation-toolbox.pkrvars.hcl             # Overrides for the Automation Toolbox image
```

## Platform Quick Reference

| Platform | Template | Auth method | Output |
|----------|----------|-------------|--------|
| **Proxmox** — Automation Toolbox | `ubuntu-2604-automation-toolbox-proxmox.pkr.hcl` | `PKR_VAR_proxmox_password` | VM Template |
| **Proxmox** — Ansible Server | `ubuntu-2604-ansible-server-proxmox.pkr.hcl` | `PKR_VAR_proxmox_password` | VM Template |
| **Proxmox** — Generic | `ubuntu-2404-proxmox.pkr.hcl` | `PKR_VAR_proxmox_password` | VM Template |
| **VMware** | `ubuntu-2404-vmware.pkr.hcl` | `PKR_VAR_vsphere_password` | vSphere Template |
| **AWS** | `ubuntu-2404-aws.pkr.hcl` | `aws configure` | AMI |
| **Azure** | `ubuntu-2404-azure.pkr.hcl` | `az login` | Managed Image |
| **GCP** | `ubuntu-2404-gcp.pkr.hcl` | `gcloud auth` | Custom Image |

---

## Running the Build (Windows PowerShell)

A ready-made PowerShell script — `build-automation-toolbox.ps1` — handles the full build lifecycle: git pull, packer init, validate, and build. It reads credentials from Windows environment variables so nothing sensitive is ever typed into the terminal or stored in a file.

### Step 1 — Set environment variables (do this once)

> **Do this before your first run.** Pre-setting variables means every subsequent run is completely non-interactive — no prompts, no manual input.

Open PowerShell and run:

```powershell
[System.Environment]::SetEnvironmentVariable("PKR_VAR_proxmox_password",         "your-proxmox-root-password",  "User")
[System.Environment]::SetEnvironmentVariable("PKR_VAR_ssh_password",             "your-chosen-ssh-password",    "User")
[System.Environment]::SetEnvironmentVariable("PKR_VAR_semaphore_admin_password", "your-semaphore-password",     "User")
```

These are stored in your Windows user profile. They survive reboots, are invisible to other users, and are **never written to disk inside the repo or synced to GitHub**.

Open a **new** PowerShell terminal after setting them so the values are loaded into the session.

> **What if I skip this step?** The script will detect the missing variables and prompt you to enter them securely (input is hidden). Prompted values are used for that run only — they are not saved anywhere.

### Step 2 — Prerequisites

| Requirement | Minimum version | Install |
|------------|-----------------|---------|
| Packer | 1.10.0 | [developer.hashicorp.com/packer/downloads](https://developer.hashicorp.com/packer/downloads) |
| Git | any | [git-scm.com](https://git-scm.com) |
| Access to Proxmox host | — | VPN or LAN connectivity required |

Verify Packer is on your PATH:

```powershell
packer version
```

### Step 3 — Build the cidata ISO (first run only)

The Ubuntu autoinstall uses a pre-built cloud-init cidata ISO. Upload it to Proxmox storage before the first build:

```bash
# On the Proxmox host
cd /var/lib/vz/template/iso
mkdosfs -n CIDATA -C ubuntu-2604-cidata.iso 8192
mcopy -oi ubuntu-2604-cidata.iso user-data meta-data ::
```

Or build it on Linux/macOS and upload via the Proxmox web UI. The ISO path is set by `PKR_VAR_cidata_iso_file` (default: `NFS-10GB-PROXMOX-1:iso/ubuntu-2604-cidata.iso`).

### Step 4 — Run the script

Open a PowerShell terminal, navigate to the packer directory, and run:

```powershell
cd D:\GitHub\monorepo\automation\packer

# Validate the template first (no VM is created — fast sanity check)
.\build-automation-toolbox.ps1 -DryRun

# Full build (20–40 minutes)
.\build-automation-toolbox.ps1

# Full build with verbose Packer output (useful for debugging)
.\build-automation-toolbox.ps1 -Verbose
```

During the build, switch to the **Proxmox console** (Datacenter → `POSVMPWS01` → the new VM → Console) to watch the Ubuntu autoinstall progress.

### What the script does

1. Checks for (or prompts for) the three required credentials
2. Pulls the latest template code from GitHub
3. Runs `packer init` to download/verify plugins
4. Runs `packer validate` — exits here if `-DryRun` was specified
5. Runs `packer build` — boots a VM in Proxmox, installs Ubuntu, provisions tools, converts to a template
6. Clears all credential env vars from the session on exit (even on failure)

---

## Manual Build (Linux / macOS / bash)

```bash
# Set credentials in the shell
export PKR_VAR_proxmox_password="your-root-password"
export PKR_VAR_ssh_password="your-packer-user-password"
export PKR_VAR_semaphore_admin_password="your-semaphore-password"

cd automation/packer

# Download plugins
packer init ubuntu-2604-automation-toolbox-proxmox.pkr.hcl

# Validate
packer validate \
  -var-file="environments/homelab.pkrvars.hcl" \
  -var-file="environments/automation-toolbox.pkrvars.hcl" \
  ubuntu-2604-automation-toolbox-proxmox.pkr.hcl

# Build
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  -var-file="environments/automation-toolbox.pkrvars.hcl" \
  ubuntu-2604-automation-toolbox-proxmox.pkr.hcl
```

---

## Build Pipeline (what happens during `packer build`)

```
packer build ubuntu-2604-automation-toolbox-proxmox.pkr.hcl
      │
      ├─ [1] Create VM in Proxmox (ID 9002)
      ├─ [2] Attach Ubuntu 26.04 ISO + cidata ISO
      ├─ [3] Boot VM — autoinstall reads cidata, installs Ubuntu unattended
      ├─ [4] Wait for SSH (up to 90 min — OS install + first boot)
      │
      ├─ [5] Provisioner: scripts/provision.sh
      │         ├── apt-get update && upgrade
      │         ├── Install: Ansible, Packer, Terraform, AWS CLI, Azure CLI
      │         ├── Install: kubectl, Helm, Docker, GitHub CLI, Semaphore
      │         └── Harden SSH, configure UFW
      │
      ├─ [6] Provisioner: scripts/cleanup.sh
      │         ├── Clean cloud-init cache
      │         ├── Remove SSH host keys
      │         ├── Reset machine-id
      │         └── Clear logs and temp files
      │
      ├─ [7] Convert VM to Proxmox template
      └─ [8] Write packer-manifest-automation-toolbox.json
```

Total build time: approximately 20–40 minutes depending on network speed and Proxmox host performance.

---

## CI/CD Integration

The `.github/workflows/validate.yml` workflow validates every template on every push — syntax checking only, no real builds. To run actual builds in CI you would add runner credentials as GitHub Actions Secrets and a separate workflow.

---

## Troubleshooting

**SSH timeout during build?**
The autoinstall takes 15–30 minutes. The script sets `ssh_timeout = "90m"` and `ssh_handshake_attempts = 50`. If it times out, check the Proxmox console — is the VM stuck at a boot menu?

**`packer init` fails?**
Ensure internet access and Packer ≥ 1.10.0: `packer version`

**Duplicate variable error in CI?**
Each template must not redeclare variables already defined in `variables.pkr.hcl`. Both files are visible during validation and Packer treats duplicates as errors.

**VM IP not found?**
The `qemu-guest-agent` must be installed and started inside the VM. It is installed by `provision.sh` — if you customised that script, ensure the agent install step is present.

**`packer-manifest-automation-toolbox.json` not found?**
The manifest is written to the directory where `packer build` ran (`automation/packer/`). It is git-ignored and stays local.

---

## Further Reading

- [Packer Documentation](https://developer.hashicorp.com/packer/docs)
- [Proxmox Plugin Docs](https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox)
- [Ubuntu Autoinstall Reference](https://ubuntu.com/server/docs/install/autoinstall-reference)
- [Packer + Ansible Integration](https://developer.hashicorp.com/packer/integrations/hashicorp/ansible)
- [`environments/README.md`](environments/README.md) — full variable reference
