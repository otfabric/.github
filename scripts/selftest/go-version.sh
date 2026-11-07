#!/usr/bin/env bash
# Cases of the "Resolve Go version" step of go-binary-release.yml, run on the
# go.mod fixtures with the exact step script. Both copies of the step (the
# prepare job and the build job) must be the same script.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
wf="$root/.github/workflows/go-binary-release.yml"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 "$root/scripts/selftest/extract-step.py" "$wf" "Resolve Go version" > "$work/step.sh"
count=$(grep -c -- '- name: Resolve Go version' "$wf")
[ "$count" = 2 ] || { echo "FAIL want 2 Resolve Go version steps, got $count"; exit 1; }
# extract-step.py prints the first step; check the second has the same run block.
python3 - "$wf" "$work/step.sh" <<'EOF'
import sys
lines = open(sys.argv[1]).read().split("\n")
first = open(sys.argv[2]).read().strip()
starts = [i for i, l in enumerate(lines) if l.strip() == "- name: Resolve Go version"]
blocks = []
for i in starts:
    j = next(k for k in range(i, len(lines)) if lines[k].strip() == "run: |")
    ind = len(lines[j]) - len(lines[j].lstrip())
    body = []
    for l in lines[j + 1:]:
        if l.strip() and len(l) - len(l.lstrip()) <= ind:
            break
        body.append(l[ind + 2:] if l.strip() else "")
    blocks.append("\n".join(body).strip())
if len(set(blocks)) != 1 or blocks[0] != first:
    sys.exit("FAIL the two Resolve Go version steps differ")
EOF

fail=0
check() { # fixture want-exit want-version
  local got=0 out="$work/out"
  : > "$work/output"
  GO_MOD="$root/testdata/go-version/$1.go.mod" GITHUB_OUTPUT="$work/output" bash -e "$work/step.sh" > "$out" 2>&1 || got=$?
  local version
  version=$(sed -n 's/^version=//p' "$work/output")
  if [ "$got" = "$2" ] && [ "$version" = "$3" ]; then
    echo "ok   $1: exit $got, version '${version}'"
  else
    echo "FAIL $1: exit $got version '${version}', want exit $2 version '$3'"; cat "$out"; fail=1
  fi
}

check patch 0 1.26
check minor 0 1.26
check toolchain-newer 0 1.27
check toolchain-same 0 1.27
check two-digit 0 1.10
check no-go 1 ""
check missing 1 ""
exit $fail
