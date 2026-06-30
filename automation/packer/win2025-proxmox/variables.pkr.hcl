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

variable "winrm_username" {
  type    = string
  default = "packer"
}

variable "winrm_password" {
  type      = string
  default   = ""
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
