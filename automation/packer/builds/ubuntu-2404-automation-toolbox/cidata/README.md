# cidata ISO — pre-built

`ubuntu-2404-cidata.iso` is a pre-built cloud-init NoCloud seed ISO, committed
here so it's available directly from GitHub — no local build tools (WSL,
`dosfstools`, `mtools`) required before running a build.

It contains exactly two files, copied byte-for-byte from `../../../http/`:

| File in ISO | Source |
|---|---|
| `user-data` | `automation/packer/http/user-data` |
| `meta-data` | `automation/packer/http/meta-data` |

Volume label: `cidata` (required by cloud-init's NoCloud datasource).

## Using it

Upload this file to your Proxmox storage pool at the path expected by
`cidata_iso_file` in `../variables.pkr.hcl` (default:
`NFS-10GB-PROXMOX-1:iso/ubuntu-2404-cidata.iso`). This is a one-time step per
Proxmox host/storage pool — the file itself doesn't need to change unless
`http/user-data` or `http/meta-data` changes.

## Rebuilding after a `user-data` / `meta-data` change

If you edit `automation/packer/http/user-data` or `meta-data`, this ISO is
now stale and must be rebuilt and re-uploaded. On any Linux machine:

```bash
cd automation/packer/http
genisoimage -output ubuntu-2404-cidata.iso -volid cidata -joliet -rock user-data meta-data
mv ubuntu-2404-cidata.iso ../builds/ubuntu-2404-automation-toolbox/cidata/
```

(`apt-get install -y genisoimage` if you don't have it.) Commit the
regenerated file, then re-upload it to Proxmox to replace the stale copy.
