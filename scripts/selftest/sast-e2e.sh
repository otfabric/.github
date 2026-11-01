#!/usr/bin/env bash
# The pinned scanners through the workflow's own scripts, on the fixtures:
# detection, baseline, enforcement, and scanner failures kept apart from
# findings. sast-e2e.sh <gosec> <opengrep>
set -uo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
export GOSEC_BIN=$1 OPENGREP_BIN=$2
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gate=$root/sast/sast_gate.py

fail() { echo "FAIL: $*"; exit 1; }

# scan <name> <fixture dir> <module-dir or empty>: reports into $tmp/<name>.
scan() {
  local out=$tmp/$1 src=$2
  mkdir -p "$out"
  (cd "$src" && bash "$root/sast/run-gosec.sh" "$out" && OPENGREP_EXCLUDE=vendor bash "$root/sast/run-opengrep.sh" "$out")
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
             "otfabric-exec-shell-dynamic", "otfabric-defer-in-unbounded-loop", "otfabric-http-body-unbounded-read",
             "G101", "otfabric-go-http-path-to-file"):
    assert rule in by_rule, f"{rule} missing: {sorted(by_rule)}"
assert len(by_rule["G402"]) == 2, "#nosec must not waive a finding"
assert all(f["disposition"] == "below-threshold" for f in by_rule["G115"]), "G115 stays below the threshold"
assert all(f["in_threshold"] for f in by_rule["otfabric-wire-length-unchecked-make"]), "nosemgrep must not waive a finding"
PY
echo "detection: gosec and custom rules find the planted Go weaknesses"

o=$tmp/repo-other
cp -R testdata/sast/other "$o"
scan o "$o"
evaluate "$tmp/o" "$o" report
python3 - "$tmp/o" <<'PY' || fail "other languages"
import json, sys
d = sys.argv[1]
findings = json.load(open(f"{d}/findings.json"))["findings"]
status = json.load(open(f"{d}/status.json"))
seen = {f["rule"] for f in findings}
for rule in ("otfabric-gha-untrusted-input-in-script", "otfabric-shell-pipe-to-interpreter", "otfabric-shell-disables-tls-verification",
             "otfabric-shell-world-writable", "otfabric-python-shell-dynamic", "otfabric-python-tls-verification-disabled",
             "otfabric-private-key-in-tree", "otfabric-js-command-dynamic", "otfabric-js-tls-verification-disabled",
             "otfabric-github-token-in-tree", "otfabric-aws-credential-in-tree", "otfabric-gha-workflow-run-checkout"):
    assert rule in seen, f"{rule} missing: {sorted(seen)}"
assert status["tools"]["gosec"]["status"] == "not-applicable", status
assert status["scan_status"] == "completed", "no Go is not a failure when Opengrep ran"
assert status["tools"]["opengrep"]["ruleset"]["packs"] == ["core", "protocol"], status
PY
expect "a tree without Go passes the scan check" 0 python3 "$gate" check-scan --out "$tmp/o"
echo "detection: workflow, shell, Python, JS and secret rules fire, .semgrepignore hides nothing, Gosec skips a tree with no Go"

# The profile picks the packs.
p=$tmp/repo-profile
cp -R testdata/sast/vulnerable-go "$p"
mkdir -p "$p/.otfabric"
printf 'policy: "1.3"\nprofile: website # comment\nmode: report\n' > "$p/.otfabric/policy.yaml"
scan p "$p"
evaluate "$tmp/p" "$p" report
python3 - "$tmp/p" <<'PY' || fail "profile scoping"
import json, sys
d = sys.argv[1]
seen = {f["rule"] for f in json.load(open(f"{d}/findings.json"))["findings"]}
assert json.load(open(f"{d}/status.json"))["tools"]["opengrep"]["ruleset"]["packs"] == ["core"]
assert "otfabric-secret-in-log" in seen and "otfabric-wire-length-unchecked-make" not in seen, sorted(seen)
PY
echo "profiles: a website runs the core pack only"

# Nested modules: each scan sees its own module, and says what it left out.
n=$tmp/repo-nested
cp -R testdata/sast/nested-go "$n"
scan n "$n"
evaluate "$tmp/n" "$n" enforce
expect "the outer module passes" 0 python3 "$gate" check-findings --out "$tmp/n"
grep -q '"G402"' "$tmp/n/findings.json" && fail "a scan of the outer module reached the nested one"
python3 -c "import json,sys; assert json.load(open('$tmp/n/status.json'))['tools']['gosec']['nested_modules_not_scanned'] == ['sub']" || fail "the nested module is named"
mkdir -p "$tmp/ns"
(cd "$n/sub" && bash "$root/sast/run-gosec.sh" "$tmp/ns")
python3 "$gate" evaluate --out "$tmp/ns" --root "$n" --bundle "$root" --module-dir sub --opengrep false --mode enforce --keep-raw --today 2026-11-01 > /dev/null
expect "module-dir reaches the nested module" 1 python3 "$gate" check-findings --out "$tmp/ns"
python3 -c "import json,sys; f=json.load(open('$tmp/ns/findings.json'))['findings'][0]; assert f['path'] == 'sub/sub.go', f" || fail "paths stay relative to the repository"
echo "nested modules: scanned by module-dir, listed otherwise"

# Go code with no module here is a wrong module-dir, not a tree without Go.
g=$tmp/repo-nomod
cp -R testdata/sast/go-no-module "$g"
scan g "$g"
evaluate "$tmp/g" "$g" report
expect "Go code without go.mod fails the scan" 3 python3 "$gate" check-scan --out "$tmp/g"

# Safe code of every language: no finding of any severity.
s=$tmp/repo-safe
cp -R testdata/sast/clean-other "$s"
scan s "$s"
evaluate "$tmp/s" "$s" enforce
python3 -c "import json; c=json.load(open('$tmp/s/status.json'))['counts']; assert c['total'] == 0, json.load(open('$tmp/s/findings.json'))" || fail "safe fixtures have no findings"
echo "safe fixtures: nothing reported"

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
(cd "$c" && GOSEC_BIN=/nonexistent/gosec bash "$root/sast/run-gosec.sh" "$tmp/f"; OPENGREP_BIN=/nonexistent/opengrep bash "$root/sast/run-opengrep.sh" "$tmp/f")
evaluate "$tmp/f" "$c" enforce
expect "missing scanners are a scanner failure" 3 python3 "$gate" check-scan --out "$tmp/f"
expect "and not a finding" 0 python3 "$gate" check-findings --out "$tmp/f"
evaluate "$tmp/f" "$c" report
expect "and fail in report mode too" 3 python3 "$gate" check-scan --out "$tmp/f"
grep -q 'NOT fully scanned' "$tmp/log" || fail "the failure must say the commit was not scanned"
grep -q '"scan_status": "incomplete"' "$tmp/f/status.json" || fail "status must say incomplete"

# bundle <name>: a copy of the bundle to damage.
bundle() {
  mkdir -p "$tmp/$1" "$tmp/$1-out"
  cp -R sast "$tmp/$1/sast"
}
# damaged <what> <name>: scan with the damaged copy, in report mode.
damaged() {
  (cd "$c" && bash "$tmp/$2/sast/run-opengrep.sh" "$tmp/$2-out")
  python3 "$gate" evaluate --out "$tmp/$2-out" --root "$c" --bundle "$tmp/$2" --mode report --gosec false > /dev/null
  expect "$1" 3 python3 "$gate" check-scan --out "$tmp/$2-out"
}

# A rule the engine rejects leaves opengrep looking healthy: exit 0, no findings.
bundle badrule
printf 'rules:\n  - id: broken\n    languages: [go]\n    severity: ERROR\n    message: x\n    patterns:\n      - pattern: "func("\n' > "$tmp/badrule/sast/opengrep/rules/core/broken.yaml"
damaged "a rule that does not load is a scanner failure" badrule
bundle onemissing
rm "$tmp/onemissing/sast/opengrep/rules/core/secret-in-log.yaml"
damaged "a missing rule file changes the digest" onemissing
grep -q 'digest' "$tmp/log" || fail "the digest is the reason"
bundle packmissing
rm -rf "$tmp/packmissing/sast/opengrep/rules/protocol"
damaged "a missing pack is a scanner failure" packmissing
bundle packempty
rm "$tmp"/packempty/sast/opengrep/rules/core/*.yaml
damaged "an empty pack is a scanner failure" packempty
echo "scanner failures: exit 3 in every mode, never a finding; rule files missing or rejected fail the scan"
echo "all SAST scanner cases match"
