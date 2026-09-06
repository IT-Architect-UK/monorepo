# Cal.com event-type sync

`sync-event-types.py` keeps the Cal.com booking calendar in step with the
IT Surgery service catalogue. One catalogue drives the site, the n8n booking
workflow and Cal.com; this script is the Cal.com leg.

## What it does

- Reads `projects/web/itsurgery/src/_data/catalogue.json`, found by walking up
  from the script to the `.git` root, so it runs from anywhere in the checkout.
- Takes every service marked `"bookable": true` and matches it to a Cal.com
  event type **by slug**.
- For each, sets the title, `lengthInMinutes`, a description carrying the
  fixed price (ex VAT for business, inc VAT for home) and the £5 booking-fee
  wording, `useDestinationCalendarEmail` (invites come from the business
  address), and the location: the customer's address, or Cal Video when the
  catalogue entry says `"location": "video"`.
- Prints a plan — `CREATE`, `UPDATE` (with the drifted fields), `ok`, `leave` —
  and only writes with `--apply`.

Three rules it will not break:

- **Dry run by default.** Nothing is written without `--apply`.
- **It never deletes.** An event type on Cal.com whose slug is not in the
  catalogue is printed as `leave … untouched`.
- **Prices are description text only.** Cal.com is never told to charge
  anything; payment stays with the Xero invoice and Stripe flow.

A service with `"existing": true` predates the catalogue and its description
was written by hand: title and duration are still kept honest, the wording is
left alone.

## Running it

```bash
export CALCOM_API_KEY=cal_live_...        # or leave unset and it prompts (getpass)
python3 automation/calcom/sync-event-types.py            # dry run: prints the plan
python3 automation/calcom/sync-event-types.py --apply    # does it
```

The key lives in Bitwarden. Never commit it or paste it into a command that
ends up in shell history you would share.

## Two things not to simplify out

Both are in `call()` and both look redundant until removed:

- The `cal-api-version: 2024-06-14` header is mandatory. Without it the
  `https://api.cal.com/v2/event-types` endpoint answers with a different shape
  and the sync misreads it.
- A custom `User-Agent`. Cloudflare in front of `api.cal.com` bans urllib's
  default agent outright (error 1010) before the API ever sees the request.
  Any honest identity passes.

## Tests

`tests/test_sync_event_types.py` — eight tests, no network and no Cal.com. The
script's HTTP layer and catalogue read are replaced with fakes, so the plan it
builds and the writes it makes with `--apply` are checked against a synthetic
catalogue and account; the last test reads the real catalogue and checks every
bookable service has what the sync needs.

```bash
python3 -m pytest -q automation/calcom/tests
```

CI runs them on every push and pull request (`.github/workflows/test.yml`,
which runs pytest over everything under `automation/`).

## Changing the catalogue

Do not edit Cal.com by hand to add or reprice a service; change the catalogue
and re-run the sync. The `add-itsurgery-service` skill covers the whole
sequence — catalogue, site, Cal.com, booking allow-list and webhook check.
