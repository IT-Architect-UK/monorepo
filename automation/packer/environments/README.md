# Packer Environments — Variable Files

Variable files (`.pkrvars.hcl`) separate your infrastructure-specific values from the template logic. You never need to edit a `.pkr.hcl` template file to adapt a build to your environment — change the var file instead.

## How Variable Files Work

```bash
# Single var file
packer build \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  .

# Two var files — base environment + template-specific overrides
# (template-specific files live alongside their template, not here)
packer build \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  -var-file="automation-toolbox.pkrvars.hcl" \
  .
```

When two files are supplied, later values override earlier ones. Put your environment (Proxmox URL, storage names) in the first file, and template-specific overrides (VM size, image name) in the second.

Two things to know before passing `homelab.pkrvars.hcl` to a template by hand:

- It sets `proxmox_vm_id = 106` and `image_name = "ubuntu-2604-homelab"`, which override every Proxmox template's own VM ID and name. Only the toolbox puts its values back (its own var file is applied second). The build wrappers avoid this by not using var files at all — they read the site-general keys out of the file and pass them as `PKR_VAR_*` environment variables, leaving VM ID, name and sizing to the template. Building manually, add `-var proxmox_vm_id=…` after the var file.
- It covers every hypervisor, so it sets variables a given template does not use. The Proxmox templates declare those (`vsphere_*`, `win_iso_file`, …) with `default = null` purely to keep `packer validate` quiet; the cloud templates do not, and print an "undeclared variable" warning for each.

## Files in This Directory

Only files shared across more than one template live here. A template-specific override file (used by exactly one template) lives in that template's own `builds/<template-name>/` directory instead — currently just `builds/ubuntu-2404-automation-toolbox/automation-toolbox.pkrvars.hcl`.

| File | Purpose |
|---|---|
| `homelab.pkrvars.hcl` | Home lab environment — Proxmox API, node, storage pools, bridge/VLAN, TLS skip, pre-uploaded ISO paths, vSphere placement, sizing (2 / 2048 / 20) |
| `win2025.pkrvars.hcl` | Windows Server 2025 — `t-win2025` name, 4 vCPU / 4096 MB / 60 GB, `win_vm_id = 9003`. Use after `homelab.pkrvars.hcl` |
| `production.pkrvars.hcl` | Cloud production values — AWS `t3.small`, Azure `Standard_B2s`, GCP `e2-small`, `rg-golden-images`, 30 GB disk |

## Setting Up Your Own Environment

Copy `homelab.pkrvars.hcl` and edit it:

```bash
cp homelab.pkrvars.hcl mylab.pkrvars.hcl
```

You only need to set the values that differ from the defaults in the template's `variables.pkr.hcl`. Anything not in your var file uses the default.

## Variable Reference

There is no shared variables file: each `builds/<template>/variables.pkr.hcl` declares the set that template uses, so a name only exists for the templates listed against it. Sensitive values (passwords, tokens) must **always** be set as environment variables — never put them in a var file.

Template abbreviations: **TB** = ubuntu-2404-automation-toolbox, **U24** = ubuntu-2404-proxmox, **U26** = ubuntu-2604-proxmox, **VMW** = ubuntu-2604-vmware, **W-P** = win2025-proxmox, **W-V** = win2025-vmware.

### Proxmox connection

| Variable | Default | Templates | Description |
|---|---|---|---|
| `proxmox_url` | `https://192.168.1.10:8006/api2/json` | TB, U24, U26, W-P | Proxmox API endpoint |
| `proxmox_node` | `pve` | TB, U24, U26, W-P | Node to build on |
| `proxmox_username` | `root@pam` | TB, U24, U26, W-P | API user, or `user@realm!tokenid` for token auth |
| `proxmox_password` | — | TB, U24, U26, W-P | **`PKR_VAR_proxmox_password`** |
| `proxmox_token` | _(empty)_ | U24, U26, W-P | **`PKR_VAR_proxmox_token`** — API token secret; leave empty to use the password. Not supported by TB |
| `proxmox_skip_tls_verify` | `false` | TB, U24, U26, W-P | Skip the API certificate check. `true` only for a self-signed host (the home-lab file sets it); better: trust the Proxmox CA on the build machine |

### Proxmox storage and network

| Variable | Default | Templates | Description |
|---|---|---|---|
| `proxmox_storage_pool` | `local-lvm` | TB, U24, U26, W-P | Where the template disk (and EFI/TPM/cloud-init disks) go |
| `proxmox_iso_storage` | `local` | TB, U24, U26, W-P | ISO storage — also where the generated cidata / autounattend CD is staged |
| `proxmox_network_bridge` | `VLANs` (TB, U24, U26) / `vmbr0` (W-P) | TB, U24, U26, W-P | Bridge for the build VM's NIC |
| `proxmox_vlan_tag` | `"4"` (TB, U24, U26) / `""` = untagged (W-P) | TB, U24, U26, W-P | VLAN tag on that NIC |

### ISO sources

| Variable | Default | Templates | Description |
|---|---|---|---|
| `ubuntu_iso_file` | _(empty)_ | U24, U26 | volid of a pre-uploaded ISO, e.g. `NFS:iso/ubuntu-26.04-live-server-amd64.iso`. The wrappers stage one automatically if unset |
| `ubuntu_iso_url` / `ubuntu_iso_checksum` | _(empty)_ (TB) / pinned 26.04 URL + sha256 (VMW) | TB, VMW | Direct download + checksum. TB sets both in `automation-toolbox.pkrvars.hcl` and has Proxmox fetch the file server-side |
| `cidata_iso_file` | `NFS-10GB-PROXMOX-1:iso/ubuntu-2404-cidata.iso` | TB | Pre-built cloud-init seed ISO (see `builds/ubuntu-2404-automation-toolbox/cidata/`). U24, U26 and VMW generate theirs at build time from `http/user-data` + `meta-data` via `cd_files` |
| `win_iso_file` | `local:iso/windows-server-2025.iso` | W-P | Windows Server 2025 ISO volid. W-V hardcodes `[<datastore>] ISO/windows-server-2025.iso` instead |
| `virtio_iso_file` | `local:iso/virtio-win.iso` | W-P | virtio-win drivers ISO volid |

### VM sizing

Defaults differ per template; `homelab.pkrvars.hcl` (2 / 2048 / 20) overrides all of them, so pass a per-template file or `-var` after it.

| Template | `vm_cpu_count` | `vm_memory_mb` | `vm_disk_gb` | VM ID variable |
|---|---|---|---|---|
| TB | 4 | 8192 | 60 (80 via `automation-toolbox.pkrvars.hcl`) | `proxmox_vm_id` = **9002** |
| U24 | 2 | 2048 | 20 | `proxmox_vm_id` = **9004** |
| U26 | 2 | 2048 | 20 | `proxmox_vm_id` = **9006** |
| VMW | 2 | 2048 | 20 | — |
| W-P | 2 | 4096 | 50 (4 / 4096 / 60 via `win2025.pkrvars.hcl`) | `win_vm_id` = **9003** |
| W-V | 2 | 4096 | 50 | — |
| Azure, GCP | — | — | 20 (`os_disk_size_gb` / `disk_size`) | — |

`homelab.pkrvars.hcl` sets `proxmox_vm_id = 106` — see the note above.

### Image

| Variable | Default | Templates | Description |
|---|---|---|---|
| `image_name` | `t-ubuntu-2604` (U26, VMW, AWS, Azure, GCP) / `t-ubuntu-2404` (U24) / `t-win2025` (W-P, W-V) / `ubuntu-2404-automation-toolbox` (TB, overridden to `T-UBUNTU-24-DEPLOY`) | all | Base name. A `YYYYMMDD-HHmm` timestamp is appended everywhere except TB, which rebuilds in place under a fixed name |
| `image_description` | _(set per template)_ | all except Azure, W-V | Stored in the template / image metadata |
| `vm_company_name` | `IT-Architect` | all Ubuntu templates | Passed to `provision.sh` as `COMPANY_NAME` for MOTD, banner and prompt |

### Build access

| Variable | Default | Templates | Description |
|---|---|---|---|
| `ssh_username` | `packer` | TB, U24, U26, VMW | Temporary build user created by `http/user-data`. AWS uses `ubuntu`; Azure and GCP use `packer` (hardcoded) |
| `ssh_password` | `packer-temp-password` (TB, U24, U26) / _(empty)_ (VMW) | TB, U24, U26, VMW | Must match the hash in `http/user-data`. Only VMW requires **`PKR_VAR_ssh_password`**; an empty value means SSH never authenticates and the build times out |
| `winrm_username` | `packer` | W-P, W-V | WinRM user (must match `autounattend.xml`) |
| `winrm_password` | — | W-P, W-V | **`PKR_VAR_winrm_password`**, 12+ characters, validated. Injected into `autounattend.xml`; also the built-in Administrator's password until first boot |
| `keep_administrator` | `false` | W-P, W-V | `true` leaves the built-in Administrator enabled with `winrm_password`; `false` schedules it to be disabled on the clone's first boot |
| `admin_username` | _(empty)_ | TB | Personal admin login (set to `it-admin` in `automation-toolbox.pkrvars.hcl`) |
| `admin_password` | _(empty)_ | TB | **`PKR_VAR_admin_password`** — optional; unset means SSH key only |
| `admin_ssh_public_key` | _(empty)_ | TB | Public key installed for `admin_username` only |
| `semaphore_admin_password` | — | TB | **`PKR_VAR_semaphore_admin_password`** — Semaphore UI initial admin password |

### Windows hardware

| Variable | Default | Templates | Description |
|---|---|---|---|
| `windows_image_index` | `"2"` | W-P | `install.wim` index to install (2 = Standard, Desktop Experience). W-V selects by edition name inside its own `autounattend.xml` instead |
| `win_cpu_type` | `x86-64-v2-AES` | W-P | vCPU model. WS2025 needs POPCNT + SSE4.2, which the Proxmox default `kvm64` lacks; `host` also works |

### VMware vSphere

| Variable | Default | Templates | Description |
|---|---|---|---|
| `vsphere_server` | `vcenter.lab.local` | VMW, W-V | vCenter hostname or IP |
| `vsphere_username` | `administrator@vsphere.local` | VMW, W-V | vCenter user |
| `vsphere_password` | — | VMW, W-V | **`PKR_VAR_vsphere_password`** |
| `vsphere_datacenter` | `Datacenter` | VMW, W-V | Placement |
| `vsphere_cluster` | `Cluster01` | VMW, W-V | Placement |
| `vsphere_datastore` | `datastore1` | VMW, W-V | Disk placement (W-V also reads its ISO from here) |
| `vsphere_network` | `VM Network` | VMW, W-V | Port group for the vmxnet3 NIC |
| `vsphere_folder` | `Templates` | VMW, W-V | vCenter folder for the template |

### Cloud (AWS / Azure / GCP)

| Variable | Default | Templates | Description |
|---|---|---|---|
| `aws_region` | `eu-west-2` | AWS | Region |
| `aws_instance_type` | `t3.micro` | AWS | Build instance type |
| `aws_vpc_id` | _(empty)_ | AWS | Build in this VPC; empty = default VPC |
| `azure_subscription_id` | — | Azure | **`PKR_VAR_azure_subscription_id`** |
| `azure_resource_group` | `rg-packer-images` | Azure | Resource group that receives the managed image |
| `azure_location` | `uksouth` | Azure | Region |
| `azure_vm_size` | `Standard_B1s` | Azure | Build VM size |
| `gcp_project_id` | _(empty)_ | GCP | Project ID (**required**) |
| `gcp_zone` | `europe-west2-a` | GCP | Zone |
| `gcp_machine_type` | `e2-micro` | GCP | Build machine type |

## Credential Security

- **Never commit passwords to git.** Use environment variables for all sensitive values.
- The `sensitive = true` flag in each `variables.pkr.hcl` masks values in Packer logs.
- For team use, store secrets in a vault (HashiCorp Vault, AWS Secrets Manager, GitHub Secrets) and inject them as env vars at build time.

```bash
# Minimal required env vars for an Ubuntu Proxmox golden build
export PKR_VAR_proxmox_password="..."        # or PKR_VAR_proxmox_username + PKR_VAR_proxmox_token

# Windows Server 2025 (either hypervisor)
export PKR_VAR_winrm_password="..."          # 12+ characters

# automation-toolbox (Semaphore UI)
export PKR_VAR_semaphore_admin_password="..."
```
