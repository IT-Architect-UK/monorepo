# Ubuntu 26.04 Automation Toolbox — Proxmox

Builds a Proxmox VM template pre-loaded with every tool needed to run infrastructure automation from a single host.

## What Gets Installed

| Category | Tools |
|----------|-------|
| Infrastructure as Code | Ansible, Packer, Terraform |
| Cloud CLIs | AWS CLI v2, Azure CLI, Google Cloud SDK |
| Kubernetes | kubectl, Helm |
| Containers | Docker CE, Docker Compose |
| Source control | Git, GitHub CLI (`gh`) |
| Languages / runtimes | Python 3, pip, boto3, azure-identity, google-cloud |
| Utilities | jq, yq, curl, wget, unzip |
| Automation UI | Semaphore (web UI for Ansible playbooks) |

The resulting Proxmox template (default VM ID: **9002**, name: **POSLXPDEPLOY01**) is ready to clone and use immediately.

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10.0 | [Download](https://developer.hashicorp.com/packer/downloads) — must be on your PATH |
| Proxmox VE | API accessible from your build machine (LAN or VPN) |
| Ubuntu 26.04 ISO | Pre-uploaded to Proxmox storage |
| cidata ISO | Built from `http/user-data` + `http/meta-data` — see below |

---

## One-Time Setup

### 1. Set credentials as persistent environment variables

Run once in PowerShell — survives reboots, never written to disk or GitHub:

```powershell
[System.Environment]::SetEnvironmentVariable("PKR_VAR_proxmox_password",         "your-proxmox-root-password",  "User")
[System.Environment]::SetEnvironmentVariable("PKR_VAR_semaphore_admin_password", "your-semaphore-password",     "User")
[System.Environment]::SetEnvironmentVariable("PKR_VAR_admin_password",           "your-admin-login-password",   "User")
```

Open a **new** PowerShell terminal after setting these. If you skip this step the build script will prompt for each value at runtime (input is hidden).

Note: `PKR_VAR_ssh_password` is not needed — it's a temporary, build-only
credential pinned to `variables.pkr.hcl`'s default and unrelated to any
login you'll actually use afterward.

### 2. Upload the Ubuntu 26.04 ISO to Proxmox

Download from [ubuntu.com/download/server](https://ubuntu.com/download/server) and upload via the Proxmox web UI:

- **Datacenter → Storage → NFS-10GB-PROXMOX-1 → ISO Images → Upload**

The expected path is set in `../../environments/homelab.pkrvars.hcl`:

```hcl
ubuntu_iso_file = "NFS-10GB-PROXMOX-1:iso/ubuntu-26.04-live-server-amd64.iso"
```

### 3. Build and upload the cidata ISO (autoinstall)

The template uses Ubuntu autoinstall via a NoCloud cidata ISO — this replaces the HTTP server approach and works reliably with Proxmox.

On a Linux machine or the Proxmox host:

```bash
# Install tools if needed
apt-get install -y dosfstools mtools

# Build the ISO from the cloud-init files in this repo
cd automation/packer/http
mkdosfs -n CIDATA -C ubuntu-2604-cidata.iso 8192
mcopy -oi ubuntu-2604-cidata.iso user-data meta-data ::
```

Upload `ubuntu-2604-cidata.iso` to Proxmox storage (same location as the Ubuntu ISO). The expected path is set in `variables.pkr.hcl`:

```hcl
variable "cidata_iso_file" {
  default = "NFS-10GB-PROXMOX-1:iso/ubuntu-2604-cidata.iso"
}
```

---

## Running the Build

### Option A — PowerShell script (Windows, recommended)

Open a PowerShell terminal and run from this directory:

```powershell
cd D:\GitHub\monorepo\automation\packer\builds\ubuntu-2604-automation-toolbox

# Validate only (fast — no VM created)
.\build-automation-toolbox-proxmox.ps1 -DryRun

# Full build (~20–40 minutes)
.\build-automation-toolbox-proxmox.ps1

# Full build with verbose Packer output (useful for debugging)
.\build-automation-toolbox-proxmox.ps1 -Verbose
```

The script will:
1. Prompt for any missing credentials (hidden input)
2. Pull the latest code from GitHub
3. Run `packer init` to download plugins
4. Validate the template
5. Run the full build (unless `-DryRun`)
6. Scrub all credentials from the session on exit

### Option B — Packer CLI directly (Linux / macOS / bash)

```bash
export PKR_VAR_proxmox_password="your-root-password"
export PKR_VAR_ssh_password="your-packer-user-password"
export PKR_VAR_semaphore_admin_password="your-semaphore-password"

cd automation/packer/builds/ubuntu-2604-automation-toolbox

packer init .

packer validate \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  -var-file="../../environments/automation-toolbox.pkrvars.hcl" \
  .

packer build \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  -var-file="../../environments/automation-toolbox.pkrvars.hcl" \
  .
```

---

## What Happens During the Build

```
packer build .
      │
      ├─ [1] Create VM in Proxmox (ID 9002)
      ├─ [2] Attach Ubuntu 26.04 ISO + cidata ISO
      ├─ [3] Boot VM — autoinstall reads cidata, installs Ubuntu unattended
      ├─ [4] Wait for SSH (up to 90 min — install + first boot)
      │
      ├─ [5] ../../scripts/provision.sh
      │         ├── apt update + upgrade
      │         ├── Install base tools and harden SSH
      │         └── Configure UFW firewall
      │
      ├─ [6] ../../scripts/provision-automation-toolbox.sh
      │         ├── Ansible, Packer, Terraform
      │         ├── AWS CLI v2, Azure CLI, Google Cloud SDK
      │         ├── kubectl, Helm, Docker CE, GitHub CLI
      │         └── Python 3 + cloud SDKs
      │
      ├─ [7] Ansible playbook: server-baseline.yml
      │         └── Applies hardening roles from automation/ansible/
      │
      ├─ [8] ../../scripts/cleanup.sh
      │         ├── Remove SSH host keys and machine-id
      │         └── Clean logs and cloud-init cache
      │
      └─ [9] Convert VM to Proxmox template → POSLXPDEPLOY01
```

During the build, watch progress in the **Proxmox console**:
Datacenter → `POSVMPWS01` → new VM → Console

---

## Customising the Build

All overridable settings are in `../../environments/`:

| File | Purpose |
|------|---------|
| `homelab.pkrvars.hcl` | Proxmox host, storage pool, ISO paths, VM sizing |
| `automation-toolbox.pkrvars.hcl` | Image name, CPU/RAM/disk overrides, VM ID |

To use a different VM ID or image name, edit `automation-toolbox.pkrvars.hcl`:

```hcl
image_name    = "my-toolbox"
proxmox_vm_id = 9010
vm_cpu_count  = 8
vm_memory_mb  = 8192
vm_disk_gb    = 100
```

---

## After the Build

1. In Proxmox, right-click the template → **Clone** → Full Clone
2. Start the clone and SSH in as your personal admin login
   (`admin_username` in `../../environments/automation-toolbox.pkrvars.hcl`,
   authenticated via `admin_ssh_public_key` or the `admin_password` you set):
   ```bash
   ssh it-admin@<vm-ip>
   ```
   The `packer` build user and `toolbox` service account both have SSH
   password auth disabled and no key configured — they are not meant for
   interactive login.
3. Verify tools:
   ```bash
   ansible --version
   terraform --version
   packer --version
   docker --version
   ```
4. Change the Semaphore admin password — open `http://<vm-ip>:3000` in a browser

---

## Troubleshooting

**SSH timeout during build**
The autoinstall + first boot can take 20–30 min. The template allows 90 min. Check the Proxmox console — if the VM is at a boot menu, the cidata ISO may not have been attached correctly.

**`packer init` fails**
Ensure Packer ≥ 1.10.0 is installed and has internet access to download the Proxmox plugin from GitHub.

**`cidata_iso_file` not found**
Upload the cidata ISO to Proxmox before running the build. The path must match `cidata_iso_file` in `variables.pkr.hcl`.

**Duplicate variable errors**
Each build directory has its own `variables.pkr.hcl`. Do not run `packer build .` from the `builds/` parent directory — always run from inside the specific template folder.

**VM already exists (ID conflict)**
Change `proxmox_vm_id` in `automation-toolbox.pkrvars.hcl` to a free ID in your cluster.
