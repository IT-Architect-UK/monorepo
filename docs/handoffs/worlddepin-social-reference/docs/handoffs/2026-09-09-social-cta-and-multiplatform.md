# Social: dashboard CTA mismatch, wording fixes, Instagram + X posting

Status: open
Owner: Claude Code (code) · Cowork/Darren (account setup, see Phase 2/3 prerequisites)
Written by: Cowork, 2026-09-09

## Context

Darren tried to approve the queued Facebook drafts on the Social tab today and
every Approve (and "Approve all 41 drafts") fails with the browser alert
"Cannot approve — must end with the CTA".

Cause, confirmed in the code:

- `collector/social.py` line ~45: `CTA = "Get the app: worlddepin.io/app · Free licence: worlddepin.io · hello@worlddepin.io"`.
  `seed()` → `migrate()` has already rewritten every unposted `social_posts`
  row in Supabase to end with this CTA (the bodies shown on the tab confirm it).
- `dashboard/template.html` line 1811: `const SOCIAL_CTA = 'Interested? Visit worlddepin.io or email hello@worlddepin.io';`
  — the OLD CTA (the one listed in `social.py` `OLD_CTAS`). Line 1815 rejects
  any body that does not end with it, so nothing can be approved. The modal
  (line ~1803) also tells the user the wrong "Must end with:" string.

Content review of `data/social/posts.json` (42 posts) by Cowork, 2026-09-09:

- All links resolve: worlddepin.io/app (200), worlddepin.io/uptime (200),
  discord.gg/ZEvv7984by (valid invite, no expiry), t.me/WorldDePIN (200).
- "held for 14 days" (015) matches `expiry.py EXPIRE_DAYS = 14`; "nudge after
  a week" matches `activation.py REMIND_DAYS = 7`; "off for a month → released"
  (029) matches `revocations.py THRESHOLD_DAYS = 30`.
- Policy drift: posts 004, 009, 014, 033 (and 012/031 by implication) say
  "up to 5 devices/licences per account". Darren's current policy (see
  `enquiries_onboard.py` gate, 2026-09-08): 5 is the entry batch; activated
  ULOs get further batches of 5; >5 at once escalates. Wording must not
  promise a hard cap of 5.
- Unverified by Cowork, awaiting Darren's confirmation: the earnings figure
  "$0.10–$0.50 per device per day" (posts 001, 004, 006, 007, 009, 023, 036,
  039) and "nodes earn UPS, the Unity network's reward points" (023). Do not
  change these unless Darren answers in this file or in the prompt.

Darren also asked (2026-09-09) for the same content to go to Instagram and X
with platform-appropriate formatting. Constraints:

- X: 280 characters. The current CTA is 80 chars on its own. X needs a
  short body + short CTA. Posting requires an X developer app with write
  access (OAuth 1.0a user context or OAuth 2.0 user token with `tweet.write`);
  the existing `X_BEARER_TOKEN` is app-only/read-only and cannot post.
- Instagram (Graph API, `/{ig-user-id}/media` + `/media_publish`): feed
  posts REQUIRE an image (JPEG, publicly reachable URL); captions up to 2,200
  chars; URLs in captions are not clickable. Requires the World DePIN
  Instagram to be a Business/Creator account linked to the Facebook Page
  (`/{page-id}?fields=instagram_business_account`), using the same Meta
  system-user token with `instagram_basic` + `instagram_content_publish`.

## Do this

### Phase 1 — unblock Facebook today (ship first, on its own)

1. `dashboard/template.html`: replace the hard-coded `SOCIAL_CTA` with the
   collector's value. Preferred: have `dashboard/build.py` bake
   `social.CTA` into the page (e.g. `D.social_cta`) so there is one source of
   truth; at minimum set the string to match `social.py CTA` exactly and add
   a test that fails if the two ever differ (`tests/test_social.py` already
   imports `social`; grep `template.html` for the literal).
2. Fix the modal help text at line ~1803 the same way.
3. `data/social/posts.json` + a `migrate()` rule (so the already-seeded
   Supabase rows are updated too): change the "up to 5" wording:
   - 004 item 3: "You can start with up to 5 devices on one account — more
     once they're running."
   - 009: "Yes — start with up to 5 devices per account, one licence each,
     and ask for more once they're live."
   - 014: "One free licence per device; start with up to 5 and ask for more
     once they're running."
   - 033: "Start with up to 5 licences per person, all free — more once
     they're running."
4. Run the suite. Push. Confirm on the live Social tab that one draft can be
   approved (Cowork will verify in the browser and record it below).

### Phase 2 — X (text only, no new assets)

5. Add per-platform variants without duplicating content. Keep one source
   post per id in `posts.json`; add `x_body` (≤ 280 chars incl. CTA) as an
   explicit field per post — write them, do not auto-truncate. Short CTA
   constant `CTA_X = "Free licence + app: worlddepin.io"` and house rule
   `len ≤ 280`, ends with `CTA_X`, earnings caveat rule unchanged. Where a
   post cannot be cut to 280 with the caveat intact, set `x_body: null` and
   the poster skips X for that id.
6. Storage: reuse `social_posts` with `platform` = `facebook|x|instagram`
   and id `x-202609-001` etc. (the `platform` column exists; check the
   dashboard renders the platform and that Approve/Retire work per row).
   Approving the Facebook row should NOT auto-approve the X row; add an
   "Approve on all platforms" button to the modal instead.
7. Poster: `publish_x(token…, text)` via `POST https://api.x.com/2/tweets`.
   Gate on `SOCIAL_X_ENABLED` repo variable and secrets
   `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_SECRET` (OAuth
   1.0a user context; simplest for a single account). Dry-run when absent.
   Same slots, same "oldest approved first" per platform. Audit log
   `platform: "x"`.
8. Tests: CTA/length rules, dry-run, a stubbed publish, per-platform slot
   independence.

### Phase 3 — Instagram (needs an image per post)

9. Generate a branded image card per post at build time: 1080×1080 PNG/JPEG,
   dark background matching the site, World DePIN wordmark, the post's first
   sentence (or a `headline` field if added) in large type, footer
   "worlddepin.io · free licence". Pillow is fine; commit the images under
   `site/social/<id>.jpg` so Netlify serves them at a public URL the Graph
   API can fetch.
10. `ig_caption` per post: body without the raw-URL CTA, ending with
    "Free licence + app — link in bio. worlddepin.io" and 3–5 hashtags
    (#DePIN #UnityNodes #WorldDePIN #PassiveIncome — no earnings claims in
    hashtags). Same caveat rule.
11. Poster: `publish_instagram(token, ig_user_id, image_url, caption)` =
    create container → poll status → publish. Gate on
    `SOCIAL_INSTAGRAM_ENABLED` and repo variable `IG_USER_ID`. Dry-run when
    absent.
12. Tests as Phase 2.

### Prerequisites Darren/Cowork must do (not code) — record here when done

- X: create a developer app on the World DePIN X account with Read+Write,
  generate user access token/secret, add the four secrets to the repo
  (Bitwarden entry: "X developer — World DePIN"). Set `SOCIAL_X_ENABLED=true`
  only after a dry-run log line is seen.
- Instagram: convert @worlddepin (confirm handle) to a Business account,
  link it to the World DePIN Facebook Page in Meta Business Suite, add
  `instagram_basic` + `instagram_content_publish` to the system user's
  token, set repo variable `IG_USER_ID`. Put the link-in-bio to
  worlddepin.io.
- Darren: confirm or correct the "$0.10–$0.50/day" figure and the "UPS
  points" wording (Context above).

## Result

### Phase 1 — done by Claude Code, 9 Sep 2026 08:58 UTC (commit `58b42bb`)

- `dashboard/build.py` now bakes `social.CTA` into the page as
  `D.social_cta`; `template.html` reads it (with the current CTA as the
  fallback literal). One source of truth. `tests/test_social.py` fails if
  the template ever carries an old CTA, loses `D.social_cta`, or `build.py`
  stops baking it (42/42).
- Modal help text uses the same constant, so "Must end with:" is right.
- Posts 004, 009, 014, 033 reworded exactly as specified, in
  `data/social/posts.json` and via a new `WORDING_FIXES` rule in
  `migrate()`, which the seed step applies to unposted Supabase rows on the
  next collect run (09:00). A test asserts the pool carries no hard-cap
  wording.
- Suite and `test_auth.mjs` green; built page syntax-checked; the baked
  payload contains the CTA. Netlify redeploys on this push (it touches
  `dashboard/`), so the tab picks it up within a few minutes.
- **Cowork: please verify in the browser** that one draft approves on the
  live Social tab and note it here. Earnings figure / UPS wording left
  untouched pending Darren, as instructed.

### Phases 2 and 3 — code done by Claude Code, 9 Sep 2026 (see commit below); LIVE POSTING WAITS ON THE PREREQUISITES

Built as specified, dry-run until the switches and credentials exist:

- `data/social/posts.json`: `x_body` written by hand for the 14 posts that
  do not fit 280 with the CTA (001–010, 029, 036, 039, 041); the other 28
  derive automatically (Facebook text + `CTA_X`, never truncated — a post
  that would not fit gets `x_body: null` and no X row). Earnings caveat
  kept wherever a figure survives. `ig_caption` derives: body without the
  URL CTA + "Free licence + app — link in bio. worlddepin.io" + `#DePIN
  #UnityNodes #WorldDePIN #PassiveIncome`. Explicit `ig_caption` /
  `headline` fields override if ever wanted.
- `collector/social.py`: `platform_rows()` seeds `fb-` / `x-` / `ig-` rows
  (126 rows from 42 posts, all passing `house_rules(body, platform)`);
  per-platform slots (`slot_due(rows, now, platform)`) and pools;
  `publish_x` (POST api.x.com/2/tweets, OAuth 1.0a HMAC-SHA1 in stdlib —
  `oauth1_header()`); `publish_instagram` (container → poll `status_code`
  → `media_publish`); gates `_gate()` per platform; audit rows carry
  `platform`. Approving one platform's row never touches another's.
- Instagram image cards: `ensure_images()` renders 1080×1080 JPEGs with
  Pillow (added to `collector/requirements.txt`) into `site/social/<fb
  id>.jpg` — all 42 rendered and committed now; `netlify.toml`'s build
  filter includes `site/social` so Netlify publishes them at
  `https://dashboard.worlddepin.io/social/<id>.jpg` (override with
  `SOCIAL_IMAGE_BASE`). An Instagram row whose card is missing is blocked,
  not posted.
- Dashboard: Platform column and filter, per-platform pools in the tile,
  platform-aware `checkPostText()` mirroring the poster's rules (baked
  `D.social_cta_x`, `D.social_cta_ig`, `D.social_max_len`), post links per
  platform, the Instagram modal links to its card, and **Approve on all
  platforms** in the modal. Approve-all-drafts still checks every row
  against its own platform's rules.
- `collect.yml` passes `SOCIAL_X_ENABLED`, the four `X_*` secrets,
  `SOCIAL_INSTAGRAM_ENABLED`, `IG_USER_ID`. Docs: `docs/OPERATIONS.md`
  social bullet, README status.
- Tests: `tests/test_social.py` 67/67 — derivation, house rules per
  platform, every shipped row valid, OAuth header determinism, credential
  gating, per-platform slot independence, dry-run without switch/keys,
  X and Instagram publish stubs, the container poll flow against a fake
  Graph, image rendering idempotent, dashboard/poster CTA agreement.
  Whole suite and `test_auth.mjs` green; built page syntax-checked and the
  Social tab exercised headless (platform pills, X post link, per-platform
  rule messages, card link, Approve-on-all-platforms).

**Still needed before anything posts to X or Instagram** (Cowork/Darren —
the prerequisites list above stands; record here when done):
X developer app + the four secrets, then `SOCIAL_X_ENABLED=true` after a
dry-run line appears in the collect log (`[social] DRY_RUN x slot …`);
Instagram Business account linked to the Page, token permissions,
`IG_USER_ID`, bio link, then `SOCIAL_INSTAGRAM_ENABLED=true`. The 126 rows
seed as drafts on the next collect run; the X and Instagram drafts want
Darren's read-through before approval like the Facebook ones did.

### Cowork, 9 Sep 2026 09:10 UTC

- X: the app's OAuth 1.0 access token is already for @WorldDePIN with Read and write. Darren added `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_SECRET` at 09:02-09:03 UTC (`gh secret list` confirms). Values cannot be read back; the first `[social] DRY_RUN x` line (13:00 slot) is the check before `SOCIAL_X_ENABLED` is set.
- Instagram: DROPPED. There is no World DePIN Instagram account (only @itsurgery.me, wrong brand). Do not set `SOCIAL_INSTAGRAM_ENABLED`; the `ig-` rows will sit as drafts. Claude Code: optional follow-up to stop seeding `ig-` rows (or retire them) so the Drafts count is not padded by 42 rows nobody will approve.
- Earnings / UPS wording: still awaiting Darren.
### Claude Code, 9 Sep 2026 — Instagram follow-up

- `collector/social.py`: `SEEDED_PLATFORMS = ("facebook", "x")`. `seed()`
  no longer creates `ig-` rows and retires any `ig-` row still in
  draft/approved (status `retired`, error column "retired 2026-09-09: no
  World DePIN Instagram account"); posted rows are untouched, the step is
  idempotent. `run()` skips the card renderer and only polls Facebook and
  X slots. The Instagram publisher, caption and card code stay for the day
  an account exists — add `"instagram"` back to `SEEDED_PLATFORMS`.
- Social tab note and `docs/OPERATIONS.md` / `README.md` reworded.
- `tests/test_social.py` (70 checks) covers the seed set and the retire
  step. Full suite green.
- X: nothing changes here — once Darren approves at least one `x-` draft,
  the next slot run (13:00 / 20:00 / 09:00 UTC) logs
  `[social] DRY_RUN x slot … would post x-…`; `SOCIAL_X_ENABLED=true` after
  that. A slot with no approved X row logs "nothing approved to post".

### Cowork, 9 Sep 2026 09:45 UTC — Phase 1 verified live

- Darren approved fb-202609-002 on the live Social tab after the Netlify redeploy: no alert, status went to approved. The 09:30 collect run (inside the 09:00 slot hour) published it to facebook.com/WorldDePIN — seen on the page.
- Page housekeeping done by Darren after Cowork's review of the 19 published posts: dead Discord invite (r7j9PrQd) removed from the page intro; the 27 Apr "referral system coming soon" post un-featured. All other links resolve; content consistent with the drafts.
- Still open for Claude Code: stop seeding `ig-` rows (Instagram dropped). Still open for Darren: earnings / UPS wording confirmation; bulk-approve the Facebook drafts once the ig- rows are gone.