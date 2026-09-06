# Ansible Playbooks

Run every playbook from `automation/ansible/`, not from this directory.
`ansible.cfg` there sets `roles_path` and the inventory relative to the
directory Ansible is started in, so a run from anywhere else finds neither.

```bash
cd automation/ansible
ansible-playbook playbooks/<playbook>.yml
```

Add `--check --diff` for a dry run, `--limit <group>` to target a subset of
hosts, and `--ask-vault-pass` for the playbooks that read a vault file. The
standalone playbooks take `-e target_host=<ip>` for a single host; each
header lists its variables.

## Server lifecycle

| Playbook | Purpose |
|----------|---------|
| `provision-vm.yml` | Create a VM on Proxmox by cloning a template, size and start it; optionally applies the standard build (`group_vars/standard.yml`) and registers the VM in a Semaphore inventory |
| `server-baseline.yml` | The default Linux build: the `common` role, plus Webmin when `standard_webmin` is true. Run once on every new server |
| `distribute-ssh-key.yml` | Push the control node's public SSH key to managed hosts (`-k` for the one password prompt) |
| `patch-and-reboot.yml` | Rolling OS patch and reboot, one server at a time (`serial: 1`) |
| `ita-linux-customisations.yml` | Subjective OS settings, individually chosen: branding, IPv6 policy, timezone |

## Platform services

| Playbook | Purpose |
|----------|---------|
| `deploy-docker.yml` | Docker Engine + Compose v2 from Docker's own repository |
| `configure-tls.yml` | Let's Encrypt certificate via the legacy `tls` role (Certbot's nginx/apache plugin) |
| `configure-iptables.yml` | The repo's iptables ruleset, baseline or strict mode, standalone |
| `configure-fail2ban.yml` | fail2ban SSH brute-force protection, tunable retry/ban settings |
| `deploy-monitoring.yml` | Prometheus node_exporter agent |
| `deploy-webmin.yml` | Webmin on a provisioned VM reachable over SSH (port 10000) |
| `deploy-webmin-vps.yml` | Webmin on the VPS, behind nginx on its own hostname so port 10000 stays closed |
| `deploy-vitals.yml` | The host snapshot script and its timer, read by the dashboard's monitoring page |
| `deploy-auth.yml` | oauth2-proxy, the Microsoft sign-in in front of the admin pages. Run before `deploy-n8n.yml` |
| `deploy-vault.yml` | HashiCorp Vault on a target server (the toolbox's standalone secrets VM) |

## Business systems

These run the live IT Surgery platform. Ansible runs on the VPS itself and
targets localhost; see the role READMEs.

| Playbook | Purpose |
|----------|---------|
| `deploy-espocrm.yml` | EspoCRM + MariaDB in Docker behind nginx, nightly backups. Imports `deploy-docker.yml` first and owns the VPS firewall |
| `deploy-n8n.yml` | n8n + Postgres behind nginx, the dashboard host, the admin guide copy and nightly backups |
| `deploy-meshcentral.yml` | MeshCentral remote-support server behind nginx. Runs the `swapfile` role first |

## Windows (WinRM)

| Playbook | Purpose |
|----------|---------|
| `windows-baseline.yml` | The Windows default build: disks, Chocolatey + standard apps, branding, Windows Server Backup feature |
| `configure-windows-disks.yml` | Extend C:, CD/DVD to Z:, data disk to D: |
| `install-windows-apps.yml` | Chocolatey + standard apps (`win_choco_packages`) |
| `configure-windows-backup.yml` | Windows Server Backup feature, optional daily schedule |
| `ita-windows-customisations.yml` | Branding: registered organisation and logon notice |

## includes/

Task files shared between playbooks, not runnable on their own.

| File | Used by |
|------|---------|
| `register-in-inventory.yml` | `provision-vm.yml`, looped once per Semaphore inventory the new VM joins |
| `windows/disks.yml`, `windows/chocolatey.yml`, `windows/branding.yml`, `windows/backup.yml` | `windows-baseline.yml`, and one each by the four individual Windows playbooks above |
