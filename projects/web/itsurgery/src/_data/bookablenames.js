// slug -> display name, for the "Booking: X" line on /book/.
const catalogue = require("./catalogue.json");
const out = {};
for (const s of catalogue.services) if (s.bookable) out[s.slug] = s.name;
module.exports = out;
