# Ansible Control Node — Packer Build Guide

This guide walks you through building a ready-to-use **Ansible Control Node** VM using Packer and deploying it in your Proxmox home lab.

The control node is the "brain" of your automation setup — it's the one server you SSH into to manage all your other servers. From here you run playbooks to patch servers, deploy Docker containers, configure TLS certificates, set up monitoring, and more.

---

## What You'll End Up With

```
Your Laptop / Desktop
        │
        │  SSH
        ▼
┌─────────────────────────────────┐
│    Ansible Control Node VM      │
│    (built by this Packer job)   │
│                                 │
│  • Ubuntu 24.04 LTS             │
│  • Ansible (latest stable)      │
│  • All playbooks in /opt/ansible│
│  • ansible.cfg pre-configured   │
│  • 'ansible' service account    │
└──────────────┬──────────────────┘
               │  Manages via SSH
       ┌───────┼───────┐
       ▼       ▼       ▼
   web-01   db-01  docker-01  ...
```

---

## Prerequisites

| Requirement | Why | Install |
|---|---|---|
| Packer ≥ 1.10 | Builds the VM | [packer.io/downloads](https://developer.hashicorp.com/packer/downloads) |
| Proxmox VE 8.x | Where the VM is built | Your home lab |
| Ubuntu 24.04 ISO | Uploaded to Proxmox ISO storage | [releases.ubuntu.com](https://releases.ubuntu.com/24.04/) |
| Proxmox API token | Packer authenticates with this | Proxmox UI → Datacenter → API Tokens |

---

## Step 1 — Set Your Credentials

Never put passwords in var files. Use environment variables instead:

```bash
export PKR_VAR_proxmox_url="https://192.168.1.10:8006/api2/json"
export PKR_VAR_proxmox_username="root@pam"
export PKR_VAR_proxmox_password="your-proxmox-password"
export PKR_VAR_ssh_username="packer"
export PKR_VAR_ssh_password="packer-temp-password"
```

> **Tip:** Add these to `~/.bashrc` or use a secrets manager like Vault. The `sensitive = true` flag on these variables means Packer won't print them in logs.

---

## Step 2 — Update Your Var File

Edit `environments/homelab.pkrvars.hcl` and make sure these match your Proxmox setup:

```hcl
proxmox_url         = "https://192.168.1.10:8006/api2/json"
proxmox_node        = "pve"                    # your Proxmox node name
proxmox_storage_pool = "local-lvm"             # where VM disks go
proxmox_iso_storage  = "local"                 # where ISOs are stored
ubuntu_iso_url       = "local:iso/ubuntu-24.04.2-live-server-amd64.iso"
ubuntu_iso_checksum  = "file:local:iso/ubuntu-24.04.2-live-server-amd64.iso.sha256"
```

> **Where to find the ISO path:** In the Proxmox web UI → your node → local storage → ISO Images. The path format is `local:iso/<filename>`.

---

## Step 3 — Install Packer Plugins

Run this once from the `automation/packer/` directory:

```bash
cd automation/packer/
packer init .
```

Packer downloads two plugins:
- `proxmox` — talks to the Proxmox API
- `ansible` — runs Ansible playbooks as provisioners

---

## Step 4 — Validate (No Changes Made)

This checks for syntax errors and confirms all variables are set. Nothing is built yet.

```bash
packer validate \
  -var-file="environments/homelab.pkrvars.hcl" \
  -var-file="environments/ansible-server.pkrvars.hcl" \
  ubuntu-2404-ansible-server-proxmox.pkr.hcl
```

Expected output:
```
The configuration is valid.
```

---

## Step 5 — Build the Image

This takes about 10–15 minutes. Packer will:
1. Create a temporary VM in Proxmox
2. Boot the Ubuntu installer using autoinstall (fully unattended)
3. Run `provision.sh` (OS hardening, UFW, fail2ban, SSH lockdown)
4. Run `provision-ansible-server.sh` (Ansible install + service account setup)
5. Copy all playbooks and roles to `/opt/ansible/`
6. Run `server-baseline.yml` locally (the control node hardens itself)
7. Run `cleanup.sh` (seal the image — remove SSH host keys, machine-id etc.)
8. Convert the VM to a Proxmox template

```bash
PACKER_LOG=1 packer build \
  -var-file="environments/homelab.pkrvars.hcl" \
  -var-file="environments/ansible-server.pkrvars.hcl" \
  ubuntu-2404-ansible-server-proxmox.pkr.hcl 2>&1 | tee packer-build.log
```

> `PACKER_LOG=1` writes verbose output to the log file. Useful for debugging if the build fails.

When it finishes you'll see something like:
```
==> Wait completed after 12 minutes 34 seconds

Build 'ansible-server.proxmox-iso.ansible-server' finished after 12 minutes 34 seconds.

==> Builds finished. The artifacts of successful builds are:
--> ansible-server.proxmox-iso.ansible-server: A template was created: ansible-server-20260622-1430
```

---

## Step 6 — Deploy a VM from the Template

In the Proxmox web UI:
1. Find your template: **ansible-server-YYYYMMDD-HHMM**
2. Right-click → **Clone**
3. Set Mode to **Full Clone**
4. Give it a name like `ansible-01`
5. Click **Clone**, then **Start**

Or from the Proxmox shell:
```bash
qm clone 9001 200 --name ansible-01 --full
qm start 200
```

---

## Step 7 — First Boot: Bootstrap the Control Node

SSH into the new VM (get the IP from Proxmox):

```bash
ssh ubuntu@<vm-ip>
```

Then run the bootstrap script to generate the SSH key:

```bash
sudo -u ansible bash /opt/ansible/bootstrap-control-node.sh
```

This outputs something like:
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[1/3] Generating Ed25519 SSH key pair...
  ✓ Key pair generated

[2/3] Public key (copy this to your managed hosts):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ssh-ed25519 AAAAC3NzaC1... ansible-control-node@ansible-01
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Step 8 — Distribute the SSH Key to Managed Hosts

**Option A — Paste into Proxmox cloud-init (recommended for new VMs)**

When you deploy a new VM from a template in Proxmox:
- VM → Cloud-Init tab → SSH public key → paste the key above
- This means every new VM automatically trusts the control node

**Option B — Use the distribute-ssh-key playbook (for existing VMs)**

From the control node:
```bash
cd /opt/ansible
sudo -u ansible ansible-playbook playbooks/distribute-ssh-key.yml -k
# -k prompts for the managed host password (only needed this first time)
```

---

## Step 9 — Test Connectivity

```bash
cd /opt/ansible
sudo -u ansible ansible all -m ping
```

Expected output for each host:
```
web-01 | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

---

## Step 10 — Run Your First Real Playbook

```bash
cd /opt/ansible
sudo -u ansible ansible-playbook playbooks/server-baseline.yml --limit web_servers
```

---

## File Layout on the Control Node

```
/opt/ansible/
├── ansible.cfg              ← Pre-configured (inventory, roles_path, logging)
├── bootstrap-control-node.sh ← Run once on first boot
├── inventory/
│   ├── hosts.yml            ← Edit this: add your servers
│   └── group_vars/
│       └── all.yml          ← Shared variables across all hosts
├── playbooks/
│   ├── server-baseline.yml  ← Harden + configure a fresh server
│   ├── deploy-docker.yml    ← Install Docker
│   ├── configure-tls.yml    ← Let's Encrypt / TLS setup
│   ├── deploy-monitoring.yml ← Prometheus node_exporter
│   ├── setup-backup-restic.yml ← Restic backup
│   ├── patch-and-reboot.yml ← Safe rolling patch + reboot
│   └── distribute-ssh-key.yml ← Push control node key to managed hosts
└── roles/
    ├── common/              ← Base OS hardening (applied by server-baseline)
    ├── tls/                 ← TLS certificate management
    ├── monitoring-agent/    ← Prometheus node_exporter
    └── backup-restic/       ← Restic backup jobs
```

---

## Editing the Inventory

Before running playbooks, update `/opt/ansible/inventory/hosts.yml` with your servers:

```yaml
all:
  children:
    web_servers:
      hosts:
        web-01:
          ansible_host: 192.168.1.101
        web-02:
          ansible_host: 192.168.1.102
    db_servers:
      hosts:
        db-01:
          ansible_host: 192.168.1.110
```

---

## Common Commands Cheat Sheet

```bash
# Test all hosts are reachable
sudo -u ansible ansible all -m ping

# Run a playbook on all web servers
sudo -u ansible ansible-playbook playbooks/server-baseline.yml --limit web_servers

# Dry-run (check mode — no changes made)
sudo -u ansible ansible-playbook playbooks/patch-and-reboot.yml --check

# Run with verbose output (shows every task)
sudo -u ansible ansible-playbook playbooks/deploy-docker.yml -v

# View all gathered facts for a host
sudo -u ansible ansible web-01 -m setup

# Run an ad-hoc command on all servers
sudo -u ansible ansible all -m shell -a "uptime"
```

---

## Troubleshooting

| Problem | Likely Cause | Fix |
|---|---|---|
| `packer build` fails at SSH timeout | Autoinstall took longer than expected | Increase `ssh_timeout` in the template |
| `Permission denied (publickey)` when running playbooks | Key not distributed to managed host | Re-run `distribute-ssh-key.yml` with `-k` |
| `ansible: command not found` | Not running as the ansible user | Use `sudo -u ansible ansible-playbook ...` |
| Packer fails at `proxmox-iso` with 401 | Wrong credentials | Check `PKR_VAR_proxmox_password` env var |
| `UNREACHABLE` for a host | VM not started, wrong IP | Check `ansible_host` in inventory; test with `ping <ip>` |

---

## Next Steps

Once your control node is running and all hosts respond to `ansible all -m ping`, try these playbooks in order:

1. `server-baseline.yml` — harden all your servers
2. `deploy-docker.yml` — install Docker on your Docker hosts
3. `configure-tls.yml` — get Let's Encrypt certificates for your web services
4. `deploy-monitoring.yml` — install Prometheus node_exporter on all servers
5. `setup-backup-restic.yml` — automated encrypted backups to local disk or S3
