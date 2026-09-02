# Variables for win2025-proxmox template

variable "image_name" {
  type    = string
  default = "t-win2025"
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
  # whatever you set here IS the build account's password, and the built-in
  # Administrator's until first boot). No default on purpose: a password
  # that lives in Git is public. The build wrappers generate a random one
  # when nothing is supplied.
  type      = string
  default   = ""
  sensitive = true
  validation {
    condition     = length(var.winrm_password) >= 12
    error_message = "Set winrm_password to 12 or more characters (export PKR_VAR_winrm_password=...), or use the build wrapper, which generates one."
  }
}

variable "keep_administrator" {
  # false (default): cleanup-windows.ps1 disables the built-in Administrator
  # on the clone's first boot — logins come from cloud-init / the deploy
  # playbook. true: keep it enabled with winrm_password, for troubleshooting
  # while the toolbox is in development. Set from the toolbox build prompt.
  type    = bool
  default = false
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

variable "win_cpu_type" {
  # WS2025 / Win11 24H2 need POPCNT + SSE4.2 — the default kvm64 lacks them
  # and WinPE bugchecks. x86-64-v2-AES is the minimum; "host" also works
  # (fastest, but ties the template to this CPU family).
  type    = string
  default = "x86-64-v2-AES"
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
