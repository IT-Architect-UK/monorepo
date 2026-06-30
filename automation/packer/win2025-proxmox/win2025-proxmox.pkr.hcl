# =============================================================================
# win2025-proxmox.pkr.hcl
# =============================================================================
# Builds a Windows Server 2025 template on Proxmox VE using Packer.
#
# What Packer does here:
#   1. Attaches the Windows Server 2025 ISO (pre-uploaded to Proxmox storage)
#   2. Creates a temporary VM with SATA disk and e1000 NIC — both have
#      in-box Windows drivers, so no VirtIO driver injection is needed
#   3. Mounts the autounattend.xml as a secondary CD — Windows installer
#      finds it automatically and runs the installation unattended
#   4. Mounts the virtio-win ISO so provision-windows.ps1 can install the
#      QEMU Guest Agent (needed for Proxmox 'qm agent' and live migration)
#   5. Waits for WinRM to become available (autounattend.xml enables it)
#   6. Runs provision-windows.ps1 — hardening, RDP, guest agent
#   7. Runs cleanup-windows.ps1 — seals image and calls sysprep
#   8. Sysprep shuts down the VM; Packer converts it to a Proxmox template
#
# Pre-requisites:
#   1. Upload Windows Server 2025 ISO to Proxmox storage:
#        NFS-10GB-PROXMOX-1:iso/windows-server-2025.iso
#      Download (eval, 180 days):
#        https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025
#
#   2. Upload virtio-win ISO to Proxmox storage:
#        NFS-10GB-PROXMOX-1:iso/virtio-win.iso
#      Download:
#        https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso
#
#   3. Set credentials:
#        export PKR_VAR_proxmox_password="your-root-password"
#        export PKR_VAR_winrm_password="PackerBuild2025!"
#      The winrm_password MUST match the password in:
#        http/win2025-proxmox/autounattend.xml
#
# Build:
#   packer init win2025-proxmox.pkr.hcl
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="environments/win2025.pkrvars.hcl" \
#     win2025-proxmox.pkr.hcl
#
# After the build:
#   Clone the template in Proxmox and boot the new VM.
#   The cloned VM will complete the Windows OOBE "specialize" pass on first
#   boot, set a new SID, and be ready in ~5 minutes.
#   Log in with the Administrator account and the password you used above.
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

locals {
  timestamp  = formatdate("YYYYMMDD-HHmm", timestamp())
  image_name = "${var.image_name}-${local.timestamp}"
}

# ── Source: Proxmox ISO Builder ───────────────────────────────────────────────
source "proxmox-iso" "win2025" {

  # ── Proxmox connection ──────────────────────────────────────────────────
  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  # ── VM settings ─────────────────────────────────────────────────────────
  vm_id   = var.win_vm_id
  vm_name = local.image_name

  # ── Windows ISO (must be pre-uploaded to Proxmox) ────────────────────────
  # iso_file format: "storage_pool:iso/filename.iso"
  iso_file         = var.win_iso_file
  iso_storage_pool = var.proxmox_iso_storage

  # ── Hardware ─────────────────────────────────────────────────────────────
  cores  = var.vm_cpu_count
  memory = var.vm_memory_mb

  # SATA disk — Windows has SATA drivers in-box; no VirtIO injection needed
  # The QEMU Guest Agent (installed via provision-windows.ps1) communicates
  # via the Proxmox QEMU socket, not the disk bus
  disks {
    disk_size    = "${var.vm_disk_gb}G"
    storage_pool = var.proxmox_storage_pool
    type         = "sata"
    format       = "raw"
  }

  # e1000 NIC — Intel E1000 driver is bundled with Windows Server 2025
  network_adapters {
    model  = "e1000"
    bridge = "vmbr0"
  }

  # EFI config — Windows Server 2025 requires UEFI
  efi_config {
    efi_storage_pool  = var.proxmox_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true    # Enables Secure Boot (supported by WS2025)
  }

  # ── Secondary ISO: autounattend.xml ─────────────────────────────────────
  # Packer creates a small ISO from this file and mounts it.
  # The Windows installer automatically searches attached drives for
  # autounattend.xml at the drive root — no boot_command typing needed.
  additional_iso_files {
    cd_files         = ["./http/win2025-proxmox/autounattend.xml"]
    iso_storage_pool = var.proxmox_iso_storage
    cd_label = "autounattend"
    unmount  = false
  }

  # ── Secondary ISO: virtio-win drivers ────────────────────────────────────
  # Provides the QEMU Guest Agent installer that provision-windows.ps1 finds
  # by scanning CD-ROM drive letters automatically.
  additional_iso_files {
    iso_file         = var.virtio_iso_file
    iso_storage_pool = var.proxmox_iso_storage
    unmount          = false
  }

  # ── Boot settings ────────────────────────────────────────────────────────
  # Windows ISO auto-boots from EFI. The short boot_command dismisses the
  # "Press any key to boot from CD/DVD" prompt that some BIOSes show.
  boot_wait    = "4s"
  boot_command = ["<enter>"]

  # ── WinRM communicator ──────────────────────────────────────────────────
  # Packer connects via WinRM after autounattend.xml finishes setup.
  # Port 5985 (HTTP) is used during the build; cleanup-windows.ps1
  # removes the HTTP firewall rule and leaves only HTTPS (5986) open.
  communicator = "winrm"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password
  winrm_port     = 5985
  winrm_timeout  = "90m"    # Windows install + OOBE typically takes 20-40 min

  # ── Template settings ────────────────────────────────────────────────────
  template_name        = local.image_name
  template_description = "${var.image_description}\nBuilt: ${local.timestamp}"
  onboot               = false
  qemu_agent           = true    # Guest Agent socket — installed by provision-windows.ps1
}

# ── Build ─────────────────────────────────────────────────────────────────────
build {
  name    = "win2025-proxmox"
  sources = ["source.proxmox-iso.win2025"]

  # Step 1: Baseline hardening, RDP, QEMU Guest Agent, OpenSSH
  provisioner "powershell" {
    script = "scripts/provision-windows.ps1"
  }

  # Step 2: Seal the image — clears logs/temp, removes build account, runs sysprep
  # Sysprep shuts down the VM; Packer detects the disconnect and converts to template
  provisioner "powershell" {
    script = "scripts/cleanup-windows.ps1"
  }

  # Record what was built
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
