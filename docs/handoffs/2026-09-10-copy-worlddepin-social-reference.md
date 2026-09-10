# Copy the WorldDePIN social pipeline source into this repo as reference
Status: open

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
(filled in by Cowork)
