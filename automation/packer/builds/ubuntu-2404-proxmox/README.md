# Ubuntu 24.04 Golden Image — Proxmox

Builds a lean, hardened Ubuntu 24.04 LTS template on Proxmox VE — the standard base image that new servers and services are cloned from (Vault, NetBox, application servers, etc.). Unlike the [automation toolbox](../ubuntu-2404-automation-toolbox/README.md), this is a true golden image: minimal, sealed, meant to be stamped out repeatedly.

## What's in the image

**Lean by design:** fully patched Ubuntu 24.04, qemu-guest-agent, cloud-init (re-armed at seal so every clone gets a unique identity), SSH and kernel hardening, iptables baseline + fail2ban, NTP, and the standard package set — nothing opinionated.

**Make it yours:** site flavour is controlled by toggles in `automation/ansible/inventory/group_vars/all.yml`, applied by the in-guest Ansible baseline at build time — so different users cut different golden images from the same code:

| Toggle | Default | Adds |
|--------|---------|------|
| `baseline_firewall` / `baseline_fail2ban` | on | drop either if you manage them elsewhere |
| `baseline_branding` | off | login banner / MOTD / prompt branding |
| `baseline_disable_ipv6` | off | IPv6 disabled system-wide |
| `baseline_monorepo_clone` | off | this repo cloned to `/git/monorepo` on every image |
| `baseline_create_admin` | off | a fixed admin account baked in (normally logins arrive per-clone via cloud-init) |
| `common_packages`, `system_timezone`, `ntp_servers` | see file | package list, timezone, NTP sources |

Applications (Webmin, monitoring agents, Docker, …) deliberately never go into golden images — deploy them post-provision with the playbooks in `automation/ansible/playbooks/` and `applications/`.

## Three ways to build it

| Entry point | When to use |
|-------------|-------------|
| **Semaphore** — Task Templates → *Build Golden Image — Ubuntu 24.04* | Normal operation: the Deployment Toolbox builds and refreshes templates (add a Schedule for monthly patched rebuilds) |
| **`./build-ubuntu-2404-proxmox.sh`** | Standalone on any Linux/macOS machine — prompts for anything missing |
| **`.\build-ubuntu-2404-proxmox.ps1`** | Standalone on Windows — same contract as the Linux wrapper |
| **`packer build .`** | Fully manual on any OS — see the header of `ubuntu-2404-proxmox.pkr.hcl` |

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | The **only** build-machine requirement, on any OS — the Ansible baseline runs inside the build VM |
| Proxmox API access | Password, or API token (`user@realm!tokenid` + secret) — token recommended |
| Ubuntu 24.04 live-server ISO | **Staged automatically** — the wrappers find the latest release and have Proxmox download it server-side (checksum-verified), prompting for the target storage. Pin a specific ISO via `ubuntu_iso_file` if preferred. Standalone staging: `../../scripts/fetch-ubuntu-iso.sh 24.04` |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `proxmox_vm_id` | `9004` | Build VM / template ID |
| `image_name` | `t-ubuntu-2404` | Template name prefix (timestamp appended) |
| `ubuntu_iso_file` | — | volid of the uploaded ISO (**required**) |
| `vm_cpu_count` / `vm_memory_mb` / `vm_disk_gb` | 2 / 2048 / 20 | Build-time sizing — clones resize at provision time |
| `proxmox_url` / `proxmox_node` / storage / VLAN | homelab defaults | Site settings — override per environment |

## After the build

The template appears as `t-ubuntu-2404-<timestamp>`. Provision servers from it with the toolbox: **Semaphore → Provision VM (Proxmox) → Run**, entering the template name in the survey.

**Logins:** the sealed template has no interactive accounts by design — each clone gets its identity on first boot via cloud-init: hostname from the VM name, plus the account/password/SSH key you enter in the provisioning survey. (During a build, the temporary `packer` account exists and is removed at seal.) Old timestamped templates can be deleted once nothing references them.
