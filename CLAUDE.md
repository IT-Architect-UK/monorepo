# Working in this repo

**Pushing to main deploys.** `automation/n8n/**` goes straight to the live n8n
instance via `deploy-n8n.yml` (pull requests get a dry run only).
`projects/web/itsurgery/**` goes straight to live itsurgery.me and
`projects/web/it-architect/**` to live it-architect.uk, both via Netlify.
There is no staging. Propose, get approval, then push. Darren works alone on
this repo and commits to main directly; no branches or PRs unless he asks.

## What this repo is

One monorepo for IT Solution Architecture Limited, five things at once:

- **itsurgery.me**, `projects/web/itsurgery/`: the IT Surgery site (local and
  remote IT help, trading name for consumers and small businesses).
- **it-architect.uk**, `projects/web/it-architect/`: the IT Architect
  consultancy site (cloud, infrastructure, security, applied AI).
- **IT Surgery business automation**, `automation/n8n/workflows/`: booking,
  payment, CRM and Stripe flows, and the business **dashboard**
  (`dashboard.json`, served by n8n at dashboard.itsurgery.me, not by the
  website; `automation/n8n/README.md` says why, and
  `projects/web/itsurgery-dashboard/README.md` is the pointer to it).
- **The deployment toolbox**: `automation/packer` (golden images for Proxmox,
  vSphere, AWS, Azure, GCP), `automation/ansible`, `containers`, `cloud`,
  `infrastructure`, `monitoring`, `backup`, `security`, `scripts` - for
  building servers and services locally or on cloud platforms.
- **A public work sample.** The repo is itself part of Darren's portfolio, so
  READMEs, commit messages and code quality are on show. Nothing private or
  customer-identifying goes in.

## Which Claude to use

Claude Code (this) has no browser, no logins and no internet from its headless
browser. Use it for the repo, the site, scripts and anything verifiable here.
The moment a task means operating a web app Darren is logged into (Meta
Business Suite, Facebook Page settings, Google Ads or Analytics consoles,
Netlify dashboard, Cal.com, EspoCRM), say so at once and hand off to Claude in
Chrome or Cowork, which can see and drive the page. Do not walk him through
screenshots. Bring only the outputs the repo needs (an ID, a URL) back here.

## Build and CI

- Site: `cd projects/web/itsurgery && npm ci && npm run build` (Eleventy 3,
  Node 20 on Netlify, output `_site/`). No lint or test covers the site's JS.
- CI on every push and PR: `validate.yml` (bash -n, ansible syntax, packer
  validate, PowerShell parse), `lint.yml` (shellcheck, yamllint --strict,
  ansible-lint, PSScriptAnalyzer), `test.yml` (pytest over `automation/**/tests`,
  py_compile). ansible-lint's setup fetches Galaxy collections and has failed on
  a Galaxy 504 that was nothing to do with the commit; re-run before digging.

## Site gotchas (projects/web/itsurgery)

- `src/_data/catalogue.json` is the service catalogue (prices, durations,
  Cal.com slugs). `services.json` is NOT: it generates the service pages, and
  overwriting it broke the build. `bookmap.js`, `bookableslugs.js`,
  `bookablenames.js` and `catbyslug.js` derive from catalogue.json; never edit
  them. Use the `add-itsurgery-service` skill for catalogue changes.
- Templates are Nunjucks, not Jinja. `selectattr('equalto')` does not exist and
  fails silently. Do joins in a `_data` JS file.
- A `force = true` Netlify redirect on `/book` once shadowed the real page.
  Never reinstate a redirect covering `/book`.
- The Content-Security-Policy is generated at build time into `_site/_headers`
  with a hash of every inline `<script>` (see `eleventy.config.cjs`). Static
  headers live in `netlify.toml`. A new external host (a tag, an embed, a
  fetch) must be added to the CSP or the browser refuses it silently for
  users; GA4 posts to `*.analytics.google.com`, not the bare host.
- Google Analytics/Ads load only after the cookie banner (`src/assets/consent.js`);
  the privacy page's Cookies section describes that behaviour and must move
  with it. The GA4 ID is in `site.json`.
- Colour literals belong only in `:root` and `[data-theme="dark"]` in
  `styles.css`; the README has the check.
- Off-site brand assets (Ads, Facebook) are in `brand/`, rendered by
  `tools/build-brand-assets.js`; the share card by `tools/build-og-image.js`.
  Both need Playwright and Poppins installed locally.

## Automation gotchas

- n8n: a parameter is an expression only if the WHOLE value starts with `=`.
  Code nodes run once for all items and bare `$json` is undefined; use
  `$input.first().json`. Use `onError: continueRegularOutput`. Static data does
  not survive a redeploy. Retry-from-error replays old data.
- Ansible runs on the VPS itself (`ansible_connection: local`). Vault is at
  `inventory/group_vars/<group>/vault.yml`; `group_vars/<group>_vault.yml` is
  silently ignored.
- Packer file references use `abspath("${path.root}/...")`.
- Cal.com's API needs the header `cal-api-version: 2024-06-14`, and Cloudflare
  bans urllib's default User-Agent (error 1010). Both are handled in
  `automation/calcom/sync-event-types.py`; do not simplify them out.
- Secrets live in Bitwarden. Never commit a token or embed one in a remote URL.
