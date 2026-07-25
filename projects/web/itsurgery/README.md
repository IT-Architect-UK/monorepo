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
