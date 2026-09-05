// Directory data for every page under src/.
//
// date drives <lastmod> in sitemap.xml. Eleventy's default is the file's
// creation time, which on Netlify is the moment of the clone - so every page
// claimed to have changed on every deploy, and the sitemap told search engines
// nothing. "git Last Modified" uses the last commit that touched the template
// instead. Where git history is unavailable Eleventy falls back to the file
// time, so a build never fails on this.
module.exports = { date: "git Last Modified" };
