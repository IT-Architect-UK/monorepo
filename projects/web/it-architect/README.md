# IT Architect — website (`projects/web/it-architect/`)

The consultancy site for **IT Architect**, the professional-services trading name
of IT Solution Architecture Limited. Aimed at clients hiring for cloud,
infrastructure, security and applied-AI work, including via freelance platforms.

**What this demonstrates:** a templated, accessible (WCAG 2.1 AA) static site
built with Eleventy — 13 pages from shared layouts and structured data, deployed
by CI on push to Netlify. The site is itself a work sample.

## Quick start

```bash
npm install
npm run serve   # http://localhost:8080
npm run build   # production build into _site/
```

> Build on a local Linux/macOS path or `/tmp`. Building on a OneDrive- or
> NTFS-mounted path fails with `EPERM ... unlink` when Eleventy clears `_site`.

## Structure

| Path | Purpose |
|------|---------|
| `src/_data/site.json` | Contact details, company identifiers, navigation. Single source of truth. |
| `src/_data/services.json` | The five service areas. One entry generates a full page. |
| `src/_data/experience.json` | Engagement history, **client names deliberately anonymised by sector**. |
| `src/service.njk` | One template generating every service page via pagination. |
| `src/_includes/layouts/base.njk` | Page shell, schema.org markup, mobile menu script. |
| `src/assets/styles.css` | All styling. No framework. |
| `src/assets/logo.png` | Brand logo, resized from `Logos/IT Architect/PNG/LOGO-TRANSPARENT-BG.png`. |

## Client confidentiality

Engagements are described **by sector only** — "a global airline group", "a UK
life and pensions provider". Client names are not used anywhere on the site, by
deliberate choice: contracts commonly restrict using client names in marketing,
and naming them adds no credibility a described outcome does not already carry.

There is an automated check for this. Before publishing, confirm no client names
have crept in:

```bash
grep -rIn -e IAG -e ReAssure -e Kyndryl -e Cyberbase _site/ && echo LEAK || echo clean
```

## Brand

Shares the logo red `#990000` with IT Surgery, so the two brands are separated by
treatment rather than colour:

| | IT Architect | IT Surgery |
|---|---|---|
| Typeface | Inter | Poppins |
| Surfaces | Dark slate `#1c2430` | Light, warm |
| Register | Corporate, technical | Friendly, plain-English |

Two contrast pitfalls, both caught by audit and fixed — do not reintroduce them:

- `#990000` as text on the dark slate is only **2.8:1**. Use `--brand-light`
  (`#ef9a9a`, 7.3:1) for brand-coloured text on dark surfaces.
- The standard focus ring `#0b57d0` is only **2.5:1** on slate. Dark sections
  override it to `--focus-dark` (`#7cb0ff`).

## Deploy (Netlify)

1. Create a Netlify site from `IT-Architect-UK/monorepo`.
2. Set **Base directory** to `projects/web/it-architect`.
3. Build `npm run build`, publish `_site` (already in `netlify.toml`).
4. Enable **form detection** under Forms, or the contact form will 404 on submit.
5. Add an email notification for form submissions.
6. Point DNS at Netlify — see below.

## DNS — read before changing anything

`it-architect.uk` is hosted in Route 53 and **carries live Microsoft 365 email**.

- **Do not move the nameservers to Netlify.** It would break MX records and mail
  would stop.
- Apex: **A record to `75.2.60.5`** (Netlify's documented fallback — Route 53
  ALIAS only targets AWS resources, and CNAME is illegal at a zone apex).
- `www`: CNAME to the `.netlify.app` host.

The existing content is a single page on a self-hosted WordPress multisite. Once
this site is live and verified, that WordPress instance no longer needs to serve
this domain.

## Still to do

- Confirm the certifications list — only two of the stated 23 are named here.
- Add a photograph of Darren; a real face lifts a consultancy site.
- Review whether any employment contract restricts soliciting contract work.
