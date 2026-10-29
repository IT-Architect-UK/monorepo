# Dependabot: merge the four open PRs and clear six alerts

Status: open (for Claude Code)
Raised by: Cowork, 2026-10-29

## Context

Health check 2026-10-29. The monorepo has 6 open Dependabot alerts, all in
`projects/web/itsurgery/package-lock.json`, all build-time only (same low
real risk as the js-yaml ones in September; the reason to fix is that the
public showcase repo shows "2 high" on its Security tab).

| alert | severity | package | fixed in |
|---|---|---|---|
| #7, #11, #12, #13 | high x2, medium, low | markdown-it < 14.3.3 | 14.3.3 |
| #9 | medium | brace-expansion < 1.1.21 | 1.1.21 |
| #8 | medium | sprintf-js <= 1.1.3 | advisory withdrawn, no patched version |

Dependabot has already opened PRs. Four are open:

| PR | what |
|---|---|
| #7 | bump markdown-it 14.3.0 -> 14.3.3 (itsurgery site) |
| #6 | bump brace-expansion 1.1.18 -> 1.1.21 (itsurgery site) |
| #5 | bump actions/setup-node 4 -> 7 (CI) |
| #4 | bump actions/setup-python 5 -> 7 (CI) |

Nobody has looked at PRs #4 and #5 since 1 October. From now on, treat
Dependabot PRs as part of the normal queue rather than leaving them.

## Do this

1. `git pull`. Merge #7 and #6 (the site). `npm run build` in
   `projects/web/itsurgery/` must still succeed with the same page count
   (41 HTML pages last time) and no new warnings.
2. Merge #5 and #4 (CI). Check the workflows that use `setup-node` /
   `setup-python` for any breaking input changes between the majors
   (`node-version` / `python-version` handling, caching). Fix if needed.
3. Alert #8 (sprintf-js) has no patched version and the advisory is
   withdrawn. If it is still open after the merges, dismiss it on GitHub
   with reason "no fix available / advisory withdrawn" - or hand that back
   to Cowork if the session cannot reach the Dependabot API.
4. Push. Don't bump Eleventy or any direct dependency by a major as part
   of this.

## Verify

- `npm ls markdown-it brace-expansion` shows >= 14.3.3 and >= 1.1.21.
- Netlify deploy green; itsurgery.me, /book/ and /a5-flyer return 200.
- All CI workflows on main green after the Actions bumps.
- `gh api "repos/IT-Architect-UK/monorepo/dependabot/alerts?state=open"`
  returns nothing, or only #8 pending dismissal.
- `gh pr list` shows no open Dependabot PRs.

## Result

(Claude Code: fill in merged PRs, build output, alert check, anything
handed back to Cowork.)