# tls role

The original Certbot role, applied by `playbooks/configure-tls.yml` to
`web_servers`. It installs `certbot` and `python3-certbot-<web_server>` and
runs `certbot --nginx` (or `--apache`), which obtains the certificate **and
rewrites the web server's virtual host** to use it. It then confirms the
certificate file exists, prints `certbot certificates`, and enables
`certbot.timer` for renewal.

The live roles (espocrm, n8n, meshcentral, webmin) do not use it. They
template their own nginx sites and call `certbot certonly --webroot`, so
certbot never edits a file Ansible also manages — the plugin and the template
would undo each other on alternate runs. Use this role for a plain web server
whose vhost nothing else manages.

## Variables

| Variable | Default | Meaning |
|----------|---------|---------|
| `domain` | required | Certificate name. Issuance is skipped when `/etc/letsencrypt/live/<domain>/fullchain.pem` already exists |
| `email` | required | Let's Encrypt contact address |
| `web_server` | `nginx` (a play var in `configure-tls.yml`; override with `-e`) | `nginx` or `apache` — selects the plugin package and the certbot flag |
| `domain_aliases` | unset | Extra `-d` names on the same certificate |

Note the names: `domain` and `email`, not the `letsencrypt_email` the live
roles read from `group_vars/all.yml`.

## Known issue

The certificate task notifies `Reload {{ web_server }}`, but the role has no
`handlers/` directory, so there is no handler by that name. Ansible reports a
missing handler as an error once the notifying task changes — that is, on
the run that actually issues the certificate. The certificate is obtained
before the error, and the plugin reloads the web server itself, so a re-run
skips the task via `creates` and completes.
