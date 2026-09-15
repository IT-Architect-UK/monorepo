#!/usr/bin/env node
// Writes a skeleton template for a catalogue service: the header comes from
// the catalogue at build time, "what the site promises" is lifted from the
// service page in services.json, and the steps are the ones every visit
// shares. Cowork replaces the content service by service and changes
// `status: skeleton` to `status: full`.
//
//   node skeleton.js <slug>        one service (refuses to overwrite)
//   node skeleton.js --missing     every bookable service without a template

const fs = require('fs');
const path = require('path');

const HERE = __dirname;
const DATA = path.resolve(HERE, '..', 'src', '_data');
const catalogue = JSON.parse(fs.readFileSync(path.join(DATA, 'catalogue.json'), 'utf8'));
const pages = JSON.parse(fs.readFileSync(path.join(DATA, 'services.json'), 'utf8'));

// The service page that lists this catalogue slug under its fixed prices.
function promises(slug) {
  const page = pages.find((p) => (p.fixedPrices || []).includes(slug));
  return page ? { title: page.title, points: page.points || [] } : null;
}

function skeleton(svc) {
  const remote = svc.location === 'video';
  const promise = promises(svc.slug);
  const likely = promise && promise.points.length
    ? [`What the site promises for this service (${promise.title} page):`, '', ...promise.points.map((p) => `- ${p}`)]
    : ['(What this visit usually turns out to be, ranked. Not written yet.)'];
  return `---
slug: ${svc.slug}
title: ${svc.name}
status: skeleton
---

## likely

${likely.join('\n')}

## before

- [ ] Confirm ${remote ? 'the time, and which device and remote tool they will use' : 'full address, phone number, arrival time. Ask who will be there'}.
- [ ] Ask what they have already tried, and what "fixed" looks like to them.
- [ ] Ask them to have the passwords they will need to hand${remote ? '' : ' (account, Wi-Fi, any admin login)'}.
- [ ] Send the confirmation: date, time, price, "no fix, no fee".
  > If they want to book online, send itsurgery.me/book (the £${catalogue.bookingFeeGbp} comes off).

## kit

- [ ] ${remote ? 'Remote help link (help.itsurgery.me) tested, headset, second screen.' : 'USB toolkit stick, USB-C adapter, phone hotspot, power bank.'}
- [ ] ${remote ? 'This job sheet and a pen.' : 'This job sheet (printed) and a pen. Leaflets and a business card.'}

## steps

> Time budget ${svc.durationMinutes || '____'} min. Tick as you go; write what you actually found in the right-hand column — it becomes the CRM note and the customer's summary.

### A. ${remote ? 'Connect and triage' : 'Arrive and triage'}   ${remote ? 'Connected' : 'Arrived'}: ________

- [ ] See the problem as they see it. Note exact wording of any error, what changed recently, what they have tried.
- [ ] Note the device, operating system version and any pending updates.

### B. Agree the price

- [ ] Confirm the service and price on the header line. If the job is bigger than the service, say so now and quote before starting.

### C. Do the work

- [ ] (Service-specific steps go here. Not written yet.)

### D. Prove it

- [ ] Show the customer the result working. Let them try it themselves.

### E. Invoice and pay

- [ ] Raise the Xero invoice and send it; take payment by card via the Stripe link (or bank transfer). Give a receipt.

### F. Ask for a review

- [ ] Ask for a Google review while you are there — open the link on their phone if they are willing.${remote ? '' : ' Leave leaflet and card.'}

### G. After the visit

- [ ] Update the CRM lead: findings, actions, time, price paid.
- [ ] If anything was left undone, send a short follow-up email with the option and price.
- [ ] Add anything you learned to the job-sheet template for this service.

## record

- ${remote ? 'Connected / disconnected' : 'Arrived / left'}: ________  /  ________     Total: ________ min
- Cause found
- Done / changed
- Advice given
- Follow-up offered
- Price charged / paid how: £________   ☐ Stripe link  ☐ bank transfer  ☐ cash   Invoice no: ________
- Customer signature

## handover

(Plain-English summary to say and leave behind. Not written yet.)
`;
}

const arg = process.argv[2];
if (!arg) { console.error('usage: node skeleton.js <slug> | --missing'); process.exit(2); }
const targets = arg === '--missing'
  ? catalogue.services.filter((s) => s.bookable && !fs.existsSync(path.join(HERE, `${s.slug}.md`)))
  : [catalogue.services.find((s) => s.slug === arg)].filter(Boolean);
if (!targets.length) { console.error(arg === '--missing' ? 'nothing missing' : `"${arg}" is not in catalogue.json`); process.exit(arg === '--missing' ? 0 : 1); }
targets.forEach((svc) => {
  const file = path.join(HERE, `${svc.slug}.md`);
  if (fs.existsSync(file)) { console.error(`${svc.slug}.md exists — not overwritten`); process.exit(1); }
  fs.writeFileSync(file, skeleton(svc));
  console.log(`wrote ${svc.slug}.md`);
});
