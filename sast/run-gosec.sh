#!/usr/bin/env bash
# Scan the Go module in the current directory: run-gosec.sh <out dir>
# Records gosec.json and gosec.exit, and always exits 0: sast_gate.py decides
# what a failed or partial scan means. `go list` names the packages, so nested
# modules, testdata and hidden directories stay out, as in every other go-ci job;
# gosec.nested lists the nested modules, which need their own go-ci call.
# Comments cannot waive a finding (-nosec): .otfabric/sast-baseline.json does.
set -uo pipefail
out=$1
: "${GOSEC_BIN:=gosec}"
rm -f "$out/gosec.json" "$out/gosec.exit" "$out/gosec.not-applicable" "$out/gosec.nested"

if [ ! -f go.mod ]; then
  # Only a tree with no Go at all is not applicable. Go code with no module here
  # is a wrong module-dir, and skipping it would look like a clean scan.
  if [ -n "$(find . -name '*.go' -not -path '*/testdata/*' -not -path '*/vendor/*' -not -path '*/.*' -print -quit)" ]; then
    echo "Go code but no go.mod in $PWD: set module-dir" > "$out/gosec.error"
    echo 2 > "$out/gosec.exit"
    exit 0
  fi
  echo "no Go code" > "$out/gosec.not-applicable"
  exit 0
fi

find . -mindepth 2 -name go.mod -not -path '*/testdata/*' -not -path '*/vendor/*' -not -path '*/.*' |
  sed -e 's|^\./||' -e 's|/go\.mod$||' | sort > "$out/gosec.nested"
export GOPROXY=off GOFLAGS=-mod=readonly CGO_ENABLED=0 GOWORK=off
if ! go list -f '{{.Dir}}' ./... > "$out/gosec.packages" 2> "$out/gosec.error"; then
  echo 2 > "$out/gosec.exit"
  exit 0
fi
mapfile -t pkgs < "$out/gosec.packages"
rc=0
# Not -quiet: with it, a clean scan writes no report at all.
"$GOSEC_BIN" -log "$out/gosec.log" -nosec -no-fail -exclude-generated -fmt json -out "$out/gosec.json" "${pkgs[@]}" > /dev/null 2>> "$out/gosec.error" || rc=$?
echo "$rc" > "$out/gosec.exit"
[ "$rc" != 0 ] || rm -f "$out/gosec.error"
exit 0
