# IT Surgery — website (`projects/web/itsurgery/`)

The public website for **IT Surgery**, the local IT-support trading name of
IT Solution Architecture Limited. Friendly, plain-English IT help for homes and
small businesses across Penarth, Barry and Cardiff.

**What this demonstrates:** a templated, accessible (WCAG 2.1 AA) static site
built with Eleventy — 22 pages generated from shared layouts and structured data,
deployed by CI-on-push to Netlify with automatic TLS. No servers, no certificates
to renew, no page-to-page drift.

## Quick start

```bash
npm install     # once
npm run serve   # local preview at http://localhost:8080 with live reload
npm run build   # production build into _site/
```

> Build on a local Linux/macOS filesystem. Building directly on a OneDrive- or
> NTFS-mounted path can fail with `EPERM ... unlink` when Eleventy clears its
> output directory.

## How it is put together

| Path | Purpose |
|------|---------|
| `src/_data/site.json` | **Single source of truth** for phone, WhatsApp, email, address, rates and menu structure. Change the phone number here and it updates on all 22 pages. |
| `src/_data/services.json` | The 15 service pages as data — title, summary, intro, body, bullet points. |
| `src/service.njk` | One template that generates every service page from `services.json` via pagination. |
| `src/_includes/layouts/base.njk` | Page shell: `<head>`, schema.org markup, header, footer, mobile-menu script. |
| `src/_includes/partials/header.njk` | Utility bar, logo, main menu with dropdowns. |
| `src/_includes/partials/footer.njk` | Footer with full service listings and contact details. |
| `src/assets/styles.css` | All styling. No CSS framework. |
| `eleventy.config.cjs` | Eleventy config — input `src/`, output `_site/`. |
| `netlify.toml` | Netlify build settings and security headers. |

### Adding a service page

Add an object to `src/_data/services.json` with `slug`, `title`, `group`
(`business` or `personal`), `summary`, `intro`, `body` and `points`. The page,
the menu entry, the hub-page card, the footer link and the site map all appear
automatically. No template edits needed.

Optionally add `fixedPrices`, a list of catalogue slugs from `catalogue.json`.
Those jobs render on the service page as a "Fixed prices for this" box with
prices, times and Book buttons, joined via `src/_data/catbyslug.js`. Leave it
out and the page shows a "Get a quote" button instead.

## Pages

`/` · `/pricing/` · `/about-us/` · `/quote/` · `/site-map/`
`/business-it/` + 8 service pages · `/personal-it/` + 7 service pages

URLs deliberately match the previous itsurgery.me site so existing search
rankings and any external links are preserved.

## Brand

Carried over from the original site:

| Element | Value |
|---------|-------|
| Tagline | Curing IT Headaches |
| Brand red | `#990000` |
| Headings | Poppins 600, `#222222` |
| Body text | System UI stack, `#333333` |
| Dark panels | `#3f444b` / `#2f3338` |
| Logo | Inline SVG cross (sharp at any size, no image file) |

Poppins loads from Google Fonts. To drop that third-party dependency, self-host
the `woff2` files and add an `@font-face` rule — the body stack needs no webfont.

## Pricing shown on the site

£30 per hour. £20 booking fee, deducted from the first hour, refunded if the
problem cannot be fixed ("no fix, no fee").

## Contact channels

Phone, WhatsApp (`wa.me` click-to-chat) and email sit in the top utility bar on
every page, all the same size. The Quote Request page carries a callback form
handled by **Netlify Forms** — no backend required; submissions appear in the
Netlify dashboard.

## Theming (light / dark)

Colour tokens are named by **role**, not appearance — `--surface`, `--text`,
`--brand-accent` — because a token called `--white` cannot be re-pointed for a
dark theme without the name becoming a lie. Light values live in `:root`, dark
values override the same names in `[data-theme="dark"]`.

**Rule: no colour literal belongs in any rule outside those two blocks.** Check
before committing:

```bash
python3 - <<'EOF'
import re
s=open('src/assets/styles.css').read()
b=re.sub(r':root \{.*?\n\}\n','',s,flags=re.S)
b=re.sub(r'\[data-theme="dark"\] \{.*?\n\}\n','',b,flags=re.S)
b=re.sub(r'/\*.*?\*/','',b,flags=re.S)
print(sorted(set(re.findall(r'#[0-9a-fA-F]{3,8}|rgba?\([^)]*\)', b))) or 'clean')
EOF
```

Three things that will bite if forgotten:

- **`--brand-solid` and `--brand-accent` are different roles.** `#990000` is a
  fine button fill but only 2.8:1 as text on a dark surface, so the accent
  lightens in dark mode and the fill brightens (a dark red fill goes muddy on a
  near-black page). Never collapse them back into one token.
- **"invert" surfaces are dark in *both* themes.** In dark mode the page is
  darker than they are, so they read as raised panels instead of merging into
  one flat void. Anything sitting on an invert surface therefore keeps fixed
  light values (`--chip-bg`, `--on-invert-strong`).
- **The theme script in `<head>` must stay inline and blocking.** Moved to an
  external file it runs after the stylesheet has painted, and every navigation
  gives dark-mode visitors a white flash.

**Resolution order: explicit choice, then OS, then light.** A theme the visitor
has picked here always wins and persists in `localStorage`. Otherwise the site
follows `prefers-color-scheme`. `matchMedia` reports false when the OS states no
preference, so light is the fallback without a special case. The OS is also
followed live, but only until the visitor makes a choice of their own. The
toggle is hidden until JS reveals it, so it is never shown in a state where it
cannot work.

## Deploy (Netlify)

1. Create a Netlify site from the `IT-Architect-UK/monorepo` repository.
2. Set **Base directory** to `projects/web/itsurgery`.
3. Build command `npm run build`, publish directory `_site` (already in `netlify.toml`).
4. Verify the deploy, then point `itsurgery.me` at Netlify.
5. Enable form detection so the Quote Request form is captured.

## Images — deliberately none

The site is text-only by design. The stock photography on the previous site was
generic, appeared on every competitor's site from the same libraries, and worked
against the "local, personal, real person" positioning while costing mobile load
time. The layout is built to look complete without images.

Worth adding later, when available:

- A photo of Darren for the About Us page — the strongest trust signal for a
  local service business.
- Before/after or on-the-job photos from real customer visits.

## Still to do

- Embed the Cal.com booking widget on the Quote Request page once configured.
- Add a Reviews page and testimonials as they arrive.
- Confirm whether the Sully address should be published (it is on the current site).

## CRM integration (Netlify Forms to EspoCRM)

Quote form submissions become Leads in EspoCRM at crm.itsurgery.me.

The form still posts to Netlify exactly as before, so the submission is
captured and the notification email sent **first**. Only then does an outgoing
webhook call `netlify/functions/crm-lead.js`, which reshapes the payload and
creates the Lead. If the CRM is down the enquiry is not lost — it is still in
Netlify's dashboard and still reached the inbox, it just needs entering by hand.

### Setting it up

**1. In EspoCRM** — Administration > Lead Capture > create a record.

Set *Payload Fields* to: `firstName`, `lastName`, `emailAddress`,
`phoneNumber`, `description`. Fields not listed there are silently discarded,
so this is the setting most likely to cause a puzzling empty Description later.

Set *Lead Source* to **Web Site** and *Telephone country code* to **GB +44**.
The function does not send a source — the capture record applies it.

**Leave "Subscribe to Target List" unchecked.** It exists for mailing-list
signups, and ticking it makes Target List mandatory. Someone asking for help
with a slow laptop has not consented to marketing, and auto-subscribing them
would be a UK GDPR problem.

*Duplicate Check* is worth leaving on, but be aware it means a second enquiry
from the same person may not create a second Lead.

The side panel then shows the full endpoint URL including the API key — copy it.

**2. In Netlify** — Site configuration > Environment variables:

| Variable | Value |
|---|---|
| `ESPOCRM_LEAD_CAPTURE_URL` | the endpoint URL from step 1, key included |
| `NETLIFY_WEBHOOK_JWS_SECRET` | a secret you generate; used in step 3 |

**3. In Netlify** — Forms > Form notifications > add an **outgoing webhook**:

- Event: new form submission
- Form: `quote`
- URL: `https://itsurgery.me/.netlify/functions/crm-lead`
- JWS secret: the same value as `NETLIFY_WEBHOOK_JWS_SECRET`

The JWS secret is not optional. Without it the function is a public endpoint
and anyone could inject Leads; it rejects unsigned and mis-signed requests.

### Checking it works

Submit the form, then look at Netlify > Functions > `crm-lead` for
`created lead from submission <id>`, and at Leads in EspoCRM.

The function never logs the enquirer's name, phone number or problem — function
logs are not an appropriate place for customer data. Only the submission ID and
the outcome are logged, which is enough to trace a failure.
