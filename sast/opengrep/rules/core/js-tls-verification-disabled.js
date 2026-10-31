const https = require("https");

// ruleid: otfabric-js-tls-verification-disabled
const bad = new https.Agent({ rejectUnauthorized: false });
// ruleid: otfabric-js-tls-verification-disabled
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

// ok: otfabric-js-tls-verification-disabled
const good = new https.Agent({ rejectUnauthorized: true, ca: ca });
