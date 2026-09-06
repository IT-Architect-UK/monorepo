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
| Dashboards | Homepage (status/launcher, :3002) · Portainer CE (container management, :9443) · Webmin (:10000) |

The build produces a Proxmox template (default VM ID: **9002**, name: **T-UBUNTU-24-DEPLOY**, set in `automation-toolbox.pkrvars.hcl`; no timestamp suffix, since the build rebuilds in place) as its output artefact -- clone it once to stand up the real toolbox server (see "After the Build" below). **POSLXPDEPLOY01** is the default name of that clone, as used by the build wrapper and the cleanup script.

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
# Optional: the LAN(s) every server built from the toolbox opens all ports to.
# Prompted for during the build if unset; stored in Semaphore, never in Git.
[System.Environment]::SetEnvironmentVariable("TRUSTED_SUBNETS",                   "192.168.4.0/24",              "User")
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
export PKR_VAR_semaphore_admin_password="your-semaphore-password"
export PKR_VAR_admin_password="your-admin-login-password"   # optional (SSH key only if unset)
# PKR_VAR_ssh_password is NOT needed — it defaults to the value whose hash is in http/user-data

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
      ├─ [1]  Create VM in Proxmox (ID 9002)
      ├─ [2]  Proxmox downloads + checksum-verifies the Ubuntu 24.04 ISO from Canonical; cidata ISO attached
      ├─ [3]  Boot VM — autoinstall reads cidata, installs Ubuntu unattended
      ├─ [4]  Wait for SSH (up to 90 min — install + first boot)
      │
      ├─ [5]  Upload helper scripts to /tmp/ (apply-branding, disable-cloud-init,
      │       disable-ipv6, setup-iptables, sync-monorepo — from infrastructure/)
      ├─ [6]  ../../scripts/provision.sh  (HYPERVISOR=proxmox, BUILD_PROFILE=toolbox)
      │         ├── apt update + upgrade, qemu-guest-agent, branding
      │         ├── iptables + iptables-persistent + fail2ban; setup-iptables.sh baseline ruleset
      │         ├── SSH and kernel hardening, timezone
      │         └── Clone this repo to /git/monorepo (sync-monorepo.sh cron)
      │
      ├─ [7]  ../../scripts/provision-automation-toolbox.sh  (ADMIN_* vars)
      │         ├── Ansible, Packer, Terraform
      │         ├── AWS CLI v2, Azure CLI, Google Cloud SDK
      │         ├── kubectl, Helm, Docker CE, GitHub CLI
      │         └── Python 3 + cloud SDKs; 'toolbox' service account + admin login
      │
      ├─ [8]  ../../scripts/provision-semaphore.sh  (SEMAPHORE_ADMIN_PASS)
      ├─ [9]  applications/webmin/install-webmin.sh
      ├─ [10] applications/homepage/install-homepage.sh
      ├─ [11] containers/portainer/install-portainer.sh
      ├─ [12] ../../scripts/write-toolbox-banner.sh   (web UI URLs in /etc/issue + MOTD)
      │
      ├─ [13] Upload automation/ansible → /opt/toolbox/ansible (for Semaphore's own use)
      ├─ [14] ../../scripts/verify-monorepo-sync.sh   (hard gate: /git/monorepo must exist)
      ├─ [15] ansible-playbook playbooks/server-baseline.yml
      │         └── Runs from /git/monorepo/automation/ansible against localhost
      │
      ├─ [16] scripts/collect-diagnostics.sh → downloaded to logs/build-diagnostics-<timestamp>.log
      │
      ├─ [17] ../../scripts/cleanup.sh
      │         ├── Remove SSH host keys and machine-id
      │         └── Clean logs and cloud-init cache (re-armed for clones)
      │
      └─ [18] Convert VM to Proxmox template → T-UBUNTU-24-DEPLOY
              (manifest written to packer-manifest-automation-toolbox.json)
```

During the build, watch progress in the **Proxmox console**:
Datacenter → `POSVMPWS01` → new VM → Console

---

## Customising the Build

The build layers two var files, and the second wins:

| File | Purpose |
|------|---------|
| `../../environments/homelab.pkrvars.hcl` | Site settings shared by every template — Proxmox host, node, storage pools, bridge/VLAN, TLS skip. Also sets a VM ID, image name and 2 / 2048 / 20 sizing that the next file overrides |
| `automation-toolbox.pkrvars.hcl` (this directory) | Image name `T-UBUNTU-24-DEPLOY`, Ubuntu ISO url/checksum, 80 GB disk, VM ID 9002, admin username and SSH public key |

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
   SSH access policy: `it-admin` accepts the SSH key from the pkrvars file
   **and** the password set at build time (`PKR_VAR_admin_password`). All
   other accounts (`root`, `packer`, `toolbox`) are key-only or no-login —
   they are not meant for interactive use.
3. Verify tools:
   ```bash
   ansible --version
   terraform --version
   packer --version
   docker --version
   ```
(Manual path — only needed if you answered "n" to automatic deployment.)
The build script normally does all of this itself: clone → start → bootstrap,
using the answers you gave up-front. To do it by hand instead, clone the
template in Proxmox, then on the VM run:
```bash
sudo /git/monorepo/automation/packer/builds/ubuntu-2404-automation-toolbox/scripts/bootstrap-toolbox.sh
```
The bootstrap configures Semaphore (project, repository, encrypted Proxmox
credentials, ready-to-run job templates), finalises the Homepage dashboard,
verifies password SSH for your admin account, and offers the firewall
lockdown. Credentials go into Semaphore's encrypted store, never to disk.

Either way, when it finishes: open `http://<vm-ip>/`, log in as `admin`, and
provision your first VM — **Task Templates → Provision VM (Proxmox) → Run**.
For the standalone Vault server: provision a VM, note its IP, run **Deploy
Vault Server**, and store the unseal keys it prints somewhere safe.

---

## Rebuild / Test Cycle

Testing a change end-to-end means: delete the old template and test clone, rebuild, re-clone, re-bootstrap. The cleanup step is scripted:

```powershell
.\cleanup-automation-toolbox-proxmox.ps1        # deletes template 9002, any VM named POSLXPDEPLOY01 AND golden templates 9003/9004/9006 (asks first)
.\build-automation-toolbox-proxmox.ps1          # build → clone → bootstrap, one command end-to-end
```

Note the default scope: with no switches the cleanup script also deletes the **golden image templates** at VM IDs 9003, 9004 and 9006 (only if the VM at that ID is actually a template). Add `-KeepGolden` to leave them alone. It also purges local build artefacts (manifest, `packer_cache/`, `.tmp/`, `logs/`).

| Parameter | Default | Effect |
|-----------|---------|--------|
| `-TemplateId` | `9002` | VM ID of the toolbox template to delete |
| `-CloneName` | `POSLXPDEPLOY01` | Name of the cloned toolbox VM to delete |
| `-GoldenIds` | `9003,9004,9006` | Golden template IDs to delete |
| `-ProxmoxUrl` / `-Node` | from `../../environments/homelab.pkrvars.hcl` | API host and node; prompted if the site file has no value |
| `-ProxmoxUser` | `root@pam` | API user (password from `PKR_VAR_proxmox_password`, prompted if unset) |
| `-TemplateOnly` | off | Only the toolbox template |
| `-CloneOnly` | off | Only the cloned VM |
| `-GoldenOnly` | off | Only the golden templates |
| `-KeepGolden` | off | Toolbox template + clone, golden templates untouched |
| `-Force` | off | Skip the `yes` confirmation |

All questions (VM name, Proxmox API token, firewall subnet, VM sizing —
default 4 vCPU / 8 GB, increase offered) are asked up-front. The web-UI
admin password (shared by Semaphore and Portainer) must be 12+ characters;
pressing Enter accepts the default `Change-Me-Toolbox!` — change it
after first login in both UIs. Everything is asked up-front,
so the run is hands-off after that — a fully bootstrapped toolbox comes out the
other end with its URLs printed at the finish.

Use `-CloneName <name>` if your test clone uses a different name.

---

## Troubleshooting

**Every build produces a health report automatically** — check `logs/build-diagnostics-<timestamp>.log` next to your build log before anything else.

To re-run the same health check later on the running server:

```bash
sudo /git/monorepo/automation/packer/builds/ubuntu-2404-automation-toolbox/scripts/collect-diagnostics.sh
```

One command produces a complete health report (services, Homepage, SSH policy, firewall, tooling versions, bootstrap state, recent errors) in `/var/log/toolbox-diagnostics/`. Secrets are redacted — the file is safe to share when asking for help.


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

Priority order for the platform (this build is stage 1):

1. ✅ **Deployment Toolbox** — Semaphore, Homepage, Portainer, Webmin; single-command build → clone → bootstrap; pre-flight health dashboard.
2. ✅ **Golden images** — Ubuntu 24.04 pipeline proven end-to-end (lean baseline, group_vars flavour toggles); Ubuntu 26.04 and Windows 2025 built from the same pattern, first live validation pending.
3. **Vault** — standalone secrets server, provisioned BY the toolbox (`Deploy Vault Server` job); Semaphore/Ansible secrets migrate to it.
4. **PKI** — offline root CA + Vault PKI issuing CA; issue certificates for every site and service and retrofit TLS across the estate (toolbox UIs included — removes the self-signed workarounds). Let's Encrypt stays for public-facing certs. The AD CS issuing CA joins under the same root when AD DS arrives.
5. **Additional infrastructure services** — backups (Proxmox Backup Server), monitoring (Prometheus + Grafana with certificate-expiry alerting), AD DS (+ GPO certificate auto-enrolment), NetBox inventory, and whatever the lab needs next — each deployed as a toolbox workload.

