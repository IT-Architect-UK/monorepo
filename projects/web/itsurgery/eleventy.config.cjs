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
const crypto = require("crypto");

module.exports = function (eleventyConfig) {
  // Copy the stylesheet through untouched.
  eleventyConfig.addPassthroughCopy({ "src/assets": "assets" });

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
