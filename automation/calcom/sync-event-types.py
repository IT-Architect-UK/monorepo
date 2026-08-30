#!/usr/bin/env python3
"""Create/update Cal.com event types from the service catalogue.

One catalogue drives the site, the booking workflow and Cal.com; this script
is the Cal.com leg. It reads projects/web/itsurgery/src/_data/services.json,
compares against the event types already on the account, and makes them match:
one event type per bookable service, matched by slug, with the title, duration
and a description carrying the price and the £5-fee terms.

Standalone by design. Run it from anywhere in the repo checkout:

    export CALCOM_API_KEY=cal_live_...        # or let it prompt
    python3 automation/calcom/sync-event-types.py            # dry run — prints the plan
    python3 automation/calcom/sync-event-types.py --apply    # does it

Rules it will not break:
  - DRY RUN by default. Nothing is written without --apply.
  - It never deletes an event type, and never touches one whose slug is not
    in the catalogue (your remote-support-session is matched and left alone
    unless its title/length drift from the catalogue).
  - Every booking is the £5 fee; prices appear in the DESCRIPTION so the
    customer reads them, but Cal.com is never told to charge anything —
    payment stays with the Xero invoice + Stripe flow.
"""
import json, os, sys, urllib.request, urllib.error, getpass
from pathlib import Path

API = "https://api.cal.com/v2/event-types"
VER = "2024-06-14"     # cal-api-version; without it the endpoint shape differs

def repo_root() -> Path:
    p = Path(__file__).resolve()
    for parent in p.parents:
        if (parent / ".git").exists():
            return parent
    sys.exit("Run me from inside the monorepo checkout.")

def call(method, url, key, body=None):
    req = urllib.request.Request(url, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {key}",
                 "cal-api-version": VER,
                 "Content-Type": "application/json",
                 # Cloudflare in front of api.cal.com bans urllib's default
                 # User-Agent outright (error 1010) before the API ever sees
                 # the request. Any honest identity passes.
                 "User-Agent": "itsurgery-catalogue-sync/1.0 (+https://itsurgery.me)"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:500]
        sys.exit(f"{method} {url} -> HTTP {e.code}\n{detail}")

def description(svc, fee):
    lines = []
    if "priceExVat" in svc:
        unit = f" {svc['unit']}" if svc.get("unit") else ""
        lines.append(f"Fixed price £{svc['priceExVat']} ex VAT{unit}.")
    lines.append(f"A £{fee} booking fee is taken now and deducted from the "
                 "final invoice. Need more than one service? Ask for a custom "
                 "quote at itsurgery.me instead.")
    return " ".join(lines)

def main():
    apply = "--apply" in sys.argv
    key = os.environ.get("CALCOM_API_KEY") or getpass.getpass("Cal.com API key: ")
    cat = json.loads((repo_root() /
        "projects/web/itsurgery/src/_data/services.json").read_text())
    fee = cat["bookingFeeGbp"]
    wanted = [s for s in cat["services"] if s.get("bookable")]

    existing = call("GET", API, key).get("data", [])
    by_slug = {e.get("slug"): e for e in existing}
    print(f"Cal.com has {len(existing)} event types; catalogue wants {len(wanted)}.\n")

    creates, updates, ok = [], [], []
    for svc in wanted:
        want = {"title": svc["name"],
                "lengthInMinutes": svc["durationMinutes"],
                "description": description(svc, fee)}
        have = by_slug.get(svc["slug"])
        if have is None:
            creates.append((svc, want)); continue
        drift = {k: v for k, v in want.items()
                 if have.get(k if k != "lengthInMinutes" else "lengthInMinutes",
                             have.get("length")) != v}
        (updates if drift else ok).append((svc, drift, have))

    strangers = [s for s in by_slug if s not in {w["slug"] for w in wanted}]
    for svc, want in creates:
        print(f"CREATE  {svc['slug']:32} {want['lengthInMinutes']:>4} min  {want['title']}")
    for svc, drift, have in updates:
        print(f"UPDATE  {svc['slug']:32} fields: {', '.join(drift)}")
    for svc, _, _ in ok:
        print(f"ok      {svc['slug']}")
    for s in strangers:
        print(f"leave   {s}  (on Cal.com, not in the catalogue — untouched)")

    if not apply:
        print(f"\nDry run: would create {len(creates)}, update {len(updates)}. "
              "Re-run with --apply to do it.")
        return
    for svc, want in creates:
        out = call("POST", API, key, {**want, "slug": svc["slug"]})
        print(f"created {svc['slug']} -> id {out.get('data', {}).get('id')}")
    for svc, drift, have in updates:
        call("PATCH", f"{API}/{have['id']}", key, drift)
        print(f"updated {svc['slug']}")
    print("\nDone. Spot-check one in the Cal.com UI, then book a test slot.")

if __name__ == "__main__":
    main()
