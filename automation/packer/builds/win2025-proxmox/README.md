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
| Packer ≥ 1.10 | The only build-machine requirement — provisioning runs in-guest via WinRM |
| Windows Server 2025 ISO | The wrapper walks you through it: **pick an ISO already on Proxmox storage, or upload one from a local folder** (no auto-download — Microsoft licensing; eval ISOs from the [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/)). Scripted runs set `win_iso_file` directly. **Strongly recommended:** run the ISO through `../../scripts/make-windows-noprompt-iso.sh` once — it removes the "Press any key to boot from CD" pause (using the no-prompt loaders Microsoft ships inside every ISO), making builds fully deterministic |
| virtio-win drivers ISO | **Staged automatically** by the wrapper from the stable upstream URL; or upload manually and set `virtio_iso_file` |

The build is fully unattended — no custom "no-prompt" ISO is required. Disk-first
boot order means the post-install reboot boots Windows directly and never hits the
"Press any key" DVD prompt. (`scripts/make-windows-noprompt-iso.sh` remains available
as optional belt-and-braces if a specific ISO ever misbehaves.)
| WinRM password | Whatever you set as `winrm_password` **is** the build account's password — it's injected into the unattended install at build time. Default `PackerBuild2025!`; the account is removed when the image is sealed |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `win_vm_id` | see file | Build VM / template ID |
| `image_name` | `t-win2025` | Template name prefix (timestamp appended) |
| `win_iso_file` | `local:iso/windows-server-2025.iso` | Windows ISO volid |
| `virtio_iso_file` | `local:iso/virtio-win.iso` | VirtIO drivers ISO volid |
| `winrm_username` / `winrm_password` | `packer` / — | Build account (must match autounattend.xml) |

## After the build

The template appears as `t-win2025-<timestamp>`. Provision Windows servers from it via **Semaphore → Provision VM (Proxmox)**. First planned consumer: the AD DS domain controller (see the toolbox roadmap).
