# Dashboard: a Job sheets section, one branded printable sheet per service

Status: done (Phase 1); content for 48 skeleton sheets is Cowork's
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

Claude Code, 2026-09-15. Everything is in the repo and deploys on this
push: the n8n page through `deploy-n8n.yml`, the Word files through the
new `jobsheets.yml`.

**Where things are**

- Templates: `projects/web/itsurgery/jobsheets/<slug>.md`, 49 of them (one
  per bookable catalogue service), with `README.md` saying how to write
  one. `home-malware-removal.md` is `status: full`, converted from
  `jobsheet.js` section for section; the other 48 are `status: skeleton`
  from `skeleton.js` (header from the catalogue, "what the site promises"
  from the service page's `points` where the page lists that slug, the
  generic steps A-G).
- Generator: `build.js` (docx 9.7.1, the reference's helpers: kv table,
  tick-box checklist with Result/notes, Poppins h1/h2, logo + tagline +
  red rule, footer with page number). `node build.js --check` is the test.
  The master logo moved to `projects/web/itsurgery/brand/IT_Surgery_Logo_RGB.jpg`.
- Publishing: `.github/workflows/jobsheets.yml` builds on push and uploads
  `dist/*.docx` + `index.json` as the assets of a rolling pre-release
  tagged `jobsheets`. Chosen over committing the .docx files (binary churn
  in a public portfolio repo) and over a folder on the VPS (nothing on the
  box pulls the repo on push). The files are public on GitHub, as the
  templates already are; the dashboard page, not the files, is what sits
  behind SSO.
- Dashboard: `automation/n8n/workflows/jobsheets.json`. Page at
  `https://dashboard.itsurgery.me/webhook/jobsheets` (the `/webhook/`
  prefix is what nginx already proxies with the sign-in; a pretty
  `/jobsheets` alias needs one nginx `location` and a playbook run - say
  if wanted). "Job sheets" is in the nav of the Dashboard, Monitoring,
  Backup, Guide pages and the Webmin frame template. Download links are
  `?file=JS-<slug>.docx`, checked against `^JS-[a-z0-9-]+\.docx$` before
  anything is fetched.
- Job references: "Take next number" POSTs to `/webhook/jobsheets-next`,
  increments the counter in workflow static data and redirects back with
  the number shown. Static data does not survive a redeploy of that
  workflow (CLAUDE.md), so `TAKEN_FLOOR = { year: 2026, last: 1 }` in both
  Code nodes is the safety net; raise it by hand after any redeploy
  (README says so). Next free today: JS-2026-002.
- `?lead=` pre-fill: not done. It needs the generator callable from n8n
  (no Node on the VPS, and a `workflow_dispatch` round trip is a minute
  per sheet); Phase 2.

**Faithfulness notes on the malware sheet**: customer, device and
reported-problem values from the Stonhold visit are now blank header cells
(the header is generic); "£99 service" and "£35" in two steps became "see
the price list" (prices only from the catalogue); "Surface firmware" became
"firmware"; "This job sheet as PDF" became "This job sheet". Everything
else is word for word, same order, same page breaks.

**Verified here**

- `node build.js`: 49 sheets, 1 full, 48 skeleton; `--check` clean.
- OOXML XSD validation (the docx skill's `validate.py`) passes on the
  malware, WiFi-coverage and remote-support sheets; python-docx reads the
  malware sheet back with all 15 headings, 12 tables, header and footer.
- LibreOffice Writer renders the malware sheet to 6 A4 pages, page 1
  matching `page-1.jpg` block for block (logo, tagline, rule, header table,
  causes list, checklist with tick boxes and Result/notes). Fonts differ
  here only because Calibri/Poppins are not installed in the container.
- The n8n page code ran locally against the built `index.json`: 49
  download links in catalogue order, home and business columns, skeleton
  pills, next-free number, "taken" banner; with the release missing it
  shows the explanation instead of an empty page. No horizontal scroll at
  400px. `yamllint --strict` and the workflow JSON check pass.

**Not verified here** (no browser into the dashboard): the first live run
of `jobsheets.yml` creating the release, the page listing it, a download
opening in Word without a repair prompt, "Take next number" giving
JS-2026-002. Cowork: open the page, download
`JS-home-malware-removal.docx`, open it in Word, press the button once,
and record the result below.


### Cowork, 2026-09-16 - live check

- https://dashboard.itsurgery.me/webhook/jobsheets loads behind the sign-in
  (first click on the nav link bounced to the dashboard home once - the
  SSO round-trip - then loaded). Page text: "49 services - 1 written in
  full, 48 skeleton - built 15 Sept, 15:55", grouped Home/Business with
  the catalogue prices, malware sheet shown without the skeleton pill,
  next free JS-2026-002.
- Release: gh release view jobsheets -> 50 assets, published
  2026-09-15T14:55:51Z; JS-home-malware-removal.docx 39,257 bytes,
  index.json 14,392 bytes. jobsheets.yml run 34984940564 success, 24 s.
- Download in Word: not exercised from the page (in-page fetch is blocked
  by the page CSP and a browser download needs Darren's click). The
  Cowork-built .docx of the same content opens in Word; the CI file is
  the same size to within 300 bytes.
- "Take next number": deliberately not pressed - it would consume
  JS-2026-002 with no visit behind it. Darren presses it at the next
  booking.
- Follow-up handoff: 2026-09-16-jobsheet-malware-c-section.md (no
  "Before you go" section; section C expanded).
