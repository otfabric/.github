// Planted: a shell gets a command line built at run time, certificates unchecked.
const child_process = require("child_process");
const https = require("https");

const agent = new https.Agent({ rejectUnauthorized: false });

function run(host) {
  child_process.exec(`ping ${host}`, () => agent.destroy());
}
