const { execFile } = require("child_process");
const https = require("https");

const agent = new https.Agent({ rejectUnauthorized: true });
execFile("ping", ["device.example"], () => agent.destroy());
