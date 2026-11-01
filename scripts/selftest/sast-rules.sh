#!/usr/bin/env bash
# Every rule against its fixtures, and the rule set against its recorded
# version: sast-rules.sh <opengrep>
set -euo pipefail
cd "$(dirname "$0")/../.."
opengrep=$1
for pack in sast/opengrep/rules/*/; do
  "$opengrep" test "$pack"
done
for y in sast/opengrep/rules/*/*.yaml; do
  case "$y" in *.test.yaml) continue ;; esac
  stem=${y%.yaml}
  grep -q 'ruleid:' "$stem".[!y]* || { echo "$y has no vulnerable fixture"; exit 1; }
  grep -q 'ok:' "$stem".[!y]* || { echo "$y has no safe fixture"; exit 1; }
  grep -q 'id: otfabric-' "$y" || { echo "$y: rule ids start with otfabric-"; exit 1; }
  grep -Eq 'confidence: (HIGH|MEDIUM|LOW)' "$y" || { echo "$y has no confidence"; exit 1; }
done
# shellcheck source=sast/versions.env
. sast/versions.env
digest=$(python3 sast/sast_gate.py rules-digest --bundle .)
[ "$digest" = "$OPENGREP_RULESET_SHA256" ] || { echo "rules changed: bump the version, add to CHANGELOG.md, digest $digest"; exit 1; }
grep -q "^## $OPENGREP_RULESET_VERSION\$" sast/opengrep/CHANGELOG.md || { echo "no changelog for $OPENGREP_RULESET_VERSION"; exit 1; }
echo "rule set $OPENGREP_RULESET_VERSION: fixtures present and passing, digest recorded"
