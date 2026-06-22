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
├── playbooks/              # What to do
│   ├── server-baseline.yml      # Harden and configure new servers
│   ├── deploy-docker.yml        # Install Docker Engine
│   ├── configure-tls.yml        # Install Let's Encrypt certificates
│   ├── deploy-monitoring.yml    # Deploy Prometheus node_exporter
│   ├── setup-backup-restic.yml  # Configure Restic encrypted backups
│   └── patch-and-reboot.yml     # Apply OS patches safely
│
├── inventory/              # Where to do it (which servers)
│   ├── hosts.yml                # Server inventory — IPs and groups
│   └── group_vars/
│       └── all.yml              # Default variables for all servers
│
└── roles/                  # Reusable task libraries
    ├── common/              # Base OS configuration (called by server-baseline)
    ├── tls/                 # TLS certificate management
    ├── monitoring-agent/    # Prometheus node_exporter
    └── backup-restic/       # Restic backup configuration
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

### 3. Set your variables

Open `inventory/group_vars/all.yml` and review the defaults. At minimum, change:
- `admin_user` — the non-root user Ansible will create
- `restic_password` — use Ansible Vault for this (see Security section below)

### 4. Test connectivity

```bash
# Test that Ansible can reach all servers
ansible all -i inventory/hosts.yml -m ping
```

You should see `"ping": "pong"` for each server.

### 5. Run your first playbook

```bash
# Apply baseline configuration to all servers
ansible-playbook -i inventory/hosts.yml playbooks/server-baseline.yml

# Apply to a specific group only
ansible-playbook -i inventory/hosts.yml playbooks/server-baseline.yml --limit web_servers

# Dry run — show what would change without making changes
ansible-playbook -i inventory/hosts.yml playbooks/server-baseline.yml --check
```

## 🔐 Security — Ansible Vault

Never store passwords in plain text. Use Ansible Vault to encrypt secrets:

```bash
# Encrypt a single value (paste the output into your vars file)
ansible-vault encrypt_string 'my-super-secret-password' --name 'restic_password'

# Encrypt an entire file
ansible-vault encrypt inventory/group_vars/secrets.yml

# Edit an encrypted file
ansible-vault edit inventory/group_vars/secrets.yml

# Run a playbook with vault (prompts for vault password)
ansible-playbook -i inventory/hosts.yml playbooks/setup-backup-restic.yml --ask-vault-pass
```

## 📋 Playbook Reference

| Playbook | Purpose | Typical use |
|----------|---------|-------------|
| `server-baseline.yml` | Initial server hardening | Run once after provisioning |
| `deploy-docker.yml` | Install Docker + Compose | Run on container hosts |
| `configure-tls.yml` | Let's Encrypt certificate | Run on web servers |
| `deploy-monitoring.yml` | Prometheus node_exporter | Run on all servers |
| `setup-backup-restic.yml` | Restic encrypted backup | Run on all servers |
| `patch-and-reboot.yml` | OS patching | Run monthly or for CVEs |

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
→ Some tasks use community modules. Install them:
  `ansible-galaxy collection install community.general`

**Playbook makes changes every run (not idempotent)?**
→ Check tasks for `command:` or `shell:` modules — these always report "changed".
→ Add `changed_when: false` or use a more specific module.
