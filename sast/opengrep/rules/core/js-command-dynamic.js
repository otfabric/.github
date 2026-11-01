const child_process = require("child_process");

function vulnerable(host) {
  // ruleid: otfabric-js-command-dynamic
  child_process.exec(`ping ${host}`);
  // ruleid: otfabric-js-command-dynamic
  child_process.execSync("ping " + host);
}

function safe(host) {
  // ok: otfabric-js-command-dynamic
  child_process.execFile("ping", [host]);
  // ok: otfabric-js-command-dynamic
  child_process.exec("ip link show");
}
