# Cal.com: create the two Surgery Appointment event types and verify the booking flow
Status: done

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
Done by Claude Cowork, 2026-09-06 08:00-08:40 BST, from D:\GitHub\monorepo at 5984dea.

**Steps 1-3 — sync.** First dry run (Python 3.14.5, Windows): the two expected
CREATE lines **plus 11 UPDATE lines** (10 `title`, 1 `description`). Stopped.
Byte-level comparison showed the 10 titles were identical on both sides; the
script was mis-reading the catalogue. Root cause: `read_text()` with no
`encoding=` argument falls back to the locale codepage (cp1252) on Windows, so
every em dash decoded as `â€"`. Applying would have overwritten 10 live Cal.com
titles with mojibake. The script had only ever been run on Linux before, where
UTF-8 is the default.

Re-ran with `PYTHONUTF8=1` set: 2 CREATE + 1 UPDATE. The remaining UPDATE was
real — `google-workspace-setup`'s Cal.com description contained a hand-added
phrase "if you prefer Google to Microsoft" not in the catalogue. Darren chose
to let the catalogue win. Applied:

    created surgery-appointment -> id 6960907
    created business-surgery-appointment -> id 6960908
    updated google-workspace-setup

Re-run dry run: `Cal.com has 49 event types; catalogue wants 49` — create 0,
update 0. Converged.

**Step 4 — webhook.** One webhook, `https://n8n.itsurgery.me/webhook/cal-booking`,
under Settings > Developer > Webhooks (account level; event-type-scoped
webhooks live inside an event type instead). Edit form has no event-type
selector. Enabled; triggers: Booking created, rescheduled, canceled. Account-
scoped as required. No change made.

**Step 5 — end to end.**
- /fixed-prices/ first row: £25, 30 min, Book → `/book/?service=surgery-appointment`. Correct.
- /book/ embed loaded "IT Surgery Appointment", 30m, In Person (Attendee
  Address), description "Fixed price £25. A £5 booking fee...". Correct.
- The embed repeatedly froze the browser renderer under automation, so the
  booking was made on `cal.com/it-surgery/surgery-appointment` directly:
  Mon 7 Sep 2026 15:30-16:00, darren.pilkington@it-architect.uk, address
  Penarth, notes marked TEST. Booking uid 2zWf7GyiHfwMwMdNzDeEFU.
- 08:28:08 Cal.com confirmation email sent. **08:28:14 Xero INV-0096, £5.00,
  "Booking fee — 07 Sep 2026 15:30"** — six seconds after booking. (b) confirmed.
- Cancelled the booking in Cal.com with a reason. INV-0096 was **voided
  automatically** by the cancellation workflow; confirmed Voided in Xero.
  Nothing done by hand in Xero.

**Differed from plan — for Claude Code:**
1. **Encoding bug in `automation/calcom/sync-event-types.py`.** `read_text()`
   needs `encoding="utf-8"`. Until fixed, only run it with `PYTHONUTF8=1`.
2. **Fallback link on /book/ is wrong.** "Open the booking page in a new tab"
   is hardcoded to `https://cal.com/it-surgery/remote-support-session`; it
   ignores `?service=`. A customer whose embed fails is sent to book the wrong
   service.
3. **(a) "/booked/ with payment link" is untested, not failed.** All 49 event
   types have `successRedirectUrl = null`, so the /booked/ landing must be
   done by the site's embed JS, which a direct cal.com booking bypasses. Needs
   one booking through the embed on itsurgery.me to confirm. Also means the
   fallback link path (item 2) never lands on /booked/ either.
4. **Cal.com API key was rotated during this work** (the previous one leaked
   into a chat transcript by accident). New key is in Bitwarden under Cal.com
   and in the User-scope env var `CALCOM_API_KEY` on Darren's PC.
