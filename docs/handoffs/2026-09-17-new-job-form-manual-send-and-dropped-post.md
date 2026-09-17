# New job form: "I'll send it myself" option, and the first POST is being dropped

Status: code done; nginx change needs the n8n playbook run on the VPS, then a live test
Owner: Claude Code
Asked for by Darren 2026-09-17 (first real invoice, JS-2026-001).

## Context

`automation/n8n/workflows/custom-job.json` behind the dashboard's **New
job** form (`dashboard.json`, `<form method="POST" action="/webhook/custom-job">`):
Check it -> Raise the invoice (Xero, AUTHORISED) -> Get the pay link ->
Send it to them (Xero `/Invoices/{id}/Email`) -> Add them to the CRM
(Contact) -> Show the link.

**Problem 1 - the first POST after a page load never reaches n8n.**
Reproduced by Cowork 2026-09-17 14:14 UTC in Edge, signed in: submitting
the form (blank, so validation would fail) returned HTTP 200 with the
dashboard home page at `/` - the form re-rendered empty, nothing ran.
Submitting again immediately returned the workflow's "Not sent / Nothing
was raised" page as designed. Darren saw the same on his real submission
(bounced to an empty form, no Xero invoice, no CRM Contact, nothing in
"Money this month"). So the POST is being swallowed between the browser
and n8n on the first attempt - most likely the sign-in proxy
(oauth2-proxy + nginx `auth_request`) refreshing the session cookie on a
POST and redirecting to `/`, losing the body. It is not the workflow.
The webhook node is set to `authentication: basicAuth`; confirm nginx
injects that header for `/webhook/` (it evidently does on the second
attempt) and look at the oauth2-proxy cookie-refresh setting and the
nginx `error_page 401` redirect for `/webhook/`.

**Problem 2 - Darren wants to send the invoice himself sometimes.**
Customers who pay by bank transfer, or who should get the job sheet and
invoice in one personal email, do not need Xero's automated email. Today
the form always sends.

## Do this

1. Find and fix the dropped first POST: reproduce with a blank submit
   (safe - validation fails), fix the proxy/nginx config in the repo (the
   Ansible role or nginx template that provisions the dashboard), deploy,
   and prove three consecutive fresh-page-load submits all return the
   workflow's page. If the cause is a cookie refresh on POST, make the
   dashboard page also refresh the session on load (a tiny GET to an
   authenticated path) so the POST never triggers it. Keep the
   `ask-review` form in mind - same path, same problem.
2. Add a **Send** choice to the form under VAT:
   `( ) Email it from Xero now   ( ) I'll send it myself`, default = Xero.
   Field name `send`, values `xero` | `manual`. `Check it` passes it
   through; an IF after "Get the pay link" skips "Send it to them" when
   `manual`. The invoice is still raised AUTHORISED and the Contact still
   created either way.
3. "Show the link" page for both paths shows: invoice number, amount,
   customer, the pay link (copyable), a link to open the invoice in Xero
   (`https://go.xero.com/AccountsReceivable/View.aspx?InvoiceID=<id>`),
   and for `manual` the line "Not emailed. Download the PDF from Xero and
   send it with the job sheet." If Xero's `GET /Invoices/{id}` with
   `Accept: application/pdf` is easy to proxy through the workflow, add a
   "Download PDF" button instead of the Xero link - optional.
4. Record the choice on the CRM Contact description ("Invoice INV-xxxx,
   sent by Xero" / "sent manually") so the dashboard's "Needs you -
   unpaid" card has the context.
5. Push (deploy-n8n.yml deploys). Verify with a real submit on a test
   customer (your own email, £1, manual): invoice raised, no Xero email,
   Contact created, result page correct; then void that invoice in Xero
   and delete the test Contact. Put the run ids in Result.

## Result

Claude Code, 2026-09-17.

**Problem 1, cause (from the config, not guessed; reproduced with a local
nginx against stand-ins for oauth2-proxy and n8n).** Two defects in
`automation/ansible/roles/n8n/templates/dashboard.nginx.conf.j2`:

1. oauth2-proxy refreshes the session every hour (`cookie_refresh = 1h`)
   and hands the refreshed cookie back on the `/oauth2/auth` subrequest.
   nginx's `auth_request` discards that Set-Cookie unless it is copied out
   with `auth_request_set` and re-added, so the browser kept the stale
   cookie. The page load refreshed and passed; the POST straight after it
   arrived with the already-used refresh token, oauth2-proxy answered 401,
   and nginx sent the person to sign in. That is the "first POST after a
   page load" pattern, and why the second attempt worked: the sign-in had
   just set a fresh cookie properly through `/oauth2/callback`.
2. The sign-in redirect used `rd=$scheme://$host$request_uri`. oauth2-proxy
   only follows an absolute return URL whose host is in
   `whitelist_domains` (ours lists only login.microsoftonline.com), and
   otherwise sends the person to `/`. Hence the empty form at `/` with no
   error, and Cowork's "first click on the nav link bounced to the
   dashboard home".

**Fix, in the repo:**

- New snippet `dashboard-auth.conf.j2` (installed by a new task): the
  `auth_request` plus `auth_request_set` lines capturing the refreshed
  cookies. Every gated location includes it. Four `map`s rebuild each
  cookie from its own value plus the attributes of the first one
  (`$upstream_http_set_cookie` is all the cookies joined with ", ", which
  no browser accepts as one header), and server-level `add_header
  Set-Cookie` lines return them: `_oauth2_proxy`, and chunks `_0` to `_3`
  (Entra sessions are chunked). Repeated inside `/webmin/` and
  `/webmin-frame`, whose own `add_header` would otherwise cancel the
  inherited ones.
- `@sign_in` now uses `rd=$request_uri` (relative, always allowed), so a
  re-login returns to the page asked for. `/webhook/` has its own
  `@sign_in_again` returning to `/?resend=1`, and `dashboard.json` shows a
  notice on that: "You were signed in again... it did not go through:
  please do it once more." A posted form body cannot survive a sign-in
  round trip, so this is the honest outcome for the rare case that still
  hits it (a session past its 12 h `cookie_expire`).
- No page-load "session refresh" JavaScript was needed: once the refreshed
  cookie is returned, the page load itself is that refresh.

Local proof (rendered template, nginx 1.24, fake upstreams): a
refresh-due request returns the page with three separate, clean
`Set-Cookie` headers; a request without refresh returns none; a dead
session on `/monitoring` redirects to `/oauth2/start?rd=/monitoring`; a
dead session POST to `/webhook/custom-job` redirects to
`rd=/?resend=1`; a live POST reaches n8n with its body and the basic-auth
header; HSTS and the other server headers are still on gated pages.

**Needs Darren on the VPS (Ansible runs on the box):**

```
cd /opt/monorepo && git pull && cd automation/ansible
ansible-playbook playbooks/deploy-n8n.yml --ask-vault-pass
```

Then the three-consecutive-submits check from "Do this" 1 is Cowork's:
load `/`, submit the New job form blank, expect the "Nothing was raised"
page every time. Not done here: no route to the VPS or the browser.

**Problem 2, done in `custom-job.json` + `dashboard.json`** (deploys on
this push):

- Form: a "Send" choice under VAT, `Email it from Xero now` (default) /
  `I'll send it myself`, field `send` = `xero` | `manual`; button now
  reads "Raise invoice".
- `Check it` passes `manual`; new IF "Email it from Xero?" after "Get the
  pay link" skips "Send it to them" when manual. Invoice is AUTHORISED
  and the Contact created either way.
- Result page for both paths: invoice number, customer, amount, how it was
  sent, the pay link (click selects it), "Open the invoice in Xero"
  (`go.xero.com/AccountsReceivable/View.aspx?InvoiceID=...`), and for
  manual the line "Not emailed. Download the PDF from Xero and send it
  with the job sheet." The PDF proxy was not added: the Xero link is one
  click and the workflow would otherwise have to stream a binary through
  a Respond node it has never done before.
- CRM Contact description: "Custom job: <work>. Invoice INV-xxxx, sent by
  Xero" / "sent manually".
- The two result pages' "Back to the dashboard" links now go to `/`
  rather than `/webhook/dashboard`.

Verified here: `Check it` returns `manual: true` for `send=manual` and
`false` when the field is absent; the dashboard page renders the two
radios, the new button text, and the notice only when `?resend=1` is
present; workflow JSON validates. The real £1 manual submit, the void in
Xero and the test Contact clean-up (step 5) are Cowork's, after the
deploy: put the run ids here.

**Seen in passing, not changed:** `/webmin-frame` answers with `return
200`, which nginx runs before `auth_request`, so that static frame page
is served without a sign-in. It holds only the tab bar; the `/webmin/`
inside it is gated. Worth a one-line fix (serve it from a file instead of
`return`) in a later handoff.

