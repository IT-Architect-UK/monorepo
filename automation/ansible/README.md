# Ansible — Infrastructure Automation

Ansible automates repetitive IT tasks: server configuration, software deployment, patch management, and more. It is agentless — it connects to servers over SSH, runs tasks, and disconnects. No software needs to be installed on managed servers.

## 🤔 Why Ansible?

| Manual approach | With Ansible |
|----------------|-------------|
| SSH to each server, run commands | Define once, run on 1 or 1000 servers |
| Hope you remembered every step | Playbook documents every step |
| Hard to repeat exactly | Idempotent — run twice, same result |
| No audit trail | Full task logs, git history |

### Cloud equivalents

| Ansible | AWS | Azure | GCP |
|---------|-----|-------|-----|
| Playbooks | Systems Manager (SSM) Run Command | Azure Automation / DSC | OS Config / Ansible Tower |
| Roles | SSM State Manager Associations | Policy + Extensions | VM Manager |
| Inventory | EC2 dynamic inventory | Azure dynamic inventory | GCP dynamic inventory |

## 📁 Folder Structure

```
ansible/
├── ansible.cfg             # roles_path and inventory, relative — run Ansible from this directory
├── requirements.yml        # Galaxy collections the roles need
├── .env.example            # Site values for CLI runs (copy to .env — git-ignored)
├── .yamllint               # Extends the repo-root config; ansible-lint config is /.ansible-lint
│
├── inventory/              # Where to do it (which servers)
│   ├── hosts.yml                # Groups and hosts — example IPs; the VPS groups target localhost
│   └── group_vars/
│       ├── all.yml              # Defaults for every host (admin user, SSH, firewall, packages)
│       ├── standard.yml         # "The standard build" toggles applied by provision-vm.yml
│       ├── espocrm/             # vars.yml in Git, vault.yml encrypted (see Vault below)
│       ├── meshcentral/         # vars.yml only — no secrets to keep
│       └── n8n/                 # vars.yml in Git, vault.yml encrypted
│
├── playbooks/              # What to do — 23 playbooks, all listed below and in playbooks/README.md
│   ├── server-baseline.yml, provision-vm.yml, patch-and-reboot.yml, deploy-*.yml, configure-*.yml, ...
│   └── includes/                # Task files shared between playbooks
│       ├── register-in-inventory.yml    # Semaphore inventory registration, looped by provision-vm.yml
│       └── windows/                     # backup, branding, chocolatey, disks
│
└── roles/                  # Reusable task libraries — one README each (see Roles below)
    ├── common/              # Baseline: packages, timezone, SSH, iptables, fail2ban
    ├── swapfile/            # Swap file where a host has none
    ├── tls/                 # Legacy Certbot role (--nginx/--apache plugin)
    ├── monitoring-agent/    # Prometheus node_exporter
    ├── webmin/              # Webmin, optionally behind nginx + Let's Encrypt
    ├── vitals/              # Host snapshot for the dashboard's monitoring page
    ├── oauth2-proxy/        # Microsoft Entra sign-in in front of the admin pages
    ├── espocrm/             # CRM in Docker behind nginx; owns the VPS firewall
    ├── n8n/                 # n8n + Postgres, the dashboard host, guide and vitals feed
    ├── meshcentral/         # Remote-support server
    └── microsoft/           # Not a role: two one-line collection-install notes, no tasks
```

## 🚀 Getting Started

### 1. Install Ansible

```bash
# Ubuntu / Debian
sudo apt update && sudo apt install -y ansible

# macOS
brew install ansible

# pip (any platform)
pip3 install ansible
```

### 2. Edit the inventory

Open `inventory/hosts.yml` and replace the example IPs with your server addresses:

```yaml
web_servers:
  hosts:
    web01:
      ansible_host: 192.168.1.11   # ← change this to your server's IP
```

### 3. Install the collections

```bash
ansible-galaxy collection install -r requirements.yml
```

### 4. Set your variables

Open `inventory/group_vars/all.yml` and review the defaults. At minimum, change:
- `admin_user` — the non-root user Ansible will create

Private network detail (your trusted subnets) is **not** stored in the repo.
For CLI runs, copy `.env.example` to `.env`, edit it, and `source .env` before
running a playbook. On the Deployment Toolbox the same values come from
Semaphore's *Proxmox* variable group and are set during the toolbox build.
See [Firewall](#-firewall) below.

### 5. Test connectivity

```bash
# Test that Ansible can reach all servers
ansible all -i inventory/hosts.yml -m ping
```

You should see `"ping": "pong"` for each server.

### 6. Run your first playbook

Run from `automation/ansible/`: `ansible.cfg` resolves `roles_path` and the
inventory relative to the directory Ansible is started in, so a run from
`playbooks/` finds neither.

```bash
# Apply baseline configuration to all servers
ansible-playbook -i inventory/hosts.yml playbooks/server-baseline.yml

# Apply to a specific group only
ansible-playbook -i inventory/hosts.yml playbooks/server-baseline.yml --limit web_servers

# Dry run — show what would change without making changes
ansible-playbook -i inventory/hosts.yml playbooks/server-baseline.yml --check
```

## 🔥 Firewall

The `common` role applies the repo's iptables baseline
(`infrastructure/networking/firewall/setup-iptables.sh`) to every host it
builds. `configure-iptables.yml` applies the same script standalone.

**Default (baseline) mode** — SSH from anywhere, ICMP from RFC-1918 ranges,
and every port from the trusted subnets. **Strict mode** — only the listed
ports, only from the management subnets (setting `firewall_mgmt_subnets`
switches to strict).

| Variable (`group_vars/all.yml`) | Source | Meaning |
|---|---|---|
| `firewall_trusted_subnets` | `TRUSTED_SUBNETS` env var (`.env` locally, Semaphore on the toolbox) | Comma-separated CIDRs that get every port. Empty = SSH + ICMP only. |
| `firewall_mgmt_subnets` | inventory | Strict mode: the only source CIDRs allowed at all |
| `firewall_allowed_tcp_ports` | inventory | Strict mode: the only TCP ports opened. Defaults to the SSH port; if you set it, include SSH yourself |
| `firewall_extra_rules` | inventory (per group or host) | Extra ACCEPTs on top of the baseline in either mode, e.g. `- { port: 10000, source: "192.168.4.0/24" }`. `proto` defaults to `tcp`, `source` to anywhere. |

How re-applies work:

- The role writes the script to `/usr/local/sbin/setup-iptables.sh` and records
  a fingerprint of the script plus the effective variables in
  `/etc/iptables/.baseline-fingerprint`. The ruleset is re-applied only when
  that fingerprint changes, so a routine run does not flush a working firewall
  and the play reports `changed` only when it actually did something.
- Rules declared in `firewall_extra_rules` are part of the baseline and survive
  every re-apply. Rules added by hand on the host belong in the `LOCAL-INPUT`
  chain, which the script preserves across re-applies; anything added by hand
  directly to `INPUT` is lost on the next apply.
- The ruleset is persisted with `iptables-persistent`.

Never commit real CIDRs: `.env` is git-ignored and `.env.example` carries
only placeholders.

## 🔐 Security — Ansible Vault

Never store passwords in plain text. Secrets for a group live in an encrypted
file inside a directory named after that group:

| Path | Loaded? |
|---|---|
| `inventory/group_vars/<group>/vault.yml` | Yes. Every file in a directory named after a group is loaded, so `vars.yml` (plain, in Git) and `vault.yml` (encrypted) sit side by side |
| `inventory/group_vars/<group>_vault.yml` | **No.** Ansible would be looking for a group called `<group>_vault`, and says nothing |

`espocrm/` and `n8n/` use this layout (`meshcentral/` has no secrets to keep).
The roles assert that their secrets are present, so a missing vault file fails
the run rather than deploying with a default password.

```bash
# Create the vault file for a group
ansible-vault create inventory/group_vars/n8n/vault.yml

# Edit it later
ansible-vault edit inventory/group_vars/n8n/vault.yml

# Encrypt a single value to paste into a vars file instead
ansible-vault encrypt_string 'my-super-secret-password' --name 'some_password'

# Run a playbook that reads a vault file (prompts for the vault password)
ansible-playbook playbooks/deploy-n8n.yml --ask-vault-pass
```

The vault password, and a copy of every secret in the vault, belong in
Bitwarden.

## 📋 Playbook Reference

### Server lifecycle

| Playbook | Purpose | When to run |
|----------|---------|-------------|
| `provision-vm.yml` | Create a VM on Proxmox from a template | New server |
| `server-baseline.yml` | Initial server hardening | Once after provisioning |
| `distribute-ssh-key.yml` | Push an SSH key to managed hosts | Onboarding a new admin |
| `patch-and-reboot.yml` | OS patching | Monthly, or for a CVE |
| `ita-linux-customisations.yml` | House customisations (Linux): branding, IPv6 policy, timezone | Build time |

### Platform services

| Playbook | Purpose | When to run |
|----------|---------|-------------|
| `deploy-docker.yml` | Install Docker + Compose | Container hosts |
| `configure-tls.yml` | Let's Encrypt certificate | Web servers |
| `configure-iptables.yml` | Firewall ruleset | Any host |
| `configure-fail2ban.yml` | SSH brute-force protection | Any host |
| `deploy-monitoring.yml` | Prometheus node_exporter | All servers |
| `deploy-webmin.yml` | Webmin administration UI | Where a GUI is wanted |
| `deploy-vault.yml` | HashiCorp Vault | Secrets host |
| `deploy-webmin-vps.yml` | Webmin behind nginx on its own hostname, port 10000 closed | The VPS |
| `deploy-vitals.yml` | Host snapshot script and timer for the dashboard's monitoring page | The VPS |
| `deploy-auth.yml` | oauth2-proxy: Microsoft sign-in in front of the admin pages | The VPS, before `deploy-n8n.yml` |

### Business systems

These run the live business. See the role READMEs for what each one does and
how to restore it.

| Playbook | Purpose | When to run |
|----------|---------|-------------|
| `deploy-espocrm.yml` | EspoCRM in Docker behind nginx, with nightly restorable backups | CRM host |
| `deploy-n8n.yml` | n8n + Postgres behind nginx — runs the booking pipeline; also the dashboard host, the admin guide copy and the vitals feed | Automation host |
| `deploy-meshcentral.yml` | MeshCentral remote-support server behind nginx; adds swap first | Remote-help host |

### Windows

| Playbook | Purpose | When to run |
|----------|---------|-------------|
| `windows-baseline.yml` | Windows hardening baseline | Once after provisioning |
| `install-windows-apps.yml` | Application install via Chocolatey | Build time |
| `configure-windows-disks.yml` | Disk initialisation and layout | Build time |
| `configure-windows-backup.yml` | Windows Server Backup | Build time |
| `ita-windows-customisations.yml` | House customisations (Windows) | Build time |

## 🧱 Roles

One README per role, next to its tasks.

| Role | What it does | README |
|------|--------------|--------|
| `common` | The baseline every Linux host gets: packages, timezone and NTP, SSH hardening, the fingerprinted iptables baseline, fail2ban, optional branding/IPv6/monorepo clone/admin user. No `defaults/`: everything comes from `group_vars/all.yml` | [roles/common](roles/common/README.md) |
| `swapfile` | Creates `/swapfile` only on a host with no swap; sets swappiness | [roles/swapfile](roles/swapfile/README.md) |
| `tls` | Legacy Certbot role using the `--nginx`/`--apache` plugin, which rewrites the vhost. The live roles use `certonly --webroot` instead | [roles/tls](roles/tls/README.md) |
| `monitoring-agent` | Prometheus node_exporter on port 9100 | [roles/monitoring-agent](roles/monitoring-agent/README.md) |
| `webmin` | Webmin from its official apt repository (pinned, checksummed setup script); with `webmin_domain` set, nginx + Let's Encrypt + basic auth in front so port 10000 stays closed | [roles/webmin](roles/webmin/README.md) |
| `vitals` | Timer-driven host snapshot (`/opt/vitals/vitals.json`) that the dashboard's monitoring page reads | [roles/vitals](roles/vitals/README.md) |
| `oauth2-proxy` | One Microsoft Entra sign-in for every admin page, via nginx `auth_request` | [roles/oauth2-proxy](roles/oauth2-proxy/README.md) |
| `espocrm` | EspoCRM + MariaDB in Docker behind nginx, nightly backups; owns the firewall on the VPS | [roles/espocrm](roles/espocrm/README.md) |
| `n8n` | n8n + Postgres behind nginx, the dashboard host, admin guide copy, vitals feed, nightly backups | [roles/n8n](roles/n8n/README.md) |
| `meshcentral` | MeshCentral remote-support server behind nginx, nightly backups | [roles/meshcentral](roles/meshcentral/README.md) |
| `microsoft` | Not a role. Two one-line notes (`adds/`, `chocolatey/`) giving the `ansible-galaxy collection install` command for the Windows collections; no tasks | — |

## 🧩 Useful Commands

```bash
# List all hosts in inventory
ansible all -i inventory/hosts.yml --list-hosts

# List all tasks a playbook will run (without running them)
ansible-playbook playbooks/server-baseline.yml --list-tasks

# Run only tasks tagged 'ssh'
ansible-playbook -i inventory/hosts.yml playbooks/server-baseline.yml --tags ssh

# Skip tasks tagged 'packages'
ansible-playbook -i inventory/hosts.yml playbooks/server-baseline.yml --skip-tags packages

# Run ad-hoc command on all servers
ansible all -i inventory/hosts.yml -m command -a "uptime"

# Run ad-hoc command on one group
ansible web_servers -i inventory/hosts.yml -m shell -a "df -h /"
```

## ❓ Troubleshooting

**SSH connection refused?**
→ Ensure the target server is running and SSH is accessible.
→ Test manually: `ssh sysadmin@192.168.1.11`

**"sudo: a password is required"?**
→ Configure passwordless sudo for the Ansible user, or add `--ask-become-pass` to the command.

**Module not found errors?**
→ The roles use community collections. Install them all:
  `ansible-galaxy collection install -r requirements.yml`

**Playbook makes changes every run (not idempotent)?**
→ Check tasks for `command:` or `shell:` modules — these always report "changed".
→ Add `changed_when: false` or use a more specific module.
