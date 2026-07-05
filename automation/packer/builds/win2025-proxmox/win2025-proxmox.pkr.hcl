# =============================================================================
# win2025-proxmox.pkr.hcl
# =============================================================================
# Builds a Windows Server 2025 template on Proxmox VE using Packer.
#
# What Packer does here:
#   1. Attaches the Windows Server 2025 ISO (pre-uploaded to Proxmox storage)
#   2. Creates a temporary VM matching a proven WS2025 template: q35,
#      VirtIO SCSI (iothread) + VirtIO NIC + TPM 2.0. VirtIO storage/network
#      drivers are injected during Setup via the autounattend DriverPaths
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
  password                 = var.proxmox_password == "" ? null : var.proxmox_password
  token                    = var.proxmox_token == "" ? null : var.proxmox_token
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

  # Machine + controller matched to a proven WS2025 template: q35 chipset,
  # VirtIO SCSI single with iothread. The VirtIO storage driver (vioscsi) is
  # injected during Windows Setup via the autounattend DriverPaths, so WinPE
  # can see the disk (unlike SATA, VirtIO needs the driver at install time).
  machine         = "q35"
  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "${var.vm_disk_gb}G"
    storage_pool = var.proxmox_storage_pool
    type         = "scsi"
    format       = "raw"
    io_thread    = true
  }

  # VirtIO NIC — faster than e1000. The NetKVM driver is injected during
  # Setup (same DriverPaths), so the network is up for WinRM. Bridge/VLAN
  # come from site variables.
  network_adapters {
    model    = "virtio"
    bridge   = var.proxmox_network_bridge
    vlan_tag = var.proxmox_vlan_tag == "" ? null : var.proxmox_vlan_tag
  }

  # UEFI firmware — must accompany efi_config (same SeaBIOS-default trap
  # caught live on the Ubuntu golden build)
  bios = "ovmf"

  # EFI config — Windows Server 2025 requires UEFI
  efi_config {
    efi_storage_pool  = var.proxmox_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true    # Enables Secure Boot (supported by WS2025)
  }

  # TPM 2.0 — Windows Server 2025 expects it (the reference template has it).
  tpm_config {
    tpm_storage_pool = var.proxmox_storage_pool
    version          = "v2.0"
  }

  # ── Secondary ISO: autounattend.xml ─────────────────────────────────────
  # Packer creates a small ISO from this file and mounts it.
  # The Windows installer automatically searches attached drives for
  # autounattend.xml at the drive root — no boot_command typing needed.
  additional_iso_files {
    # The password you set in winrm_password is injected INTO the
    # autounattend at build time (the XML's placeholder is replaced), so
    # there is exactly ONE source of truth — no manual XML editing.
    cd_content = {
      "autounattend.xml" = replace(
        replace(
          file("${path.root}/../../http/win2025-proxmox/autounattend.xml"),
          "PackerBuild2025!",
          var.winrm_password
        ),
        "WINDOWS_IMAGE_INDEX",
        var.windows_image_index
      )
    }
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
  # The Windows ISO shows "Press any key to boot from CD or DVD..." for only
  # a few seconds; miss it and OVMF drops to "no bootable device" (caught
  # live on VM 9003 — a single keystroke at 4s arrived outside the window).
  # Start early and keep pressing for ~15s so the prompt cannot be missed.
  boot_wait    = "1s"
  boot_command = ["<enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter><wait><enter>"]

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
    script = abspath("${path.root}/../../scripts/provision-windows.ps1")
  }

  # Step 2: Seal the image — clears logs/temp, removes build account, runs sysprep
  # Sysprep shuts down the VM; Packer detects the disconnect and converts to template
  provisioner "powershell" {
    script = abspath("${path.root}/../../scripts/cleanup-windows.ps1")
  }

  # Record what was built
  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
