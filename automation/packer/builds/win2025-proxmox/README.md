# Windows Server 2025 Golden Image — Proxmox

Builds a sysprep-sealed Windows Server 2025 template on Proxmox VE — the base image for Windows workloads (AD DS domain controllers, RDS, application servers). Unattended install via `autounattend.xml`, provisioning over WinRM, VirtIO drivers baked in.

## Three ways to build it

| Entry point | When to use |
|-------------|-------------|
| **Semaphore** — Task Templates → *Build Golden Image — Windows 2025* | Normal operation from the Deployment Toolbox (set `WINRM_PASSWORD` in the variable group) |
| **`./build-win2025-proxmox.sh`** | Standalone on any Linux/macOS machine — prompts for anything missing |
| **`.\build-win2025-proxmox.ps1`** | Standalone on Windows — same contract |
| **`packer build .`** | Fully manual on any OS — see the header of `win2025-proxmox.pkr.hcl` |

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | The only build-machine requirement — provisioning runs in-guest via WinRM |
| Windows Server 2025 ISO | The wrapper walks you through it: **pick an ISO already on Proxmox storage, or upload one from a local folder** (no auto-download — Microsoft licensing; eval ISOs from the [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/)). Scripted runs set `win_iso_file` directly |
| virtio-win drivers ISO | **Staged automatically** by the wrapper from the stable upstream URL; or upload manually and set `virtio_iso_file` |
| WinRM password | The `packer` account password in `../../http/win2025-proxmox/autounattend.xml` must match `winrm_password` — change the placeholder (`PackerBuild2025!`) in BOTH places for anything internet-adjacent |

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
