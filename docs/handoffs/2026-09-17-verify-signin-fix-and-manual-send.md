# Verify the sign-in fix and the New job manual-send option, live
Status: done (Cowork); Darren to void INV-0098 and INV-0099 and delete the two test Contacts
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

Done by Cowork, 2026-09-17 ~14:00-14:10 UTC, Edge (Claude in Chrome), signed in. Times are UTC from the page/JS clock.

**1. Fresh submits (blank form, validation fails, nothing raised).** Five attempts, each after a fresh reload of /:
- 1st (session idle ~50 min beforehand): landed on /?resend=1 with the yellow "You were signed in again. If you had just sent a form or pressed a button, it did not go through: please do it once more." notice. Correct honest behaviour, but the POST was still lost.
- 2nd, 3rd, 4th, 5th (within the next ~4 min): the workflow's "Not sent / Nothing was raised" page every time.
So: the notice works and no silent loss any more, but the first POST after a refresh is still dropped. **It is not hourly**: in step 4 the bounce recurred ~1 minute after a successful submit (INV-0098 raised at ~14:05, the next POST at ~14:06 landed on /?resend=1 with the notice, the re-submit at 14:07:32 succeeded). Whatever triggers the refresh fires more often than once an hour - or a successful /webhook/custom-job response itself rotates the cookie. Worth a look at the refresh interval / what the "Invoice raised" response sets.

**2. Refreshed cookie expiry.** Not measurable from here: the browser extension blocks document.cookie and there is no DevTools access. Behavioural evidence only (the refresh notice appearing, then POSTs succeeding). Darren can check Application > Cookies himself.

**3. Manual send, GBP 1.** Customer "Test Manual", Darren's own email, work "Test - void me", amount 1, VAT home, Send = "I'll send it myself". Result page: "Invoice INV-0098 raised - Customer Test Manual - Amount GBP 1 - Sent: not emailed - you are sending it - Not emailed. Download the PDF from Xero and send it with the job sheet. - Pay link https://in.xero.com/SsJU4hVtorBJwgqcKgCWfdUdFaW9hpyt4wkaHK6M - Open the invoice in Xero - Back to the dashboard". No Xero email arrived (Outlook search, all folders). CRM Contact 6aabf3f7c6d112821 "Test Manual", description "Custom job: Test - void me. Invoice INV-0098, sent manually".

**4. Default send, GBP 1.** Same with Send = "Email it from Xero now", work "Test - void me 2" (first attempt bounced with the notice, see 1; second went through). Result page: "Invoice INV-0099 raised - Sent: emailed from Xero with a Pay Now button - pay link https://in.xero.com/4U9yWzMLA5jh7pprDBBvgahxExE5r4SUWV4JOhA2". Xero email "Invoice INV-0099 from IT Surgery for Test Manual" from messaging-service@post.xero.com received 14:07:42Z. CRM Contact 6aabf426bcb0f7700, description "Custom job: Test - void me 2. Invoice INV-0099, sent by Xero".

**5. Records.** Invoices INV-0098 (manual) and INV-0099 (Xero-emailed), both GBP 1.00 AUTHORISED, both show under "Needs you - unpaid". Contacts 6aabf3f7c6d112821 and 6aabf426bcb0f7700. n8n execution ids: not available - n8n needs its own sign-in, which Cowork does not have. Nothing voided or deleted, per Darren's instruction; the dashboard "customers" count is now 1 and "invoiced" GBP 11.00 until he does.
