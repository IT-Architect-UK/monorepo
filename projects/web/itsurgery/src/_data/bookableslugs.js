// The slug allow-list the /book/ page embeds. Only catalogue-approved slugs
// may reach the Cal.com embed from a query parameter.
const catalogue = require("./catalogue.json");
module.exports = catalogue.services.filter(s => s.bookable).map(s => s.slug);
