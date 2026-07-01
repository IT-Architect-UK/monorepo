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

image_name        = "POSLXPDEPLOY01"
image_description = "Ubuntu 24.04 Automation Toolbox — Ansible, Packer, Terraform, AWS CLI, Azure CLI, kubectl, Helm, Docker, GitHub CLI, Semaphore"

# This template is permanently pinned to Ubuntu 24.04 LTS, not the 26.04 used
# by the other templates in this repo -- chosen for stability, since 24.04
# ('noble') already has full upstream package-repo support everywhere this
# image needs it (Azure CLI, Docker, HashiCorp), whereas 26.04 support is
# still rolling out across those vendors as of mid-2026. Overriding here
# rather than in the shared homelab.pkrvars.hcl, which stays on 26.04 for
# the other templates.
ubuntu_iso_file = "NFS-10GB-PROXMOX-1:iso/ubuntu-24.04-live-server-amd64.iso"

# More resources than a standard VM — this host runs Packer builds,
# Terraform plans, Docker containers, and the Semaphore web UI concurrently.
vm_cpu_count = 6
vm_memory_mb = 8192
vm_disk_gb   = 80    # Tools + Docker images + Terraform state + Semaphore data

# Dedicated VM ID — change if 9002 is already in use in your Proxmox cluster
proxmox_vm_id = 9002

# Personal admin login — separate from the 'toolbox' service account.
# admin_password is NOT set here (sensitive) — set via PKR_VAR_admin_password.
admin_username        = "it-admin"
admin_ssh_public_key   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKolhAjPEYFfBGs2mz9fJAi9EfBYDbY5uuqH9TQLce9M"
