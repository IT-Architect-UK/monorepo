/**
 * Eleventy configuration for the IT Surgery website.
 *
 * Input  : src/
 * Output : _site/  (what Netlify publishes)
 *
 * Pages use directory-style URLs (e.g. /about-us/) so the existing
 * itsurgery.me URLs are preserved and search rankings are not lost.
 */
module.exports = function (eleventyConfig) {
  // Copy the stylesheet through untouched.
  eleventyConfig.addPassthroughCopy({ "src/assets": "assets" });

  // Current year, for the footer copyright line.
  eleventyConfig.addShortcode("year", () => `${new Date().getFullYear()}`);

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
