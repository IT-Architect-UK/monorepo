// Slugs of bookable services delivered remotely (catalogue location: video).
// /booked/ uses it to word "what happens next" for a call rather than a visit.
const catalogue = require("./catalogue.json");
module.exports = catalogue.services.filter((s) => s.bookable && s.location === "video").map((s) => s.slug);
