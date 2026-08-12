# Web

Websites for the business's two trading brands, built as static sites and
deployed to Netlify (CI on push, automatic TLS). Source of truth lives here in
the monorepo — nothing is edited on the server.

## Projects

| Project | Path | Purpose |
|---------|------|---------|
| IT Surgery | `itsurgery/` | Local IT support for homes and small businesses in Penarth, Barry and Cardiff. Eleventy, 34 pages. Takes live bookings and deposits. |
| IT Architect | `it-architect/` | Consultancy site — cloud, infrastructure, security and applied AI. Eleventy, 13 pages. |
| Enquiry agent | `enquiry-agent/` | AI enquiry triage + Cal.com scheduling agent driving bookings for the IT Surgery site *(planned)*. |

Each project is self-contained with its own README, dependencies and deploy
configuration, and can be built and run on its own.

## Conventions

- **Static output.** No runtime server; the build produces plain HTML/CSS.
- **Accessibility.** WCAG 2.1 AA as a baseline — these sites are used by
  non-technical and older visitors.
- **Single source of truth for content.** Site-wide values (phone, email, rates,
  navigation) live in one data file per project, not repeated across templates.
- **Preserve URLs.** When replacing an existing site, keep the original paths so
  search rankings and inbound links survive.
