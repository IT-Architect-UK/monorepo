#!/usr/bin/env node
/**
 * Render the off-site brand assets into brand/ from the logo and site.json.
 *
 *   node tools/build-brand-assets.js
 *
 * Produces:
 *   brand/social-square-1200.png       1200x1200  Google Ads / Instagram / any square slot
 *   brand/facebook-profile-720.png      720x720   Facebook Page profile picture (the cross; FB crops to a circle)
 *   brand/facebook-cover-1640x924.png  1640x924   Facebook Page cover (text kept central for the mobile crop)
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
  ["facebook-cover-1640x924.png", 1640, 924, body(1640, 924, `${bars(26)}
    <img src="data:image/png;base64,${logo}" style="width:640px;height:auto;margin-bottom:40px">
    <div style="font-weight:600;font-size:64px;color:#222;margin-bottom:40px">${site.tagline}</div>
    <div style="font-weight:500;font-size:34px;color:#5a6068;margin-bottom:40px">Friendly IT help for homes &amp; small businesses</div>
    <div style="font-weight:600;font-size:30px;color:#990000;letter-spacing:2px;text-transform:uppercase;line-height:1.6;margin-bottom:40px">${areas}<br>Remote support UK-wide</div>
    <div style="font-weight:600;font-size:34px;color:#222">${site.url.replace(/^https?:\/\//, "")}</div>`)],
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
