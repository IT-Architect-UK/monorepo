# http/ — Unattended-install answer files

Despite the directory name, nothing here is served over HTTP any more. Every template attaches these files as a virtual CD (`cd_files` / `cd_content`) or, for the automation toolbox, as a pre-built ISO.

## Ubuntu autoinstall — `user-data` + `meta-data`

A cloud-init **NoCloud** seed for Ubuntu's `autoinstall`. Attached as a CD labelled `cidata` by `ubuntu-2404-proxmox`, `ubuntu-2604-proxmox` and `ubuntu-2604-vmware`; the toolbox uses the same two files baked into `builds/ubuntu-2404-automation-toolbox/cidata/ubuntu-2404-cidata.iso`.

What `user-data` does:

| Setting | Value |
|---------|-------|
| Locale / keyboard | `en_GB.UTF-8`, `gb` |
| Network | DHCP on every `en*` interface |
| Storage | `direct` layout — single root partition on the first disk |
| Identity | hostname `packer-build`, user **`packer`** with the SHA-512 hash of `packer-temp-password` |
| SSH | server installed, password auth allowed for the build (`provision.sh` hardens it afterwards) |
| Packages | `qemu-guest-agent` only — everything else is `provision.sh`'s job |
| `updates` | `security` (the minimum the key allows) |
| Late commands | passwordless sudo for `packer` (`/etc/sudoers.d/packer`), enable `qemu-guest-agent` |

`meta-data` holds only `instance-id: packer-build-instance`, which NoCloud requires.

### The password contract

The `ssh_password` variable in each Ubuntu template must be the plaintext of the hash in `user-data`. The three Proxmox templates default it to `packer-temp-password`; `ubuntu-2604-vmware` has no default and needs `PKR_VAR_ssh_password`. To change the password:

```bash
openssl passwd -6 "new-password"      # paste the result into user-data
```

then set `PKR_VAR_ssh_password` (or the variable default) to match, **and rebuild the toolbox cidata ISO** — `builds/ubuntu-2404-automation-toolbox/cidata/ubuntu-2404-cidata.iso` is a committed copy of these two files and goes stale the moment either changes. The rebuild command is in [`builds/ubuntu-2404-automation-toolbox/cidata/README.md`](../builds/ubuntu-2404-automation-toolbox/cidata/README.md); commit the new ISO and re-upload it to Proxmox.

## Windows — `win2025-proxmox/autounattend.xml` and `win2025-vmware/autounattend.xml`

Windows Setup answer files, one per hypervisor, delivered as a CD labelled `autounattend` via `cd_content`. Both partition the disk (EFI + MSR + Windows), create the `packer` local administrator, auto-log it on and enable WinRM on 5985 so Packer can connect. Neither contains a password: the template substitutes placeholders at build time, so the values live only in `PKR_VAR_*` variables.

| Placeholder | Replaced with | Proxmox | VMware |
|-------------|---------------|---------|--------|
| `WINRM_PASSWORD_PLACEHOLDER` | `var.winrm_password` — the `packer` account's password and the built-in Administrator's until first boot | yes | yes |
| `WINDOWS_IMAGE_INDEX` | `var.windows_image_index` — `install.wim` index (`/IMAGE/INDEX`) | yes | no — selects by `/IMAGE/NAME`, `Windows Server 2025 Standard Evaluation (Desktop Experience)`, edited in the XML |

Other differences: the Proxmox file targets the SATA disk + e1000 NIC the build uses (in-box drivers, so no VirtIO injection) and omits the deprecated `SkipMachineOOBE` / `SkipUserOOBE` flags, which break OOBE on Server 2025; the VMware file still sets them and relies on the in-box `pvscsi` / `vmxnet3` drivers.

Keep the `packer` username in sync with `winrm_username` if you change either.
