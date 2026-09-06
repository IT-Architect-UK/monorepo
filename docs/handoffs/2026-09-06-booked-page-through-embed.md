# Confirm the /booked/ landing and pay link after a booking made through the site's embed
Status: open

## Context
Cowork's Cal.com handoff (2026-09-06) verified the invoice leg but made the
test booking on cal.com directly, which bypasses the site. The redirect to
`/booked/` is done by the embed script on `itsurgery.me/book/` (Cal.com's own
redirect is a paid feature, and every event type has `successRedirectUrl =
null`). So the `/booked/` page and its pay-link lookup are still untested for
a real customer path. The embed froze under browser automation last time, so
this is a hands-on test in a normal browser.

Fixed since that handoff (commit after 7eb5cf8): the "Open the booking page in
a new tab" fallback on `/book/` now follows `?service=` instead of always
opening the remote-support event.

## Do this
1. In an ordinary browser window on a PC, open
   https://itsurgery.me/book/?service=surgery-appointment
   Confirm the calendar shows "IT Surgery Appointment", 30 min.
2. Book a slot with Darren's own email, notes marked TEST.
3. Expected within a few seconds of confirming: the page itself navigates to
   `https://itsurgery.me/booked/?uid=...`, shows "Your session is booked", and
   within ~30 seconds shows a Pay button / auto-redirects to the Stripe
   payment page. Record what actually happened, with timings. Do NOT pay.
4. Also click "Open the booking page in a new tab" on `/book/?service=surgery-appointment`
   and confirm the tab opens `cal.com/it-surgery/surgery-appointment`.
5. Cancel the test booking in Cal.com; confirm the £5 invoice is voided in Xero.

## Result
(to be filled in by the agent that does the work)
