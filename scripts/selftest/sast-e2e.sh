#!/usr/bin/env bash
# The pinned scanners through the workflow's own scripts, on the fixtures:
# detection, baseline, enforcement, and scanner failures kept apart from
# findings. sast-e2e.sh <gosec> <opengrep> <rules dir>
set -uo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
export GOSEC_BIN=$1 OPENGREP_BIN=$2
rules=$3
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gate=$root/sast/sast_gate.py

fail() { echo "FAIL: $*"; exit 1; }

# scan <name> <fixture dir> <module-dir or empty>: reports into $tmp/<name>.
scan() {
  local out=$tmp/$1 src=$2
  mkdir -p "$out"
  (cd "$src" && bash "$root/sast/run-gosec.sh" "$out" && OPENGREP_EXCLUDE=vendor bash "$root/sast/run-opengrep.sh" "$out" "$rules")
}

# evaluate <out> <root> <mode> [baseline file]; keeps raw reports for reruns.
evaluate() {
  python3 "$gate" evaluate --out "$1" --root "$2" --bundle "$root" --mode "$3" --keep-raw --today 2026-11-01 \
    ${4:+--baseline "$4"} > "$1/log"
}

# expect <what> <want exit> <cmd...>
expect() {
  local what=$1 want=$2 got=0
  shift 2
  "$@" > "$tmp/log" 2>&1 || got=$?
  [ "$got" = "$want" ] || { cat "$tmp/log"; fail "$what: exit $got, want $want"; }
}

v=$tmp/repo-go
cp -R testdata/sast/vulnerable-go "$v"
scan v "$v"
evaluate "$tmp/v" "$v" report

python3 - "$tmp/v" <<'PY' || fail "detection"
import json, sys
d = sys.argv[1]
findings = json.load(open(f"{d}/findings.json"))["findings"]
status = json.load(open(f"{d}/status.json"))
by_rule = {}
for f in findings:
    by_rule.setdefault(f["rule"], []).append(f)
assert status["scan_status"] == "completed", status
for rule in ("G402", "G204", "G115", "otfabric-wire-length-unchecked-make", "otfabric-secret-in-log",
             "otfabric-exec-shell-dynamic", "otfabric-defer-in-unbounded-loop", "otfabric-http-body-unbounded-read"):
    assert rule in by_rule, f"{rule} missing: {sorted(by_rule)}"
assert len(by_rule["G402"]) == 2, "#nosec must not waive a finding"
assert all(f["disposition"] == "below-threshold" for f in by_rule["G115"]), "G115 stays below the threshold"
assert all(f["in_threshold"] for f in by_rule["otfabric-wire-length-unchecked-make"]), "nosemgrep must not waive a finding"
PY
echo "detection: gosec and custom rules find the planted Go weaknesses"

o=$tmp/repo-other
cp -R testdata/sast/other "$o"
mkdir -p "$tmp/o"
(cd "$o" && OPENGREP_EXCLUDE=vendor bash "$root/sast/run-opengrep.sh" "$tmp/o" "$rules")
python3 "$gate" evaluate --out "$tmp/o" --root "$o" --bundle "$root" --mode report --gosec false --keep-raw > /dev/null
python3 - "$tmp/o" <<'PY' || fail "other languages"
import json, sys
findings = json.load(open(f"{sys.argv[1]}/findings.json"))["findings"]
seen = {f["rule"] for f in findings}
for rule in ("run-shell-injection", "curl-pipe-bash", "otfabric-shell-disables-tls-verification",
             "otfabric-shell-world-writable", "subprocess-shell-true", "disabled-cert-validation", "detected-private-key"):
    assert rule in seen, f"{rule} missing: {sorted(seen)}"
key = [f for f in findings if f["rule"] == "detected-private-key"]
assert key[0]["confidence"] == "high", "catalog override applies"
PY
echo "detection: workflow, shell, Python and secret rules fire, and .semgrepignore hides nothing"

# Enforcement: new findings block outside report mode.
expect "report never blocks" 0 python3 "$gate" check-findings --out "$tmp/v"
evaluate "$tmp/v" "$v" baseline
expect "baseline blocks new" 1 python3 "$gate" check-findings --out "$tmp/v"
expect "the scan itself is fine" 0 python3 "$gate" check-scan --out "$tmp/v"
evaluate "$tmp/v" "$v" enforce
expect "enforce blocks new" 1 python3 "$gate" check-findings --out "$tmp/v"
echo "enforcement: new high-confidence findings block in baseline and enforce"

# Baseline: recording current findings clears the baseline mode, not enforce.
mkdir -p "$v/.otfabric"
python3 "$gate" baseline --findings "$tmp/v/findings.json" --baseline "$v/.otfabric/sast-baseline.json" \
  --owner selftest --expires 2027-05-01 --ref "https://example.invalid/1" --today 2026-11-01 > /dev/null
evaluate "$tmp/v" "$v" baseline
expect "baselined findings pass in baseline mode" 0 python3 "$gate" check-findings --out "$tmp/v"
evaluate "$tmp/v" "$v" enforce
expect "state baseline still blocks in enforce" 1 python3 "$gate" check-findings --out "$tmp/v"

# A new vulnerability next to baselined ones is a regression.
cat >> "$v/vulnerable.go" <<'GO'

func Regression() *tls.Config {
	return &tls.Config{InsecureSkipVerify: true, ServerName: "regression"}
}
GO
scan v "$v"
evaluate "$tmp/v" "$v" baseline
expect "a new finding blocks despite the baseline" 1 python3 "$gate" check-findings --out "$tmp/v"
grep -q '"blocking": 1' "$tmp/v/status.json" || fail "exactly the new finding blocks"
echo "baseline: debt passes, a regression next to it blocks"

# Moving code does not change a fingerprint.
sed -i.bak '1i\
// moved down one line' "$v/vulnerable.go"
rm -f "$v/vulnerable.go.bak"
scan v "$v"
evaluate "$tmp/v" "$v" baseline
grep -q '"blocking": 1' "$tmp/v/status.json" || fail "a moved line keeps its record"
echo "baseline: fingerprints survive moved lines"

# Scanner failures: never a green scan, never reported as findings.
c=$tmp/repo-clean
cp -R testdata/sast/clean-go "$c"
scan c "$c"
evaluate "$tmp/c" "$c" enforce
expect "clean module passes the scan check" 0 python3 "$gate" check-scan --out "$tmp/c"
expect "clean module passes the findings check" 0 python3 "$gate" check-findings --out "$tmp/c"

b=$tmp/repo-broken
cp -R testdata/sast/broken-go "$b"
scan b "$b"
evaluate "$tmp/b" "$b" enforce
expect "code that does not type-check is an incomplete scan" 3 python3 "$gate" check-scan --out "$tmp/b"

mkdir -p "$tmp/f"
(cd "$c" && GOSEC_BIN=/nonexistent/gosec bash "$root/sast/run-gosec.sh" "$tmp/f"; OPENGREP_BIN=/nonexistent/opengrep bash "$root/sast/run-opengrep.sh" "$tmp/f" "$rules")
evaluate "$tmp/f" "$c" enforce
expect "missing scanners are a scanner failure" 3 python3 "$gate" check-scan --out "$tmp/f"
expect "and not a finding" 0 python3 "$gate" check-findings --out "$tmp/f"
evaluate "$tmp/f" "$c" report
expect "report mode warns about it" 0 python3 "$gate" check-scan --out "$tmp/f"
grep -q 'NOT fully scanned' "$tmp/log" || fail "report mode must say the commit was not scanned"
grep -q '"scan_status": "incomplete"' "$tmp/f/status.json" || fail "status must say incomplete"

# A rule the engine rejects leaves opengrep looking healthy: exit 0, no findings.
mkdir -p "$tmp/badrules" "$tmp/r"
cp -R sast "$tmp/badrules/sast"
printf 'rules:\n  - id: broken\n    languages: [go]\n    severity: ERROR\n    message: x\n    patterns:\n      - pattern: "func("\n' > "$tmp/badrules/sast/opengrep/rules/broken.yaml"
(cd "$c" && bash "$tmp/badrules/sast/run-opengrep.sh" "$tmp/r" "$rules")
python3 "$gate" evaluate --out "$tmp/r" --root "$c" --bundle "$root" --mode enforce --gosec false > /dev/null
expect "a rule that does not load is a scanner failure" 3 python3 "$gate" check-scan --out "$tmp/r"
echo "scanner failures: exit 3 in enforcing modes, a warning in report mode, never a finding"
echo "all SAST scanner cases match"
