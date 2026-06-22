# Proxmox — LXC Container Deployment

LXC containers are significantly lighter than full VMs. They share the Proxmox host's Linux kernel, which means they boot in seconds and use a fraction of the RAM.

## When to Use LXC vs a Full VM

| Situation | Use LXC | Use VM |
|-----------|---------|--------|
| Running a Linux web/database server | ✅ | |
| Running Windows | | ✅ |
| Need to run Docker inside the guest | | ✅ (unprivileged LXC has limitations) |
| Maximum container density on the host | ✅ | |
| Need complete OS isolation | | ✅ |
| DNS, monitoring agent, Nginx proxy | ✅ | |

## Scripts

| Script | What it does |
|--------|-------------|
| `deploy-ubuntu-lxc.sh` | Creates a new Ubuntu 24.04 LXC container |
| `lxc-baseline.sh` | Applies OS hardening and baseline configuration |

## Usage

```bash
# Minimal container (good for lightweight services)
./deploy-ubuntu-lxc.sh -i 300 -n "pihole" -m 256 -d 4

# Monitoring container
./deploy-ubuntu-lxc.sh -i 301 -n "monitoring" -m 1024 -d 20 -c 2

# Enter a running container's shell
pct enter 300

# Stop / start a container
pct stop 300
pct start 300
```
