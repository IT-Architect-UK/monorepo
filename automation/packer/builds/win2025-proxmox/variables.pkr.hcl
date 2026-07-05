# Variables for win2025-proxmox template

variable "image_name" {
  type    = string
  default = "win2025-golden"
}

variable "image_description" {
  type    = string
  default = "Windows Server 2025 golden image — built with Packer"
}

variable "win_iso_file" {
  type    = string
  default = "local:iso/windows-server-2025.iso"
}

variable "virtio_iso_file" {
  type    = string
  default = "local:iso/virtio-win.iso"
}

variable "windows_image_index" {
  # Which edition (by INDEX) to install from the ISO's install.wim. Index is
  # unambiguous — no edition-name matching to get wrong. List an ISO's
  # editions on the Proxmox host:
  #   apt-get install -y wimtools
  #   mount -o loop <iso> /mnt/w
  #   wiminfo /mnt/w/sources/install.wim   (or install.esd)
  # Typical Windows Server 2025 layout:
  #   1 = Standard Core   2 = Standard (Desktop Experience)
  #   3 = Datacenter Core 4 = Datacenter (Desktop Experience)
  type    = string
  default = "2"
}

variable "winrm_username" {
  type    = string
  default = "packer"
}

variable "winrm_password" {
  # Injected into autounattend.xml at build time (single source of truth —
  # whatever you set here IS the build account's password). The default
  # matches the XML placeholder so a bare 'packer build .' still works.
  type      = string
  default   = "PackerBuild2025!"
  sensitive = true
}

variable "vm_cpu_count" {
  type    = number
  default = 2
}

variable "vm_memory_mb" {
  type    = number
  default = 4096
}

variable "vm_disk_gb" {
  type    = number
  default = 50
}

variable "proxmox_network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "proxmox_vlan_tag" {
  # Empty = untagged. Site value comes from environments/homelab.pkrvars.hcl
  # via the build wrapper.
  type    = string
  default = ""
}

variable "proxmox_token" {
  # API token secret — used with proxmox_username "user@realm!tokenid".
  # Leave empty to authenticate with proxmox_password instead.
  type      = string
  default   = ""
  sensitive = true
}

variable "win_vm_id" {
  type    = number
  default = 9003
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
