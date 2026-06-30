# =============================================================================
# win2025-vmware.pkr.hcl
# =============================================================================
# Builds a Windows Server 2025 template on VMware vSphere using Packer.
#
# What Packer does here:
#   1. Creates a temporary VM on vCenter using the vsphere-iso builder
#   2. Attaches the Windows Server 2025 ISO from the vCenter datastore
#   3. Creates a virtual CD containing autounattend.xml — vSphere mounts
#      this as a second CD-ROM; the Windows installer finds it automatically
#   4. Waits for WinRM to become available (autounattend.xml enables it)
#   5. Runs provision-windows.ps1 — hardening, RDP, VMware Tools install
#   6. Runs cleanup-windows.ps1 — seals image and calls sysprep
#   7. Sysprep shuts down the VM; Packer converts it to a vSphere template
#
# Pre-requisites:
#   1. Upload the Windows Server 2025 ISO to a vCenter datastore:
#        [datastore1] ISO/windows-server-2025.iso
#      Download (eval, 180 days):
#        https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025
#
#   2. Set credentials:
#        export PKR_VAR_vsphere_password="your-vcenter-password"
#        export PKR_VAR_winrm_password="PackerBuild2025!"
#      The winrm_password MUST match the password in:
#        http/win2025-vmware/autounattend.xml
#
# Build:
#   packer init win2025-vmware.pkr.hcl
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="environments/win2025.pkrvars.hcl" \
#     win2025-vmware.pkr.hcl
#
# Author  : IT-Architect-UK
# Repo    : https://github.com/IT-Architect-UK/monorepo
# =============================================================================

packer {
  required_version = ">= 1.10.0"

  required_plugins {
    vsphere = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/vsphere"
    }
  }
}

locals {
  timestamp  = formatdate("YYYYMMDD-HHmm", timestamp())
  image_name = "${var.image_name}-${local.timestamp}"
}

# ── Source: vSphere ISO Builder ───────────────────────────────────────────────
source "vsphere-iso" "win2025" {

  # ── vCenter connection ──────────────────────────────────────────────────
  vcenter_server      = var.vsphere_server
  username            = var.vsphere_username
  password            = var.vsphere_password
  insecure_connection = true

  # ── Placement ────────────────────────────────────────────────────────────
  datacenter = var.vsphere_datacenter
  cluster    = var.vsphere_cluster
  datastore  = var.vsphere_datastore
  folder     = var.vsphere_folder
  vm_name    = local.image_name

  # ── Hardware ─────────────────────────────────────────────────────────────
  # Windows Server 2025 — use the newest recognised guest OS type.
  # If your vCenter version doesn't know "windows2025srv64Guest", use
  # "windows2022srvNext64Guest" or "windows2019srvNext64Guest" instead.
  guest_os_type = "windows2025srv64Guest"

  CPUs     = var.vm_cpu_count
  RAM      = var.vm_memory_mb
  firmware = "efi"    # Windows Server 2025 requires UEFI

  # pvscsi is built into Windows Server 2025 — no driver injection needed
  disk_controller_type = ["pvscsi"]

  storage {
    disk_size             = var.vm_disk_gb * 1024    # vsphere takes MB
    disk_thin_provisioned = true
  }

  # vmxnet3 is built into Windows Server 2025
  network_adapters {
    network      = var.vsphere_network
    network_card = "vmxnet3"
  }

  # ── Windows ISO ──────────────────────────────────────────────────────────
  # Path format: "[datastore_name] path/to/file.iso"
  iso_paths = ["[${var.vsphere_datastore}] ISO/windows-server-2025.iso"]

  # ── autounattend.xml delivery via virtual CD ──────────────────────────────
  # Packer creates a virtual CD-ROM from the listed files.
  # Windows installer automatically searches attached drives for autounattend.xml.
  cd_files = [abspath("${path.root}/../../http/win2025-vmware/autounattend.xml")]
  cd_label = "autounattend"

  # ── Boot settings ────────────────────────────────────────────────────────
  boot_wait    = "4s"
  boot_command = ["<enter>"]    # Dismiss "Press any key to boot from CD"

  # ── WinRM communicator ──────────────────────────────────────────────────
  communicator   = "winrm"
  winrm_username = var.winrm_username
  winrm_password = var.winrm_password
  winrm_port     = 5985
  winrm_timeout  = "90m"

  # ── Template settings ────────────────────────────────────────────────────
  # Convert to template after provisioning
  convert_to_template = true
}

# ── Build ─────────────────────────────────────────────────────────────────────
build {
  name    = "win2025-vmware"
  sources = ["source.vsphere-iso.win2025"]

  # Step 1: Baseline hardening, RDP, OpenSSH
  # Note: VMware Tools must be installed separately. Options:
  #   a) Install from vCenter datastore ISO in provision-windows.ps1 (recommended)
  #   b) Let vCenter install via VMware Tools upgrade policy
  #   c) Download from https://packages.vmware.com/tools/releases/latest/
  provisioner "powershell" {
    script = abspath("${path.root}/../../scripts/provision-windows.ps1")
  }

  # Step 2: Install VMware Tools (downloaded from VMware's public CDN)
  provisioner "powershell" {
    inline = [
      # Download VMware Tools installer
      "$url = 'https://packages.vmware.com/tools/releases/latest/windows/x64/VMware-tools-windows-latest.exe'",
      "$out = \"$env:TEMP\\vmwaretools.exe\"",
      "Write-Host 'Downloading VMware Tools...'",
      "try {",
      "  Invoke-WebRequest -Uri $url -OutFile $out -TimeoutSec 120",
      "  Start-Process -FilePath $out -ArgumentList '/S /v /qn REBOOT=ReallySuppress' -Wait",
      "  Write-Host 'VMware Tools installed'",
      "} catch {",
      "  Write-Warning \"VMware Tools download failed: $_ (non-fatal — install manually after deploy)\"",
      "}"
    ]
  }

  # Step 3: Seal — clear logs/temp, remove build account, sysprep + shutdown
  provisioner "powershell" {
    script = abspath("${path.root}/../../scripts/cleanup-windows.ps1")
  }

  post-processor "manifest" {
    output     = "packer-manifest.json"
    strip_path = true
  }
}
