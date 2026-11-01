#!/usr/bin/env bash
# Scan the current directory: run-opengrep.sh <out dir>
# Records opengrep.json, opengrep.exit and opengrep.packs, and always exits 0:
# sast_gate.py decides what a failed or partial scan means. Files in the scanned
# tree decide nothing: .semgrepignore and .gitignore are ignored, and nosemgrep
# comments cannot waive a finding (.otfabric/sast-baseline.json does).
#
# The profile in .otfabric/policy.yaml picks the rule packs; it is read as text.
# Without one, every pack runs.
set -uo pipefail
out=$1
here=$(cd "$(dirname "$0")" && pwd)
: "${OPENGREP_BIN:=opengrep}"
: "${OPENGREP_EXCLUDE:=testdata,vendor,node_modules,*_test.go}"
rm -f "$out/opengrep.json" "$out/opengrep.exit" "$out/opengrep.packs"

profile=$(sed -n 's/^profile:[[:space:]]*\([a-z-]*\).*/\1/p' .otfabric/policy.yaml 2> /dev/null | head -n 1)
case "$profile" in
  interoperability | infrastructure | website | information-model) packs=(core) ;;
  *) packs=(core protocol) ;;
esac
echo "${packs[*]}" > "$out/opengrep.packs"

args=(scan --quiet --disable-version-check --no-git-ignore --x-ignore-semgrepignore-files --disable-nosem
  --timeout=30 --timeout-threshold=3 --json-output="$out/opengrep.json")
for pack in "${packs[@]}"; do
  # An empty directory would be a scan with no rules, and exit 0.
  if ! ls "$here/opengrep/rules/$pack"/*.yaml > /dev/null 2>&1; then
    echo "rule pack $pack has no rules" > "$out/opengrep.error"
    echo 2 > "$out/opengrep.exit"
    exit 0
  fi
  args+=(--config="$here/opengrep/rules/$pack")
done
IFS=',' read -r -a excludes <<<"$OPENGREP_EXCLUDE"
for e in "${excludes[@]}"; do
  args+=(--exclude="$e")
done
rc=0
"$OPENGREP_BIN" "${args[@]}" . > /dev/null 2> "$out/opengrep.error" || rc=$?
echo "$rc" > "$out/opengrep.exit"
[ "$rc" != 0 ] || rm -f "$out/opengrep.error"
exit 0
