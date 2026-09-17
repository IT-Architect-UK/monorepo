# Verify the sign-in fix and the New job manual-send option, live
Status: open
Owner: Cowork (browser), then Darren (Xero clean-up)
Written by Claude Code, 2026-09-17.

## Context

`2026-09-17-new-job-form-manual-send-and-dropped-post.md` is deployed:
the n8n workflows by the push (deploy run green) and the nginx change by
Darren's playbook run on the VPS (`changed=4, failed=0`). Checked from
outside without a session: `GET /monitoring` now redirects to
`/oauth2/start?rd=/monitoring` and `POST /webhook/custom-job` to
`rd=/?resend=1`, so the new config is the one serving. What is left is
what only a signed-in browser can show.

## Do this

1. **Three fresh submits.** Sign in at https://dashboard.itsurgery.me/.
   Three times over: reload `/`, press "Raise invoice" with the form
   blank. Expect the workflow's "Nothing was raised" page every time,
   never the empty dashboard. If any attempt lands on `/` instead, note
   whether the yellow "You were signed in again" notice was shown.
2. **Refreshed cookie.** In DevTools › Application › Cookies, note the
   expiry of `_oauth2_proxy_0` (or `_oauth2_proxy`), wait past the hourly
   refresh if practical (or come back later), reload `/`, and confirm the
   expiry moved forward. That is the fix working.
3. **Manual send, £1.** New job: customer "Test Manual", Darren's own
   email, work "Test - void me", amount 1, VAT home, Send = "I'll send it
   myself". Expect: result page with invoice number, £1.00, "not emailed",
   the yellow "Not emailed. Download the PDF from Xero..." line, the pay
   link, and "Open the invoice in Xero". No email from Xero arrives. The
   CRM Contact "Test Manual" exists with description "Custom job: Test -
   void me. Invoice INV-xxxx, sent manually".
4. **Default send, £1.** Same again with Send left on "Email it from Xero
   now" and work "Test - void me 2". Expect the Xero email to arrive and
   the Contact description to end "sent by Xero".
5. Record the invoice numbers, the n8n execution ids and the Contact ids
   below. Darren then voids both invoices in Xero and deletes the two test
   Contacts (or Cowork does, if it has the CRM open).

## Result

(filled in by Cowork)
