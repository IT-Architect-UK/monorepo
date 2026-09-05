#!/usr/bin/env node
/**
 * Render the social share image (Open Graph / Twitter card) for the site.
 *
 *   node tools/build-og-image.js            -> src/assets/og-image.png
 *
 * Why a browser and not an image library: the image is typeset in Poppins, the
 * site's heading face, and a browser is the one renderer that lays out and hints
 * text exactly as the site does. Playwright with Chromium is used; Poppins must
 * be installed as a local font on the machine that runs this (the site loads it
 * from Google Fonts, which a screenshot of a data: page cannot).
 *
 * 1200x630 is the size every platform agrees on (Facebook, WhatsApp, LinkedIn,
 * X, Slack, iMessage). The logo is placed at the native width of the 3x asset
 * so it is never resampled; upscaling it is what made the first draft look soft.
 * Wording is taken from site.json so the image cannot drift from the site.
 */
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const site = require(path.join(root, "src/_data/site.json"));
const logo = fs.readFileSync(path.join(root, "src/assets/logo@3x.png")).toString("base64");
const out = path.join(root, "src/assets/og-image.png");

const strap = `${site.areas.join(" · ")} · Remote support UK-wide`;

(async () => {
  const browser = await chromium.launch();
  const page = await (await browser.newContext({ viewport: { width: 1200, height: 630 } })).newPage();
  await page.setContent(`<body style="margin:0;width:1200px;height:630px;background:#fff;
      font-family:Poppins,sans-serif;display:flex;flex-direction:column;align-items:center;
      justify-content:center;gap:30px;position:relative">
    <div style="position:absolute;top:0;left:0;right:0;height:18px;background:#990000"></div>
    <img src="data:image/png;base64,${logo}" style="width:537px;height:auto" alt="">
    <div style="font-weight:600;font-size:54px;color:#222;letter-spacing:-0.5px">${site.tagline}</div>
    <div style="font-weight:500;font-size:30px;color:#5a6068">Friendly IT help for homes &amp; small businesses</div>
    <div style="font-weight:600;font-size:28px;color:#990000;letter-spacing:2px;text-transform:uppercase">${strap}</div>
    <div style="position:absolute;bottom:0;left:0;right:0;height:18px;background:#990000"></div>
  </body>`);
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: out, type: "png" });
  await browser.close();
  console.log(`wrote ${path.relative(root, out)} (${fs.statSync(out).size} bytes)`);
})();
