# Ansible Playbooks

Each playbook is self-contained and documented. Run with:

```bash
ansible-playbook -i ../inventory/hosts.yml <playbook>.yml
```

| Playbook | Purpose |
|----------|---------|
| `provision-vm.yml` | Create a new VM on Proxmox by cloning a template (API-driven, no SSH needed) |
| `deploy-vault.yml` | Install HashiCorp Vault on a target server (the toolbox's standalone secrets VM) |
| `server-baseline.yml` | Initial hardening — run once on every new server |
| `deploy-docker.yml` | Install Docker Engine + Compose |
| `configure-tls.yml` | Let's Encrypt certificate via Certbot |
| `deploy-monitoring.yml` | Prometheus node_exporter agent |
| `setup-backup-restic.yml` | Restic encrypted backup with systemd timer |
| `patch-and-reboot.yml` | Rolling OS patch + reboot (one server at a time) |

Add `--check` to any command for a dry run. Add `--limit <group>` to target a subset of hosts.
