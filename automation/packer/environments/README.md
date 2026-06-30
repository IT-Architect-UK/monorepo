# Packer Environments — Variable Files

Variable files (`.pkrvars.hcl`) separate your infrastructure-specific values from the template logic. You never need to edit a `.pkr.hcl` template file to adapt a build to your environment — change the var file instead.

## How Variable Files Work

```bash
# Single var file (most templates)
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  ubuntu-2604-proxmox.pkr.hcl

# Two var files — base environment + template-specific overrides
packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  -var-file="environments/automation-toolbox.pkrvars.hcl" \
  ubuntu-2604-automation-toolbox-proxmox.pkr.hcl
```

When two files are supplied, later values override earlier ones. Put your environment (Proxmox URL, storage names) in the first file, and template-specific overrides (VM size, image name) in the second.

## Files in This Directory

| File | Purpose |
|---|---|
| `homelab.pkrvars.hcl` | Home lab environment — Proxmox/VMware addresses, storage pools, ISO paths |
| `automation-toolbox.pkrvars.hcl` | Overrides for the automation toolbox image (larger VM, extra tools) |
| `ansible-server.pkrvars.hcl` | Overrides for the Ansible control node image |
| `win2025.pkrvars.hcl` | Windows Server 2025 specific values |
| `production.pkrvars.hcl` | Production environment values |

## Setting Up Your Own Environment

Copy `homelab.pkrvars.hcl` and edit it:

```bash
cp homelab.pkrvars.hcl mylab.pkrvars.hcl
```

You only need to set the values that differ from the defaults in `variables.pkr.hcl`. Anything not in your var file uses the default.

## Variable Reference

All variables are defined in `../variables.pkr.hcl`. Sensitive values (passwords) must **always** be set as environment variables — never put them in a var file.

### Connection

| Variable | Default | Description |
|---|---|---|
| `proxmox_url` | `https://192.168.1.10:8006/api2/json` | Proxmox API endpoint |
| `proxmox_username` | `root@pam` | Proxmox API user |
| `proxmox_password` | — | **Set via `PKR_VAR_proxmox_password` env var** |
| `proxmox_node` | `pve` | Proxmox node to build on |
| `vsphere_server` | `vcenter.lab.local` | vCenter hostname or IP |
| `vsphere_username` | `administrator@vsphere.local` | vCenter user |
| `vsphere_password` | — | **Set via `PKR_VAR_vsphere_password` env var** |

### Storage

| Variable | Default | Description |
|---|---|---|
| `proxmox_storage_pool` | `local-lvm` | Where the template disk is stored |
| `proxmox_iso_storage` | `local` | Where ISO files are stored |
| `ubuntu_iso_file` | _(empty)_ | Pre-uploaded Ubuntu ISO path (e.g. `NFS:iso/ubuntu-26.04-live-server-amd64.iso`) |
| `cidata_iso_file` | `NFS-10GB-PROXMOX-1:iso/ubuntu-2604-cidata.iso` | Pre-built cloud-init cidata ISO path |
| `win_iso_file` | `local:iso/windows-server-2025.iso` | Windows Server 2025 ISO path |
| `virtio_iso_file` | `local:iso/virtio-win.iso` | virtio-win drivers ISO path |

### VM Sizing

| Variable | Default | Description |
|---|---|---|
| `vm_cpu_count` | `2` | vCPUs for the build VM |
| `vm_memory_mb` | `2048` | RAM in MB |
| `vm_disk_gb` | `20` | Root disk size in GB |
| `proxmox_vm_id` | `9000` | Proxmox VM ID for the template |

### Image

| Variable | Default | Description |
|---|---|---|
| `image_name` | `ubuntu-2604-golden` | Base name — a timestamp is appended automatically |
| `image_description` | _(set per template)_ | Description stored in the template metadata |
| `vm_company_name` | `IT-Architect` | Used in MOTD, login banner, and shell prompt |

### SSH / Build Access

| Variable | Default | Description |
|---|---|---|
| `ssh_username` | `packer` | Temporary user created during the build |
| `ssh_password` | — | **Set via `PKR_VAR_ssh_password` env var** |

### Windows

| Variable | Default | Description |
|---|---|---|
| `winrm_username` | `packer` | WinRM user (must match `autounattend.xml`) |
| `winrm_password` | — | **Set via `PKR_VAR_winrm_password` env var** |
| `win_vm_id` | `9003` | Proxmox VM ID for the Windows template |

### Cloud (AWS / Azure / GCP)

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `eu-west-2` | AWS region |
| `aws_instance_type` | `t3.micro` | Build instance type |
| `azure_subscription_id` | — | **Set via `PKR_VAR_azure_subscription_id` env var** |
| `azure_resource_group` | `rg-packer-images` | Resource group for the managed image |
| `azure_location` | `uksouth` | Azure region |
| `gcp_project_id` | _(empty)_ | GCP project ID |
| `gcp_zone` | `europe-west2-a` | GCP zone |

### Other

| Variable | Default | Description |
|---|---|---|
| `semaphore_admin_password` | — | **Set via `PKR_VAR_semaphore_admin_password` env var** — Semaphore UI initial admin password |

## Credential Security

- **Never commit passwords to git.** Use environment variables for all sensitive values.
- The `sensitive = true` flag in `variables.pkr.hcl` masks values in Packer logs.
- For team use, store secrets in a vault (HashiCorp Vault, AWS Secrets Manager, GitHub Secrets) and inject them as env vars at build time.

```bash
# Minimal required env vars for a Proxmox build
export PKR_VAR_proxmox_password="..."
export PKR_VAR_ssh_password="..."

# For automation-toolbox / ansible-server
export PKR_VAR_semaphore_admin_password="..."
```
