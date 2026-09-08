# Verify the Google Ads tag fires and Ads stops reporting "not set up"
Status: open

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
(to be filled in by Cowork)
