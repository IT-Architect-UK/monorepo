# IT Surgery social posting — requirements (DRAFT for Darren's approval)
Status: open
Owner: Claude Code (code) Â· Cowork/Darren (Meta token, content pool, verification)
Approved by Darren 2026-09-10.

## Context


Written by Cowork, 2026-09-10. Modelled on the WorldDePIN dashboard's
social pipeline (`WorldDePIN/worlddepin-dashboard`, `collector/social.py`,
handoff `docs/handoffs/2026-09-09-social-cta-and-multiplatform.md`), which
is live for Facebook and built for X and Instagram.

### Goal

Post to IT Surgery's Facebook Page and Instagram automatically from a pool
of posts that Darren has read and approved in advance. Nothing goes out
that he has not approved. No AI tokens are spent per post: the pool is
written once (by Cowork, with Darren), approved in bulk, and the poster is
plain code.

### Platforms

| Platform | How | Status |
|---|---|---|
| Facebook Page "I.T. Surgery" (facebook.com/itsurgery) | Graph API, page token, as WorldDePIN | Automate |
| Instagram @itsurgery.me (Business, linked to the Page) | Graph API container → publish, needs a 1080×1080 image per post; WorldDePIN already has the card renderer and publisher, unused there | Automate |
| Google Business Profile posts | API needs Google approval and is not worth it; Darren pastes the same post weekly | Manual, same pool |
| Nextdoor business page | No API | Manual, same pool |
| X, LinkedIn | Wrong audience for local home/SMB IT help (LinkedIn is IT Architect's brand) | Not now |

### Reuse, don't rewrite

Port `collector/social.py` (seed / house rules / slots / publishers /
audit), `ensure_images()` (Pillow cards) and the dashboard Social tab from
worlddepin-dashboard. Keep the same row model (`fb-YYYYMM-NNN`,
`ig-YYYYMM-NNN`, status draft → approved → posted / failed / retired,
oldest-approved-first per slot, per-platform approval, "Approve on all
platforms"). Strip the WorldDePIN-specific rules (earnings caveat, store
links) and replace with IT Surgery's (below).

### Where it lives

- Repo: `IT-Architect-UK/monorepo`, new `projects/marketing/itsurgery-social/`
  (self-contained, own README — it is also a showcase piece).
- Pool: `posts.json` in that folder. Fields: `id`, `topic`, `body`,
  `ig_caption` (optional override), `headline` (optional, for the card),
  `image` (optional: path to a real photo instead of a generated card).
- Approval UI: a Social tab on dashboard.itsurgery.me, which already sits
  behind oauth2-proxy + Entra SSO. State store: Claude Code to propose the
  least new infrastructure — preference order (a) a second Supabase project
  (free tier) mirroring the WorldDePIN tables, because that code exists;
  (b) something simpler if it can still give Approve / Approve all / Retire
  / edit-body from a browser.
- Scheduler: GitHub Actions workflow in the monorepo, fired by cron from
  the itsurgery.me VPS the same way `vps/wd-trigger.sh` fires WorldDePIN
  (GitHub cron was unreliable there). Two slots a day is enough for a local
  business: 08:30 and 18:30 UK time, Mon–Sat. One post per platform per
  slot at most; a slot with nothing approved logs and exits.
- Cards: 1080×1080 JPEG per post, IT Surgery brand (logo from
  `projects/web/itsurgery/brand/`, site colours), headline in large type,
  footer "itsurgery.me · £5 to book". Committed under
  `projects/web/itsurgery/src/social/` so Netlify serves them at
  `https://itsurgery.me/social/<id>.jpg` for the Instagram fetch.

### House rules (enforced at post time, whatever the row says)

- Every Facebook body ends with the CTA
  `Book online at itsurgery.me/book — £5 to book, comes off your first hour.`
  Instagram caption ends with `Book — link in bio. itsurgery.me` plus 3–5
  hashtags from a fixed list (#Penarth #Barry #Cardiff #ITSupport
  #ComputerRepair #ValeOfGlamorgan). No hashtags on Facebook.
- Prices other than the £5 booking fee are never stated in a post — link to
  the site's price pages instead (the site is the single source of truth
  and prices change).
- "No fix, no fee" may be used; "Since 2008" must not (standing rule).
- Facebook ≤ 2,000 chars, Instagram ≤ 2,200. No URLs in Instagram captions
  except itsurgery.me in the CTA.
- Tone: friendly, plain English, no jargon, never scare-mongering.

### Content pool (Cowork's job, not code)

~40 posts, one `topic` each, mixed so consecutive posts differ: quick tips
(backups, scam calls, Wi-Fi black spots, phone storage full, printer
offline), "did you know we do…" (one service per post, from
`catalogue.json`), local (Penarth / Barry / Cardiff / Sully / Dinas Powys
mentions, house-call radius), remote support explainer, business (M365,
backups, firewalls), seasonal (back to school, Christmas new-device setup,
tax-year backups). Written by Cowork, read and approved by Darren in the
dashboard. Cowork keeps the pool topped up quarterly.

### Gates and secrets

- Dry-run until repo variable `SOCIAL_POSTING_ENABLED=true` (Facebook)
  and `SOCIAL_INSTAGRAM_ENABLED=true`. Dry-run logs exactly what it would
  post.
- Secrets in GitHub Actions, never committed: Meta system-user token with
  `pages_manage_posts`, `pages_read_engagement`, `instagram_basic`,
  `instagram_content_publish` (Bitwarden entry to be named by Darren);
  variables `FB_PAGE_ID`, `IG_USER_ID`.
- Darren/Cowork prerequisites (not code): generate the system-user token
  in Meta Business Suite for the "It Solution Architecture Limited"
  portfolio scoped to the I.T. Surgery Page and @itsurgery.me; put the
  Instagram bio link on itsurgery.me/book.

## Do this

1. Build it as specified in Context, in projects/marketing/itsurgery-social/, porting from worlddepin-dashboard (read that repo's collector/social.py, dashboard/ Social tab and 	ests/test_social.py first).
2. Propose the state store in your first reply in this file before building the dashboard tab; proceed with (a) Supabase if Darren does not answer within the session.
3. Ship dry-run only. Do not set any SOCIAL_* variable.
4. Seed posts.json with three placeholder posts that pass the house rules so the pipeline can be exercised; Cowork replaces them with the real pool.
5. Commit, push, list the prerequisites still owed by Darren/Cowork in Result.

### Verification (Claude Code)

Tests as WorldDePIN's `tests/test_social.py`: house rules per platform,
every shipped row valid, dry-run without switches, stubbed publishers,
slot independence, card rendering idempotent, dashboard/poster CTA
agreement. Then a dry-run log line from a real scheduled run before any
switch is set. First live post verified by Cowork in the browser.

### Not in scope

Replying to comments or messages; reading Facebook groups or Nextdoor
(separate proposal); paid boosts; analytics beyond the audit log.

## Result

(filled in by Claude Code)
