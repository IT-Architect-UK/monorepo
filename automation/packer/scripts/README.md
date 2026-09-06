# scripts/ — Shared Packer scripts

Sixteen scripts in three groups. The in-guest provisioners are referenced from the `.pkr.hcl` templates by `abspath("${path.root}/../../scripts/…")`; the host-side helpers are called by the Proxmox build wrappers and can also be run standalone. Two more toolbox-specific scripts (`bootstrap-toolbox.sh`, `collect-diagnostics.sh`) live in `builds/ubuntu-2404-automation-toolbox/scripts/` because they run on the toolbox after it is cloned, not during the build.

## In-guest provisioners

Run inside the build VM by Packer's `shell` / `powershell` provisioners.

| Script | Used by | What it does |
|--------|---------|--------------|
| `provision.sh` | every Ubuntu template | Base OS setup: updates, iptables + fail2ban, guest agent for `HYPERVISOR`, branding, IPv6 off, iptables baseline, SSH and kernel hardening, timezone, monorepo sync cron to `/git/monorepo`. Helper scripts from `infrastructure/` are uploaded to `/tmp/` first |
| `provision-automation-toolbox.sh` | toolbox | Installs Ansible, Packer, Terraform, AWS/Azure/Google Cloud CLIs, kubectl, Helm, GitHub CLI, Docker CE, jq/yq; creates the `toolbox` service account and the optional `ADMIN_USERNAME` login |
| `provision-semaphore.sh` | toolbox | Installs Semaphore UI (.deb, BoltDB) behind nginx on port 80 with `SEMAPHORE_ADMIN_PASS` as the initial admin password |
| `write-toolbox-banner.sh` | toolbox | Appends the Semaphore / Webmin / Homepage / Portainer URLs to `/etc/issue` and a MOTD fragment, using agetty escapes so every clone shows its own address |
| `verify-monorepo-sync.sh` | toolbox | Pre-flight gate before the in-guest Ansible baseline: fails with a specific reason if the `/git/monorepo` clone or its cron job is missing |
| `cleanup.sh` | every Ubuntu template | Seals the image as the last step: re-arms cloud-init, removes SSH host keys, machine-id, DHCP leases, history and temp files |
| `provision-windows.ps1` | both Windows templates | Baseline hardening, RDP, OpenSSH, en-GB / UTC, automatic updates and Store updates off; installs VirtIO drivers + QEMU Guest Agent from the virtio-win ISO (skipped on VMware) |
| `install-cloudbase-init.ps1` | win2025-proxmox | Installs Cloudbase-Init configured for Proxmox ConfigDrive2 and stages its `Unattend.xml` for sysprep, so clones get hostname, network, user and SSH keys on first boot |
| `cleanup-windows.ps1` | both Windows templates | Seals the image: removes the build-only WinRM rule, clears logs/temp/pagefile, schedules `packer` account removal and Administrator disable via `RunOnce` (honours `KEEP_ADMINISTRATOR`), zero-fills free space, runs sysprep |

## Host-side Proxmox helpers

Run on the machine driving the build, against the Proxmox API. All take `PROXMOX_HOST` / `PROXMOX_USER` / `PROXMOX_TOKEN_ID` + `PROXMOX_TOKEN_SECRET` (or `PROXMOX_PASSWORD`) / `PROXMOX_NODE` from the environment, fall back to `environments/homelab.pkrvars.hcl` for the host and node, and prompt for anything still missing. The `.sh` versions need `bash`, `curl` and `jq`; the `.ps1` twins have the same contract on Windows.

| Script | What it does |
|--------|--------------|
| `fetch-ubuntu-iso.sh` / `.ps1` | Finds the newest live-server ISO for a release (`24.04`, `26.04`) and has **Proxmox itself** download and checksum-verify it onto an ISO-capable storage (`ISO_STORAGE` or a menu). Idempotent; prints the volid last. Also stages any direct URL (`url` mode, used for virtio-win) |
| `select-or-upload-iso.sh` / `.ps1` | Interactive: pick an ISO already on Proxmox storage, or upload a local `.iso` through the API. Used by the Windows wrapper for the licensed ISO. Prints the volid last |
| `remove-vm-if-exists.sh` | Deletes the VM or template at a given VMID (`VM_ID=9006 ./remove-vm-if-exists.sh` or `./remove-vm-if-exists.sh 9006`) so a fixed-ID golden build can be re-run in place. Idempotent |
| `make-windows-noprompt-iso.sh` | Optional: rebuilds a Windows ISO with Microsoft's own `*_noprompt` boot loaders so it never shows "Press any key to boot from CD". Needs `xorriso`. The Proxmox Windows build no longer depends on it |

## Diagnostics

| Script | What it does |
|--------|--------------|
| `task-probe.sh` | Point a Semaphore task template at it to see the execution context a task gets — user, cwd, PATH, tool availability and which `PROXMOX_*` / `PKR_VAR_*` / `SEMAPHORE_*` / `ISO_*` variables arrive (names and lengths only, never values) |
