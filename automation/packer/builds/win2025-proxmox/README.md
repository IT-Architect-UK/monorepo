# Windows Server 2025 Golden Image — Proxmox

Builds a sysprep-sealed Windows Server 2025 template on Proxmox VE — the base image for Windows workloads (AD DS domain controllers, RDS, application servers). Unattended install via `autounattend.xml`, provisioning over WinRM, VirtIO drivers baked in.

## Three ways to build it

| Entry point | When to use |
|-------------|-------------|
| **Semaphore** — Task Templates → *Build Golden Image — Windows 2025* | Normal operation from the Deployment Toolbox (`WINRM_PASSWORD` is stored by the bootstrap; add it to the Proxmox variable group manually only if you skipped that prompt) |
| **`./build-win2025-proxmox.sh`** | Standalone on any Linux/macOS machine — prompts for anything missing |
| **`.\build-win2025-proxmox.ps1`** | Standalone on Windows — same contract |
| **`packer build .`** | Fully manual on any OS — see the header of `win2025-proxmox.pkr.hcl` |

## Which Windows edition gets installed

`windows_image_index` (default **2** = Standard, Desktop Experience) selects
the edition by index — unambiguous, unlike edition-name matching (which will
silently stall Setup and leave an empty disk if it's off by a word, e.g.
"Evaluation" vs retail). List your ISO's editions on the Proxmox host:

```bash
apt-get install -y wimtools
mount -o loop <your.iso> /mnt/w
wiminfo /mnt/w/sources/install.wim   # or install.esd
umount /mnt/w
```

Typical Windows Server 2025 layout: 1=Standard Core, 2=Standard Desktop,
3=Datacenter Core, 4=Datacenter Desktop. Override via
`PKR_VAR_windows_image_index` (Semaphore variable group) or `-var`.

## Virtual hardware

**q35** machine, **`x86-64-v2-AES` CPU** (WS2025/Win11-24H2 require POPCNT +
SSE4.2 — the default `kvm64` vCPU lacks them and WinPE bugchecks), **TPM
2.0**, UEFI/Secure Boot. The build itself uses a
**SATA disk + e1000 NIC** — both have in-box Windows drivers, so WinPE sees
the disk and Setup completes reliably with no driver injection. The full
**VirtIO** driver set is then installed by `provision-windows.ps1`
(virtio-win-guest-tools), so the sealed template's OS can boot from VirtIO —
**clones may be switched to VirtIO SCSI + VirtIO NIC** (faster) and will work
because the drivers are already present. Building directly on VirtIO hardware
needs reliable WinPE driver injection and is a separate exercise, off the
critical path to a working template.

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | The only requirement for a raw `packer build .` — provisioning runs in-guest via WinRM |
| xorriso | Checked for by `build-win2025-proxmox.sh` — Packer needs it to build the autounattend CD |
| curl, jq | Needed by the host-side helpers the `.sh` wrapper calls: `select-or-upload-iso.sh`, `fetch-ubuntu-iso.sh` (URL mode, for virtio-win) and `remove-vm-if-exists.sh` (clears VM ID 9003 before a rebuild) |
| Windows Server 2025 ISO | The wrapper walks you through it: **pick an ISO already on Proxmox storage, or upload one from a local folder** (no auto-download — Microsoft licensing; eval ISOs from the [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/)). Scripted runs set `win_iso_file` directly. A stock ISO works as-is — see the note below |
| virtio-win drivers ISO | **Staged automatically** by the wrapper from the stable upstream URL; or upload manually and set `virtio_iso_file` |
| WinRM password | `PKR_VAR_winrm_password` (12+ characters) **is** the build account's password — it's injected into `autounattend.xml` at build time and is also the built-in Administrator's password until first boot. No default: the wrappers generate a random one if you set nothing. `cleanup-windows.ps1` cannot delete the account it is running as, so it schedules `net user packer /delete` via a `RunOnce` key — the account is removed on the **clone's first boot**, not when the image is sealed. Set `keep_administrator=true` to leave the built-in Administrator enabled with that password for troubleshooting; otherwise it is disabled on first boot the same way |

The build is fully unattended with a stock ISO — no custom "no-prompt" ISO is required. The template boots disk-first (`order=sata0;ide2;…`), so the post-install reboot boots Windows directly and never reaches the "Press any key" DVD prompt; the first boot, with an empty disk, falls through to the DVD and a repeated `<enter>` in `boot_command` catches that one prompt. `../../scripts/make-windows-noprompt-iso.sh` remains available as optional belt-and-braces if a specific ISO ever misbehaves.

## What the build installs

| Step | Script | What it does |
|------|--------|--------------|
| 1 | `provision-windows.ps1` | Baseline hardening, RDP, OpenSSH, VirtIO drivers + QEMU Guest Agent (from the virtio-win ISO), en-GB / UTC, automatic updates off |
| 2 | `install-cloudbase-init.ps1` | Installs **Cloudbase-Init** (Windows cloud-init) configured for Proxmox's ConfigDrive2, and stages its `Unattend.xml` for sysprep — this is how a clone gets its hostname, network, admin user/password and SSH keys from the Proxmox cloud-init drive on first boot |
| 3 | `cleanup-windows.ps1` | Removes the build-only WinRM rule, clears logs/temp/pagefile, schedules the `packer` account removal and Administrator disable via `RunOnce`, zero-fills free space, runs sysprep `/generalize` |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `win_vm_id` | `9003` | Build VM / template ID |
| `image_name` | `t-win2025` | Template name prefix (timestamp appended) |
| `win_iso_file` | `local:iso/windows-server-2025.iso` | Windows ISO volid |
| `virtio_iso_file` | `local:iso/virtio-win.iso` | VirtIO drivers ISO volid |
| `winrm_username` / `winrm_password` | `packer` / — | Build account (injected into autounattend.xml; random if unset) |
| `keep_administrator` | `false` | Keep the built-in Administrator enabled (troubleshooting); default disables it on first boot |
| `windows_image_index` | `2` | Edition to install from `install.wim` (see above) |
| `win_cpu_type` | `x86-64-v2-AES` | vCPU model — the default `kvm64` cannot boot WS2025 |

## After the build

The template appears as `t-win2025-<timestamp>`. Provision Windows servers from it via **Semaphore → Provision VM (Proxmox)**. First planned consumer: the AD DS domain controller (see the toolbox roadmap).
