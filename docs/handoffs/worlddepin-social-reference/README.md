# WorldDePIN social pipeline - reference copy

Copied from `WorldDePIN/worlddepin-dashboard` main at commit
`f2d6bef3ab08b3567a2b3bfdf809301a57de030b` (2026-09-09 10:37 +0100), on
2026-09-10. Reference only - not built, not tested here; delete once
ported to `projects/marketing/itsurgery-social/`.

Files and why:

- `collector/social.py` - the pipeline (seed / migrate / house rules /
  slots / Facebook, X, Instagram publishers / Pillow card renderer).
- `collector/audit.py`, `collector/templates.py` - the only in-repo modules
  `social.py` imports. Supabase is called over plain REST inside
  `social.py` (`seed()`, `post_one()`); there is no separate client
  wrapper.
- `dashboard/build.py`, `dashboard/template.html` - the whole dashboard is
  one template; the Social tab, its approve / approve-all / retire / edit
  handlers and the platform rules live inside `template.html` (search for
  `social_cta`, `social_posts`). Approvals write to Supabase directly from
  the browser behind login + RLS; there are no server-side handlers.
- `tests/test_social.py` - 70 checks; the spec in executable form.
- `data/social/posts.json` - the pool format (`id`, `platform`, `topic`,
  `body`, optional `x_body`, `ig_caption`, `headline`).
- `supabase/migrations/20260831190000_social_posts.sql` - the table.
- `.github/workflows/collect.yml`, `test.yml` - how the poster is run and
  which variables/secrets it is passed (`SOCIAL_*`, `META_TOKEN`,
  `FB_PAGE_ID`, `IG_USER_ID`, `X_*`).
- `netlify.toml` - the build filter that publishes `site/social/*.jpg` for
  the Instagram fetch.
- `collector/requirements.txt` - Pillow is the only extra dependency.
- `docs/handoffs/2026-09-09-social-cta-and-multiplatform.md` - the design
  handoff and its results.

Not copied: `collector/session.enc` (encrypted session), anything under
`data/` other than the posts pool, the 42 rendered cards. Scanned for
tokens/keys before commit: none.
