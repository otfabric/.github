#!/usr/bin/env bash
# Cases of the docsync step of docs-check.yml, run on the fixtures with the
# exact step script. The reusable workflow cannot be called with
# continue-on-error, so the failing case runs here.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 "$root/scripts/selftest/extract-step.py" "$root/.github/workflows/docs-check.yml" docsync > "$work/step.sh"
version=$(sed -nE '/docsync-version:/,/default:/s/^ *default: "(v[^"]+)"$/\1/p' "$root/.github/workflows/docs-check.yml")
mkdir -p "$work/bin"
GOBIN="$work/bin" GOWORK=off go install "github.com/otfabric/docsync@${version}"

fail=0
check() { # fixture mode want
  local got=0
  (cd "$root/testdata/docs-check/$1" && RUNNER_TEMP="$work" GITHUB_STEP_SUMMARY="$work/summary" VERSION="$version" MODE="$2" GOWORK=off bash -e "$work/step.sh") > "$work/out" 2>&1 || got=$?
  if [ "$got" = "$3" ]; then
    echo "ok   $1 $2: exit $got"
  else
    echo "FAIL $1 $2: exit $got, want $3"; cat "$work/out"; fail=1
  fi
}

check pass enforce 0
check fail enforce 1
check fail warn 0
check pass bogus 2
grep -q '^::warning ' "$work/out" && { echo "FAIL a bad mode printed findings"; fail=1; }
exit "$fail"
