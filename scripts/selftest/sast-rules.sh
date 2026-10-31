#!/usr/bin/env bash
# Every rule of the catalog against its fixtures: sast-rules.sh <opengrep> <rules dir>
# Custom rules have their own in sast/opengrep/rules; each upstream rule is
# tested with the fixtures its own repository ships.
set -euo pipefail
cd "$(dirname "$0")/../.."
opengrep=$1
rules=$2
"$opengrep" test sast/opengrep/rules
for y in sast/opengrep/rules/*.yaml; do
  stem=${y%.yaml}
  ls "$stem".* | grep -qv '\.yaml$' || { echo "$y has no fixture"; exit 1; }
  grep -q 'ruleid:' "$stem".[!y]* || { echo "$y has no vulnerable fixture"; exit 1; }
  grep -q 'ok:' "$stem".[!y]* || { echo "$y has no safe fixture"; exit 1; }
done
while read -r path _; do
  case "$path" in '' | '#'*) continue ;; esac
  [ -f "$rules/$path" ] || { echo "upstream rule $path does not exist at the pinned commit"; exit 1; }
done < sast/opengrep/upstream.txt
echo "rule catalog: fixtures present and passing"
