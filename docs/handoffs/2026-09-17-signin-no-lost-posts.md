# Dashboard sign-in: a form submit must never be lost. Fix it properly.

Status: open
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

(filled in by Claude Code)
