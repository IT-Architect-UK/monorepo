# =============================================================================
# environments/automation-toolbox.pkrvars.hcl
# =============================================================================
# Variable overrides specific to the Automation Toolbox image.
# Use alongside homelab.pkrvars.hcl:
#
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="environments/automation-toolbox.pkrvars.hcl" \
#     ubuntu-2604-automation-toolbox-proxmox.pkr.hcl
#
# Sensitive values must be set as environment variables:
#   export PKR_VAR_proxmox_password="your-root-password"
#   export PKR_VAR_ssh_password="your-chosen-packer-user-password"
# =============================================================================

image_name        = "POSLXPDEPLOY01"
image_description = "Ubuntu 26.04 Automation Toolbox — Ansible, Packer, Terraform, AWS CLI, Azure CLI, kubectl, Helm, Docker, GitHub CLI, Semaphore"

# More resources than a standard VM — this host runs Packer builds,
# Terraform plans, Docker containers, and the Semaphore web UI concurrently.
vm_cpu_count = 6
vm_memory_mb = 8192
vm_disk_gb   = 80    # Tools + Docker images + Terraform state + Semaphore data

# Dedicated VM ID — change if 9002 is already in use in your Proxmox cluster
proxmox_vm_id = 9002

# Public key for the 'toolbox' user — SSH password auth is disabled by
# provision.sh, so this is the only way in once the build completes.
toolbox_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKolhAjPEYFfBGs2mz9fJAi9EfBYDbY5uuqH9TQLce9M"
