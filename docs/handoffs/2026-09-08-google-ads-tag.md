# Google Ads tag: populate adsConversionId on the IT Surgery site

Status: open

## Context

Google Ads account 434-072-9821, Smart campaign "Curing IT Headaches" (live
since 2026-09-07). The campaign dashboard says "Finish setting up conversion
tracking" and Data manager → Google tag reports **Tag quality: No recent
data** — the Ads tag has never fired from itsurgery.me.

The site already supports it: `projects/web/itsurgery/src/_data/site.json`
line 110 has `"adsConversionId": ""` (empty). `src/assets/consent.js` reads
`data-ads` from `#consent-banner` and, when present, calls
`gtag('config', ADS, ...)` after cookie consent alongside GA4
(G-48BXC0QKL9). Conversions themselves are imported from GA4 events
(`booking_confirmed`, `generate_lead`) and need no change.

Value to set (read from Ads → Data manager → Google tag, 2026-09-08):

    adsConversionId: AW-18351825515

(The same tag also carries the container ID GT-5DDFPW75; not needed.)

## Do this

1. In `projects/web/itsurgery/src/_data/site.json` set
   `"adsConversionId": "AW-18351825515"`.
2. Confirm the template that renders `#consent-banner` passes
   `site.adsConversionId` into `data-ads` (grep `data-ads` under
   `projects/web/itsurgery/src/`). If it does not, wire it the same way
   `data-ga` is wired.
3. Build the site. In the built HTML, verify `#consent-banner` has
   `data-ads="AW-18351825515"` and that `consent.js` is unchanged.
4. Commit: `IT Surgery site: Google Ads tag AW-18351825515 via consent banner`.
   Push (deploys to Netlify) — Darren has approved this change.
5. After deploy: load https://itsurgery.me, accept cookies, and check the
   network tab for a request to `googleads.g.doubleclick.net` or
   `google.com/pagead` containing `AW-18351825515`. Record what you saw.

## Result

(filled in by Claude Code)
