#!/usr/bin/env bash
# Check the artifact of the sast-workflow selftest job: sast-report.sh <dir>
set -euo pipefail
dir=$1
[ "$SCAN_STATUS" = completed ] || { echo "scan-status '$SCAN_STATUS'"; exit 1; }
[ "$FINDING_STATUS" = new ] || { echo "finding-status '$FINDING_STATUS'"; exit 1; }
python3 - "$dir" <<'PY'
import json, sys
d = sys.argv[1]
status = json.load(open(f"{d}/status.json"))
findings = json.load(open(f"{d}/findings.json"))["findings"]
assert status["scan_status"] == "completed", status
assert status["tools"]["gosec"]["status"] == "completed", status
assert status["tools"]["opengrep"]["status"] == "completed", status
assert status["counts"]["blocking"] == 0, "report mode never blocks"
seen = {f["rule"] for f in findings}
for rule in ("G402", "otfabric-wire-length-unchecked-make", "otfabric-shell-world-writable", "run-shell-injection", "detected-private-key"):
    assert rule in seen, f"{rule} missing"
for name in ("gosec", "opengrep"):
    sarif = json.load(open(f"{d}/{name}.sarif"))
    assert sarif["version"] == "2.1.0" and sarif["runs"][0]["results"], name
text = open(f"{d}/findings.json").read()
assert "not-a-key-only" not in text and "InsecureSkipVerify: true" not in text, "reports carry no source"
PY
echo "workflow report: completed scan, planted findings, no source lines"
