# Variables for ubuntu-2404-automation-toolbox-proxmox template
# Full variable reference: ../environments/README.md

variable "image_name" {
  type    = string
  default = "ubuntu-2404-automation-toolbox"
}

variable "image_description" {
  type    = string
  default = "Ubuntu 24.04 Automation Toolbox — Ansible, Packer, Terraform, Docker, and more"
}

# Packer downloads and checksum-verifies this ISO directly from Canonical --
# no manual download/upload to Proxmox storage required. Bump the filename
# when Canonical retires this point release; the checksum URL below never
# needs to change.
variable "ubuntu_iso_url" {
  type    = string
  default = ""
}

variable "ubuntu_iso_checksum" {
  type    = string
  default = ""
}

variable "cidata_iso_file" {
  type    = string
  default = "NFS-10GB-PROXMOX-1:iso/ubuntu-2404-cidata.iso"
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  # Must match the password hash baked into http/user-data for the 'packer'
  # user (default: "packer-temp-password"). This is a temporary, build-only
  # credential — SSH password auth is disabled before the image is sealed —
  # so there's no security reason to require re-entering it every run. If you
  # regenerate the cidata ISO with a different password, update this default
  # (or override via PKR_VAR_ssh_password) to match.
  type      = string
  default   = "packer-temp-password"
  sensitive = true
}

variable "vm_cpu_count" {
  type    = number
  default = 4
}

variable "vm_memory_mb" {
  type    = number
  default = 4096
}

variable "vm_disk_gb" {
  type    = number
  default = 60
}

variable "proxmox_url" {
  type    = string
  default = "https://192.168.1.10:8006/api2/json"
}

variable "proxmox_username" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "proxmox_storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "proxmox_iso_storage" {
  type    = string
  default = "local"
}

variable "proxmox_network_bridge" {
  type    = string
  default = "VLANs"
}

variable "proxmox_vlan_tag" {
  type    = string
  default = "4"
}

variable "proxmox_vm_id" {
  type    = number
  default = 9002
}

variable "vm_company_name" {
  type    = string
  default = "IT-Architect"
}

variable "semaphore_admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "admin_username" {
  # Personal login account, separate from the 'toolbox' service account.
  # Gets standard 'sudo' group membership (password required), a real
  # password, and the SSH key below. Not a secret — safe to commit.
  type    = string
  default = ""
}

variable "admin_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "admin_ssh_public_key" {
  # Public key — not a secret, safe to set in a committed .pkrvars.hcl file.
  # Installed to /home/<admin_username>/.ssh/authorized_keys. This is the
  # only account this key is installed for; 'toolbox' has no SSH key.
  type    = string
  default = ""
}

# ─── Unused elsewhere ──────────────────────────────────────────────────────────
# environments/homelab.pkrvars.hcl is a shared file covering every hypervisor
# (Proxmox, VMware, Windows) by design. This template is Proxmox+Ubuntu only,
# so it doesn't use these — declared here purely so packer validate/build
# stop warning "was set but was not declared as an input variable" for them.
variable "vsphere_server" {
  type    = string
  default = null
}

variable "vsphere_datacenter" {
  type    = string
  default = null
}

variable "vsphere_cluster" {
  type    = string
  default = null
}

variable "vsphere_datastore" {
  type    = string
  default = null
}

variable "vsphere_network" {
  type    = string
  default = null
}

variable "vsphere_folder" {
  type    = string
  default = null
}

variable "win_iso_file" {
  type    = string
  default = null
}

variable "ubuntu_iso_file" {
  # Superseded here by ubuntu_iso_url/ubuntu_iso_checksum (Packer fetches
  # and verifies the ISO itself -- see above). Still declared as unused
  # because homelab.pkrvars.hcl sets it for the ubuntu-2604-* templates,
  # which still use the pre-uploaded-ISO pattern.
  type    = string
  default = null
}

variable "virtio_iso_file" {
  type    = string
  default = null
}
