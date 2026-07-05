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

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | The only build-machine requirement — provisioning runs in-guest via WinRM |
| Windows Server 2025 ISO | The wrapper walks you through it: **pick an ISO already on Proxmox storage, or upload one from a local folder** (no auto-download — Microsoft licensing; eval ISOs from the [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/)). Scripted runs set `win_iso_file` directly. **Strongly recommended:** run the ISO through `../../scripts/make-windows-noprompt-iso.sh` once — it removes the "Press any key to boot from CD" pause (using the no-prompt loaders Microsoft ships inside every ISO), making builds fully deterministic |
| virtio-win drivers ISO | **Staged automatically** by the wrapper from the stable upstream URL; or upload manually and set `virtio_iso_file` |
| WinRM password | Whatever you set as `winrm_password` **is** the build account's password — it's injected into the unattended install at build time. Default `PackerBuild2025!`; the account is removed when the image is sealed |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `win_vm_id` | see file | Build VM / template ID |
| `image_name` | `win2025-golden` | Template name prefix (timestamp appended) |
| `win_iso_file` | `local:iso/windows-server-2025.iso` | Windows ISO volid |
| `virtio_iso_file` | `local:iso/virtio-win.iso` | VirtIO drivers ISO volid |
| `winrm_username` / `winrm_password` | `packer` / — | Build account (must match autounattend.xml) |

## After the build

The template appears as `win2025-golden-<timestamp>`. Provision Windows servers from it via **Semaphore → Provision VM (Proxmox)**. First planned consumer: the AD DS domain controller (see the toolbox roadmap).
