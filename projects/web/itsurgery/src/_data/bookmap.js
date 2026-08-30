// Label -> catalogue entry, joined here in JavaScript because the template
// tried to do it with selectattr("equalto"), which is Jinja, not Nunjucks —
// and Nunjucks failed it silently into "no buttons at all". A data file can
// be unit-thought; a clever template expression evidently cannot.
const catalogue = require("./catalogue.json");
const map = {};
for (const s of catalogue.services) map[s.name] = s;
module.exports = map;
