#!/usr/bin/env node
// Renders every job-sheet template in this folder (<slug>.md) to a Word
// document in dist/, plus dist/index.json for the dashboard's Job sheets
// page. The layout is the one Cowork built for the first visit
// (docs/handoffs/jobsheet-reference/jobsheet.js): logo, tagline, red rule,
// Poppins headings, key/value tables, tick-box checklists with a
// Result/notes column, company footer with page numbers.
//
// The header block (job reference, customer, device, service line, terms)
// comes from the catalogue, not the template, so a price change on the site
// changes the sheet on the next build. README.md says how to write a
// template.
//
//   node build.js            write dist/
//   node build.js --check    parse every template and report, write nothing

const fs = require('fs');
const path = require('path');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType,
  AlignmentType, HeadingLevel, BorderStyle, ShadingType, LevelFormat, PageBreak,
  Header, Footer, PageNumber, ImageRun,
} = require('docx');

const HERE = __dirname;
const SITE = path.resolve(HERE, '..');
const DIST = path.join(HERE, 'dist');
const LOGO = path.join(SITE, 'brand', 'IT_Surgery_Logo_RGB.jpg');
const catalogue = JSON.parse(fs.readFileSync(path.join(SITE, 'src', '_data', 'catalogue.json'), 'utf8'));
const site = JSON.parse(fs.readFileSync(path.join(SITE, 'src', '_data', 'site.json'), 'utf8'));

// --- brand ------------------------------------------------------------------
const RED = '990000';
const INK = '222222';
const BODY = '333333';
const QUIET = '666666';
const LINE = 'CCCCCC';
const HEAD = 'Poppins';
const W = 9638; // A4 text width at 2 cm margins, in DXA

const SECTIONS = {
  likely: 'What to expect',
  before: 'Before you go (phone call)',
  kit: 'Kit to take',
  steps: 'On site',
  record: 'Record',
  appendix: 'Appendix',
  handover: 'What to tell the customer (plain English)',
};
const ORDER = ['likely', 'before', 'kit', 'steps', 'record', 'appendix', 'handover'];
const PAGE_BREAK_BEFORE = new Set(['steps', 'appendix']);

// --- template parsing --------------------------------------------------------
// Front matter, then `## section` headings, each holding a flat list of
// blocks: paragraph, note, h2, bullet, numbered, check (with optional note),
// kv (record rows) and table. Inline **bold** is the only inline markup.

function parseFrontMatter(text) {
  const m = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?/);
  if (!m) throw new Error('no front matter');
  const meta = {};
  m[1].split(/\r?\n/).forEach((line) => {
    const i = line.indexOf(':');
    if (i > 0) meta[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  });
  return { meta, body: text.slice(m[0].length) };
}

function parseSections(body) {
  const sections = {};
  const titles = {};
  let current = null;
  const lines = body.replace(/\r/g, '').split('\n');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    let m;
    if ((m = line.match(/^## +([a-z]+)\s*(?::\s*(.*))?$/i))) {
      current = m[1].toLowerCase();
      if (!SECTIONS[current]) throw new Error(`unknown section "${m[1]}" (line ${i + 1})`);
      sections[current] = [];
      if (m[2]) titles[current] = m[2].trim();
      continue;
    }
    if (!current) {
      if (line.trim()) throw new Error(`text before the first section (line ${i + 1})`);
      continue;
    }
    const blocks = sections[current];
    if (!line.trim()) continue;
    if ((m = line.match(/^### +(.*)$/))) { blocks.push({ type: 'h2', text: m[1].trim() }); continue; }
    if ((m = line.match(/^- \[ \] +(.*)$/))) { blocks.push({ type: 'check', text: m[1].trim(), note: null }); continue; }
    if ((m = line.match(/^\s+> +(.*)$/))) {
      const last = blocks[blocks.length - 1];
      if (!last || last.type !== 'check') throw new Error(`indented note without a checklist step above it (line ${i + 1})`);
      last.note = (last.note ? last.note + ' ' : '') + m[1].trim();
      continue;
    }
    if ((m = line.match(/^> +(.*)$/))) { blocks.push({ type: 'note', text: m[1].trim() }); continue; }
    if ((m = line.match(/^(\d+)\. +(.*)$/))) { blocks.push({ type: 'numbered', n: m[1], text: m[2].trim() }); continue; }
    if ((m = line.match(/^- +(.*)$/))) {
      if (current === 'record') {
        const kv = m[1].match(/^(.*?)(?::\s*(.*))?$/);
        blocks.push({ type: 'kv', key: kv[1].trim(), value: (kv[2] || '').trim() });
      } else {
        blocks.push({ type: 'bullet', text: m[1].trim() });
      }
      continue;
    }
    if (line.startsWith('|')) {
      const cells = (l) => l.trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
      const last = blocks[blocks.length - 1];
      if (/^\|\s*:?-{2,}/.test(line)) continue; // the |---|---| rule
      if (last && last.type === 'table' && last.open) last.rows.push(cells(line));
      else blocks.push({ type: 'table', header: cells(line), rows: [], open: true });
      continue;
    }
    // Plain text: a paragraph, joined with the previous line when it was one too.
    const last = blocks[blocks.length - 1];
    if (last && last.type === 'paragraph' && last.open) last.text += ' ' + line.trim();
    else blocks.push({ type: 'paragraph', text: line.trim(), open: true });
    // Anything that is not a continuation closes an open block.
    blocks.forEach((b) => { if (b !== blocks[blocks.length - 1]) b.open = false; });
  }
  return { sections, titles };
}

function parseTemplate(text, file) {
  const { meta, body } = parseFrontMatter(text);
  ['slug', 'title', 'status'].forEach((k) => { if (!meta[k]) throw new Error(`${file}: front matter needs ${k}`); });
  if (!['full', 'skeleton'].includes(meta.status)) throw new Error(`${file}: status must be full or skeleton`);
  const { sections, titles } = parseSections(body);
  return { meta, sections, titles };
}

// --- docx building blocks ----------------------------------------------------
const border = { style: BorderStyle.SINGLE, size: 4, color: LINE };
const borders = { top: border, bottom: border, left: border, right: border };

const run = (text, opts = {}) => new TextRun({ text, font: 'Calibri', size: 20, color: BODY, ...opts });

// "**bold** rest" -> runs
function inline(text, base = {}) {
  const out = [];
  const re = /\*\*(.+?)\*\*/g;
  let last = 0; let m;
  while ((m = re.exec(text))) {
    if (m.index > last) out.push(run(text.slice(last, m.index), base));
    out.push(run(m[1], { ...base, bold: true }));
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push(run(text.slice(last), base));
  return out.length ? out : [run('', base)];
}

const para = (text, opts = {}) => new Paragraph({ spacing: { after: 80 }, children: inline(text, opts) });
const h1 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 240, after: 100 }, children: [new TextRun({ text, font: HEAD, size: 26, bold: true, color: INK })] });
const h2 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { before: 180, after: 60 }, children: [new TextRun({ text, font: HEAD, size: 21, bold: true, color: RED })] });
const note = (text) => new Paragraph({ spacing: { after: 80 }, children: inline(text, { italics: true, color: QUIET }) });
const bullet = (text) => new Paragraph({ numbering: { reference: 'bullets', level: 0 }, spacing: { after: 40 }, children: inline(text) });
const pageBreak = () => new Paragraph({ children: [new PageBreak()] });

function cell(children, width, opts = {}) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    shading: opts.shade ? { type: ShadingType.CLEAR, fill: opts.shade, color: 'auto' } : undefined,
    children: Array.isArray(children) ? children : [children],
  });
}
const cp = (text, opts = {}) => new Paragraph({ spacing: { after: 0 }, children: inline(text, opts) });

function kv(rows, wl = 2600) {
  const wr = W - wl;
  return new Table({
    width: { size: W, type: WidthType.DXA },
    columnWidths: [wl, wr],
    rows: rows.map(([k, v]) => new TableRow({ children: [
      cell(cp(k, { bold: true }), wl, { shade: 'F5F0F0' }),
      cell(cp(v || ''), wr),
    ] })),
  });
}

function checklist(rows) {
  const w = [500, 6338, 2800];
  return new Table({
    width: { size: W, type: WidthType.DXA },
    columnWidths: w,
    rows: [
      new TableRow({ tableHeader: true, children: [
        cell(cp('', { bold: true }), w[0], { shade: 'EFE3E3' }),
        cell(cp('Step', { bold: true }), w[1], { shade: 'EFE3E3' }),
        cell(cp('Result / notes', { bold: true }), w[2], { shade: 'EFE3E3' }),
      ] }),
      ...rows.map((r) => new TableRow({ children: [
        cell(cp('☐', { size: 24 }), w[0]),
        cell([cp(r.text), ...(r.note ? [cp(r.note, { color: QUIET, size: 18 })] : [])], w[1]),
        cell(cp(''), w[2]),
      ] })),
    ],
  });
}

function table(t) {
  const n = t.header.length;
  const widths = n === 3 ? [3000, 4438, 2200] : Array(n).fill(Math.floor(W / n));
  return new Table({
    width: { size: W, type: WidthType.DXA },
    columnWidths: widths,
    rows: [
      new TableRow({ tableHeader: true, children: t.header.map((h, i) => cell(cp(h, { bold: true }), widths[i], { shade: 'EFE3E3' })) }),
      ...t.rows.map((r) => new TableRow({ children: widths.map((w, i) => cell(cp(r[i] || '', i === n - 1 && n === 3 ? { color: QUIET, size: 18 } : {}), w)) })),
    ],
  });
}

function renderBlocks(blocks) {
  const out = [];
  let pending = [];
  const flush = () => { if (pending.length) { out.push(checklist(pending)); pending = []; } };
  const kvRows = [];
  blocks.forEach((b) => {
    if (b.type !== 'check') flush();
    switch (b.type) {
      case 'check': pending.push(b); break;
      case 'h2': out.push(h2(b.text)); break;
      case 'h1': out.push(h1(b.text)); break;
      case 'note': out.push(note(b.text)); break;
      case 'paragraph': out.push(para(b.text)); break;
      case 'bullet': out.push(bullet(b.text)); break;
      case 'numbered': out.push(bullet(`${b.n}. ${b.text}`)); break;
      case 'kv': kvRows.push([b.key, b.value]); break;
      case 'table': out.push(table(b)); break;
      default: throw new Error(`unknown block ${b.type}`);
    }
  });
  flush();
  if (kvRows.length) out.push(kv(kvRows));
  return out;
}

// --- the header block, from the catalogue -----------------------------------
function serviceLine(svc) {
  const mins = svc.durationMinutes ? `up to ${svc.durationMinutes} min` : null;
  const price = svc.audience === 'business'
    ? (svc.priceExVat != null ? `£${svc.priceExVat} + VAT (fixed price)` : null)
    : (svc.priceIncVat != null ? `£${svc.priceIncVat} inc. VAT (fixed price)` : null);
  const rate = svc.audience === 'business' ? `£${site.businessHourlyRate} an hour + VAT` : `£${site.hourlyRate} an hour inc. VAT`;
  const where = svc.location === 'video' ? 'remote' : svc.audience === 'business' ? 'business service' : 'home service';
  return [svc.name, [where, mins, price || rate].filter(Boolean).join(', ')].join(' — ');
}

function headerRows(svc) {
  return [
    ['Job reference', 'JS-________'],
    ['Visit date', '________________________     Time: ____________'],
    ['Customer', ''],
    ['Address', ''],
    ['Phone / email', '__________________________   /   __________________________'],
    ['Device', '(model / serial: ______________________)'],
    ['Reported problem', ''],
    ['Service', serviceLine(svc)],
    ['Terms', `£${catalogue.bookingFeeGbp} booking fee comes off the price if booked online. No fix, no fee. Anything beyond this service is quoted separately before starting.`],
    ['Price agreed on site', '£________   Booked online? ☐ yes ☐ no'],
  ];
}

// --- one document --------------------------------------------------------------
function buildDoc(tpl, svc) {
  const title = tpl.meta.title;
  const children = [];
  children.push(new Paragraph({ spacing: { after: 60 }, children: [new ImageRun({ type: 'jpg', data: fs.readFileSync(LOGO), transformation: { width: 210, height: 61 } })] }));
  children.push(new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: site.tagline, font: HEAD, size: 20, bold: true, color: RED })] }));
  children.push(new Paragraph({
    spacing: { after: 200 },
    border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: RED, space: 4 } },
    children: [new TextRun({ text: `Job sheet  —  ${title}`, font: HEAD, size: 26, bold: true, color: INK })],
  }));
  if (tpl.meta.status === 'skeleton') {
    children.push(note('Skeleton sheet: the header and the generic steps are real; the service-specific content has not been written yet.'));
  }
  children.push(kv(headerRows(svc)));

  ORDER.forEach((key) => {
    const blocks = tpl.sections[key];
    if (!blocks || !blocks.length) return;
    if (PAGE_BREAK_BEFORE.has(key)) children.push(pageBreak());
    // Appendices are top-level: each "###" inside the appendix section is its
    // own h1 and the section itself has no heading.
    if (key === 'appendix') {
      children.push(...renderBlocks(blocks.map((b) => (b.type === 'h2' ? { ...b, type: 'h1' } : b))));
      return;
    }
    children.push(h1(tpl.titles[key] || SECTIONS[key]));
    children.push(...renderBlocks(blocks));
  });

  const footerText = `${site.legalName} t/a ${site.name} · ${site.phoneDisplay} · ${site.email.toLowerCase()} · ${site.url.replace(/^https?:\/\//, '')} · Page `;
  return new Document({
    creator: site.name,
    title: `Job sheet - ${title}`,
    styles: { default: { document: { run: { font: 'Calibri', size: 20, color: BODY } } } },
    numbering: { config: [{ reference: 'bullets', levels: [
      { level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 360, hanging: 260 } } } },
      { level: 1, format: LevelFormat.BULLET, text: '–', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 260 } } } },
    ] }] },
    sections: [{
      properties: { page: { margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 } } },
      headers: { default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [run(`${site.name} · Job sheet · ${title}`, { color: QUIET, size: 16 })] })] }) },
      footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [run(footerText, { color: QUIET, size: 16 }), new TextRun({ children: [PageNumber.CURRENT], font: 'Calibri', size: 16, color: QUIET })] })] }) },
      children,
    }],
  });
}

// --- main ------------------------------------------------------------------------
async function main() {
  const check = process.argv.includes('--check');
  const files = fs.readdirSync(HERE).filter((f) => f.endsWith('.md') && f !== 'README.md').sort();
  const bySlug = Object.fromEntries(catalogue.services.map((s) => [s.slug, s]));
  const index = [];
  const problems = [];
  if (!check) fs.mkdirSync(DIST, { recursive: true });
  for (const file of files) {
    let tpl;
    try {
      tpl = parseTemplate(fs.readFileSync(path.join(HERE, file), 'utf8'), file);
      if (tpl.meta.slug !== file.replace(/\.md$/, '')) throw new Error(`${file}: slug "${tpl.meta.slug}" does not match the file name`);
      const svc = bySlug[tpl.meta.slug];
      if (!svc) throw new Error(`${file}: "${tpl.meta.slug}" is not in catalogue.json`);
      if (!tpl.sections.steps || !tpl.sections.steps.some((b) => b.type === 'check')) throw new Error(`${file}: the steps section needs at least one "- [ ]" step`);
      const doc = buildDoc(tpl, svc);
      const out = `JS-${tpl.meta.slug}.docx`;
      if (!check) fs.writeFileSync(path.join(DIST, out), await Packer.toBuffer(doc));
      index.push({
        slug: svc.slug, name: svc.name, audience: svc.audience, group: svc.group || null,
        durationMinutes: svc.durationMinutes || null,
        price: svc.audience === 'business' ? svc.priceExVat ?? null : svc.priceIncVat ?? null,
        status: tpl.meta.status, file: out,
      });
    } catch (e) {
      problems.push(e.message);
    }
  }
  // Every bookable service must have a sheet; a new catalogue entry without one fails the build.
  catalogue.services.filter((s) => s.bookable && !index.some((i) => i.slug === s.slug))
    .forEach((s) => problems.push(`no template for bookable service "${s.slug}" (run: node skeleton.js ${s.slug})`));
  if (problems.length) {
    problems.forEach((p) => console.error('ERROR ' + p));
    process.exit(1);
  }
  // The page lists sheets in catalogue order, not file order.
  const pos = Object.fromEntries(catalogue.services.map((s, i) => [s.slug, i]));
  index.sort((a, b) => pos[a.slug] - pos[b.slug]);
  if (!check) {
    fs.writeFileSync(path.join(DIST, 'index.json'), JSON.stringify({ generated: new Date().toISOString(), sheets: index }, null, 2) + '\n');
  }
  const full = index.filter((i) => i.status === 'full').length;
  console.log(`${check ? 'checked' : 'wrote'} ${index.length} job sheet(s): ${full} full, ${index.length - full} skeleton`);
}

main().catch((e) => { console.error(e); process.exit(1); });
