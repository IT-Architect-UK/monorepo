#!/usr/bin/env node
/**
 * Render the off-site brand assets into brand/ from the logo and site.json.
 *
 *   node tools/build-brand-assets.js
 *
 * Produces:
 *   brand/social-square-1200.png       1200x1200  Google Ads / Instagram / any square slot
 *   brand/facebook-profile-720.png      720x720   Facebook Page profile picture (the cross; FB crops to a circle)
 *   brand/facebook-cover-1640x624.png  1640x624   Facebook Page cover (2x of the 820x312 desktop display; content central for the phone crop)
 *
 * The on-site share image (src/assets/og-image.png) has its own script,
 * tools/build-og-image.js, because it ships with the site; these do not.
 * Same approach as that script: a headless browser is the one renderer that
 * sets Poppins exactly as the site does, so Playwright + Chromium, with Poppins
 * installed locally. Wording comes from site.json so nothing here can drift.
 */
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const site = require(path.join(root, "src/_data/site.json"));
const logo = fs.readFileSync(path.join(root, "src/assets/logo@3x.png")).toString("base64");
const icon = fs.readFileSync(path.join(root, "src/icons/icon.svg"), "utf8");
const out = path.join(root, "brand");
fs.mkdirSync(out, { recursive: true });

const areas = site.areas.join(" · ");
const bars = (h) => `<div style="position:absolute;top:0;left:0;right:0;height:${h}px;background:#990000"></div>` +
                    `<div style="position:absolute;bottom:0;left:0;right:0;height:${h}px;background:#990000"></div>`;
const body = (w, h, inner) => `<body style="margin:0;width:${w}px;height:${h}px;background:#fff;font-family:Poppins,sans-serif;
  display:flex;flex-direction:column;align-items:center;justify-content:center;position:relative;text-align:center">${inner}</body>`;

const assets = [
  ["social-square-1200.png", 1200, 1200, body(1200, 1200, `${bars(22)}
    <img src="data:image/png;base64,${logo}" style="width:760px;height:auto;margin-bottom:48px">
    <div style="font-weight:600;font-size:72px;color:#222;margin-bottom:48px">${site.tagline}</div>
    <div style="font-weight:500;font-size:38px;color:#5a6068;margin-bottom:48px">Friendly IT help for homes &amp; small businesses</div>
    <div style="font-weight:600;font-size:34px;color:#990000;letter-spacing:2px;text-transform:uppercase;line-height:1.5">${areas}<br>Remote support UK-wide</div>`)],
  ["facebook-profile-720.png", 720, 720, body(720, 720,
    `<div style="width:400px;height:400px">${icon.replace("<svg", '<svg width="400" height="400"')}</div>`)],
  // Facebook shows Page covers at 820x312 on desktop (2.63:1) and about
  // 640x360 on phones, which trims the sides. So: 1640x624 (2x desktop),
  // laid out sideways - logo left, text right - with everything inside the
  // central 1200px so the phone crop keeps it.
  ["facebook-cover-1640x624.png", 1640, 624, `<body style="margin:0;width:1640px;height:624px;background:#fff;font-family:Poppins,sans-serif;position:relative">
    ${bars(18)}
    <div style="position:absolute;left:220px;top:0;bottom:0;width:1200px;display:flex;align-items:center;justify-content:center;gap:64px">
      <img src="data:image/png;base64,${logo}" style="width:520px;height:auto;flex:0 0 auto">
      <div style="text-align:left">
        <div style="font-weight:600;font-size:56px;color:#222;line-height:1.1;margin-bottom:18px">${site.tagline}</div>
        <div style="font-weight:500;font-size:28px;color:#5a6068;margin-bottom:22px">Friendly IT help for homes &amp; businesses</div>
        <div style="font-weight:600;font-size:22px;color:#990000;letter-spacing:2px;text-transform:uppercase;line-height:1.6">${areas}<br>Remote support UK-wide</div>
        <div style="font-weight:600;font-size:26px;color:#222;margin-top:22px">${site.url.replace(/^https?:\/\//, "")}</div>
      </div>
    </div></body>`],
];

(async () => {
  const browser = await chromium.launch();
  for (const [name, w, h, html] of assets) {
    const page = await (await browser.newContext({ viewport: { width: w, height: h } })).newPage();
    await page.setContent(html);
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot({ path: path.join(out, name) });
    console.log(`wrote brand/${name}`);
  }
  await browser.close();
})();
