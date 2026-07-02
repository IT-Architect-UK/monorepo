# Storage

Linux storage operations for Ubuntu servers. Usage details in each script's header.

| Script | Purpose |
|--------|---------|
| `linux/extend-disks.sh` | Grow an LVM logical volume into all unallocated space on the OS disk (after enlarging a virtual disk) |
| `linux/mount-nfs-volume.sh` | Mount an NFS share, optionally persisted in `/etc/fstab` |

```bash
sudo ./linux/extend-disks.sh      # after growing the disk in the hypervisor
```
