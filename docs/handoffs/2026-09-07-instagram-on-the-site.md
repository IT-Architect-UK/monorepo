# Add the Instagram profile to the IT Surgery site
Status: open

## Context
An Instagram business account now exists and is connected to the Facebook
Page: **https://www.instagram.com/itsurgery.me/** (handle `@itsurgery.me` —
`@itsurgery` was not available; an earlier account `itsurgeryme` was disabled
by Meta in August 2025 and is dead). Created 2026-09-07 by Darren, bio set by
Cowork, category Information Technology Company, converted to a professional
(business) account, linked to facebook.com/itsurgery.

The site currently lists only Facebook in `site.json`:

- `sameAs` — array used by the Organization schema in
  `src/_includes/layouts/base.njk` (feeds Google's knowledge panel)
- `facebookUrl` — used wherever the site links to the Page

Facebook and Instagram profile copy is recorded outside the repo in
`Projects/Freelancer/content-production/social-profiles.md`.

## Do this
1. In `projects/web/itsurgery/src/_data/site.json`, add
   `https://www.instagram.com/itsurgery.me/` to the `sameAs` array, and add an
   `instagramUrl` key alongside `facebookUrl` with the same value.
2. Wherever the site renders a Facebook link (footer, contact block, About —
   grep for `facebookUrl`), render an Instagram link next to it in the same
   style. Follow the existing accessible-link pattern (visible label plus the
   "opens in a new tab" hidden text).
3. Build the site and verify: the Organization JSON-LD in the built HTML
   contains both URLs in `sameAs`; the Instagram link appears where the
   Facebook one does; no other page changed.
4. Commit. Do not push — Darren approves pushes, and this deploys live.

Not in scope: WhatsApp. The WhatsApp Business number is not yet issued; a
separate handoff will cover `site.whatsapp`, the business card and the leaflet
when it is.

## Result
(to be filled in by the agent that does the work)
