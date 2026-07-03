# =============================================================================
# builds/ubuntu-2404-automation-toolbox/automation-toolbox.pkrvars.hcl
# =============================================================================
# Variable overrides specific to the Automation Toolbox image.
# Use alongside homelab.pkrvars.hcl:
#
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="automation-toolbox.pkrvars.hcl" \
#     ubuntu-2404-automation-toolbox-proxmox.pkr.hcl
#
# Sensitive values must be set as environment variables:
#   export PKR_VAR_proxmox_password="your-root-password"
#   export PKR_VAR_ssh_password="your-chosen-packer-user-password"
# =============================================================================

image_name        = "T-UBUNTU-24-DEPLOY"
image_description = "Ubuntu 24.04 Automation Toolbox — Ansible, Packer, Terraform, AWS CLI, Azure CLI, kubectl, Helm, Docker, GitHub CLI, Semaphore"

# This host is permanently pinned to Ubuntu 24.04 LTS, not the 26.04 used by
# the golden image templates in this repo -- chosen for stability, since
# 24.04 ('noble') already has full upstream package-repo support everywhere
# this image needs it (Azure CLI, Docker, HashiCorp), whereas 26.04 support
# is still rolling out across those vendors as of mid-2026.
#
# Packer downloads and checksum-verifies this ISO directly from Canonical --
# no manual download/upload to Proxmox storage needed. The exact filename
# includes the point release and needs bumping the rare times Canonical
# retires an old one; the checksum URL is stable and never needs to change.
ubuntu_iso_url      = "https://releases.ubuntu.com/noble/ubuntu-24.04.4-live-server-amd64.iso"
ubuntu_iso_checksum = "file:https://releases.ubuntu.com/noble/SHA256SUMS"

# Sizing is NOT fixed here: defaults are 4 vCPU / 8 GB (variables.pkr.hcl)
# and the build wrapper asks whether to increase them — 8 vCPU / 16 GB is
# recommended if the host has the capacity, especially once NetBox and
# Prometheus/Grafana are deployed onto this server. To pin values, uncomment:
# vm_cpu_count = 8
# vm_memory_mb = 16384
vm_disk_gb   = 80    # Tools + Docker images + Terraform state + Semaphore data

# Dedicated VM ID — change if 9002 is already in use in your Proxmox cluster
proxmox_vm_id = 9002

# Personal admin login — separate from the 'toolbox' service account.
# admin_password is NOT set here (sensitive) — set via PKR_VAR_admin_password.
admin_username        = "it-admin"
admin_ssh_public_key   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKolhAjPEYFfBGs2mz9fJAi9EfBYDbY5uuqH9TQLce9M"
