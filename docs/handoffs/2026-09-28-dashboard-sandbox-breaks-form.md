# URGENT: New job form fails on every submit since the sign-in deploy - n8n's sandbox header

Status: open
Owner: Claude Code. Priority over everything else.
Written by Cowork, 2026-09-28 ~13:55 UTC.

## Context

Darren ran the deploy from `2026-09-17-signin-no-lost-posts.md` today
(`deploy-auth.yml` then `deploy-n8n.yml`, then `deploy-auth.yml -e
oauth2_proxy_cookie_refresh=2m` for part C). Part A works: signed-in GETs of
`/` and `/monitoring` load, and a GET of `/webhook/custom-job` redirects to
`/?resend=1`. Part B's script is on the page.

**Part C attempt 1 (13:52:19 UTC)**, signed in, fresh load of `/`, fields
customer `x`, email `a@b.co`, work `test`, amount `1`, send `manual`,
submitted with `form.requestSubmit()` (so the page's submit handler ran):

- landed on `/?resend=1` with the **generic** notice "You were signed in
  again. If you had just sent a form ... please do it once more."
- form fields **empty** (not refilled)
- nothing reached the workflow

Cause, observed in the page itself:

- `window.origin` === `"null"`
- `sessionStorage` throws `SecurityError: ... The document is sandboxed and
  lacks the 'allow-same-origin' flag.`

n8n adds a `Content-Security-Policy` with `sandbox` (no `allow-same-origin`)
to HTML served from webhook "Respond to Webhook" nodes - the iframe-sandbox
hardening in current n8n (opt-out env var
`N8N_INSECURE_DISABLE_WEBHOOK_IFRAME_SANDBOX`). The 17 Sep Result said
"There is no CSP on the dashboard host ... Cowork's blocked fetch was the
extension" - not so; the page is sandboxed, which is also why every in-page
`fetch` from Cowork failed on 17 Sep. The mock n8n used for testing did not
add the header.

Consequences of the opaque origin, all deterministic:

1. `sessionStorage.setItem` throws, so no copy of the form is ever kept.
2. `fetch('/oauth2/auth')` from origin `null` is cross-origin to the
   dashboard host: the session cookie is not sent (or the response is
   unreadable), so the check always reads "signed out".
3. The handler therefore sends **every** submit to
   `/oauth2/start?rd=%2F%3Fresend%3D1` - the POST never happens.

So the New job form (and very likely the Ask-for-review form, same
handler) cannot raise an invoice at all right now. Before this deploy it
worked on the second try; now it never does. Darren has been told not to
use it until this is fixed.

## Do this

1. Scope the fix to the dashboard host, not n8n globally: on the internal
   `127.0.0.1:8081` server in `roles/n8n/templates/dashboard.nginx.conf.j2`,
   `proxy_hide_header Content-Security-Policy;` for the n8n-proxied
   locations (`/`, `/monitoring`, `/guide`, `/backup`, `/webhook/`), and
   set our own policy instead - same-origin scripts/forms/fetch, inline
   script allowed for the one page script, `frame-ancestors 'self'`
   (Webmin frame), no `sandbox`. Leave n8n.itsurgery.me's own webhooks
   sandboxed. If you judge the env-var route better, say why in Result.
2. Make the page script fail open, not closed: if `sessionStorage` throws,
   carry on without the copy; if the `/oauth2/auth` fetch **throws** (as
   opposed to returning 401/403), submit the form rather than redirect.
   Only a real 401/403 should send the person to sign in. A security
   header change must never again turn into "form never submits".
3. Test against the **real** n8n response headers, not a mock: capture
   `curl -sI` of a webhook HTML response from the running container (or
   have Darren paste it) and put it in Result.
4. Push. List the exact VPS commands Darren must run in Result
   (`deploy-n8n.yml` and/or `deploy-auth.yml`), and **keep the
   `-e oauth2_proxy_cookie_refresh=2m` on deploy-auth** if it is rerun -
   part C of the earlier handoff still needs doing afterwards, and Cowork
   will run it.
5. After the deploy, Cowork verifies: `window.origin` is
   `https://dashboard.itsurgery.me`, then runs part C (10 submits over 15
   minutes, zero lost, plus one real GBP 1 manual job).

## Result

(filled in by Claude Code)
