# oauth2-proxy role

One Microsoft sign-in for every admin page on the VPS. nginx on the dashboard
host asks this service, through `auth_request`, whether the visitor has a
valid session before serving anything administrative; without one they are
sent to the Microsoft 365 login (with its MFA) and returned to where they
were going. Behind that gate nginx injects the per-service credential, so n8n
keeps its own lock but nobody types it.

Applied by `playbooks/deploy-auth.yml` to the `n8n` group. The nginx side
lives in the n8n role (`templates/dashboard.nginx.conf.j2`), switched on by
`oauth2_proxy_enabled: true` in `inventory/group_vars/n8n/vars.yml`, so the
order is `deploy-auth.yml` first, then `deploy-n8n.yml`. See
[roles/n8n](../n8n/README.md#the-dashboard-host) for what sits behind the
gate.

## What it does

- Asserts the tenant id, the three vault secrets and the dashboard password
  are present, and stops with a message if not — a missing secret fails the
  deploy loudly rather than locking anyone out quietly
- Runs `quay.io/oauth2-proxy/oauth2-proxy:v7.15.4` under Docker Compose in
  `/opt/oauth2-proxy`, published on `127.0.0.1:4180` only (nginx is the only
  caller), as uid 65532 — the image's `nonroot` user, which also owns the
  mounted config files. A root-only file mounted into the container reads as
  permission denied; that exact mistake cost a deploy
- Writes `oauth2-proxy.cfg` (provider `entra-id`, single tenant,
  `skip_provider_button`, `reverse_proxy = true`, secure cookies) and the
  `emails.txt` allow-list, both mode 0400
- Installs `python3-passlib` and writes `/etc/nginx/.htpasswd-services`, the
  basic-auth door for the watchdog — a machine, which cannot sign in with
  Microsoft — using the same credential n8n's dashboard webhook checks
- Waits for `http://127.0.0.1:4180/ping` to answer before finishing

Authentication is not authorisation: anyone in the tenant can sign in at
Microsoft, but only addresses in the allow-list are let through.

## Variables

| Variable | Default | Where set |
|----------|---------|-----------|
| `oauth2_proxy_tenant_id` | `""`, required | `inventory/group_vars/n8n/vars.yml` |
| `oauth2_proxy_allowed_emails` | one address | `defaults/main.yml` |
| `oauth2_proxy_redirect_url` | `https://dashboard.itsurgery.me/oauth2/callback` | defaults |
| `oauth2_proxy_http_port` | `4180` | defaults |
| `oauth2_proxy_cookie_expire` / `oauth2_proxy_cookie_refresh` | `12h` / `1h` — refreshed hourly against Entra, dead after twelve hours regardless | defaults |
| `oauth2_proxy_image` / `oauth2_proxy_image_tag` | `quay.io/oauth2-proxy/oauth2-proxy` / `v7.15.4` | defaults |
| `oauth2_proxy_uid` | `65532` | defaults |
| `oauth2_proxy_base_dir` | `/opt/oauth2-proxy` | defaults |

Vault only, in `inventory/group_vars/n8n/vault.yml`:

| Variable | What |
|----------|------|
| `oauth2_proxy_client_id` | The app registration's Application (client) ID |
| `oauth2_proxy_client_secret` | Its client secret |
| `oauth2_proxy_cookie_secret` | 32 URL-safe bytes: `openssl rand -base64 32 \| tr '+/' '-_'` |
| `n8n_dashboard_basic_password` | The dashboard login password (paired with `n8n_dashboard_basic_user`, default `dashboard`). Used for the service htpasswd here, and injected by nginx in the n8n role |

## The Entra app registration

What the configuration needs from it, and nothing more:

- A single-tenant registration. Its tenant id goes in
  `oauth2_proxy_tenant_id`; the issuer is built from it as
  `https://login.microsoftonline.com/<tenant>/v2.0`
- A **Web** redirect URI equal to `oauth2_proxy_redirect_url`
- A client secret. The Application ID and the secret go in the vault

Creating the registration is a browser job in the Entra admin centre, not
one for this repo; only the three values above come back here.

## Sign-out

`whitelist_domains` permits the redirect to `login.microsoftonline.com`, so
signing out ends the Microsoft session as well. Without that, the still-live
Microsoft session signs the next request straight back in and logout appears
broken.
