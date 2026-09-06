# Web

Websites for the business's two trading brands, built as static sites and
deployed to Netlify (CI on push, automatic TLS). Source of truth lives here in
the monorepo — nothing is edited on the server.

## Projects

| Project | Path | Purpose |
|---------|------|---------|
| IT Surgery | `itsurgery/` | Local IT support for homes and small businesses in Penarth, Barry and Cardiff. Eleventy, 40 pages. Takes live bookings and deposits. |
| IT Architect | `it-architect/` | Consultancy site — cloud, infrastructure, security and applied AI. Eleventy, 13 pages. |
| IT Surgery dashboard | `itsurgery-dashboard/` | Pointer only. `dashboard.itsurgery.me` is an n8n workflow in `automation/n8n/`, not a static site; the README there says where everything is and why. |

Each project is self-contained with its own README, dependencies and deploy
configuration, and can be built and run on its own.

Cal.com scheduling is live for IT Surgery: `automation/calcom/sync-event-types.py`
keeps the event types in step with the service catalogue, the n8n workflows
`cal-booking.json` and `cal-get-pay-link.json` handle each booking, and the
calendar itself is embedded on `/book/`. Planned, not started: an AI
enquiry-triage agent for the site. It has no directory here yet.

## Conventions

- **Static output.** No runtime server; the build produces plain HTML/CSS.
- **Accessibility.** WCAG 2.1 AA as a baseline — these sites are used by
  non-technical and older visitors.
- **Single source of truth for content.** Site-wide values (phone, email, rates,
  navigation) live in one data file per project, not repeated across templates.
- **Preserve URLs.** When replacing an existing site, keep the original paths so
  search rankings and inbound links survive.
