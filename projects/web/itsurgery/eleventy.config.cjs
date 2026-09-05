/**
 * Eleventy configuration for the IT Surgery website.
 *
 * Input  : src/
 * Output : _site/  (what Netlify publishes)
 *
 * Pages use directory-style URLs (e.g. /about-us/) so the existing
 * itsurgery.me URLs are preserved and search rankings are not lost.
 */
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

module.exports = function (eleventyConfig) {
  // Copy the stylesheet through untouched.
  eleventyConfig.addPassthroughCopy({ "src/assets": "assets" });

  // Favicons and the web manifest are copied to the site root, not into
  // /assets/. Browsers and crawlers request /favicon.ico by that exact path
  // whether or not the page declares it, so it has to live there.
  eleventyConfig.addPassthroughCopy({ "src/icons": "." });

  /**
   * Cache-busting fingerprint for the stylesheet.
   *
   * Assets are served with a long Cache-Control max-age (see netlify.toml).
   * Because the filename never changes, a returning visitor would otherwise
   * keep the previous CSS for up to a day after a deploy and see an unstyled
   * or half-styled page. Appending a hash of the file contents gives each
   * revision its own URL, so changes are picked up immediately while unchanged
   * builds stay cached.
   */
  eleventyConfig.addGlobalData("assetHash", () =>
    crypto
      .createHash("md5")
      .update(fs.readFileSync("src/assets/styles.css"))
      .digest("hex")
      .slice(0, 8)
  );

  /**
   * Cache-bust any asset by content hash: {{ '/assets/logo.png' | v }}.
   *
   * netlify.toml caches /assets/* for 24 hours, and the images are not
   * fingerprinted, so a replaced logo kept showing the old file on devices that
   * had already cached it — a rebuilt logo looked unchanged on a phone for a
   * day. Only styles.css was versioned; this covers everything else.
   */
  eleventyConfig.addFilter("v", (assetPath) => {
    const file = path.join("src", assetPath);
    if (!fs.existsSync(file)) return assetPath;      // fail open, never break a build
    const hash = crypto.createHash("md5").update(fs.readFileSync(file)).digest("hex").slice(0, 8);
    return `${assetPath}?v=${hash}`;
  });

  // Minutes from the catalogue -> "45 min", "1 hour", "1½ hours", "2 hours".
  eleventyConfig.addFilter("duration", (mins) => {
    if (!mins) return "";
    if (mins < 60) return `${mins} min`;
    const h = mins / 60;
    const whole = Math.floor(h);
    const half = h - whole >= 0.5;
    const label = half ? `${whole}½ hours` : `${whole} hour${whole === 1 ? "" : "s"}`;
    return label;
  });

  /**
   * Content-Security-Policy with per-build script hashes.
   *
   * The site has five inline <script> blocks (theme, menu, booking, payment,
   * problem report). A CSP that allows them with 'unsafe-inline' would also
   * allow any script an attacker managed to inject, which is most of what a
   * CSP is for. Hashes allow exactly those five and nothing else - but two of
   * them are templated (the booking page embeds the catalogue), so the hashes
   * change with the data and cannot live in netlify.toml. Instead every built
   * page is scanned for inline scripts as it is written, and the policy is
   * emitted afterwards as _site/_headers, which Netlify merges with the static
   * headers in netlify.toml.
   *
   * Everything else the site touches is listed by host: the Cal.com embed
   * (its script, its iframe, its fonts and its own styles), the n8n pay-link
   * endpoint, and Netlify Forms posting back to this origin. Nothing else may
   * load, frame this site, or receive a form post.
   *
   * Note for `eleventy --serve`: incremental rebuilds only transform changed
   * files, so the hash set can be incomplete in dev. The local server ignores
   * _headers anyway; a full `npm run build` always produces the complete list.
   */
  const scriptHashes = new Set();
  eleventyConfig.addTransform("csp-script-hashes", function (content) {
    if (!(this.page.outputPath || "").endsWith(".html")) return content;
    const re = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
    let m;
    while ((m = re.exec(content)) !== null) {
      const attrs = m[1];
      if (/\bsrc\s*=/.test(attrs)) continue;                 // external
      if (/type\s*=\s*["']application\/ld\+json["']/.test(attrs)) continue; // data block, not executed
      const hash = crypto.createHash("sha256").update(m[2], "utf8").digest("base64");
      scriptHashes.add(`'sha256-${hash}'`);
    }
    return content;
  });
  eleventyConfig.on("eleventy.after", ({ dir }) => {
    const csp = [
      "default-src 'self'",
      // Google tag (Analytics / Ads) loads only after cookie consent; see consent.js.
      `script-src 'self' https://app.cal.com https://www.googletagmanager.com ${[...scriptHashes].sort().join(" ")}`,
      // The Cal.com embed writes <style> elements and style attributes into
      // the page; inline styles cannot be hashed the way scripts can.
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: https://app.cal.com https://www.googletagmanager.com https://www.google-analytics.com https://*.google-analytics.com https://www.google.com https://www.google.co.uk https://googleads.g.doubleclick.net https://pagead2.googlesyndication.com",
      "font-src 'self' https://cal.com",
      "connect-src 'self' https://app.cal.com https://n8n.itsurgery.me https://www.googletagmanager.com https://www.google-analytics.com https://*.google-analytics.com https://analytics.google.com https://*.analytics.google.com https://stats.g.doubleclick.net https://www.google.com https://googleads.g.doubleclick.net https://www.googleadservices.com https://pagead2.googlesyndication.com",
      "frame-src https://app.cal.com https://td.doubleclick.net",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "object-src 'none'",
      "upgrade-insecure-requests"
    ].join("; ");
    const out = path.join(dir.output, "_headers");
    fs.writeFileSync(out, `# Generated by eleventy.config.cjs - do not edit. Static headers live in netlify.toml.\n/*\n  Content-Security-Policy: ${csp}\n`);
  });

  // Current year, for the footer copyright line.
  eleventyConfig.addShortcode("year", () => `${new Date().getFullYear()}`);

  // ISO date for sitemap.xml <lastmod>.
  eleventyConfig.addFilter("dateISO", (d) =>
    (d instanceof Date ? d : new Date()).toISOString().slice(0, 10)
  );

  return {
    dir: {
      input: "src",
      output: "_site",
      includes: "_includes",
      data: "_data"
    },
    // Nunjucks for templates, Markdown allowed inside pages if wanted later.
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
    templateFormats: ["njk", "md", "html"]
  };
};
