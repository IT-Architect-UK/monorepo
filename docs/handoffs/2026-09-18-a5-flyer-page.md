# Publish the simple A5 leaflet at itsurgery.me/a5-flyer

Status: done
Owner: Claude Code
Approved by Darren 2026-09-18 ("perfect. please make this available from the
website via https://itsurgery.me/a5-flyer").

## Context

A second, simpler leaflet to sit alongside the existing detailed one at
`/flyer/`. One side, A5 portrait, no price list, no durations - a hook, four
promises, two service columns (At home / For business), and a contact block.
It is for handing out and for noticeboards; the detailed A4 leaflet stays as
it is and is NOT replaced.

The finished design, signed off by Darren after several rounds, is in this
repo at `docs/handoffs/flyer-a5-reference/flyer-a5.html`. It is a single
self-contained HTML file with site-relative asset paths
(`/assets/fonts.css`, `/assets/logo.png`), so it already works as an
Eleventy page body plus a stylesheet. Build the page from it - do not
redesign it.

Details that took several rounds and must not drift:

- **The contact block is the business card's `.details` block**, from
  `src/assets/business-card.css`: a two-column grid, labels left, a 0.3mm
  `#990000` vertical rule between labels and values, row spacing from
  padding and never `gap` (a gap breaks the rule into segments - the card's
  own CSS comment says so). Scaled up for A5: `grid-template-columns:22mm 1fr`,
  10pt. All four values are red 700 (Darren 2026-09-18 - the card has email
  and phone dark, the flyer does not).
- **The two service boxes are exactly equal in height and their internal
  rules line up.** The boxes stretch (`.cols{align-items:stretch}`,
  `.box{flex:1}`) and the italic closing note is bottom-pinned with
  `margin-top:auto` and `min-height:15mm` so the rule above it lands at the
  same y in both columns. Verified by measurement, not by eye: the two
  `.more` elements' `getBoundingClientRect().top` must be identical.
- **The QR is the same height as the contact block beside it**: both are
  fixed at 33.5mm (four rows x (10pt x 1.3 + 1.9mm + 1.9mm)). Do not try to
  do this with `align-self:stretch` + `aspect-ratio` - that feeds back on
  itself and the QR grows to fill the page (tried, 2026-09-18).
- The QR is an inline SVG (generated with `segno`, error correction M)
  pointing at **https://itsurgery.me/book**. Keep it inline and committed;
  do not add a build-time QR dependency for one code.
- No prices anywhere except none at all - the leaflet points at the website
  so print cannot go stale. "Since 2008" must never appear.

## Do this

1. `src/assets/flyer-a5.css` - the `<style>` block from the reference file,
   with the leaflet's own `@page { size: A5; margin: 0 }`. Do not merge it
   into `flyer.css`; that file is A4 and its comment explains why the
   leaflet is standalone.
2. `src/_includes/layouts/flyer-a5.njk` - a copy of `layouts/flyer.njk`
   pointing at `flyer-a5.css`. (Or parameterise the existing layout with a
   `stylesheet` front-matter variable and use it for both - your call, say
   which in Result.)
3. `src/flyer-a5.njk` - the body from the reference file, with
   `permalink: /a5-flyer/`, `title: A5 leaflet`,
   `eleventyExcludeFromCollections: true`, and the same `noindex` treatment
   the other print pages get. Pull the contact values from `_data/site.json`
   as the business card does (`site.tagline`, `site.phoneDisplay`,
   `site.email | lower`, `site.url | replace("https://","")`); the WhatsApp
   handle `@itsurgery` is hard-coded on the card, so hard-code it here too.
   The service lists and the two italic notes are hand-written marketing
   copy - keep them in the template verbatim, they are not catalogue data.
4. Confirm `/a5-flyer` (no trailing slash) reaches the page - add a Netlify
   redirect if Eleventy's permalink does not handle it.
5. Do NOT link it from the site navigation. Like `/flyer/` and
   `/business-card/` it is a print asset Darren opens directly.

## Verify before saying done

- `/a5-flyer/` renders; print preview is **one** A5 page, nothing clipped,
  at A5 / margins None / background graphics on.
- In the rendered page, measured in a browser: the two `.more` elements have
  the same `top`; `.details` and `.qr` have the same `top` and `bottom`;
  `.qr` is square.
- The QR scans to https://itsurgery.me/book from a phone.
- Legal line reads "... Company 12066050" with no "Penarth".
- `/flyer/` is unchanged.

## Result

Claude Code, 2026-09-18. Live at https://itsurgery.me/a5-flyer/ on this push.

- `src/assets/flyer-a5.css`: the reference `<style>` block with its own
  `@page { size: A5; margin: 0 }`, plus one print rule: Chromium rounds A5
  to 209.9mm, so a 210mm sheet spilled a hairline onto page 2; in print the
  sheet is 209.5mm (the footer is bottom-pinned, so nothing moves).
- Layout: `layouts/flyer.njk` now takes a `stylesheet` front-matter
  variable, defaulting to `/assets/flyer.css`, so both leaflets share it.
  `/flyer/` output still links `flyer.css`.
- `src/flyer-a5.njk`: the reference body; tagline, email, phone, website,
  legal name and company number come from `site.json`; `@itsurgery`, the
  service lists and the notes are verbatim. `noindex` via the layout,
  excluded from collections and the sitemap.
- Measured in Chromium on the built page: both `.more` tops 614.1;
  `.details` and `.qr` both 704.9 to 831.5; `.qr` square; PDF at A5 is one
  page; the QR in the printed page decodes to https://itsurgery.me/book;
  legal line "IT Surgery is a trading name of IT Solution Architecture
  Limited · Company 12066050", no Penarth. `/a5-flyer` without the slash
  is Netlify's standard redirect to `/a5-flyer/`, checked live below.

