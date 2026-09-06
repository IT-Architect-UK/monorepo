# Ubuntu 26.04 Golden Image — Proxmox

Builds a lean, hardened Ubuntu 26.04 LTS template on Proxmox VE — the standard base image that new servers and services are cloned from (Vault, NetBox, application servers, etc.). Unlike the [automation toolbox](../ubuntu-2404-automation-toolbox/README.md), this is a true golden image: minimal, sealed, meant to be stamped out repeatedly.

## What's in the image

Fully patched Ubuntu 26.04, qemu-guest-agent, cloud-init (re-armed at seal time so every clone gets a unique identity/hostname/IP), the `server-baseline` Ansible hardening (SSH policy, firewall baseline, NTP/DNS, standard packages), and nothing else.

## Three ways to build it

| Entry point | When to use |
|-------------|-------------|
| **Semaphore** — Task Templates → *Build Golden Image — Ubuntu 26.04* | Normal operation: the Deployment Toolbox builds and refreshes templates (add a Schedule for monthly patched rebuilds) |
| **`./build-ubuntu-2604-proxmox.sh`** | Standalone on any Linux/macOS machine — prompts for anything missing |
| **`.\build-ubuntu-2604-proxmox.ps1`** | Standalone on Windows — same contract as the Linux wrapper |
| **`packer build .`** | Fully manual on any OS — see the header of `ubuntu-2604-proxmox.pkr.hcl` |

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | The only requirement for a raw `packer build .` — the Ansible baseline runs inside the build VM, so no Ansible on the build machine |
| xorriso | Checked for by `build-ubuntu-2604-proxmox.sh` — Packer needs it to build the cidata CD from `http/user-data` + `meta-data` |
| curl, jq | Needed by `../../scripts/fetch-ubuntu-iso.sh` (automatic ISO staging) and `remove-vm-if-exists.sh` (clears VM ID 9006 before a rebuild), both called by the `.sh` wrapper |
| Proxmox API access | Password, or API token (`user@realm!tokenid` + secret) — token recommended |
| Ubuntu 26.04 live-server ISO | **Staged automatically** — the wrappers find the latest release and have Proxmox download it server-side (checksum-verified), prompting for the target storage. Pin a specific ISO via `ubuntu_iso_file` if preferred. Standalone staging: `../../scripts/fetch-ubuntu-iso.sh 26.04` |

**Known issue:** `build-ubuntu-2604-proxmox.ps1` contains a stray form-feed byte in the path it uses to call `..\..\scripts\fetch-ubuntu-iso.ps1` (line 57), so automatic ISO staging fails on Windows. Set `$env:PKR_VAR_ubuntu_iso_file` to a pre-uploaded ISO volid before running it, or use the `.sh` wrapper.

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `proxmox_vm_id` | `9006` | Build VM / template ID |
| `image_name` | `t-ubuntu-2604` | Template name prefix (timestamp appended) |
| `ubuntu_iso_file` | — | volid of the uploaded ISO (**required**) |
| `vm_cpu_count` / `vm_memory_mb` / `vm_disk_gb` | 2 / 2048 / 20 | Build-time sizing — clones resize at provision time |
| `proxmox_url` / `proxmox_node` / storage / VLAN | homelab defaults | Site settings — override per environment |

## After the build

The template appears as `t-ubuntu-2604-<timestamp>`. Provision servers from it with the toolbox: **Semaphore → Provision VM (Proxmox) → Run**, entering the template name in the survey. Old timestamped templates can be deleted once nothing references them.
