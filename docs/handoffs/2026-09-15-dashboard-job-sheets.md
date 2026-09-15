# Dashboard: a Job sheets section, one branded printable sheet per service

Status: open
Owner: Claude Code (code) / Cowork (sheet content for the remaining services)
Asked for by Darren 2026-09-15.

## Context

IT Surgery's first customer visit is 2026-09-16 (malware pop-ups, Surface
Pro). Cowork wrote a job sheet for it as a Word/PDF document
(Freelancer folder, `jobs/2026-09-16-stonhold-sully/`). Darren wants job
sheets for every service in the catalogue, and wants them to live on
dashboard.itsurgery.me as a new section rather than as loose documents.

What exists:

- `dashboard.itsurgery.me` sits behind oauth2-proxy + Entra. Its pages are
  rendered by n8n workflows in `automation/n8n/workflows/` (`dashboard.json`,
  `monitoring.json`); the nav is Dashboard / Monitoring / Webmin / Backup /
  Guide.
- The service catalogue is `projects/web/itsurgery/src/_data/catalogue.json`
  (47 services; `slug`, `name`, `group`, `audience`, `durationMinutes`,
  `priceIncVat` for home / `priceExVat` for business, `bookable`).
  `bookingFeeGbp` is 5. `services.json` holds the per-service-page copy
  (`points` = what the site promises for that service).
- Brand (from `Freelancer/brand-and-decisions.md`): master logo is
  `docs/handoffs/jobsheet-reference/IT_Surgery_Logo_RGB.jpg` (1769x514) -
  move it to `projects/web/itsurgery/brand/` as part of this work, since
  that folder only holds the social crops today. Brand red `#990000`,
  headings Poppins 600 `#222222`, body `#333333`, tagline "Curing IT
  Headaches". Never "Since 2008".
- Company footer line: IT Solution Architecture Limited t/a IT Surgery,
  07775 580371, help@itsurgery.me, itsurgery.me (from `site.json`).
- The worked example: `docs/handoffs/jobsheet-reference/jobsheet.js` is the
  docx-js source of the malware sheet; `page-1.jpg` beside it is how the
  rendered header looks. Its content is the spec for the section layout:
  header block (job ref, visit date/time, customer, address, phone/email,
  device, reported problem, service line with duration and price, terms,
  price agreed), "What this almost certainly is" (ranked likely causes),
  "Before you go" (phone-call checklist), "Kit to take", "On site" steps
  A-G (Triage, Contain, Find and remove, Scan, Protect, Prove it and hand
  over, After the visit) as tick-box tables with a Result/notes column,
  "Record" block, Appendix A (USB toolkit), Appendix B (plain-English
  handover script).
- CRM is EspoCRM at crm.itsurgery.me; bookings arrive as `Lead` records
  with custom fields `cBookingId`, `cBookingStart`, `cPayUrl` (n8n API user;
  custom fields carry a `c` prefix; unknown fields are silently dropped).

## Do this

### Phase 1 - templates in the repo, rendered on the dashboard

1. Templates live in the repo, one per catalogue slug:
   `projects/web/itsurgery/jobsheets/<slug>.md` (Markdown with a small
   front-matter block). Sections are fixed so every sheet reads the same:
   `likely` (ranked causes / what to expect), `before` (phone-call
   checklist), `kit`, `steps` (lettered groups, each a checklist), `record`
   fields, `handover` (plain-English script), `appendix` (optional). A
   checklist line is `- [ ] step text` with an optional indented
   `  > note` line under it. Write a `README.md` in that folder saying how
   to write one.
2. Convert the malware sheet from `jobsheet.js` into
   `home-malware-removal.md` faithfully (all content, same order). Then
   generate a skeleton for every other bookable slug from `catalogue.json`
   + `services.json`: header from the catalogue, the service's `points`
   listed under `likely` as "what the site promises", and the generic
   steps every visit shares (arrive/triage, agree price, do the work,
   prove it, invoice and pay, ask for a review, update CRM). Mark each
   skeleton `status: skeleton` in front-matter; Cowork will replace the
   content service by service.
3. **Output is Word (.docx), not HTML/PDF.** Darren 2026-09-15: "I need
   to be able to amend, so PDF should not be used." Each template is
   rendered to a .docx with docx-js exactly as `jobsheet.js` does (same
   helpers: kv table, checklist table with the tick-box column and
   Result/notes column, h1/h2 in Poppins, logo + tagline + red rule header,
   company footer with page number). Put the generator in the repo as
   `projects/web/itsurgery/jobsheets/build.js` (Node, `docx` package,
   reads every `<slug>.md`, writes `dist/JS-<slug>.docx`). Run it in CI on
   push to main when anything under `jobsheets/` changes, and publish the
   .docx files where the dashboard can serve them behind SSO (the VPS
   already serves the dashboard; a static folder is fine - your call,
   state it in Result). Templates must be committed files so Cowork can
   edit content by handoff.
4. New dashboard section **Job sheets** (nav entry after Monitoring):
   - Index page: the services grouped as in the catalogue, each with
     duration, price, a "Download Word sheet" link and the template's
     status (full / skeleton). Skeletons are labelled as such.
   - Header fields in the .docx (job ref, date, time, customer, address,
     phone, email, device, reported problem, price agreed) are left as the
     blank/underscored cells in the reference sheet - Darren fills them in
     Word. Job reference guidance on the index page: `JS-YYYY-NNN`, next
     free number shown from n8n static data and incremented when Darren
     clicks "Take next number"; JS-2026-001 is taken (the Stonhold visit).
   - Optional, only if cheap: `?lead=<id>` on the index produces a .docx
     with the header pre-filled from the EspoCRM Lead (n8n API user: name,
     phone, email, address, `cBookingStart`, description). That needs the
     generator callable from n8n (Node on the VPS, or a GitHub
     `workflow_dispatch` that commits the file) - if it is not cheap,
     leave it for Phase 2 and say so.
5. Deploy the way the other dashboard workflows deploy. Verify: every
   bookable service has a .docx; open `JS-home-malware-removal.docx` and
   confirm it matches the reference sheet section for section (compare
   with `jobsheet-reference/page-1.jpg` for the header); the file opens
   in Word without a repair prompt (run the docx validator if there is
   one in the toolchain); the index page lists and serves the files.
   Put the URL and the list of generated files in Result.

### Phase 2 (separate handoff, not now)

Upload the completed .docx from the visit against the Lead (attachment +
note with the Record block), mark the Lead converted/closed, and raise the
Xero invoice for the service line from the same page. Pre-filled headers
from a Lead if not done in Phase 1.

## Result

(filled in by Claude Code)
