# Ubuntu 26.04 Golden Image — VMware vSphere

Builds a hardened Ubuntu 26.04 LTS template on vSphere with the `vsphere-iso` builder, talking to vCenter's API only — no SSH to ESXi hosts. The finished VM is converted to a template (`convert_to_template = true`) in `vsphere_folder`.

## How it works

1. Packer downloads the Ubuntu ISO pinned by `ubuntu_iso_url` + `ubuntu_iso_checksum` and uploads it to the datastore
2. Creates a VM: `ubuntu64Guest`, EFI firmware, `pvscsi` disk controller, thin-provisioned disk, `vmxnet3` NIC on `vsphere_network`
3. Bundles `../../http/user-data` + `meta-data` into a second CD labelled `cidata` (`cd_files`), and the boot command tells the installer `ds=nocloud;seedfrom=/dev/sr1/`
4. Waits for SSH (40 min), uploads the helper scripts from `infrastructure/`, runs `../../scripts/provision.sh` (`HYPERVISOR=vmware`), then the `server-baseline.yml` Ansible playbook, then `../../scripts/cleanup.sh`
5. Converts the VM to a template; the description and build time go into the VM notes

The **Ansible provisioner runs on the build host**, so Ansible must be installed alongside Packer. There is no build wrapper script for this template.

## Prerequisites

| Requirement | Detail |
|-------------|--------|
| Packer ≥ 1.10 | Plugins `vsphere ~> 1.4` and `ansible ~> 1.1` (`packer init .`) |
| Ansible | On the build machine |
| xorriso (Linux) | Packer needs it to build the cidata CD from `cd_files` |
| vCenter access | `PKR_VAR_vsphere_password` for `vsphere_username`. `insecure_connection = true` is hardcoded in the template, so vCenter's certificate is **not** verified — edit the template to `false` once vCenter has a trusted certificate |
| `PKR_VAR_ssh_password` | **Required** — unlike the Proxmox templates this one has no default, and it must be `packer-temp-password` (or whatever hash you put in `http/user-data`) |

## Key variables (`variables.pkr.hcl`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `vsphere_server` / `vsphere_username` / `vsphere_password` | `vcenter.lab.local` / `administrator@vsphere.local` / — | vCenter connection |
| `vsphere_datacenter` / `vsphere_cluster` / `vsphere_datastore` | `Datacenter` / `Cluster01` / `datastore1` | Placement |
| `vsphere_network` / `vsphere_folder` | `VM Network` / `Templates` | Port group and template folder |
| `ubuntu_iso_url` | `https://releases.ubuntu.com/resolute/ubuntu-26.04-live-server-amd64.iso` | ISO to install from |
| `ubuntu_iso_checksum` | `sha256:e907d92e…` | Checksum of that ISO — bump both together for a new point release |
| `ssh_username` / `ssh_password` | `packer` / — | Build user from `http/user-data` |
| `vm_cpu_count` / `vm_memory_mb` / `vm_disk_gb` | 2 / 2048 / 20 | Build-time sizing |
| `image_name` | `t-ubuntu-2604` | Template name prefix (timestamp appended) |
| `image_description` | `Ubuntu 26.04 LTS golden image — built with Packer` | VM notes |
| `vm_company_name` | `IT-Architect` | Branding passed to `provision.sh` |

## Build

```bash
cd automation/packer/builds/ubuntu-2604-vmware
export PKR_VAR_vsphere_password="..."
export PKR_VAR_ssh_password="packer-temp-password"
packer init .
packer build -var-file="../../environments/homelab.pkrvars.hcl" .
```

`homelab.pkrvars.hcl` supplies the vSphere placement values but also sets `image_name = "ubuntu-2604-homelab"` — add `-var image_name=t-ubuntu-2604` after it to keep the standard name.

## Output

A vSphere template `t-ubuntu-2604-<YYYYMMDD-HHmm>` in `vsphere_folder`, plus `packer-manifest.json` in this directory.
