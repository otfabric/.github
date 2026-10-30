#!/usr/bin/env bash
# Run the release-notes awk of the shared release workflows on the fixture and
# compare with golden output. The awk is taken from the workflows, not copied.
set -euo pipefail
cd "$(dirname "$0")/../.."
for wf in go-package-release go-binary-release; do
  program=$(sed -n "/awk -v target=\"## \${TAG}\" '/,/' RELEASE.md > \"\$out\"/p" ".github/workflows/$wf.yml" |
    sed -e '1d' -e '$d')
  [ -n "$program" ] || { echo "no release-notes awk in $wf.yml"; exit 1; }
  for tag in v2.0.0 v1.9.0 v1.8.0; do
    got=$(awk -v target="## $tag" "$program" testdata/release-notes/RELEASE.md)
    want=$(cat "testdata/release-notes/$tag.golden")
    [ "$got" = "$want" ] || { printf '%s %s: got\n%s\nwant\n%s\n' "$wf" "$tag" "$got" "$want"; exit 1; }
  done
  echo "$wf: release-notes extraction matches"
done
