# Google Ads tag: populate adsConversionId on the IT Surgery site

Status: done

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
Done by Claude Code, 2026-09-08.

1. `site.json`: `adsConversionId` set to `AW-18351825515`.
2. `base.njk` already passes it: `data-ads="{{ site.adsConversionId }}"` on
   `#consent-banner`, wired the same way as `data-ga`. No template change.
3. Built: `#consent-banner` carries `data-ads="AW-18351825515"`; `consent.js`
   unchanged; the CSP already allows googleads.g.doubleclick.net,
   www.googleadservices.com and td.doubleclick.net.
4. Committed and pushed (deploys itsurgery.me).
5. **Not done here**: Claude Code has no browser on the internet. Someone
   with a browser should load https://itsurgery.me, accept cookies, and look
   for a request to googleads.g.doubleclick.net or google.com/pagead carrying
   AW-18351825515. Until then, Ads will keep reporting "No recent data".

Note for Darren: the tag still loads only after cookie consent (basic
consent mode). Google's tag checker never consents, so Ads' "tag not set
up" warning will persist and no data flows from visitors who decline.
Switching to Google's advanced consent mode (tag always loads, denied
state until consent, cookieless pings only) is the fix; proposed on
2026-09-07, awaiting Darren's go.
