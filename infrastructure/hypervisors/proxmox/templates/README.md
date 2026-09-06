# Template Preparation

Scripts run **inside a guest** before it is turned into a template — patching,
removing SSH host keys and the machine-id, truncating logs and shutting down so
clones come up unique. Only one of them is Proxmox-specific; the rest were
written for VMware guests and are kept here for reference.

| Script | What it does | Target |
|--------|--------------|--------|
| `ubuntu-proxmox-template-prepare.sh` | `apt upgrade`, autoremove, remove SSH host keys, reset machine-id, truncate `/var/log/*.log`, clear tmp and shell history, shut down. Then `qm template <vmid>` on the host | Proxmox (Ubuntu) |
| `ubuntu-vm-template-prepare.sh` | As above, plus installs `open-vm-tools`, enables VMware guest-customisation scripts (`deployPkg enable-custom-scripts`) and removes persistent-net udev rules | VMware (Ubuntu) |
| `alma-vm-template-prepare.sh` | `dnf` upgrade, `open-vm-tools` + `vmtoolsd`, VMware customisation enabled, NetworkManager reset to a single DHCP profile, IPv6 disabled (GRUB + sysctl), SSH password auth on, cloud-init disabled, identity and logs cleared, power off | VMware (AlmaLinux) |
| `ubuntu-default.sh` | VMware guest-customisation hook (`$1` is `precustomization` or `postcustomization`). Post-customisation it installs git, clones this repo to `/source-files/github/monorepo`, `apt-get upgrade`, reboots | VMware (Ubuntu) |

**Known issues**

- `ubuntu-proxmox-template-prepare.sh` does no cloud-init handling. Clean
  cloud-init state yourself (`cloud-init clean`) if the template is to be
  cloned with cloud-init, or use the Packer builds below.
- `ubuntu-default.sh` `cd`s into `scripts/bash/ubuntu/{configuration,server-roles,packages}`
  after cloning; those paths no longer exist in this repo, so the script fails
  (`set -e`) before the upgrade and reboot.

For fully automated template *builds* (rather than preparing an existing VM),
see `automation/packer/builds/`.
