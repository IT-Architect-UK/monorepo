# Job sheets

One printable Word job sheet per service in the catalogue, for the visit
itself: what to ask on the phone, what to take, the steps to tick off on
site with a Result/notes column, the record block, and what to say to the
customer at the end. They are downloaded from the dashboard's **Job sheets**
page (dashboard.itsurgery.me, behind the sign-in) and filled in by hand or
in Word.

## How it fits together

| Piece | What it does |
|-------|--------------|
| `<slug>.md` | One template per catalogue service, named by its `catalogue.json` slug. The content Cowork and Darren write. |
| `build.js` | Renders every template to `dist/JS-<slug>.docx` and writes `dist/index.json`. The header block comes from the catalogue, so a price or duration change on the site changes the sheet. |
| `skeleton.js` | Writes a starting template for a service that has none. |
| `.github/workflows/jobsheets.yml` | On every push to `main` that touches this folder or the catalogue: builds, then uploads the files as the assets of the rolling `jobsheets` GitHub release. |
| `automation/n8n/workflows/jobsheets.json` | The dashboard page: lists the sheets from `index.json`, serves each `.docx` from the release, and hands out job reference numbers. |

`dist/` is build output and is not committed.

## Writing a template

```
---
slug: home-wifi-coverage          # must match the file name and the catalogue
title: WiFi — coverage in every room
status: skeleton                  # or full, once the content is written
---

## likely: What this almost certainly is     <- optional heading text after the colon

A paragraph. **Bold** is the only inline markup.

1. **Ranked cause.** Explanation.

## before

- [ ] A checklist step.
  > An optional note under the step, in grey.

## kit

- [ ] What to take.

## steps

> An italic note at the top of the section.

### A. Triage  (10 min)   Arrived: ________

- [ ] Steps, ticked on site.

## record

- Arrived / left: ________  /  ________
- Cause found                     <- no value = an empty box to write in

## appendix

### Appendix A — USB toolkit

| Tool | Use | Source |
|---|---|---|
| Name | What for | where from |

## handover

"What to say to the customer, in plain English."
```

Rules:

- Sections are `likely`, `before`, `kit`, `steps`, `record`, `appendix`,
  `handover`, in that order. Any may be left out except `steps`, which
  needs at least one `- [ ]` line. `steps` and `appendix` start a new page.
- `- [ ]` lines that follow each other become one tick-box table. A line
  indented and starting `>` belongs to the step above it.
- In `record`, `- Key: value` is one row of the record table.
- `### ` inside `steps` is a lettered group heading; inside `appendix` it
  is the appendix title.
- Prices belong in the header, which the build takes from the catalogue.
  Do not write a price into the body: it goes stale. "No fix, no fee" is
  fine; "Since 2008" is not.
- The build fails if a bookable service has no template, a slug does not
  match its file name, or a template does not parse.

## Commands

```
npm ci                 # once
node build.js          # dist/JS-<slug>.docx + dist/index.json
node build.js --check  # parse only, nothing written (what CI runs on a PR)
node skeleton.js <slug>      # a starting template for one service
node skeleton.js --missing   # one for every bookable service without a template
```

Word needs the Poppins font installed to show the headings as designed;
without it Word substitutes, which is harmless. The body is Calibri.

## Job references

`JS-YYYY-NNN`, one per visit, handed out by the **Take next number** button
on the dashboard page. The counter is n8n workflow static data, which a
redeploy of `jobsheets.json` wipes, so the highest number known to be taken
is also written into the workflow as `TAKEN_FLOOR` (in both Code nodes) and
must be raised by hand after a redeploy loses the count. JS-2026-001 was
the first visit.
