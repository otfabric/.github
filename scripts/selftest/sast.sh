#!/usr/bin/env bash
# The gate of sast_gate.py on hand-written reports, with no scanner: statuses,
# exit codes, baseline records, and hostile names in findings. sast-e2e.sh runs
# the real scanners.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
gate=$root/sast/sast_gate.py
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
repo=$tmp/repo
mkdir -p "$repo/.otfabric" "$repo/pkg"
printf 'package pkg\n\nvar x = insecure()\n' > "$repo/pkg/a.go"

fail() { echo "FAIL: $*"; exit 1; }

# report <exit> <issues json> [stats files] [golang errors json]
report() {
  local out=$tmp/out
  rm -rf "$out"
  mkdir -p "$out"
  echo "$1" > "$out/gosec.exit"
  printf '{"Golang errors": %s, "Issues": %s, "Stats": {"files": %s, "found": 0}}' "${4:-{\}}" "$2" "${3:-1}" > "$out/gosec.json"
}

issue() {
  printf '{"severity": "%s", "confidence": "%s", "cwe": {"id": "295"}, "rule_id": "G402", "details": "d", "file": "%s", "line": "3"}' "$1" "$2" "${3:-$repo/pkg/a.go}"
}

evaluate() {
  python3 "$gate" evaluate --out "$tmp/out" --root "$repo" --bundle "$root" --opengrep false --keep-raw --today 2026-11-01 --mode "$@"
}

# expect <what> <want> <subcommand>
expect() {
  local got=0
  python3 "$gate" "$3" --out "$tmp/out" > "$tmp/log" 2>&1 || got=$?
  [ "$got" = "$2" ] || { cat "$tmp/log"; fail "$1: exit $got, want $2"; }
}

status() { python3 -c "import json,sys; print(json.load(open('$tmp/out/status.json'))$1)"; }

# Modes on one new high-confidence finding.
report 0 "[$(issue HIGH HIGH)]"
evaluate report > /dev/null; expect "report" 0 check-findings; expect "report scan" 0 check-scan
[ "$(status "['finding_status']")" = new ] || fail "report mode names the new finding"
evaluate baseline > /dev/null; expect "baseline" 1 check-findings
evaluate enforce > /dev/null; expect "enforce" 1 check-findings

# Thresholds: confidence and severity both have to reach them.
report 0 "[$(issue HIGH MEDIUM),$(issue MEDIUM HIGH)]"
evaluate enforce > /dev/null; expect "below the thresholds" 0 check-findings
[ "$(status "['counts']['below_threshold']")" = 2 ] || fail "below-threshold count"
evaluate enforce --block-confidence medium > /dev/null; expect "lowered confidence" 1 check-findings
echo "modes and thresholds match"

# Records: states against modes, then what makes a record stop counting.
report 0 "[$(issue HIGH HIGH)]"
evaluate report > /dev/null
fp=$(python3 -c "import json; print(json.load(open('$tmp/out/findings.json'))['findings'][0]['fingerprint'])")
record() { # state, then extra JSON fields
  printf '{"schema": 1, "findings": [{"fingerprint": "%s", "tool": "gosec", "rule": "G402", "path": "pkg/a.go", "state": "%s", "justification": "j", "owner": "o", "ref": "r"%s}]}' "$fp" "$1" "$2" > "$repo/.otfabric/sast-baseline.json"
}
record baseline ', "reviewed": "2026-10-31", "expires": "2027-04-30"'
evaluate baseline > /dev/null; expect "debt in baseline mode" 0 check-findings
evaluate enforce > /dev/null; expect "debt in enforce mode" 1 check-findings
record false-positive ', "reviewed": "2026-10-31", "reconsider": "when TLS changes"'
evaluate enforce > /dev/null; expect "false positive in enforce mode" 0 check-findings
record accepted-risk ', "reviewed": "2026-10-31", "expires": "2027-04-30"'
evaluate enforce > /dev/null; expect "accepted risk in enforce mode" 0 check-findings
record baseline ', "reviewed": "2026-01-01", "expires": "2026-06-30"'
evaluate baseline > /dev/null; expect "an expired record no longer applies" 1 check-findings
[ "$(status "['baseline']['expired'][0]")" = "$fp" ] || fail "expired records are listed"
record false-positive ', "reviewed": "2026-01-01", "reconsider": "x"'
evaluate baseline > /dev/null
[ "$(status "['baseline']['review_due'][0]")" = "$fp" ] || fail "a record past six months is due for review"
record baseline ', "reviewed": "2026-10-31", "reconsider": "x"'
evaluate baseline > /dev/null; expect "debt with no end is invalid" 3 check-scan
echo '{"schema": 1, "findings": [{"fingerprint": "x"}]}' > "$repo/.otfabric/sast-baseline.json"
evaluate baseline > /dev/null; expect "an invalid record is a broken gate" 3 check-scan
echo 'nope' > "$repo/.otfabric/sast-baseline.json"
evaluate enforce > /dev/null; expect "an unreadable baseline is a broken gate" 3 check-scan
record false-positive ', "reviewed": "2026-10-31", "reconsider": "x"'
report 0 "[]"
evaluate enforce > /dev/null; expect "no findings" 0 check-findings
[ "$(status "['baseline']['stale'][0]")" = "$fp" ] || fail "records matching nothing are listed"
rm "$repo/.otfabric/sast-baseline.json"
echo "baseline records match"

# Anything less than a whole scan is not completed, and says why.
report 0 "[]" 0
evaluate enforce > /dev/null; expect "no files scanned" 3 check-scan
report 0 "[]" 3 '{"/x/a.go": [{"line": 1}]}'
evaluate enforce > /dev/null; expect "type errors" 3 check-scan
report 2 "[]"; echo 'boom' > "$tmp/out/gosec.error"
evaluate enforce > /dev/null; expect "exit 2" 3 check-scan; grep -q boom "$tmp/log" || fail "the reason is shown"
report 0 "[]"; echo '{' > "$tmp/out/gosec.json"
evaluate enforce > /dev/null; expect "broken JSON" 3 check-scan
report 0 "[]"; rm "$tmp/out/gosec.json"
evaluate enforce > /dev/null; expect "no report" 3 check-scan
report 0 "[]"; rm "$tmp/out/gosec.exit"
evaluate enforce > /dev/null; expect "no exit code" 3 check-scan
report 0 "[]"; echo '{"Issues": "x"}' > "$tmp/out/gosec.json"
evaluate enforce > /dev/null; expect "unknown shape" 3 check-scan
rm -rf "$tmp/out"; mkdir -p "$tmp/out"
expect "no status at all" 3 check-scan
python3 "$gate" evaluate --out "$tmp/out" --root "$repo" --bundle "$root" --gosec false --opengrep false --mode enforce > /dev/null
expect "nothing enabled is no scan" 3 check-scan
[ "$(status "['scan_status']")" = incomplete ] || fail "nothing enabled is not completed"
echo "incomplete scans match"

# An opengrep report that exits 0 but did not run its rules.
mkdir -p "$tmp/out"
opengrep() {
  python3 "$gate" evaluate --out "$tmp/out" --root "$repo" --bundle "$root" --gosec false --mode enforce --keep-raw > /dev/null
}
echo 0 > "$tmp/out/opengrep.exit"
echo '{"results": [], "paths": {"scanned": ["a.go"]}, "errors": [{"level": "error", "type": "Rule parse error", "message": "x"}]}' > "$tmp/out/opengrep.json"
opengrep; expect "a rule error" 3 check-scan
echo '{"results": [], "paths": {"scanned": ["a.go"]}, "errors": [{"level": "warn", "type": "Timeout", "message": "x"}]}' > "$tmp/out/opengrep.json"
opengrep; expect "a rule timeout" 3 check-scan
echo '{"results": [], "paths": {"scanned": ["a.go"]}, "errors": [{"level": "warn", "type": ["PartialParsing", []], "message": "x"}]}' > "$tmp/out/opengrep.json"
opengrep; expect "partial parsing is only noted" 0 check-scan
[ "$(status "['notes'][0]")" = "opengrep could not fully parse 1 file(s)" ] || fail "partial parsing is noted"
echo '{"results": [], "paths": {"scanned": []}, "errors": []}' > "$tmp/out/opengrep.json"
opengrep; expect "no files" 3 check-scan
echo "opengrep reports match"

# Hostile names reach no workflow command and no Markdown structure, and no
# report holds source text. File names can hold newlines; these are the payloads.
hostile=$'pkg/x\n::set-output name=x::y|<img src=x>`.go'
mkdir -p "$repo/pkg"
printf 'password = "hunter2-secret-value"\n' > "$repo/$hostile"
python3 - "$tmp/out" "$repo/$hostile" <<'PY'
import json, sys
out, path = sys.argv[1:3]
issue = {"severity": "HIGH", "confidence": "HIGH", "cwe": {"id": "798"}, "rule_id": "G101", "details": "%0A::error::x\n::warning::y", "file": path, "line": "1", "code": "hunter2-secret-value"}
json.dump({"Golang errors": {}, "Issues": [issue], "Stats": {"files": 1}}, open(f"{out}/gosec.json", "w"))
open(f"{out}/gosec.exit", "w").write("0")
PY
python3 "$gate" evaluate --out "$tmp/out" --root "$repo" --bundle "$root" --opengrep false --mode baseline --keep-raw > "$tmp/log"
[ "$(grep -c '^::' "$tmp/log")" = 1 ] || { cat "$tmp/log"; fail "one finding is one workflow command"; }
grep -q '^::set-output' "$tmp/log" && fail "file name started a workflow command"
grep -q '<img' "$tmp/out/summary.md" && ! grep -q '\\<img' "$tmp/out/summary.md" && fail "Markdown not escaped"
rm "$tmp/out/gosec.json"
python3 "$gate" evaluate --out "$tmp/out" --root "$repo" --bundle "$root" --opengrep false --mode report > /dev/null || true
for f in "$tmp"/out/{findings.json,status.json,summary.md,gosec.sarif}; do
  ! grep -q hunter2 "$f" || fail "$f carries source text"
done
rm -f "$repo/$hostile"

echo "hostile input is neutralised"
echo "all SAST gate cases match"
