# Confirm the /booked/ landing and pay link after a booking made through the site's embed
Status: done

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
Done 2026-09-06, ~10:30-11:00 BST. Steps 1 and 4 by Claude Cowork via the
browser; steps 2-3 hands-on by Darren in Edge (the embed is a cross-origin
iframe automation cannot click into); step 5 by Cowork.

**1. Embed shows the right event type.** `/book/?service=surgery-appointment`
loads "IT Surgery Appointment", 30m, In Person (Attendee Address). Confirmed.

**2-3. The customer path works end to end.** Darren booked Wed 9 Sep 2026
16:00 through the embed with notes "Test". After Confirm the page itself
navigated to `itsurgery.me/booked/?uid=...` and showed:
- "Your session is booked"
- "Taking you to our secure payment page in 4 seconds..." with a countdown bar
- a "Pay £5 now" button
- "Confirmed, Wednesday 9 September at 16:00"
It then auto-redirected to Stripe Checkout showing "IT Surgery — invoice
INV-0097, £5.00". Not paid. Both screenshots seen by Cowork.

Timing: the pay-link lookup and redirect completed inside the 4-second
countdown — well under the ~30 s the handoff allowed for.

**4. Fallback link fixed.** "Open the booking page in a new tab" on
`/book/?service=surgery-appointment` now points at
`https://cal.com/it-surgery/surgery-appointment`. Confirmed.

**5. Cleanup.** Booking uid fQJUT4t522wSchttq7eCqh cancelled in Cal.com with a
reason. Xero INV-0097 "Booking fee — 09 Sep 2026 16:00" shows **Voided** —
done automatically by the cancellation workflow, nothing by hand.

**Differed from plan / for Claude Code:**
1. **Copy on /booked/ assumes remote support.** Under "What happens next" it
   says "We'll join the call at the agreed time and connect to your
   computer". This was an in-person Surgery Appointment. The page should vary
   that line by the service's `location` (in person vs video), or use wording
   that fits both.
2. Cal.com autofilled the booking with a previous guest identity from
   Darren's browser (name "Ziqi Zhang", email wmtx@earthnode.network), so the
   confirmation emails went to that address rather than Darren's. Not a site
   bug — a browser autofill artefact — but it means the mailbox timing check
   was not possible this time; the Stripe page and Xero were the evidence.
