# Ansible Playbooks

Each playbook is self-contained and documented. Run with:

```bash
ansible-playbook -i ../inventory/hosts.yml <playbook>.yml
```

| Playbook | Purpose |
|----------|---------|
| `provision-vm.yml` | Create a new VM on Proxmox by cloning a template; reports its IP and optionally applies the standard build (`group_vars/standard.yml`) |
| `deploy-vault.yml` | Install HashiCorp Vault on a target server (the toolbox's standalone secrets VM) |
| `ita-linux-customisations.yml` | Subjective OS settings, individually chosen: branding, IPv6 policy, timezone |
| `configure-iptables.yml` | iptables ruleset — baseline or strict mode, explicit and standalone |
| `configure-fail2ban.yml` | fail2ban SSH brute-force protection, tunable retry/ban settings |
| `deploy-webmin.yml` | Install Webmin on any provisioned server |
| `server-baseline.yml` | Initial hardening — run once on every new server |
| `deploy-docker.yml` | Install Docker Engine + Compose |
| `configure-tls.yml` | Let's Encrypt certificate via Certbot |
| `deploy-monitoring.yml` | Prometheus node_exporter agent |
| `setup-backup-restic.yml` | Restic encrypted backup with systemd timer |
| `patch-and-reboot.yml` | Rolling OS patch + reboot (one server at a time) |

Add `--check` to any command for a dry run. Add `--limit <group>` to target a subset of hosts.
