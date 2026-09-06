# webmin role

Installs Webmin from its official apt repository. On its own that is what a
provisioned VM on a private network needs: Webmin on port 10000, logged into
with the server's own accounts (`deploy-webmin.yml`, or `server-baseline.yml`
with `standard_webmin: true`). Set `webmin_domain` and the role additionally
puts nginx, a Let's Encrypt certificate and a basic-auth door in front of it,
so port 10000 never opens to the internet (`deploy-webmin-vps.yml`).

## Install (`tasks/main.yml`)

1. Downloads `webmin-setup-repo.sh` from the Webmin repository at tag
   `webmin_setup_tag` (2.660) and checks it against `webmin_setup_sha256`
   before running it — pinned and checksummed rather than fetched from
   `master`. Webmin publishes no checksum, so the hash in the task was taken
   from the tagged file; bump the two together.
2. Runs the script once (guarded by `/etc/apt/sources.list.d/webmin.list`),
   installs `webmin`, enables and starts the service.
3. Prints the `https://<ip>:10000` address, or continues into `proxy.yml`
   when `webmin_domain` is set.

## Reverse proxy (`tasks/proxy.yml`)

- Installs nginx, certbot and `apache2-utils` first. `htpasswd` comes from
  the last one, and the password-file check below must not run before the
  tool that creates the file is present — that trap was real.
- **Stops if `webmin_htpasswd_file` does not exist.** The file is created by
  hand, so the password never passes through the repo or the vault:

  ```bash
  sudo htpasswd -c /etc/nginx/.htpasswd-webmin <username>
  ```

  Then run the playbook again. Deploying an nginx site that points at a
  missing file would fail `nginx -t` later, with a far less obvious message.
- Rewrites the Webmin settings its own nginx recipe calls for, and restarts
  Webmin (`/etc/webmin/restart`) before nginx is pointed at it:

  | File | Setting | Why |
  |------|---------|-----|
  | `/etc/webmin/config` | `referers=<webmin_domain> <n8n_dashboard_domain>` | Otherwise Webmin rejects proxied requests as cross-site with a bare "Bad Request" |
  | `/etc/webmin/config` | `webprefix=/webmin`, `webprefixnoredir=1` | Subdirectory mode. The prefix is global, so both hostnames serve `/webmin/`, which is what lets the dashboard frame it same-origin |
  | `/etc/webmin/miniserv.conf` | `redirect_ssl=1`, `redirect_prefix=/webmin`, `cookiepath=/webmin`; `redirect_host` removed | Absolute URLs built for the public hostname; redirects follow the Host header nginx passes rather than one pinned name |

- Deploys the nginx site in two passes, like the espocrm, n8n and meshcentral
  roles: HTTP only until `certbot certonly --webroot` has issued the
  certificate (the root returns 404 meanwhile; the ACME path works), then
  again with TLS. nginx proxies to `https://127.0.0.1:10000` — Webmin keeps
  its own TLS on the loopback hop, per its documented recipe — with websocket
  upgrade for the Terminal and File Manager modules, buffering off, and a
  330 s read timeout for shell sessions and running backups.

You log in twice on purpose: nginx asks for the basic-auth password, then
Webmin asks for a Unix login. Webmin authenticates any sudo-capable user
through PAM, so there is no separate Webmin account. The outer door is not
paranoia: Webmin has had pre-authentication remote code execution
(CVE-2019-15107), and a scanner that cannot get past nginx never reaches
Webmin's code at all.

The dashboard host adds a second route to the same Webmin at
`https://<n8n_dashboard_domain>/webmin/`, behind the Microsoft sign-in; see
[roles/n8n](../n8n/README.md#the-dashboard-host).

## Variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `webmin_domain` | `""` | Set to enable the reverse proxy |
| `webmin_port` | `10000` | Webmin's own listener |
| `webmin_setup_tag` / `webmin_setup_sha256` | `2.660` / the hash in `tasks/main.yml` (inline defaults, not in `defaults/`) | Pinned repo-setup script and its checksum |
| `webmin_acme_webroot` | `/var/www/acme` | Shared with the other roles on the VPS; creating it again is harmless |
| `webmin_request_certificate` | `true` | Set false to template the site without asking certbot |
| `webmin_enable_ipv6` | `false` | Adds `[::]` listeners |
| `webmin_basic_auth` | `true` | The nginx door |
| `webmin_htpasswd_file` | `/etc/nginx/.htpasswd-webmin` | Must exist before the proxy run |
| `letsencrypt_email` | from `group_vars/all.yml` | Required with `webmin_domain` |
| `n8n_dashboard_domain` | from `group_vars/n8n/vars.yml` | Added to `referers` when set |

Handlers: `Reload nginx`; `Restart webmin`, which runs `/etc/webmin/restart`,
the supported way to reload the files under `/etc/webmin`.
