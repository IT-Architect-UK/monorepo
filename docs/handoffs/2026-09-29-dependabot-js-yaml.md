# Dependabot: two high js-yaml alerts in the IT Surgery site

Status: open (for Claude Code)
Raised by: Cowork, 2026-09-29

## Context

GitHub reports 2 open high-severity Dependabot alerts on `main`. Both are the
same advisory, both in `projects/web/itsurgery/package-lock.json`:

| alert | package | fixed in | summary |
|---|---|---|---|
| #5 | js-yaml (4.x line) | 4.3.2 | maxTotalMergeKeys does not limit CPU use for empty merge sources |
| #6 | js-yaml (3.x line) | 3.15.2 | same advisory, older major |

js-yaml is a build-time dependency (Eleventy / front matter), pulled in
transitively. It only parses our own files during the Netlify build, so real
risk is low - but the alerts should be cleared so the public showcase repo
looks maintained.

## Do this

1. `git pull`. In `projects/web/itsurgery/`, run `npm ls js-yaml` to see
   which packages pull in each copy.
2. Update to patched versions with the smallest change that works:
   first `npm update` for the parents; if a parent pins an old range, add an
   `overrides` entry in `package.json` for js-yaml (3.x -> ^3.15.2,
   4.x -> ^4.3.2, scoped per parent if both majors are needed).
3. Do not bump Eleventy or other direct dependencies by a major version as part
   of this.
4. Commit `package.json` and `package-lock.json` only, and push.

## Verify

- `npm ls js-yaml` shows only >= 3.15.2 / >= 4.3.2.
- `npm run build` (or the site's build script) succeeds locally with no new
  warnings, and the page count matches the previous build.
- After push, the Netlify deploy goes green and itsurgery.me, /book/ and
  /a5-flyer load normally.
- `gh api "repos/IT-Architect-UK/monorepo/dependabot/alerts?state=open"`
  returns no js-yaml alerts (Dependabot can take a few minutes to rescan).

## Result

(Claude Code: fill in the commit, `npm ls js-yaml` output and the alert check.)