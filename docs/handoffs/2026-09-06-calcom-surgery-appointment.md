# Cal.com: create the two Surgery Appointment event types and verify the booking flow
Status: open

## Context
IT Surgery's bookable services are defined in
`projects/web/itsurgery/src/_data/catalogue.json`. Each bookable service needs
a matching Cal.com event type (account `it-surgery`), created by
`automation/calcom/sync-event-types.py`. A Cal.com webhook then calls the n8n
workflow that raises the £5 booking-fee invoice in Xero.

Commit 5984dea (2026-09-06) added two bookable services that Cal.com does not
yet have. Until they exist, the Book buttons on the first row of
https://itsurgery.me/fixed-prices/ and /business-fixed-prices/ open a calendar
for an event type that is missing.

| slug | name | length |
|------|------|--------|
| `surgery-appointment` | IT Surgery Appointment | 30 min |
| `business-surgery-appointment` | IT Surgery Appointment for business | 30 min |

Known trap (has happened before): if the Cal.com webhook is attached to
specific event types rather than the whole account, new event types accept
bookings but never trigger the invoice, and nothing reports an error.

## Do this
1. `git pull` on the local clone of the monorepo. Work from the repo root.
2. Get the Cal.com API key from Bitwarden (entry: Cal.com). Then:
   ```
   export CALCOM_API_KEY=cal_live_...
   python3 automation/calcom/sync-event-types.py
   ```
   This is a dry run. Expected: exactly two `CREATE` lines, for the two slugs
   above, and `leave`/no change for everything else. If you see `UPDATE` or
   anything unexpected, stop and record it under Result before applying.
3. `python3 automation/calcom/sync-event-types.py --apply`
   Do not edit the script: the `cal-api-version` header and the custom
   User-Agent it sets are both required.
4. In Cal.com (app.cal.com, Settings, Developer, Webhooks): find the webhook
   pointing at `n8n.itsurgery.me`. Confirm it is account-scoped (all event
   types). If it is scoped to specific event types, change it to account scope.
   Record what you found.
5. Test end to end: open https://itsurgery.me/fixed-prices/, click Book on the
   first row. Confirm the calendar is the 30-minute appointment. Book a slot
   with Darren's own email. Confirm the site lands on `/booked/` and shows a
   payment link, and that a £5 invoice appears in Xero. Then cancel the test
   booking in Cal.com and void the invoice in Xero.

## Result
(to be filled in by the agent that does the work)
