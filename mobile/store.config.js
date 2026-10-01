// The App Store listing for EAS Metadata (eas.json points here). The listing is
// in store.config.json; the contact for Apple's reviewers (email and phone) is
// private, so it comes from store.review.local.json, which stays out of git:
//   { "email": "...", "phone": "+39 ..." }
// or from the APPLE_REVIEW_EMAIL and APPLE_REVIEW_PHONE environment variables.
const fs = require('node:fs');
const path = require('node:path');
const config = require('./store.config.json');

const file = path.join(__dirname, 'store.review.local.json');
const local = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {};
config.apple.review.email = process.env.APPLE_REVIEW_EMAIL || local.email || config.apple.review.email;
config.apple.review.phone = process.env.APPLE_REVIEW_PHONE || local.phone || config.apple.review.phone;

module.exports = config;
