# Office opening, 1 October 2026: site and Google Business Profile changes
Status: open (do not action before 1 October 2026)

## Context
The IT Surgery office and test lab (the converted garage at 8 Beechwood
Close, Sully, CF64 5WW - the address already on the site) opens on
1 October 2026, **by appointment only**, not drop-in. Decisions taken with
Darren on 2026-09-06:

- One price for the Surgery Appointment, £25, wherever it happens: at the
  customer's home or business, or at the office. No separate "come to us"
  price, so no new catalogue entry and no Cal.com change.
- The office is mentioned as an option, not pushed: most customers still
  want a visit or a remote session.

## Do this (Claude Code, on or after 1 October)
1. `projects/web/itsurgery/src/about-us.njk`, "Where to find us": add a
   sentence that the office and test lab in Sully are open by appointment,
   for anyone who would rather bring a device to us.
2. `projects/web/itsurgery/src/_data/faq.json`, "What is a Surgery
   Appointment?": append "at your home or business, or at our office in
   Sully by appointment."
3. `src/_data/pricelist.json` and `businessprices.json`, the appointment
   blurb: append "At your place or ours."
4. Build, check, push. Nothing else on the site refers to the office.

## Do this (Cowork, after the site push)
5. Google Business Profile: change the business from a service-area-only
   listing to one with a visitable address at 8 Beechwood Close, Sully,
   CF64 5WW, marked "by appointment only", keeping the existing service
   areas (Penarth, Barry, Cardiff, Vale of Glamorgan). Add the office as a
   location on the Facebook Page too.
6. Confirm the address shows correctly on the Google listing and that the
   listing still says appointments are required.

## Result
(to be filled in on the day)
