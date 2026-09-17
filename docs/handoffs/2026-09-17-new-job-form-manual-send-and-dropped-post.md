# New job form: "I'll send it myself" option, and the first POST is being dropped

Status: open
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

(filled in by Claude Code)
