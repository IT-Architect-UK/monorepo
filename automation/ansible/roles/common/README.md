# common role

The baseline every managed Linux host gets. `server-baseline.yml` applies it,
and `provision-vm.yml` applies that when asked for the standard build. The
role has no `defaults/` directory: every variable comes from
`inventory/group_vars/all.yml`, with the flavour toggles overridden by
`inventory/group_vars/standard.yml` for the standard build.

## What it does

| Step | Tag | Detail |
|------|-----|--------|
| Packages | `packages` | `apt update` (cache valid for an hour), install `common_packages` (curl, git, htop, jq, fail2ban, ...), then `upgrade: safe` |
| Time | `timezone`, `ntp` | `system_timezone` via `community.general.timezone`; `ntp_servers` templated into `/etc/systemd/timesyncd.conf` |
| Admin user | `users` | Creates `admin_user` in `admin_groups` — only when `baseline_create_admin` is true. Off by default: logins arrive per clone via cloud-init, and a baked-in account conflicts with that |
| SSH | `ssh` | Templates `/etc/ssh/sshd_config`, validated with `sshd -t` before it lands: key-only, no root login, `MaxAuthTries 3`, no agent/TCP/X11 forwarding, idle sessions dropped after ten minutes. `ssh_port` and `ssh_password_auth_users` (accounts allowed a password, as `Match User` blocks) are the two variables the template reads |
| Firewall | `firewall` | The repo's iptables baseline, below — when `baseline_firewall` is true |
| fail2ban | `security` | Writes `/etc/fail2ban/jail.local` (`fail2ban_bantime`, `fail2ban_findtime`, `fail2ban_maxretry`; defaults 3600 / 600 / 5; `[sshd]` on `ssh_port`) and starts the service — when `baseline_fail2ban` is true |
| Branding | `branding` | Runs `infrastructure/servers/linux/configuration/apply-branding.sh` with `branding_company` (default `IT-Architect`) — when `baseline_branding` is true |
| IPv6 | `ipv6` | Runs `disable-ipv6.sh` from the same directory — when `baseline_disable_ipv6` is true |
| Monorepo | `monorepo` | Runs `sync-monorepo.sh` to keep a clone of this repo on the host — when `baseline_monorepo_clone` is true |

The three optional steps reuse the standalone scripts from `infrastructure/`,
so the result is identical to running them by hand.

Handlers: `Restart SSH`, `Restart timesyncd`, `Restart fail2ban`.

## Firewall

The modes, rules and variables (`firewall_trusted_subnets`,
`firewall_mgmt_subnets`, `firewall_allowed_tcp_ports`, `firewall_extra_rules`)
are documented once, in the
[Firewall section of the Ansible README](../../README.md#-firewall). What the
role does with them:

1. Copies `infrastructure/networking/firewall/setup-iptables.sh` to
   `/usr/local/sbin/setup-iptables.sh`.
2. Hashes the script together with its inputs — the three subnet/port
   variables, `firewall_extra_rules` flattened to `proto:port:source`, and
   `ssh_port` — and compares that with `/etc/iptables/.baseline-fingerprint`
   on the host.
3. Runs the script only when the fingerprint differs, passing the inputs as
   the `MGMT_SUBNETS`, `ALLOWED_TCP_PORTS`, `TRUSTED_SUBNETS` and
   `EXTRA_RULES` environment variables, then records the new fingerprint.

So a routine run leaves a working firewall alone and reports nothing
changed, while a new subnet, port or script fix does reach hosts built before
it. `firewall_extra_rules` are part of the fingerprinted state and survive
every re-apply; rules added by hand survive only in the `LOCAL-INPUT` chain.

Hosts where another role owns the firewall set `baseline_firewall: false` —
the VPS does, in `inventory/group_vars/espocrm/vars.yml`, because the
baseline's SSH-from-anywhere rule would sit alongside the espocrm role's
source restriction and defeat it.

## Known issue

`ssh_permit_root_login`, `ssh_password_authentication` and
`ssh_max_auth_tries` in `group_vars/all.yml` are not read by
`templates/sshd_config.j2`, which fixes those settings itself (`no`, `no`,
`3`). Changing the variables changes nothing on the host.
