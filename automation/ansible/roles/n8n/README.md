# n8n role

Runs n8n with Postgres in Docker behind nginx with TLS, and produces nightly
backups that can actually be restored.

n8n is what runs the booking pipeline: Cal.com calls a webhook here, and this
creates the customer and the appointment in EspoCRM and raises the £5 invoice
in Xero.

## What you get

- n8n and Postgres as containers, bound to `127.0.0.1` only
- nginx in front, with a Let's Encrypt certificate and HSTS
- A nightly `pg_dump` plus an archive of the n8n data directory, written to
  `/opt/n8n/backups/` for the off-box backup to collect
- When `n8n_dashboard_domain` is set: a second nginx site for the business
  dashboard, the admin guide, the host vitals feed and Webmin, behind the
  Microsoft sign-in — see [The dashboard host](#the-dashboard-host) below

## Before you run it

**1. Point DNS at the server.** Certbot proves ownership over plain HTTP, so
the A record must already resolve or the certificate step fails.

**2. Generate the encryption key and keep a copy in Bitwarden.**

n8n encrypts every stored credential with `N8N_ENCRYPTION_KEY`. Restore the
database onto another machine without the same key and every credential is
unreadable — the workflows survive, the passwords and API keys do not. The
backup script deliberately does not include the key, so that a stolen backup is
not also the means to decrypt it. That only works if you have the key somewhere
else. Put it in Bitwarden before you run the playbook.

Generate one without special characters (see below for why):

```bash
openssl rand -hex 32
```

**3. Create the vault file** with the two secrets:

```bash
cd automation/ansible
ansible-vault create inventory/group_vars/n8n/vault.yml
```

The path matters. `group_vars/n8n/` is a directory named after the inventory
group, and Ansible loads every file inside it. A file named
`group_vars/n8n_vault.yml` would be ignored without warning — Ansible would be
looking for a group called `n8n_vault`.

Put this in it, with your own values:

```yaml
n8n_encryption_key: "..."
n8n_db_password: "..."
```

Neither may contain a single quote. The backup script quotes values inside
single quotes, which a literal one would terminate. In Bitwarden, turn off
special characters and raise the length instead.

The same file also holds the sign-in secrets once `oauth2_proxy_enabled` is
on: `oauth2_proxy_client_id`, `oauth2_proxy_client_secret`,
`oauth2_proxy_cookie_secret` and `n8n_dashboard_basic_password`. See
[roles/oauth2-proxy](../oauth2-proxy/README.md).

**4. Add the host to the inventory** under an `n8n` group, alongside `espocrm`.
On this VPS that means `ansible_connection: local`.

## Running it

SSH into the VPS, then:

```bash
cd /opt/monorepo/automation/ansible
ansible-playbook playbooks/deploy-n8n.yml --ask-vault-pass
```

The first run is a two-pass affair: nginx comes up HTTP-only, certbot obtains
the certificate over the challenge path, then the site is re-templated with
TLS. That is deliberate — a config that references a certificate which does not
exist yet will not start.

## First login

n8n has no default account. Visit `https://<your domain>/` and the first thing
it asks is for you to create the owner account. Do that immediately: until you
do, anyone who finds the URL can claim it.

## The dashboard host

Everything past the certificate step in `tasks/main.yml` builds the admin
side of the VPS. It runs only when `n8n_dashboard_domain` is set
(`dashboard.itsurgery.me` in `inventory/group_vars/n8n/vars.yml`).

**A vanity host, not a second n8n.** `templates/dashboard.nginx.conf.j2` is a
separate nginx site with its own Let's Encrypt certificate (same two-pass
issue as the main site) and a shared proxy snippet at
`/etc/nginx/snippets/dashboard-proxy.conf`. It proxies a handful of paths to
the same n8n webhooks that build the pages, and nothing else: `/` is the
dashboard, `/monitoring`, `/guide` and `/backup` are the other tabs, and
`/webhook/` carries the forms those pages post back. Everything else is a
404, so a leaked dashboard URL does not lead anyone to the workflow editor,
which stays at `n8n_domain`.

**The admin guide.** `automation/itsurgery-admin-and-deployment-guide.md` is
copied to `n8n_guide_dir` (`/opt/guide/guide.md`) on every run. nginx serves
it raw at `/guide.md` to loopback and the Docker bridge (`172.16.0.0/12`)
only; the Guide workflow fetches it from there and renders it.

**The vitals feed.** `/vitals.json` is served straight off disk from
`n8n_vitals_dir` (`/opt/vitals`), with the same loopback-and-bridge
restriction. The file is written by the `vitals` role
(`deploy-vitals.yml`, [roles/vitals](../vitals/README.md)); this role only
serves it. n8n never sees the request.

**The sign-in.** With `oauth2_proxy_enabled: true`, every administrative
location carries `auth_request /oauth2/auth`, answered by oauth2-proxy on
`127.0.0.1:4180` (`deploy-auth.yml`, [roles/oauth2-proxy](../oauth2-proxy/README.md)).
A request with no session is bounced to `/oauth2/start` and on to the
Microsoft login, then back to where it was going. Behind the gate nginx
injects n8n's own basic-auth header from `n8n_dashboard_basic_user` and
`n8n_dashboard_basic_password`, so the webhooks stay locked (they are also
reachable at `n8n_domain`, which this sign-in does not guard) but nobody
types the password. Two doors sit outside the gate on purpose:
`/monitoring.json`, basic auth against `/etc/nginx/.htpasswd-services` for
the watchdog, which is a machine and cannot sign in with Microsoft; and
`/signed-out`, so a freshly signed-out person is not bounced straight back
into the login. Because the template reads `n8n_dashboard_basic_password`,
`deploy-n8n.yml` needs `--ask-vault-pass`, and `deploy-auth.yml` must have
run first.

**Webmin, framed.** `/webmin/` proxies to `https://127.0.0.1:10000`
same-origin, and `/webmin-frame` is a static page from nginx with the
dashboard's header and Webmin in an iframe below it. Both sit behind the
sign-in, but no credential is injected: Webmin's own Unix login is the second
factor, so a compromised Microsoft account is not root one click deep. Without
oauth2-proxy the location falls back to basic auth against
`webmin_htpasswd_file`. Webmin itself, and its `webprefix` setting that makes
the framing work, come from `deploy-webmin-vps.yml`
([roles/webmin](../webmin/README.md)).

Order for a fresh VPS: `deploy-espocrm.yml` (firewall, Docker), then
`deploy-webmin-vps.yml`, `deploy-vitals.yml`, `deploy-auth.yml`, and this
playbook last to wire nginx to all of them.

## Upgrading

Bump `n8n_image_tag` in `defaults/main.yml`, read the release notes, and re-run
the playbook. It is pinned rather than tracking `latest` on purpose: n8n ships
several releases a week, and an unattended pull that crosses a major version is
how a working booking pipeline breaks overnight.

Take a backup first — the playbook does not do that for you.

## Restoring

You need three things: the dump, the data archive, and the encryption key from
Bitwarden.

```bash
# 1. Bring the stack up so Postgres exists, then stop n8n itself
cd /opt/n8n && docker compose up -d postgres

# 2. Replay the dump (it is --clean --if-exists, so it drops as it goes)
gunzip -c /opt/n8n/backups/n8n-db-YYYYMMDD-HHMMSS.sql.gz \
  | docker exec -i n8n-postgres psql -U n8n -d n8n

# 3. Restore the data directory
docker run --rm -v n8n_n8n_data:/data -v /opt/n8n/backups:/backup alpine:3 \
  tar xzf /backup/n8n-data-YYYYMMDD-HHMMSS.tar.gz -C /data --strip-components=1

# 4. Make sure the compose file has the ORIGINAL encryption key, then
docker compose up -d
```

If credentials show as invalid after a restore, the key is wrong. Nothing else
produces that symptom.

## Migrating to other hardware

The point of Postgres, the named volumes and the pinned image is that this is
portable. To move to Proxmox later:

1. Keep the same hostname. Cal.com's webhooks and the website both call n8n by
   URL; if the name does not change, nothing external needs re-registering.
2. Back up, restore onto the new host by the steps above, with the same
   encryption key.
3. Repoint DNS.

## TLS to outbound services

The container mounts the host's `/etc/ssl/certs` read-only and sets
`NODE_EXTRA_CA_CERTS`. Without it, n8n fails STARTTLS to Microsoft's mail relay
with *"unable to get local issuer certificate"* — the image's bundle does not
carry every intermediate that public services present.

The tempting fix is the "Ignore SSL Issues (Insecure)" toggle on the node.
Don't: it stops n8n verifying it is talking to who it thinks, it has to be
remembered on every future node, and it hides the next certificate problem
rather than surfacing it.

## Firewall

This role does not manage the firewall. The espocrm role already owns the
iptables ruleset on this host and has 80/443 open, which is all n8n needs. Two
roles writing the same ruleset is how you lock yourself out — recovery is the
OVHcloud KVM console.
