# espocrm role

Runs EspoCRM in Docker behind nginx with TLS, and produces nightly backups that
can actually be restored.

## What you get

- EspoCRM, MariaDB and the scheduled-jobs daemon as containers. Only the
  EspoCRM container publishes a port, and only on the loopback interface
  (`127.0.0.1:8080`); the database and the daemon publish none
- nginx in front, with a Let's Encrypt certificate and HSTS. The role installs
  nginx and certbot and obtains the certificate with `certonly --webroot`,
  deliberately not the nginx plugin: the plugin rewrites the vhost this role
  templates, so each would undo the other. apt's certbot registers its own
  renewal timer, so renewal needs no extra setup
- A nightly `mariadb-dump` plus an archive of uploads and customisations,
  written to `/opt/espocrm/backups/` for the off-box backup to collect

## Before you run it

**1. Point DNS at the server.** Certbot proves ownership over plain HTTP, so
the A record must already resolve or the certificate step fails.

**2. Create the vault file** with the three passwords:

```bash
cd automation/ansible
ansible-vault create inventory/group_vars/espocrm/vault.yml
```

The path matters. `group_vars/espocrm/` is a directory named after the
inventory group, and Ansible loads every file inside it. A file named
`group_vars/espocrm_vault.yml` would be ignored without warning — Ansible would
be looking for a group called `espocrm_vault`.

Put this in it, with your own values:

```yaml
espocrm_db_password: "..."
espocrm_db_root_password: "..."
espocrm_admin_password: "..."
```

Generate them with something like `openssl rand -base64 24`. The role refuses
to run if any is empty — that is deliberate, because the EspoCRM image
otherwise installs with the upstream default password of `password`. It also
refuses any password containing a single quote, because the backup script
assigns the database password inside single quotes; base64 output cannot
contain one, but a password generator with symbols turned on can.

**3. Set the domain** in `inventory/group_vars/espocrm/vars.yml`.

## Running it — on the VPS itself

There is no Ansible controller yet, so Ansible runs *on* the CRM server and
targets localhost. One host, no SSH keys to plumb from Windows, nothing else to
maintain. The `espocrm` inventory group is set to `ansible_connection: local`
for exactly this.

SSH into the VPS, then:

```bash
# 1. Tooling
sudo apt update
sudo apt install -y ansible git

# 2. The repo
sudo git clone https://github.com/IT-Architect-UK/monorepo.git /opt/monorepo
cd /opt/monorepo/automation/ansible

# 3. Collections (community.docker is required and is not bundled)
ansible-galaxy collection install -r requirements.yml

# 4. Secrets — see "Before you run it" above
ansible-vault create inventory/group_vars/espocrm/vault.yml

# 5. Dry run first. Nothing is changed; you see what would be.
#    Docker is installed by the playbook itself - it imports deploy-docker.yml
#    - so there is nothing to run beforehand.
ansible-playbook playbooks/deploy-espocrm.yml --ask-vault-pass --check --diff

# 6. For real
ansible-playbook playbooks/deploy-espocrm.yml --ask-vault-pass
```

The playbook defaults to the `espocrm` group, so no `-l` is needed.

Re-running is safe. It converges: the compose file is rewritten, the stack
brought back to the declared state, nginx reloaded only if its config changed.

### A note on the `--check` run

The dry run will report failures on tasks that depend on earlier ones having
actually happened — the "wait for EspoCRM" check cannot succeed if the
containers were never started. That is expected in check mode and is not a
problem with the playbook. Use it to review the *changes* it proposes, not as a
pass/fail gate.

### Firewall timing

The firewall task applies a default-DROP policy. Because Ansible is running
locally there is no SSH session for it to sever mid-run — but **your own SSH
session will drop if you are not connecting from an address in
`espocrm_ssh_allowed_sources`.** Check that before step 6:

```bash
who am i          # shows the address you came from
```

### Moving to a real controller later

When the toolbox VM or a WSL controller exists, change the `espocrm` group in
`inventory/hosts.yml` from `ansible_connection: local` to a normal SSH target
and run it from there instead. Nothing else in the role changes.

## If the first run does not create the admin user

`ESPOCRM_ADMIN_USERNAME` is a one-time installation variable — the image acts on
it only when the database is empty. If EspoCRM rejects the username (its
allowed-character rules are not documented upstream, and `it-admin` contains a
hyphen), the account simply will not exist and you cannot log in.

While there is no real data, the fix is cheap — wipe and redo:

```bash
cd /opt/espocrm
docker compose down --volumes     # destroys the database. Fine on a fresh install ONLY.
cd /opt/monorepo/automation/ansible
ansible-playbook playbooks/deploy-espocrm.yml --ask-vault-pass
```

Check the container log first to see what it actually objected to:

```bash
docker logs espocrm 2>&1 | tail -40
```

Once there are real customer records in there, this is no longer an option —
change the username inside EspoCRM under Administration > Users instead.

## Restoring a backup

This is the part worth rehearsing before you need it.

```bash
# 1. Stop the app so nothing writes mid-restore. Leave the database up.
docker stop espocrm espocrm-daemon

# 2. Restore the database.
gunzip -c /opt/espocrm/backups/espocrm-db-YYYYmmdd-HHMMSS.sql.gz \
  | docker exec -i espocrm-db mariadb --user=root --password=ROOT_PASSWORD espocrm

# 3. Restore the files.
docker run --rm -v espocrm_espocrm:/dest -v /opt/espocrm/backups:/src:ro alpine:3 \
  tar xzf /src/espocrm-files-YYYYmmdd-HHMMSS.tar.gz -C /dest

# 4. Start it again.
docker start espocrm espocrm-daemon
```

Then clear the cache in Administration, or `docker exec espocrm php clear_cache.php`.

## Upgrading EspoCRM

Image tags are pinned on purpose — an unattended jump across a major version
is how a working CRM breaks overnight. `defaults/main.yml` carries the pins,
but `inventory/group_vars/espocrm/vars.yml` sets `espocrm_image_tag` and
`espocrm_mariadb_tag` too and group_vars win, so that is where to bump them.
To upgrade:

1. Take a backup and confirm it restores
2. Bump `espocrm_image_tag` (and `espocrm_mariadb_tag` if due) in
   `inventory/group_vars/espocrm/vars.yml`
3. Re-run the playbook with `-e espocrm_pull_policy=always`

## Firewall — read before the first run

The role sets an iptables default-DROP policy with:

| Port | Source |
|------|--------|
| 22 (`ssh_port`) | `espocrm_ssh_allowed_sources` only (default: Darren's static IP) |
| `espocrm_public_tcp_ports` (default 80, 443) | anywhere — customers, and Certbot's HTTP-01 challenge |
| ICMP echo | anywhere, if `espocrm_firewall_allow_ping` |

The ACCEPT rules go in first and the DROP policy is set last, so the run
cannot sever its own session partway through. Rules are persisted with
`iptables-persistent` to `/etc/iptables/rules.v4`.

The repo's own `setup-iptables.sh` does not cover this shape: its `strict` mode
restricts every port to `mgmt_subnets`, which would block customers, and its
`baseline` mode leaves SSH open to the internet. Hence the rules live here.

**IPv6 is filtered too.** iptables and ip6tables are separate: a default-DROP
policy on IPv4 alone leaves ip6tables at its default ACCEPT, and SSH would be
reachable over IPv6 from anywhere. When the host has a global IPv6 address
(`espocrm_enable_ipv6`, auto-detected, and the same switch that adds the
`[::]` listeners to nginx) the role also writes an ip6tables ruleset,
persisted to `/etc/iptables/rules.v6`:

| Rule | Detail |
|------|--------|
| ICMPv6 | allowed from anywhere — neighbour discovery and path MTU discovery ride on it; drop it and IPv6 degrades in ways that look like random hangs |
| `espocrm_public_tcp_ports` | allowed from anywhere |
| SSH | **not opened.** The allowed source is an IPv4 address, so there is no v6 source to permit. Administer over IPv4 |
| INPUT, FORWARD | default DROP |

**If your IP changes, you lose SSH.** There is no second way in from the
network. Recover through the OVHcloud control panel — KVM console, or boot into
rescue mode — then add the new address to `espocrm_ssh_allowed_sources` and
re-run. If you are about to change ISP or work from elsewhere regularly, add
that address *before* you need it.

To skip firewall management entirely (for example if you manage rules
elsewhere), set `espocrm_manage_firewall: false`.

## Authentication notes

- Espo's built-in TOTP 2FA is enabled per-user under
  **Administration > Authentication**.
- OIDC (Google / Microsoft sign-in) is configured in the same place and works
  for portal users as well as staff.
- **Espo's own 2FA does not apply to OIDC logins.** If you use OIDC, MFA has to
  be enforced at Google or Microsoft instead. Do not assume ticking Espo's 2FA
  box covers those accounts.

## Backups

The nightly timer only stages files locally. Shipping them off-box is
the off-box backup's job — the pbs-client (Proxmox Backup Server) takes
`/opt/espocrm/backups`, scheduled *after* this timer.

Check it is working:

```bash
systemctl list-timers espocrm-backup.timer
journalctl -u espocrm-backup.service -n 50
ls -lh /opt/espocrm/backups/
```

## Why a dump instead of backing up the volumes directly

MariaDB writes continuously, so a file-level copy of a running database is a
torn snapshot that may not restore. `mariadb-dump --single-transaction` gives a
consistent point in time without locking the CRM while it runs.
