// Slug -> catalogue entry, for the "Fixed prices for this" block on service
// pages. Same reasoning as bookmap.js: the join lives in a data file because
// Nunjucks cannot do it reliably in a template expression.
const catalogue = require("./catalogue.json");
const map = {};
for (const s of catalogue.services) map[s.slug] = s;
module.exports = map;
