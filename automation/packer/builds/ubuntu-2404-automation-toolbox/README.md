# Ubuntu 24.04 Automation Toolbox — Proxmox

Builds the primary automation host for the lab -- pre-loaded with every tool needed to run infrastructure automation. Not a golden image: this is deployed once and used as the standing server everything else gets deployed from.

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

The build produces a Proxmox template (default VM ID: **9002**, name: **POSLXPDEPLOY01**) as its output artifact -- clone it once to stand up the real toolbox server (see "After the Build" below).

---

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10.0 | [Download](https://developer.hashicorp.com/packer/downloads) — must be on your PATH |
| Proxmox VE | API accessible from your build machine (LAN or VPN) |
| cidata ISO | Pre-built in `cidata/` — see below |

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

### 2. Nothing to do for the Ubuntu ISO

Packer downloads and checksum-verifies the Ubuntu 24.04 ISO directly from
Canonical at build time -- no manual download or upload required. This host
is pinned to 24.04 LTS (not the 26.04 used by the golden image templates in
this repo), set in `automation-toolbox.pkrvars.hcl`:

```hcl
ubuntu_iso_url      = "https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso"
ubuntu_iso_checksum = "file:https://releases.ubuntu.com/noble/SHA256SUMS"
```

The exact filename includes the point release and needs a one-line bump the
rare times Canonical retires an old one; the checksum URL never changes.

### 3. Upload the cidata ISO (autoinstall)

The template uses Ubuntu autoinstall via a NoCloud cidata ISO — this replaces the HTTP server approach and works reliably with Proxmox.

`cidata/ubuntu-2404-cidata.iso` is pre-built and committed to this repo — no
local build tools needed. See [`cidata/README.md`](cidata/README.md) for
what it contains and how to rebuild it if `http/user-data` or `http/meta-data`
ever changes.

Upload `cidata/ubuntu-2404-cidata.iso` to the Proxmox storage pool configured in `proxmox_iso_storage`. The expected path is set in `variables.pkr.hcl`:

```hcl
variable "cidata_iso_file" {
  default = "NFS-10GB-PROXMOX-1:iso/ubuntu-2404-cidata.iso"
}
```

---

## Running the Build

### Option A — PowerShell script (Windows, recommended)

Open a PowerShell terminal and run from this directory:

```powershell
cd D:\GitHub\monorepo\automation\packer\builds\ubuntu-2404-automation-toolbox

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

cd automation/packer/builds/ubuntu-2404-automation-toolbox

packer init .

packer validate \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  -var-file="automation-toolbox.pkrvars.hcl" \
  .

packer build \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  -var-file="automation-toolbox.pkrvars.hcl" \
  .
```

---

## What Happens During the Build

```
packer build .
      │
      ├─ [1] Create VM in Proxmox (ID 9002)
      ├─ [2] Download + checksum-verify Ubuntu 24.04 ISO from Canonical, attach + cidata ISO
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
| `homelab.pkrvars.hcl` | Proxmox host, storage pool, VM sizing |
| `automation-toolbox.pkrvars.hcl` | Image name, Ubuntu ISO url/checksum, CPU/RAM/disk overrides, VM ID |

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
   (`admin_username` in `automation-toolbox.pkrvars.hcl`,
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
4. Run the bootstrap script — it configures Semaphore (project, repository,
   Proxmox credentials, and ready-to-run job templates) via the API:
   ```bash
   sudo /git/monorepo/automation/packer/builds/ubuntu-2404-automation-toolbox/bootstrap-toolbox.sh
   ```
   You'll be prompted for the Semaphore admin password and your Proxmox API
   details (an API token is recommended — the script header explains how to
   create one). Credentials are stored encrypted in Semaphore, never on disk.
5. Open `http://<vm-ip>/`, log in as `admin`, and provision your first VM:
   **Task Templates → Provision VM (Proxmox) → Run** — fill in the survey
   (VM name + which template to clone) and watch the task output.
6. To stand up the standalone Vault server: provision a VM, note its IP, then
   run **Deploy Vault Server** and store the unseal keys it prints somewhere safe.

---

## Troubleshooting

**SSH timeout during build**
The autoinstall + first boot can take 20–30 min. The template allows 90 min. Check the Proxmox console — if the VM is at a boot menu, the cidata ISO may not have been attached correctly.

**`packer init` fails**
Ensure Packer ≥ 1.10.0 is installed and has internet access to download the Proxmox plugin from GitHub.

**Ubuntu ISO download fails or times out**
The build host (or Proxmox itself, since `iso_download_pve = true`) needs internet access to `releases.ubuntu.com`. Check `ubuntu_iso_url` in `automation-toolbox.pkrvars.hcl` is still current -- Canonical periodically retires old point-release files.

**`cidata_iso_file` not found**
Upload `cidata/ubuntu-2404-cidata.iso` (pre-built, already in this repo) to Proxmox before running the build. The path must match `cidata_iso_file` in `variables.pkr.hcl`.

**Duplicate variable errors**
Each build directory has its own `variables.pkr.hcl`. Do not run `packer build .` from the `builds/` parent directory — always run from inside the specific template folder.

**VM already exists (ID conflict)**
Change `proxmox_vm_id` in `automation-toolbox.pkrvars.hcl` to a free ID in your cluster.

---

## Roadmap

Planned additions to the toolbox workflow, in build order:

1. ✅ **Post-clone bootstrap** — `bootstrap-toolbox.sh` configures Semaphore (project, repo, Proxmox credentials, job templates) via the API.
2. ✅ **VM provisioning** — `automation/ansible/playbooks/provision-vm.yml` + the "Provision VM (Proxmox)" job template with survey variables.
3. ✅ **Vault server deployment** — `automation/ansible/playbooks/deploy-vault.yml` + the "Deploy Vault Server" job template. Next: move playbook secrets to `community.hashi_vault` lookups.
4. **NetBox + Proxbox** — inventory/CMDB; every provisioned VM registers automatically; becomes Ansible dynamic inventory.
5. **Prometheus + Grafana** — every new VM auto-enrolls via the `monitoring-agent` role.
6. **Portainer** — server + Agent rollout to Docker hosts via the `common` role.
