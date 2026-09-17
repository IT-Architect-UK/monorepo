# Dashboard sign-in: a form submit must never be lost. Fix it properly.

Status: built; needs deploy-auth.yml then deploy-n8n.yml on the VPS, then the 10-submit proof
Owner: Claude Code
Darren, 2026-09-17: "just get it fixed. I don't have time for this." He has
hit the bounce on his first real invoice twice. Priority over everything
else on the dashboard.

## What is happening (evidence, 2026-09-17, Cowork)

- Blank-form POSTs to `/webhook/custom-job` after a fresh load of `/`:
  1st bounced to `/?resend=1` with the notice; 2nd-5th fine (all within
  4 min).
- Manual-send invoice raised OK at ~14:05 UTC (INV-0098). The very next
  POST at ~14:06 bounced to `/?resend=1` with the notice; the re-submit at
  14:07:32 raised INV-0099. So a POST was rejected with 401 **one minute
  after a successful one on a session that had just been re-established
  at 14:04**. This is not the hourly `cookie_refresh`.
- Darren hit the same bounce at 16:16 BST on his first Brian Stonhold
  attempt (screenshot).
- GETs of `/` never fail; only the POSTs to `/webhook/` land on 401.

## Why (read `dashboard.nginx.conf.j2` + `dashboard-auth.conf.j2`)

The gate is nginx `auth_request /oauth2/auth`. oauth2-proxy answers that
subrequest with refreshed `Set-Cookie` headers whenever it rewrites the
session; nginx discards subrequest headers, so 39049ff copies them out
(`$upstream_http_set_cookie`, `$upstream_cookie__oauth2_proxy_N`) and
re-adds them with `add_header Set-Cookie ... always` built by `map`
regexes. That relay is the weak point. Ways it silently produces a bad
cookie set in the browser, any one of which explains the symptoms:

1. **A cleared chunk is never relayed.** Entra sessions are chunked
   (`_oauth2_proxy_0.._3`). When the rewritten session needs fewer chunks,
   oauth2-proxy sends `Set-Cookie: _oauth2_proxy_2=; Max-Age=0` (or
   Expires in the past). `$upstream_cookie__oauth2_proxy_2` is then empty,
   the map yields "", nginx sends nothing, the browser keeps the stale
   `_2`, oauth2-proxy concatenates 0+1+stale 2, decryption fails -> 401.
2. **Attributes are taken from the first cookie only** and appended to
   every chunk; if the first header in `$upstream_http_set_cookie` is a
   clearing cookie its attributes (Max-Age=0 / past Expires) get applied
   to the live chunks, expiring them immediately.
3. **`$upstream_http_set_cookie` joins headers with ", "** (nginx >= 1.23)
   but `Expires=Thu, 17 Sep 2026 ...` also contains ", ", so the
   `attrs` regex boundary `, _oauth2_proxy` is fine, but any cookie whose
   attributes differ from the first's (SameSite, Path) is mis-rebuilt.
4. Only `location /` has the `add_header` lines through inheritance;
   `/webhook/` inherits them too, but `/oauth2/` (callback) has its own
   headers and that is fine. Any location that later gains its own
   `add_header` silently loses the relay (already had to be repeated for
   `/webmin/` and `/webmin-frame`).

Whatever the exact trigger, the architecture is: a correctness-critical
cookie relay re-implemented in nginx regexes. Do not patch it again.

## Do this - two layers, both required

**A. Move the sign-in in front of the whole host: oauth2-proxy as the
reverse proxy, not `auth_request`.**
nginx terminates TLS on dashboard.itsurgery.me and `proxy_pass`es every
gated location to oauth2-proxy (127.0.0.1:4180); oauth2-proxy's
`upstreams` point at the n8n webhooks / Webmin / static locations that
nginx currently proxies (use a second internal nginx server on
127.0.0.1:8081 that holds today's locations minus the auth snippets, so
the routing stays in one file). oauth2-proxy then sets and refreshes its
own cookies on the real response - no relay, no maps, no `auth_request`.
Keep: the basic-auth injection to n8n (`--set-authorization-header` is
NOT what we want; keep nginx adding the `Authorization: Basic` header on
the internal server), the `/monitoring.json` basic-auth door outside the
gate, `/signed-out` outside the gate, `/vitals.json` and `/guide.md`
loopback-only, the security headers. `cookie_refresh` back to `1h`.
Delete the maps, the `auth_cookie_*` variables and
`dashboard-auth.conf.j2`. Document the shape in the role README.

**B. The form checks the session before it posts.**
In `dashboard.json`'s page (and `ask-review`'s), on submit: `fetch('/oauth2/auth', {credentials:'same-origin'})`
first. 2xx -> submit. 401/403 -> save the form fields to `sessionStorage`,
go to `/oauth2/start?rd=%2F%3Frestore%3D1`; on load with `restore=1`,
refill the form from `sessionStorage` and show "Signed in again - your
form is filled in, press Raise invoice." The page CSP must allow
`connect-src 'self'` (an in-page fetch currently fails, per Cowork). This
makes a lost submit impossible even if A regresses. Keep the existing
`resend=1` notice as the fallback.

**C. Prove it before saying done.** Temporarily set
`oauth2_proxy_cookie_refresh: "2m"` on the VPS (Darren runs the playbook;
give him the exact command), then from a signed-in browser submit the
blank form 10 times over 15 minutes with reloads between: every attempt
must return the workflow's "Nothing was raised" page; zero bounces. Then
one real GBP 1 manual-send job, then set refresh back to `1h` and run the
playbook again. Record every attempt with its time in Result. Cowork can
run the browser part if asked - write the ask in Result.

**Do not** ship a partial (B without A). Do not add more regexes.

## Result

Claude Code, 2026-09-17. A and B are built, tested locally, and in this
commit; C needs the VPS and a browser.

**One correction to "Why".** The oauth2-proxy log Darren pulled for the
window Cowork tested shows no "Refreshing session" line at all and every
session as `refresh_token:false` (Entra issues none with the scope in use),
so the cookie relay never emitted a cookie and cannot be what dropped the
POSTs. It also shows no "Error loading cookied session", so the cookie was
never corrupt: on both bounces the browser sent no session cookie. The
relay is still gone, because the architecture was wrong regardless, and B
makes a lost submit impossible whatever the browser does. The refresh
never having worked also means every session dies at the Entra token
lifetime (~72 min, `expires:` in the log), not after 12 h; adding
`offline_access` to the scope would give oauth2-proxy a refresh token and
is a one-line change for a later handoff, not this one.

**A. oauth2-proxy is the reverse proxy.**
- `roles/n8n/templates/dashboard.nginx.conf.j2`: the public 443 server
  keeps TLS, the security headers, `/vitals.json`, `/guide.md`,
  `/monitoring.json` (watchdog, basic auth) and `/signed-out`, and sends
  every other path to `127.0.0.1:4180` (websocket upgrade and 330 s
  timeouts for Webmin). A second server on `127.0.0.1:8081` holds today's
  routing with no auth of its own: `/`, `/monitoring`, `/guide`, `/backup`,
  `/webmin/` (SAMEORIGIN, no credential injection, as before),
  `/webmin-frame`, `/webhook/`, 404 for the rest; n8n's basic-auth header is
  injected there. `absolute_redirect off` so its redirects never leak the
  loopback port. A GET of `/webhook/custom-job` or `/webhook/ask-review`
  (what a sign-in turns a lost POST into) redirects to `/?resend=1`;
  `/webhook/jobsheets-next` to the Job sheets page. `auth_request`, the
  maps, the `auth_cookie_*` variables and `dashboard-auth.conf.j2` are
  deleted; a task removes the old snippet from the box.
- `roles/oauth2-proxy`: `upstreams = ["http://127.0.0.1:8081/"]`,
  `upstream_timeout = "330s"`, `http_address = "127.0.0.1:4180"`, and the
  container on `network_mode: host` so both hops stay on the loopback
  (no published ports). `cookie_refresh` stays `1h`.
- Both role READMEs, the Ansible README table and the admin guide describe
  the new shape.
- Proven locally with nginx 1.24 on the rendered template, a stand-in
  oauth2-proxy in proxy mode and a stand-in n8n: signed-in GET `/` and
  POST `/webhook/custom-job` reach n8n with the body and the basic-auth
  header; no session on `/monitoring` -> `/oauth2/start?rd=%2Fmonitoring`;
  no session POST -> sign-in, and the GET it becomes lands on `/?resend=1`
  (relative); `/webhook/jobsheets-next` GET -> `/webhook/jobsheets`;
  unknown path -> 404; `/monitoring.json` 401 without and 200 with basic
  auth, outside the gate; `/signed-out` 200 outside the gate; HSTS,
  nosniff, robots and `X-Frame-Options: DENY` present on a page; 4180 and
  8081 bound to 127.0.0.1 only. The no-sign-in variant of the template
  renders too.

**B. The form checks the session and keeps itself.** `dashboard.json`'s
page now has one inline script: on any `/webhook/` form submit it stores
the New job fields in `sessionStorage`, fetches `/oauth2/auth`
(same-origin, no-store), and only then submits; a 401 sends the person to
`/oauth2/start?rd=%2F%3Fresend%3D1`. On `/?resend=1` with a stored copy
the form is refilled and the notice reads "Signed in again. Your form is
filled in below: check it and press Raise invoice."; a plain load clears
the copy. There is no CSP on the dashboard host, so the fetch is allowed
(Cowork's blocked fetch was the extension, not the page). Driven in
Chromium against a mock: live session posts once; dead session posts
nothing, keeps customer/email/work/amount/VAT/send, comes back refilled
with the new notice; the resend posts the kept values; a plain load clears
the copy; `/?resend=1` with nothing kept shows the generic notice.

**Deploy (Darren, on the VPS; both, in this order):**

```
cd /opt/monorepo && git pull && cd automation/ansible
ansible-playbook playbooks/deploy-auth.yml --ask-vault-pass
ansible-playbook playbooks/deploy-n8n.yml --ask-vault-pass
```

The n8n workflow deploys itself on this push. Expect a few seconds of
sign-in errors between the two playbooks (oauth2-proxy restarts on the
host network before nginx is re-pointed).

**C. Proof (after the deploy).** The temporary 2-minute refresh is one
extra flag, no file edits; put it back with the plain command:

```
ansible-playbook playbooks/deploy-auth.yml --ask-vault-pass -e oauth2_proxy_cookie_refresh=2m
```

Then, signed in, over 15 minutes with a reload between each: submit the
New job form 10 times with customer `x`, email `a@b.co`, work `test`,
amount `1` (the one-letter name fails the workflow's own check, so nothing
is raised and the page must say "Nothing was raised" every time; the
browser's `required` fields stop a blank form leaving the page, which is
why the earlier blank-submit test cannot be repeated). Zero bounces; if
one happens, the form must come back filled in. Then one real GBP 1
manual-send job, void it in Xero, delete the Contact, and run
`deploy-auth.yml` without the flag. Cowork can do the browser part:
"Read docs/handoffs/2026-09-17-signin-no-lost-posts.md, do part C in the
browser, record every attempt with its time under Result."

