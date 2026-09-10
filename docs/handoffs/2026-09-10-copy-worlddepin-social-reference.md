# Copy the WorldDePIN social pipeline source into this repo as reference
Status: done

## Context
The social-posting handoff (2026-09-10-itsurgery-social-posting.md) asks
Claude Code to port the pipeline from `WorldDePIN/worlddepin-dashboard`.
Claude Code's session can only hold repos from one GitHub owner and cannot
add a WorldDePIN repo (platform limit, confirmed 2026-09-10), and the repo is
private so it cannot be cloned anonymously. Darren chose to copy the
reference files into this repo instead.

## Do this
From a local clone of `WorldDePIN/worlddepin-dashboard` (main), copy these
into `docs/handoffs/worlddepin-social-reference/`, keeping their relative
paths under that folder:

1. `collector/social.py`
2. `tests/test_social.py`
3. The dashboard Social tab: every file the Social tab is made of
   (template, JavaScript, styles, and the server/API handlers it calls for
   approve / approve-all / retire / edit-body). If unsure which, include
   the whole `dashboard/` directory.
4. Any module `social.py` imports from within that repo (for example the
   card renderer / `ensure_images()` helper, the Supabase client wrapper,
   config/settings), so the copied code can be read without gaps.
5. `docs/handoffs/2026-09-09-social-cta-and-multiplatform.md`
6. The repo's `requirements.txt` / `pyproject.toml` and any GitHub Actions
   workflow that runs the social poster (`.github/workflows/*social*`).
7. The Supabase table definitions the social code uses (SQL or migration
   files), if they are in the repo.

Then add `docs/handoffs/worlddepin-social-reference/README.md` with one
line: the source commit hash and date copied, and "reference only - not
built, not tested here; delete once ported". Do NOT copy any `.env`,
token, key or credential file, and check none of the copied files embeds
one. Commit and push.

## Result
Done by Cowork, 2026-09-10, from the local clone `D:\GitHub\worlddepin-dashboard`
(main, clean, at `f2d6bef3`, 2026-09-09).

Copied to `docs/handoffs/worlddepin-social-reference/` with paths kept:
`collector/social.py`, `collector/audit.py`, `collector/templates.py`
(the only in-repo imports - Supabase is called over REST inside social.py,
no client wrapper exists), `collector/requirements.txt`,
`dashboard/build.py`, `dashboard/template.html` (the Social tab and all its
approve/retire/edit handlers are inside this one template; approvals go
straight to Supabase from the browser - no server handlers exist),
`tests/test_social.py`, `data/social/posts.json` (pool format, not asked
for but useful), `supabase/migrations/20260831190000_social_posts.sql`,
`.github/workflows/collect.yml` + `test.yml` (no `*social*` workflow
exists; the poster runs as a stage inside collect.yml, see line ~600 of
collect.py and the SOCIAL_* env block), `netlify.toml` (publishes the
cards), and the 2026-09-09 handoff. README.md added with the commit hash,
date and the "reference only" line.

Not copied: `collector/session.enc`, `data/*` other than the pool, the
rendered cards. Grep of the copied tree for Meta/Supabase/JWT/AWS/GitHub
token patterns and PEM headers: nothing. Differences from the plan: none.
