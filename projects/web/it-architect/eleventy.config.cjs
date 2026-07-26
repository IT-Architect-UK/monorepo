/**
 * Eleventy configuration for the IT Architect site.
 * Input src/, output _site/ (published by Netlify).
 */
const fs = require("fs");
const crypto = require("crypto");

module.exports = function (eleventyConfig) {
  eleventyConfig.addPassthroughCopy({ "src/assets": "assets" });

  // Cache-busting hash for the stylesheet — assets are served with a long
  // max-age and the filename never changes.
  eleventyConfig.addGlobalData("assetHash", () =>
    crypto.createHash("md5")
      .update(fs.readFileSync("src/assets/styles.css"))
      .digest("hex").slice(0, 8)
  );

  eleventyConfig.addShortcode("year", () => `${new Date().getFullYear()}`);
  eleventyConfig.addFilter("dateISO", (d) =>
    (d instanceof Date ? d : new Date()).toISOString().slice(0, 10)
  );

  return {
    dir: { input: "src", output: "_site", includes: "_includes", data: "_data" },
    markdownTemplateEngine: "njk",
    htmlTemplateEngine: "njk",
    templateFormats: ["njk", "md", "html"]
  };
};
