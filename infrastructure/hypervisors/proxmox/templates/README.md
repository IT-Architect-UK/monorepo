# Proxmox Template Preparation

Scripts run **inside a VM** to prepare it for conversion to a Proxmox template — cleaning identity, logs, and machine-specific state so clones come up unique. After running, shut the VM down and convert: `qm template <vmid>`.

| Script | Target OS |
|--------|-----------|
| `ubuntu-proxmox-template-prepare.sh` | Ubuntu (cloud-init based template) |
| `ubuntu-vm-template-prepare.sh` | Ubuntu (generic VM) |
| `alma-vm-template-prepare.sh` | AlmaLinux |
| `ubuntu-default.sh` | Minimal Ubuntu defaults pass |

For fully automated template *builds* (rather than preparing an existing VM), see `automation/packer/builds/`.
