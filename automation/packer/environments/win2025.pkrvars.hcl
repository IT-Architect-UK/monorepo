# =============================================================================
# environments/win2025.pkrvars.hcl
# =============================================================================
# Variable overrides specific to the Windows Server 2025 image.
# Always use alongside homelab.pkrvars.hcl:
#
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="environments/win2025.pkrvars.hcl" \
#     win2025-proxmox.pkr.hcl
#
# Sensitive values via environment variables:
#   export PKR_VAR_proxmox_password="your-proxmox-root-password"
#   export PKR_VAR_winrm_password="PackerBuild2025!"
#
# IMPORTANT: PKR_VAR_winrm_password must match the password hardcoded in:
#   automation/packer/http/win2025-proxmox/autounattend.xml
# =============================================================================

image_name        = "win2025-golden"
image_description = "Windows Server 2025 Standard Evaluation golden image — built with Packer"

# Windows needs more resources than the Ubuntu baseline
vm_cpu_count = 4
vm_memory_mb = 4096
vm_disk_gb   = 60     # Minimum 40 GB; 60 gives room for updates and roles

# Dedicated VM ID — change if 9003 conflicts with an existing VM
win_vm_id = 9003
