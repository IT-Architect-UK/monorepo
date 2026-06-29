# =============================================================================
# variables.pkr.hcl — Shared variable definitions for all Packer templates
# =============================================================================
# Variables are defined here and referenced in each platform template.
# Override any variable at build time:
#   packer build -var "ssh_username=myuser" ubuntu-2404-aws.pkr.hcl
# Or create a .pkrvars.hcl file:
#   packer build -var-file="my.pkrvars.hcl" ubuntu-2404-aws.pkr.hcl
# =============================================================================

# ── Image metadata ──────────────────────────────────────────────────────────
variable "image_name" {
  type        = string
  default     = "ubuntu-2404-golden"
  description = "Base name for the output image/template"
}

variable "image_version" {
  type        = string
  default     = ""
  description = "Version tag appended to image name. Defaults to current date (YYYYMMDD) if empty."
}

variable "image_description" {
  type        = string
  default     = "Ubuntu 24.04 LTS golden image — built with Packer"
  description = "Description embedded in the image metadata"
}

# ── OS settings ─────────────────────────────────────────────────────────────
variable "ubuntu_iso_file" {
  type        = string
  default     = ""
  description = "Path to a pre-uploaded Ubuntu ISO on Proxmox storage (e.g. NFS-10GB-PROXMOX-1:iso/ubuntu-24.04.2-live-server-amd64.iso). Set this in homelab.pkrvars.hcl and Packer will use the existing ISO instead of downloading one."
}

variable "ubuntu_iso_url" {
  type        = string
  default     = "https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
  description = "URL to download the Ubuntu ISO (used by Proxmox and VMware builders)"
}

variable "ubuntu_iso_checksum" {
  type        = string
  default     = "sha256:e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433"
  description = "ISO checksum — always verify from https://releases.ubuntu.com/24.04/SHA256SUMS"
}

# ── SSH access for provisioning ─────────────────────────────────────────────
variable "ssh_username" {
  type        = string
  default     = "packer"
  description = "Temporary user Packer uses during the build. Removed from image after provisioning."
}

variable "ssh_password" {
  type        = string
  default     = "packer-temp-password"
  sensitive   = true
  description = "Password for the temporary build user. Use a vault or env var in CI."
}

# ── VM sizing (Proxmox / VMware) ────────────────────────────────────────────
variable "vm_cpu_count" {
  type        = number
  default     = 2
  description = "Number of vCPUs for the build VM"
}

variable "vm_memory_mb" {
  type        = number
  default     = 2048
  description = "RAM in MB for the build VM"
}

variable "vm_disk_gb" {
  type        = number
  default     = 20
  description = "Root disk size in GB"
}

# ── Proxmox connection ──────────────────────────────────────────────────────
variable "proxmox_url" {
  type        = string
  default     = "https://192.168.1.10:8006/api2/json"
  description = "Proxmox API URL (https://<host>:8006/api2/json)"
}

variable "proxmox_username" {
  type        = string
  default     = "root@pam"
  description = "Proxmox API username"
}

variable "proxmox_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Proxmox API password. Set via PKR_VAR_proxmox_password env var."
}

variable "proxmox_node" {
  type        = string
  default     = "pve"
  description = "Proxmox node name to build on"
}

variable "proxmox_storage_pool" {
  type        = string
  default     = "local-lvm"
  description = "Proxmox storage pool for the template disk"
}

variable "proxmox_iso_storage" {
  type        = string
  default     = "local"
  description = "Proxmox storage pool that holds ISO files"
}

variable "proxmox_vm_id" {
  type        = number
  default     = 9000
  description = "VM ID for the template in Proxmox"
}

# ── VMware vCenter connection ────────────────────────────────────────────────
variable "vsphere_server" {
  type        = string
  default     = "vcenter.lab.local"
  description = "vCenter hostname or IP"
}

variable "vsphere_username" {
  type        = string
  default     = "administrator@vsphere.local"
  description = "vCenter username"
}

variable "vsphere_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "vCenter password. Set via PKR_VAR_vsphere_password env var."
}

variable "vsphere_datacenter" {
  type        = string
  default     = "Datacenter"
  description = "vCenter datacenter name"
}

variable "vsphere_cluster" {
  type        = string
  default     = "Cluster01"
  description = "vCenter cluster name"
}

variable "vsphere_datastore" {
  type        = string
  default     = "datastore1"
  description = "vCenter datastore for the template"
}

variable "vsphere_network" {
  type        = string
  default     = "VM Network"
  description = "vCenter port group / network name"
}

variable "vsphere_folder" {
  type        = string
  default     = "Templates"
  description = "vCenter folder to store the template in"
}

# ── AWS settings ─────────────────────────────────────────────────────────────
variable "aws_region" {
  type        = string
  default     = "eu-west-2"
  description = "AWS region to build the AMI in"
}

variable "aws_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "EC2 instance type for the build instance"
}

variable "aws_vpc_id" {
  type        = string
  default     = ""
  description = "VPC ID for the build instance. Leave empty to use default VPC."
}

variable "aws_subnet_id" {
  type        = string
  default     = ""
  description = "Subnet ID for the build instance."
}

# ── Azure settings ────────────────────────────────────────────────────────────
variable "azure_subscription_id" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Azure subscription ID. Set via PKR_VAR_azure_subscription_id env var."
}

variable "azure_resource_group" {
  type        = string
  default     = "rg-packer-images"
  description = "Resource group to store the managed image in"
}

variable "azure_location" {
  type        = string
  default     = "uksouth"
  description = "Azure region"
}

variable "azure_vm_size" {
  type        = string
  default     = "Standard_B1s"
  description = "Azure VM size for the build VM"
}

# ── GCP settings ─────────────────────────────────────────────────────────────
variable "gcp_project_id" {
  type        = string
  default     = ""
  description = "GCP project ID"
}

variable "gcp_zone" {
  type        = string
  default     = "europe-west2-a"
  description = "GCP zone for the build VM"
}

variable "gcp_machine_type" {
  type        = string
  default     = "e2-micro"
  description = "GCP machine type for the build VM"
}

# ── Windows settings ──────────────────────────────────────────────────────────
variable "win_iso_file" {
  type        = string
  default     = "local:iso/windows-server-2025.iso"
  description = "Path to the Windows Server 2025 ISO already uploaded to Proxmox storage (format: pool:iso/filename.iso). Download the evaluation ISO from https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025"
}

variable "virtio_iso_file" {
  type        = string
  default     = "local:iso/virtio-win.iso"
  description = "Path to the virtio-win drivers ISO on Proxmox storage. Download from https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
}

variable "winrm_username" {
  type        = string
  default     = "packer"
  description = "Windows user Packer connects as via WinRM. Must match the account created in autounattend.xml."
}

variable "winrm_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "WinRM password. Set via PKR_VAR_winrm_password env var. Must match the password in autounattend.xml."
}

variable "win_vm_id" {
  type        = number
  default     = 9003
  description = "Proxmox VM ID for the Windows Server 2025 template"
}

# ── Branding ──────────────────────────────────────────────────────────────────
variable "vm_company_name" {
  type        = string
  default     = "IT-Architect"
  description = "Organisation name used in server branding — MOTD, login banner, and shell prompt. Override in your .pkrvars.hcl or via the PKR_VAR_vm_company_name environment variable."
}

# ── Semaphore UI ──────────────────────────────────────────────────────────────
variable "semaphore_admin_password" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Initial Semaphore UI admin password. Set via PKR_VAR_semaphore_admin_password. Change immediately after first login."
}
