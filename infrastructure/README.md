# Infrastructure

Server, hypervisor, network, identity, and storage automation.

| Directory | Purpose | Docs |
|-----------|---------|------|
| `hypervisors/proxmox/` | Deploy VMs, LXC containers, and templates on Proxmox VE | [README](hypervisors/proxmox/README.md) |
| `hypervisors/vmware/` | vSphere template prep, VM provisioning and host SNMP | [README](hypervisors/vmware/README.md) |
| `hypervisors/hyper-v/` | Placeholder — no scripts yet | — |
| `identity/active-directory/` | AD DS forest install and baseline objects | [README](identity/active-directory/README.md) |
| `networking/` | DNS, NTP, and iptables baseline for Ubuntu servers | [README](networking/README.md) |
| `servers/` | Ubuntu and Windows Server configuration scripts | [README](servers/README.md) |
| `storage/` | LVM disk extension and NFS mounting (`linux/`); `windows/` is a placeholder | [README](storage/README.md) |
