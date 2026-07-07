# Ubuntu 26.04 Golden Image — Proxmox

Builds a lean, hardened Ubuntu 26.04 LTS template on Proxmox VE — the standard base image that new servers and services are cloned from (Vault, NetBox, application servers, etc.). Unlike the [automation toolbox](../ubuntu-2604-automation-toolbox/README.md), this is a true golden image: minimal, sealed, meant to be stamped out repeatedly.

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
| Packer ≥ 1.10 | The **only** build-machine requirement, on any OS — the Ansible baseline runs inside the build VM |
| Proxmox API access | Password, or API token (`user@realm!tokenid` + secret) — token recommended |
| Ubuntu 26.04 live-server ISO | **Staged automatically** — the wrappers find the latest release and have Proxmox download it server-side (checksum-verified), prompting for the target storage. Pin a specific ISO via `ubuntu_iso_file` if preferred. Standalone staging: `../../scripts/fetch-ubuntu-iso.sh 26.04` |

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
