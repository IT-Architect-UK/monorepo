const fs = require('fs');
const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, WidthType,
  AlignmentType, HeadingLevel, BorderStyle, ShadingType, LevelFormat, PageBreak,
  Header, Footer, PageNumber, ImageRun,
} = require('docx');

const GREEN = '990000';
const INK = '222222';
const HEAD = 'Poppins';
const LINE = 'CCCCCC';
const QUIET = '666666';
const W = 9638; // A4 text width at 2cm margins (DXA)

const border = { style: BorderStyle.SINGLE, size: 4, color: LINE };
const borders = { top: border, bottom: border, left: border, right: border };
const noBorders = { top: { style: BorderStyle.NONE, size: 0 }, bottom: { style: BorderStyle.NONE, size: 0 }, left: { style: BorderStyle.NONE, size: 0 }, right: { style: BorderStyle.NONE, size: 0 } };

const t = (text, opts = {}) => new TextRun({ text, font: 'Calibri', size: 20, color: '333333', ...opts });
const p = (text, opts = {}) => new Paragraph({ children: [typeof text === 'string' ? t(text, opts.run || {}) : text], spacing: { after: 80 }, ...opts.para });
const h1 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_1, spacing: { before: 240, after: 100 }, children: [new TextRun({ text, font: HEAD, size: 26, bold: true, color: INK })] });
const h2 = (text) => new Paragraph({ heading: HeadingLevel.HEADING_2, spacing: { before: 180, after: 60 }, children: [new TextRun({ text, font: HEAD, size: 21, bold: true, color: GREEN })] });
const note = (text) => new Paragraph({ spacing: { after: 80 }, children: [t(text, { italics: true, color: QUIET })] });
const bullet = (text, level = 0) => new Paragraph({ numbering: { reference: 'bullets', level }, spacing: { after: 40 }, children: [t(text)] });
const bulletRuns = (runs, level = 0) => new Paragraph({ numbering: { reference: 'bullets', level }, spacing: { after: 40 }, children: runs });

function cell(children, width, opts = {}) {
  return new TableCell({
    width: { size: width, type: WidthType.DXA },
    borders,
    margins: { top: 60, bottom: 60, left: 100, right: 100 },
    shading: opts.shade ? { type: ShadingType.CLEAR, fill: opts.shade, color: 'auto' } : undefined,
    children: Array.isArray(children) ? children : [children],
  });
}
const cp = (text, opts = {}) => new Paragraph({ spacing: { after: 0 }, children: [t(text, opts)] });

// Two-column key/value table
function kv(rows, wl = 2600) {
  const wr = W - wl;
  return new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: [wl, wr],
    rows: rows.map(([k, v]) => new TableRow({ children: [
      cell(cp(k, { bold: true }), wl, { shade: 'F5F0F0' }),
      cell(typeof v === 'string' ? cp(v) : v, wr),
    ] })),
  });
}

// Checklist table: [ ] | step | notes
function checklist(rows) {
  const w = [500, 6338, 2800];
  return new Table({
    width: { size: W, type: WidthType.DXA }, columnWidths: w,
    rows: [
      new TableRow({ tableHeader: true, children: [
        cell(cp('', { bold: true }), w[0], { shade: 'EFE3E3' }),
        cell(cp('Step', { bold: true }), w[1], { shade: 'EFE3E3' }),
        cell(cp('Result / notes', { bold: true }), w[2], { shade: 'EFE3E3' }),
      ] }),
      ...rows.map(([step, sub]) => new TableRow({ children: [
        cell(cp('\u2610', { size: 24 }), w[0]),
        cell([cp(step), ...(sub ? [new Paragraph({ spacing: { after: 0 }, children: [t(sub, { color: QUIET, size: 18 })] })] : [])], w[1]),
        cell(cp(''), w[2]),
      ] })),
    ],
  });
}

const children = [];

// ---- Title block
children.push(new Paragraph({ spacing: { after: 60 }, children: [new ImageRun({ type: 'jpg', data: fs.readFileSync(__dirname + '/logo.jpg'), transformation: { width: 210, height: 61 } })] }));
children.push(new Paragraph({ spacing: { after: 40 }, children: [new TextRun({ text: 'Curing IT Headaches', font: HEAD, size: 20, bold: true, color: GREEN })] }));
children.push(new Paragraph({ spacing: { after: 200 }, border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: GREEN, space: 4 } }, children: [new TextRun({ text: 'Job sheet  \u2014  Malware scan, removal & protection', font: HEAD, size: 26, bold: true, color: INK })] }));

children.push(kv([
  ['Job reference', 'JS-2026-001'],
  ['Visit date', 'Tuesday 16 September 2026     Time: ____________'],
  ['Customer', 'Brian and Jenny Stonhold'],
  ['Address', 'Hayes Point, Sully  (full address: ______________________________________)'],
  ['Phone / email', '__________________________   /   __________________________'],
  ['Device', 'Microsoft Surface Pro, Windows 11  (model / serial: ______________________)'],
  ['Reported problem', 'Pop-ups saying the computer has a "trojan horse". Jenny has run a scan which found nothing; the pop-ups persist. No further detail known before the visit.'],
  ['Service', 'Malware scan, removal & protection \u2014 home service, up to 120 min, \u00a370 inc. VAT (fixed price)'],
  ['Terms', '\u00a35 booking fee comes off the price if booked online. No fix, no fee. Anything beyond this service (e.g. a full Windows reinstall) is quoted separately before starting.'],
  ['Price agreed on site', '\u00a3________   Booked online? \u2610 yes \u2610 no'],
]));

// ---- Most likely causes
children.push(h1('What this almost certainly is'));
children.push(p('A pop-up that says "trojan horse detected" on a machine whose own scan is clean is, nine times out of ten, not malware at all. Work through these in order \u2014 most visits end at 1 or 2.'));
children.push(bulletRuns([t('1. Browser push notifications from a scam site. ', { bold: true }), t('At some point a website asked "Allow notifications?" and got a Yes. It now sends fake virus alerts through Edge/Chrome, even when the browser is closed. Tell-tale: the pop-up appears bottom-right as a Windows toast with a browser icon or a random site name, and mentions McAfee/Norton/Microsoft.')]));
children.push(bulletRuns([t('2. Bundled "trial" antivirus or a PUP. ', { bold: true }), t('McAfee/Norton trials on new Surfaces nag with alarming wording after expiry; "PC Accelerate", "Driver Updater", "Web Companion" and similar are adware that fake warnings.')]));
children.push(bulletRuns([t('3. Rogue browser extension ', { bold: true }), t('injecting warnings or redirecting search.')]));
children.push(bulletRuns([t('4. Startup / scheduled-task adware ', { bold: true }), t('re-launching a pop-up window (look for tasks and Run keys pointing into AppData).')]));
children.push(bulletRuns([t('5. Genuine malware ', { bold: true }), t('(least likely given the clean scan, but rule it out with a second-opinion scanner).')]));
children.push(bulletRuns([t('6. A tech-support scam already in progress. ', { bold: true }), t('If they have ever phoned a number on a pop-up, someone may have installed remote-access software (AnyDesk, TeamViewer, UltraViewer, ScreenConnect, "Supremo", "Zoho Assist"). This changes the visit \u2014 see Contain.')]));

// ---- Kit
children.push(h1('Kit to take'));
children.push(checklist([
  ['USB toolkit stick (built with usb-toolkit.ps1 \u2014 see Appendix A). Check every file is present before leaving.', null],
  ['USB-C stick or a USB-A\u2192USB-C adapter. Surface Pro 8 and later have USB-C only; Pro 7 and earlier have USB-A.', null],
  ['Phone with hotspot (in case their Wi-Fi is part of the problem) and a charged power bank.', null],
  ['Surface charger is theirs \u2014 ask them to have it plugged in. Scans take time.', null],
  ['This job sheet (printed) and a pen. Leaflets and a business card. Payment: Xero invoice by email with the Stripe pay link, or a QR code to it.', null],
  ['Notebook or phone for screenshots of the pop-up (before) and the clean desktop (after).', null],
]));

// ---- On-site procedure
children.push(h1('On site'));
children.push(note('Time budget 120 min. Tick as you go; write what you actually found in the right-hand column \u2014 it becomes the CRM note and the customer\u2019s summary.'));

children.push(h2('A. Triage  (10 min)   Arrived: ________'));
children.push(checklist([
  ['See the pop-up live. Photograph it. Note the exact wording, any URL, phone number or product name.', null],
  ['Decide where it comes from: Windows toast (Settings \u203a System \u203a Notifications shows the sender) or a browser window/tab.', 'Click the toast\u2019s \u201c\u2026\u201d \u203a it names the sender app/site.'],
  ['Windows: Win+R \u203a winver. Note version/build. Settings \u203a Windows Update \u2014 any pending?', null],
  ['Windows Security \u203a Virus & threat protection: is Defender on? Any third-party AV installed? Protection history \u2014 anything quarantined recently?', null],
  ['Settings \u203a Apps \u203a Installed apps, sort by install date. Note anything unfamiliar from the last few months, especially remote-access tools.', null],
  ['Ask again, gently: any calls made, payments, or remote sessions? Any new bank/card alerts?', null],
]));

children.push(h2('B. Contain  (only if a scam call, payment or remote session has happened)'));
children.push(checklist([
  ['Disconnect from the internet (Wi-Fi off). Uninstall any remote-access tool they did not knowingly install. Check Windows Security \u203a Exclusions \u2014 scammers add them.', null],
  ['Change the Microsoft account password from a different device; turn on two-step verification; sign out of all sessions (account.microsoft.com \u203a Security).', null],
  ['Advise: ring the bank now on the number on the card; report to Action Fraud (actionfraud.police.uk / 0300 123 2040). Do not promise outcomes.', null],
  ['If a remote session happened, treat the machine as compromised: full offline scan (D) is mandatory, and discuss a clean reinstall (\u00a399 service) if anything is found.', null],
]));

children.push(h2('C. Find and remove the source  (30\u201345 min)'));
children.push(note('C1 is the fix for nine out of ten "trojan horse" pop-ups. Do it first, then keep going down the list regardless \u2014 the scanners in D are the proof, not the cure.'));
children.push(new Paragraph({ spacing: { before: 80, after: 40 }, children: [t('C1. Browser notification permissions (the usual cause)', { bold: true })] }));
children.push(checklist([
  ['Identify the sender first. When a pop-up appears bottom-right, click the \u201c\u2026\u201d or the cog on it \u2192 it names the app (Microsoft Edge / Google Chrome) and the website. Or: Settings \u203a System \u203a Notifications \u2192 scroll the sender list; a browser with a site name under it, or an unfamiliar app, is the culprit. Note the site name.', 'Windows 11 keeps a history: click the clock \u2192 Notification Center shows recent toasts and who sent them.'],
  ['Edge: type edge://settings/content/notifications in the address bar. Under \u201cAllow\u201d, click the \u201c\u2026\u201d beside every site and choose Remove (or Block). Leave only sites they can name and want (e.g. their email provider).', 'Then set \u201cQuiet notification requests\u201d ON so sites can no longer pop the Allow/Block question over the page.'],
  ['Chrome (if installed): chrome://settings/content/notifications \u2192 \u201cAllowed to send notifications\u201d \u2192 \u201c\u2026\u201d \u2192 Remove for each site. Set \u201cUse quieter messaging\u201d ON.', null],
  ['Firefox (if installed): Settings \u203a Privacy & Security \u203a Permissions \u203a Notifications \u203a Settings\u2026 \u2192 select each site \u2192 Remove Website \u2192 tick \u201cBlock new requests asking to allow notifications\u201d \u2192 Save Changes.', null],
  ['Windows: Settings \u203a System \u203a Notifications \u2192 under \u201cNotifications from apps and other senders\u201d turn OFF any sender you do not recognise. Browsers can stay ON (their per-site list is now clean). Further down, untick \u201cShow the Windows welcome experience\u2026\u201d and \u201cGet tips and suggestions\u2026\u201d.', 'If a website appears here as its own sender, it was installed as an app \u2014 see the next step.'],
  ['Edge: edge://apps \u2192 uninstall any website installed \u201cas an app\u201d that they did not choose. Also Windows Settings \u203a Apps \u203a Installed apps \u2192 same check.', 'Scam sites sometimes install themselves as a web app so their notifications look like a real program.'],
]));
children.push(new Paragraph({ spacing: { before: 80, after: 40 }, children: [t('C2. Browser extensions, home page, search engine', { bold: true })] }));
children.push(checklist([
  ['Edge: edge://extensions \u2192 Remove anything unfamiliar (typical names: \u201cWeb Companion\u201d, \u201cSearch Manager\u201d, \u201cPDF Converter\u201d, coupon / weather / \u201csafe browsing\u201d bars). Chrome: chrome://extensions. Firefox: about:addons.', 'Keep only ones they can name. A password manager or uBlock Origin is fine.'],
  ['Edge: edge://settings/startHomeNTP \u2192 \u201cWhen Edge starts\u201d and the Home button should be theirs or default. edge://settings/search \u2192 default search engine should be Bing or Google, not something unknown.', 'Chrome: chrome://settings/onStartup and chrome://settings/search.'],
  ['If the browser still behaves oddly afterwards: edge://settings/reset \u2192 Restore settings to their default values (keeps favourites and passwords). Chrome: chrome://settings/reset.', null],
]));
children.push(new Paragraph({ spacing: { before: 80, after: 40 }, children: [t('C3. Programs, start-up items and scheduled tasks', { bold: true })] }));
children.push(checklist([
  ['Settings \u203a Apps \u203a Installed apps \u2192 sort by Install date. Uninstall expired AV trials (McAfee, Norton) and anything unfamiliar or with \u201cOptimizer\u201d, \u201cAccelerate\u201d, \u201cDriver Updater\u201d or \u201cCleaner\u201d in the name. Reboot.', 'If McAfee/Norton refuse to uninstall, run MCPR / Norton Remove and Reinstall from the stick.'],
  ['Autoruns64.exe (stick, run as administrator): Options \u203a Hide Microsoft entries. Check the Logon, Scheduled Tasks and Services tabs. Untick anything unsigned, or whose path is in AppData, Temp or ProgramData with a random name. Note what you disabled.', null],
  ['Task Scheduler (search for it in Start) \u2192 Task Scheduler Library \u2192 sort by Created. Disable any recent task that launches a browser with a URL, or an .exe from a user folder.', null],
  ['Settings \u203a Network & internet \u203a Proxy \u2192 \u201cUse a proxy server\u201d must be OFF and \u201cAutomatically detect settings\u201d ON. Wi-Fi \u203a properties \u2192 DNS should be Automatic.', null],
  ['Notepad as administrator \u2192 open C:\\Windows\\System32\\drivers\\etc\\hosts \u2192 anything below the comment lines other than \u201c127.0.0.1 localhost\u201d is suspect; delete it.', null],
]));

children.push(h2('D. Scan  (run while you tidy; 30\u201345 min elapsed)'));
children.push(checklist([
  ['Malwarebytes (stick): install, update, Scan. Quarantine everything it finds. Uninstall Malwarebytes at the end unless they want to keep the free version (it nags for Premium).', null],
  ['AdwCleaner (stick, portable): Scan \u203a Quarantine. Reboot if asked. Catches adware, PUPs and browser hijacks Malwarebytes misses.', null],
  ['Microsoft Safety Scanner (stick, msert.exe): Quick scan. Second opinion from Microsoft, no install.', null],
  ['If anything real was found, or a remote session happened: Windows Security \u203a Scan options \u203a Microsoft Defender Offline scan (reboots, ~15 min).', null],
  ['Record findings: what was found, where, what was removed.', null],
]));

children.push(h2('E. Protect  (15 min)'));
children.push(checklist([
  ['Windows Update: install everything, including Surface firmware. Reboot.', null],
  ['Windows Security: Defender on; Tamper Protection on; Cloud-delivered and automatic sample submission on; Controlled folder access \u2014 leave off unless they ask (it breaks things). SmartScreen on for apps and Edge.', null],
  ['Edge: Settings \u203a Privacy \u203a Enhance your security on the web = Balanced. Notifications: set \u201cQuiet notification requests\u201d on.', null],
  ['Microsoft account: check Security \u203a Sign-in activity for anything odd; two-step verification on; recovery phone/email correct.', null],
  ['Backups: confirm OneDrive is signed in and Desktop/Documents/Pictures are backed up (Settings \u203a Accounts \u203a Windows backup). If not, offer the Backup set-up service (\u00a335).', null],
  ['Uninstall anything else they do not use that came bundled. Empty Recycle Bin. Storage Sense on.', null],
]));

children.push(h2('F. Prove it and hand over  (10 min)'));
children.push(checklist([
  ['Reboot. Use the machine for 5\u201310 minutes: browser, email, a few sites. No pop-ups.', null],
  ['Show them: the \u201cbefore\u201d photo, what caused it, and what a real Windows Security alert looks like (the shield icon, no phone number, never asks you to call).', null],
  ['Three rules, said out loud and left on the leaflet: never phone a number on a pop-up; never let anyone connect unless you rang IT Surgery; if in doubt, turn it off and call us.', null],
  ['Agree the price. Raise the Xero invoice and send it; take payment by card via the Stripe link (or bank transfer). Give a receipt.', null],
  ['Ask for a Google review while you are there \u2014 open the link on their phone if they are willing. Leave leaflet and card.', null],
]));

children.push(h2('G. After the visit'));
children.push(checklist([
  ['Update the CRM lead: findings, actions, time, price paid. Attach the before/after photos.', null],
  ['If anything was left undone (e.g. reinstall recommended, backup not set up), send a short follow-up email with the option and price.', null],
  ['Add anything you learned to the job-sheet template for this service.', null],
]));

// ---- Record
children.push(h1('Record'));
children.push(kv([
  ['Arrived / left', '________  /  ________     Total on site: ________ min'],
  ['Cause found', ''],
  ['Removed / changed', ''],
  ['Scans run and results', ''],
  ['Advice given', ''],
  ['Follow-up offered', ''],
  ['Price charged / paid how', '\u00a3________   \u2610 Stripe link  \u2610 bank transfer  \u2610 cash   Invoice no: ________'],
  ['Customer signature', ''],
], 2600));

// ---- Appendix A: USB toolkit
children.push(new Paragraph({ children: [new PageBreak()] }));
children.push(h1('Appendix A \u2014 USB toolkit'));
children.push(p('Built by usb-toolkit.ps1 (in the same folder as this sheet). Run it on your PC; it downloads the current version of each tool from the vendor into a folder called usb-toolkit, checks the sizes, then you copy the whole folder to the stick. Re-run it before each visit so definitions are fresh. Nothing on the stick needs an internet connection to run except Malwarebytes updates and ESET.'));

const tools = [
  ['Malwarebytes (installer)', 'Main scan. Free scan/removal; uninstall after unless kept.', 'malwarebytes.com'],
  ['AdwCleaner (portable)', 'Adware, PUPs, browser hijacks, notification spam. No install.', 'malwarebytes.com/adwcleaner'],
  ['Microsoft Safety Scanner (msert.exe)', 'Microsoft second-opinion scanner. Portable. Expires after 10 days \u2014 re-download each time.', 'learn.microsoft.com (Safety Scanner)'],
  ['ESET Online Scanner', 'Third-opinion scanner if the first two disagree. Needs internet.', 'eset.com/uk/home/online-scanner'],
  ['Sysinternals Autoruns', 'Everything that starts with Windows. Portable.', 'learn.microsoft.com/sysinternals'],
  ['Sysinternals Process Explorer', 'What is running now, signed by whom. Portable.', 'learn.microsoft.com/sysinternals'],
  ['Sysinternals TCPView', 'Live network connections \u2014 spots remote-access tools phoning home.', 'learn.microsoft.com/sysinternals'],
  ['McAfee removal tool (MCPR)', 'When the McAfee uninstaller will not.', 'mcafee.com'],
  ['Norton Remove and Reinstall', 'When the Norton uninstaller will not.', 'norton.com'],
  ['This job sheet (Word)', 'In case the printed one gets lost.', '\u2014'],
];
const tw = [3000, 4438, 2200];
children.push(new Table({
  width: { size: W, type: WidthType.DXA }, columnWidths: tw,
  rows: [
    new TableRow({ tableHeader: true, children: [cell(cp('Tool', { bold: true }), tw[0], { shade: 'EFE3E3' }), cell(cp('Use', { bold: true }), tw[1], { shade: 'EFE3E3' }), cell(cp('Source', { bold: true }), tw[2], { shade: 'EFE3E3' })] }),
    ...tools.map(r => new TableRow({ children: [cell(cp(r[0]), tw[0]), cell(cp(r[1]), tw[1]), cell(cp(r[2], { color: QUIET, size: 18 }), tw[2])] })),
  ],
}));
children.push(note('Not on the stick on purpose: Windows Defender Offline (built in), HitmanPro / Kaspersky tools (paid or brittle download links) \u2014 add later if a case needs them.'));

// ---- Appendix B: plain-English explanation to leave behind
children.push(h1('Appendix B \u2014 What to tell the customer (plain English)'));
children.push(p('"The warning you were seeing was not a virus. A website you visited once asked permission to send you notifications, and it has been using that permission to send fake alerts designed to frighten you into phoning a number. Your own scan was right \u2014 there was nothing on the computer. I have removed that permission, checked the whole machine with three different scanners, made sure Windows\u2019 own protection is on and up to date, and set the browser so sites cannot ask again without you noticing."'));
children.push(p('"A real warning from Windows never gives you a phone number and never asks you to call anyone. If you see anything like that again, close it and ring us."'));
children.push(note('Adjust to what you actually found. Never say "it was nothing" \u2014 it was a scam attempt, and they did the right thing by getting it checked.'));

const doc = new Document({
  creator: 'IT Surgery',
  title: 'Job sheet JS-2026-001 - Malware scan, removal & protection - Stonhold, Sully',
  styles: { default: { document: { run: { font: 'Calibri', size: 20, color: '333333' } } } },
  numbering: { config: [{ reference: 'bullets', levels: [
    { level: 0, format: LevelFormat.BULLET, text: '\u2022', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 360, hanging: 260 } } } },
    { level: 1, format: LevelFormat.BULLET, text: '\u2013', alignment: AlignmentType.LEFT, style: { paragraph: { indent: { left: 720, hanging: 260 } } } },
  ] }] },
  sections: [{
    properties: { page: { margin: { top: 1134, bottom: 1134, left: 1134, right: 1134 } } },
    headers: { default: new Header({ children: [new Paragraph({ alignment: AlignmentType.RIGHT, children: [t('IT Surgery \u00b7 Job sheet JS-2026-001 \u00b7 Stonhold, Sully \u00b7 16 Sep 2026', { color: QUIET, size: 16 })] })] }) },
    footers: { default: new Footer({ children: [new Paragraph({ alignment: AlignmentType.CENTER, children: [t('IT Solution Architecture Limited t/a IT Surgery \u00b7 07775 580371 \u00b7 help@itsurgery.me \u00b7 itsurgery.me \u00b7 Page ', { color: QUIET, size: 16 }), new TextRun({ children: [PageNumber.CURRENT], font: 'Calibri', size: 16, color: QUIET })] })] }) },
    children,
  }],
});

Packer.toBuffer(doc).then(buf => { fs.writeFileSync(process.argv[2], buf); console.log('written', buf.length); });
