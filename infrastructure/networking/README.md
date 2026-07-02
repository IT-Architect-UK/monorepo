# Networking

Baseline network configuration for Ubuntu servers (22.04+, systemd-based). All are used by the server-baseline flow (`infrastructure/servers/linux/configuration/server-baseline.sh`) and can be run standalone. Usage details in each script's header.

| Script | Purpose |
|--------|---------|
| `dns/dns-default-gateway.sh` | Set the DNS server on all active interfaces via `resolvectl` (defaults to the default gateway) |
| `ntp/setup-ntp.sh` | Point `systemd-timesyncd` at an NTP server (defaults to the default gateway) |
| `firewall/setup-iptables.sh` | Defence-in-depth iptables baseline: SSH + ICMP + RFC-1918 allowed, persisted with `iptables-persistent` |

```bash
sudo ./<area>/<script>.sh
```
