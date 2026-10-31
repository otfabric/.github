#!/usr/bin/env bash
# Scan the current directory: run-opengrep.sh <out dir> <rules dir>
# Records opengrep.json and opengrep.exit, and always exits 0: sast_gate.py
# decides what a failed or partial scan means. Files in the scanned tree decide
# nothing: .semgrepignore and .gitignore are ignored, and nosemgrep comments
# cannot waive a finding (.otfabric/sast-baseline.json does).
set -uo pipefail
out=$1
rules=$2
here=$(cd "$(dirname "$0")" && pwd)
: "${OPENGREP_BIN:=opengrep}"
: "${OPENGREP_EXCLUDE:=testdata,vendor,node_modules,*_test.go}"
rm -f "$out/opengrep.json" "$out/opengrep.exit"

args=(scan --quiet --disable-version-check --no-git-ignore --x-ignore-semgrepignore-files --disable-nosem
  --timeout=30 --timeout-threshold=3 --json-output="$out/opengrep.json" --config="$here/opengrep/rules")
while read -r path _; do
  case "$path" in '' | '#'*) continue ;; esac
  args+=(--config="$rules/$path")
done < "$here/opengrep/upstream.txt"
IFS=',' read -r -a excludes <<<"$OPENGREP_EXCLUDE"
for e in "${excludes[@]}"; do
  args+=(--exclude="$e")
done
rc=0
"$OPENGREP_BIN" "${args[@]}" . > /dev/null 2> "$out/opengrep.error" || rc=$?
echo "$rc" > "$out/opengrep.exit"
[ "$rc" != 0 ] || rm -f "$out/opengrep.error"
exit 0
