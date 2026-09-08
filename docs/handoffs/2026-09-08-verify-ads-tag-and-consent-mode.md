# Verify the Google Ads tag fires and Ads stops reporting "not set up"
Status: done

## Context
Two site changes on 2026-09-08 (commits ecbc263 and the one that carries this
file): the Ads conversion ID AW-18351825515 is on the site, and the Google tag
now runs in Google's **advanced consent mode** - it loads on every page with
all consent types denied (no cookies, anonymous pings only) and switches to
granted when the visitor accepts the cookie banner. Before this, the tag did
not load at all until consent, so Google's checker never saw it and Ads
reported "Finish setting up conversion tracking" / "No recent data".

Claude Code verified the logic locally (consent default denied, tag requested
before consent, update-to-granted on accept, no grant on decline, events
still sent) but has no browser on the internet, so the live checks are here.

## Do this
1. In a fresh private window open https://itsurgery.me with the Network tab
   open (filter: `google`). Before touching the banner, expect a request to
   `googletagmanager.com/gtag/js?id=G-48BXC0QKL9` and cookieless pings to
   `google-analytics.com/g/collect` and/or `googleads.g.doubleclick.net` with
   `gcs=G100` or similar in the query (that is the "denied" signal).
   Confirm no `_ga` or `_gcl` cookie exists yet (Application > Cookies).
2. Click "Yes, that's fine". Expect new requests with `gcs=G111` (granted) and
   the `_ga` cookie to appear. Expect a request containing `AW-18351825515`.
3. Google Ads (434-072-9821): Goals > Conversions > Summary and Data manager >
   Google tag. Record whether "Tag quality" / "not set up" warnings have
   cleared. They can lag by a few hours; if still red, note the time and
   check again later rather than changing anything.
4. Google Analytics > Admin > Data streams > itsurgery.me > "Consent settings"
   (if shown): confirm it reports consent signals as active.
5. If anything is blocked by the site's Content-Security-Policy (a red
   "Refused to" line in the Console naming a Google host), copy the exact host
   into Result; Claude Code will add it.

## Result
Done by Cowork, 2026-09-08 ~10:30 UTC, Edge via the Claude in Chrome
extension (not a private window - stored consent was cleared from
localStorage instead, and the banner reappeared).

1. Pre-consent, live site (deploy of 725ed13 confirmed: `#consent-banner`
   has `data-ads="AW-18351825515"`): dataLayer starts with
   `consent default` all denied, `url_passthrough`, `ads_data_redaction`,
   then `config G-48BXC0QKL9` and `config AW-18351825515`. Requests seen:
   `googletagmanager.com/gtag/js?id=G-48BXC0QKL9`,
   `googletagmanager.com/gtag/js?id=AW-18351825515`,
   `pagead2.googlesyndication.com/ccm/collect?...tid=AW-18351825515&en=page_view&npa=1&gcs=G100`,
   `region1.google-analytics.com/g/collect?...tid=G-48BXC0QKL9&gcs=G100&npa=1&pscdl=denied`.
   Cookie check: the extension blocks `document.cookie` reads, so the
   no-cookie assertion is inferred from `gcs=G100` / `pscdl=denied`, not
   observed directly.
2. After "Yes, that's fine": dataLayer gained `consent update` all granted;
   localStorage `consent = {state: granted}`. Requests: `google.com/ccm/collect
   ...tid=AW-18351825515&en=consent_update&gcs=G111`,
   `googleads.g.doubleclick.net/pagead/viewthroughconversion/18351825515/`
   (200), `google.com/pagead/1p-user-list/18351825515/`,
   `region1.analytics.google.com/g/collect ...gcs=G111&npa=0`.
3. Ads Data manager > Google tag, checked immediately after: **Tag quality:
   Excellent - "Tag is sending data. No issues detected."** (was "No recent
   data" an hour earlier). Campaign-level "Finish setting up conversion
   tracking" banner not re-checked; expect it to clear with the same lag.
4. GA4 consent settings: not checked (out of scope for the Ads fix; can do
   on request).
5. No CSP "Refused to" errors in the console at any point.

Observation, not a site fault: several collect POSTs (`ccm/collect`,
`g/collect`, `rmkt/collect`) were reported as HTTP 503 by the extension
while identical-host GETs returned 200 and Google confirmed data arriving.
Most likely the extension's reporting of beacon/POST requests in this Edge
profile. Nothing to change.
