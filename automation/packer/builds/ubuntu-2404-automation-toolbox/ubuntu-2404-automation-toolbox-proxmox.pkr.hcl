###############################################################################
# Packer Template: Ubuntu 24.04 Automation Toolbox — Proxmox
#
# PURPOSE
#   Builds a Proxmox VM template ready to use as a centralised automation
#   management host. On first boot the VM has:
#     • Ansible, Packer, Terraform, AWS CLI v2, Azure CLI
#     • kubectl, Helm, GitHub CLI, Docker CE
#     • Semaphore (Ansible web UI, http://<vm-ip>/ via nginx on port 80)
#     • Python 3 with boto3, azure-identity, google-cloud
#     • jq, yq
#
# USAGE
#   packer init .
#   export PKR_VAR_proxmox_password="your-root-password"
#   export PKR_VAR_ssh_password="your-chosen-packer-user-password"
#   export PKR_VAR_semaphore_admin_password="your-semaphore-password"
#   packer build \
#     -var-file="environments/homelab.pkrvars.hcl" \
#     -var-file="automation-toolbox.pkrvars.hcl" \
#     ubuntu-2404-automation-toolbox-proxmox.pkr.hcl
#
# VARIABLES
#   All variables are defined in variables.pkr.hcl (including cidata_iso_file).
###############################################################################

packer {
  required_version = ">= 1.10.0"
  required_plugins {
    proxmox = {
      version = ">= 1.1.8"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# ─── Locals ───────────────────────────────────────────────────────────────────
locals {
  # image_name is set via automation-toolbox.pkrvars.hcl (currently
  # "T-UBUNTU-24-DEPLOY") -- no timestamp suffix, since the build always
  # targets the same fixed vm_id and is destroyed/rebuilt between runs
  # rather than versioned by name. timestamp is kept for the human-readable
  # build date in template_description below.
  timestamp  = formatdate("YYYYMMDD-HHmm", timestamp())
  image_name = var.image_name
}

# ─── Source ───────────────────────────────────────────────────────────────────
source "proxmox-iso" "automation-toolbox" {

  proxmox_url              = var.proxmox_url
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  insecure_skip_tls_verify = true
  node                     = var.proxmox_node

  vm_id                = var.proxmox_vm_id
  vm_name              = local.image_name
  template_name        = local.image_name
  template_description = "Ubuntu 24.04 Automation Toolbox | Built ${local.timestamp} by Packer | Tools: Ansible, Packer, Terraform, AWS CLI, Azure CLI, kubectl, Helm, Docker, GitHub CLI"

  # Attaches a Proxmox-native Cloud-Init CDROM to the resulting template.
  # provision.sh deliberately skips disable-cloud-init.sh for HYPERVISOR=proxmox
  # (that script still runs for other hypervisors -- it exists to work around
  # a VMware-specific networking bug, not a Proxmox one), and cleanup.sh's
  # existing `cloud-init clean --logs --seed` wipes the cached instance-id
  # before sealing. Together, that means each clone's first boot re-runs
  # cloud-init against fresh Proxmox-generated meta-data, which sets the
  # guest hostname to match whatever name the clone was given -- see
  # build-automation-toolbox-proxmox.ps1's post-build clone prompt.
  cloud_init              = true
  cloud_init_storage_pool = var.proxmox_storage_pool

  boot_iso {
    iso_url          = var.ubuntu_iso_url
    iso_checksum     = var.ubuntu_iso_checksum
    iso_storage_pool = var.proxmox_iso_storage
    iso_download_pve = true
    unmount          = true
  }

  cores           = var.vm_cpu_count
  memory          = var.vm_memory_mb
  os              = "l26"
  qemu_agent      = true
  scsi_controller = "virtio-scsi-single"

  disks {
    disk_size    = "${var.vm_disk_gb}G"
    format       = "raw"
    storage_pool = var.proxmox_storage_pool
    type         = "virtio"
  }

  network_adapters {
    bridge   = var.proxmox_network_bridge
    model    = "virtio"
    firewall = false
    vlan_tag = var.proxmox_vlan_tag
  }

  efi_config {
    efi_storage_pool  = var.proxmox_storage_pool
    efi_type          = "4m"
    pre_enrolled_keys = true
  }
  bios = "ovmf"

  additional_iso_files {
    iso_file = var.cidata_iso_file
    unmount  = true
  }

  boot_command = [
    "<wait3>",
    "c<wait>",
    "linux /casper/vmlinuz nomodeset --- autoinstall ds=nocloud<wait>",
    "<enter><wait>",
    "initrd /casper/initrd<wait>",
    "<enter><wait>",
    "boot<enter>"
  ]
  boot_wait = "5s"

  communicator           = "ssh"
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "90m"
  ssh_handshake_attempts = 50
}

# ─── Build ────────────────────────────────────────────────────────────────────
build {
  name    = "automation-toolbox"
  sources = ["source.proxmox-iso.automation-toolbox"]

  provisioner "file" {
    sources = [
      abspath("${path.root}/../../../../infrastructure/servers/linux/configuration/apply-branding.sh"),
      abspath("${path.root}/../../../../infrastructure/servers/linux/configuration/disable-cloud-init.sh"),
      abspath("${path.root}/../../../../infrastructure/servers/linux/configuration/disable-ipv6.sh"),
      abspath("${path.root}/../../../../infrastructure/networking/firewall/setup-iptables.sh"),
      abspath("${path.root}/../../../../infrastructure/servers/linux/configuration/sync-monorepo.sh"),
    ]
    destination = "/tmp/"
  }

  provisioner "shell" {
    script          = abspath("${path.root}/../../scripts/provision.sh")
    execute_command = "sudo bash {{.Path}}"
    pause_before    = "10s"
    environment_vars = [
      "HYPERVISOR=proxmox",
      "COMPANY_NAME=${var.vm_company_name}",
    ]
  }

  provisioner "shell" {
    script          = abspath("${path.root}/../../scripts/provision-automation-toolbox.sh")
    execute_command = "sudo bash {{.Path}}"
    environment_vars = [
      "ADMIN_USERNAME=${var.admin_username}",
      "ADMIN_PASSWORD=${var.admin_password}",
      "ADMIN_SSH_PUBLIC_KEY=${var.admin_ssh_public_key}",
    ]
  }

  provisioner "shell" {
    script          = abspath("${path.root}/../../scripts/provision-semaphore.sh")
    execute_command = "sudo bash {{.Path}}"
    environment_vars = [
      "SEMAPHORE_ADMIN_PASS=${var.semaphore_admin_password}",
    ]
  }

  provisioner "shell" {
    inline          = ["chown -R ${var.ssh_username}:${var.ssh_username} /opt/toolbox"]
    execute_command = "sudo bash {{.Path}}"
  }

  # abspath() strips trailing slashes, so "ansible/" here would be uploaded
  # as "ansible" (no slash) regardless of how it's written -- and Packer's
  # file provisioner treats a no-trailing-slash source as "nest this
  # directory inside the destination", not "copy its contents into it".
  # That silently produced /opt/toolbox/ansible/ansible/... instead of
  # /opt/toolbox/ansible/... (confirmed via a real build: 'ansible-playbook
  # playbooks/server-baseline.yml' then failed with 'could not be found').
  # Fix: destination is the parent dir, so Packer creates the nested
  # "ansible" directory itself, landing content at the expected path.
  provisioner "file" {
    source      = abspath("${path.root}/../../../ansible")
    destination = "/opt/toolbox/"
  }

  # ansible.cfg (copied in by the previous provisioner) sets
  # inventory = /opt/toolbox/ansible/inventory/hosts.yml -- that's the
  # correct default for post-boot admin use (managing the real fleet:
  # web01, db01, etc.), but it means --limit=localhost matches nothing
  # here, since 'localhost' isn't a host in that real inventory. Confirmed
  # via a real build: 'Specified inventory, host pattern and/or --limit
  # leaves us with no hosts to target.' -i 'localhost,' (trailing comma,
  # single-quoted so no HCL escaping is needed) overrides ansible.cfg's
  # inventory for just this invocation with an inline single-host list,
  # which is what --connection=local actually needs for self-provisioning.
  #
  # That override has a side effect: Ansible only auto-loads group_vars/
  # from a directory next to the inventory FILE or next to the playbook --
  # an inline -i 'localhost,' string is neither, so common_packages/
  # system_timezone/admin_user/admin_groups (defined in group_vars/all.yml)
  # resolve to nothing. Confirmed via a real build: "'common_packages' is
  # undefined". -e '@group_vars/all.yml' loads that file explicitly,
  # independent of directory-adjacency rules.
  #
  # infrastructure/networking/firewall/setup-iptables.sh is referenced by
  # roles/common/tasks/main.yml via a path relative to playbook_dir
  # (../../../infrastructure/...). That resolves correctly against a FULL
  # monorepo checkout (what Semaphore uses in production), but
  # /opt/toolbox/ansible/ above is only a partial copy (automation/ansible/
  # alone) -- infrastructure/ was never uploaded there. Confirmed via a real
  # build: "Could not find or access .../infrastructure/networking/firewall/
  # setup-iptables.sh on the Ansible Controller".
  #
  # provision.sh (step 12) already clones the full monorepo to /git/monorepo
  # for the sync-monorepo.sh cron job. verify-monorepo-sync.sh (just below)
  # turns that best-effort clone into a hard precondition for this build,
  # then ansible-playbook runs against /git/monorepo/automation/ansible
  # instead of /opt/toolbox/ansible, so the relative path resolves with no
  # special-casing -- identically to how Semaphore will run it later.
  # /opt/toolbox/ansible/ itself is untouched by this change: it's still
  # needed for Semaphore's own post-boot Project/Inventory setup (see
  # provision-semaphore.sh), just not for this self-provisioning step.
  # ANSIBLE_ROLES_PATH pins role loading to the same /git/monorepo checkout
  # the playbook runs from, rather than falling through to ansible.cfg's
  # hardcoded roles_path=/opt/toolbox/ansible/roles (a different, separately
  # -uploaded copy that could in principle drift out of sync).
  provisioner "shell" {
    script          = abspath("${path.root}/../../scripts/verify-monorepo-sync.sh")
    execute_command = "sudo bash {{.Path}}"
  }

  provisioner "shell" {
    inline = [
      "cd /git/monorepo/automation/ansible && ANSIBLE_ROLES_PATH=/git/monorepo/automation/ansible/roles ansible-playbook -i 'localhost,' -e '@group_vars/all.yml' playbooks/server-baseline.yml --connection=local --limit=localhost -e ansible_python_interpreter=/usr/bin/python3"
    ]
    execute_command = "sudo bash {{.Path}}"
  }

  provisioner "shell" {
    script          = abspath("${path.root}/../../scripts/cleanup.sh")
    execute_command = "sudo bash {{.Path}}"
  }

  post-processor "manifest" {
    output     = "packer-manifest-automation-toolbox.json"
    strip_path = true
  }
}
