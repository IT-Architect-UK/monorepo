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
