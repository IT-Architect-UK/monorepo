# Windows Server 2025 Golden Image — VMware vSphere

Builds a sysprep-sealed Windows Server 2025 template on vSphere with the `vsphere-iso` builder. Unattended install via `autounattend.xml`, provisioning over WinRM, converted to a template at the end (`convert_to_template = true`).

## How it works

1. Packer creates a VM: `windows2025srv64Guest` (fall back to `windows2022srvNext64Guest` on an older vCenter), EFI firmware, `pvscsi` disk controller, `vmxnet3` NIC — both have in-box Windows Server 2025 drivers, so no driver injection
2. Attaches the Windows ISO from the datastore and a generated `autounattend` CD; `boot_command` presses `<enter>` once after 4 s to dismiss "Press any key to boot from CD"
3. Waits for WinRM on port 5985 (up to 90 min), then runs the provisioners below
4. Sysprep shuts the VM down; Packer converts it to a template

| Step | Script | What it does |
|------|--------|--------------|
| 1 | `../../scripts/provision-windows.ps1` | Baseline hardening, RDP, OpenSSH, en-GB / UTC, automatic updates off (QEMU Guest Agent install is skipped on VMware) |
| 2 | inline | Downloads and silently installs **VMware Tools** from `packages.vmware.com` — non-fatal if the download fails (install manually after deploy) |
| 3 | `../../scripts/cleanup-windows.ps1` | Clears logs/temp/pagefile, schedules removal of the `packer` account and disabling of Administrator via `RunOnce` (first boot of the clone), zero-fills free space, runs sysprep |

There is **no Cloudbase-Init step** on this template (the Proxmox one has it), and **no build wrapper script** — run Packer directly.

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | Plugin `vsphere ~> 1.4` (`packer init .`) |
| xorriso (Linux) | Packer needs it to build the autounattend CD |
| Windows Server 2025 ISO | Upload to **`[<vsphere_datastore>] ISO/windows-server-2025.iso`** — the path is hardcoded in the template (only the datastore name is a variable). Eval ISOs from the [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/) |
| vCenter access | `PKR_VAR_vsphere_password`. `insecure_connection = true` is hardcoded, so vCenter's certificate is **not** verified |
| `PKR_VAR_winrm_password` | **Required, 12+ characters** (validated). Injected into `../../http/win2025-vmware/autounattend.xml` in place of `WINRM_PASSWORD_PLACEHOLDER`; also the built-in Administrator's password until first boot |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `vsphere_server` / `vsphere_username` / `vsphere_password` | `vcenter.lab.local` / `administrator@vsphere.local` / — | vCenter connection |
| `vsphere_datacenter` / `vsphere_cluster` / `vsphere_datastore` | `Datacenter` / `Cluster01` / `datastore1` | Placement; the ISO is read from `vsphere_datastore` |
| `vsphere_network` / `vsphere_folder` | `VM Network` / `Templates` | Port group and template folder |
| `winrm_username` / `winrm_password` | `packer` / — | Build account (must match `autounattend.xml`) |
| `keep_administrator` | `false` | `true` leaves the built-in Administrator enabled with `winrm_password` for troubleshooting |
| `vm_cpu_count` / `vm_memory_mb` / `vm_disk_gb` | 2 / 4096 / 50 | Build-time sizing (`environments/win2025.pkrvars.hcl` raises it to 4 / 4096 / 60) |
| `image_name` | `t-win2025` | Template name prefix (timestamp appended) |

The edition is selected **by name** inside `http/win2025-vmware/autounattend.xml` (`Windows Server 2025 Standard Evaluation (Desktop Experience)`); this template does not support `windows_image_index`. A retail ISO needs that name edited in the XML.

## Build

```bash
cd automation/packer/builds/win2025-vmware
export PKR_VAR_vsphere_password="..."
export PKR_VAR_winrm_password="<12+ chars, build-only>"
packer init .
packer build \
  -var-file="../../environments/homelab.pkrvars.hcl" \
  -var-file="../../environments/win2025.pkrvars.hcl" \
  .
```

## Output

A vSphere template `t-win2025-<YYYYMMDD-HHmm>` in `vsphere_folder`, plus `packer-manifest.json` in this directory. Clones complete the OOBE specialize pass on first boot; log in as Administrator with the build password only if you built with `keep_administrator=true`.
