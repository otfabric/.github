#!/usr/bin/env bash
# Scan the Go module in the current directory: run-gosec.sh <out dir>
# Records gosec.json and gosec.exit, and always exits 0: sast_gate.py decides
# what a failed or partial scan means. `go list` names the packages, so nested
# modules, testdata and hidden directories stay out, as in every other go-ci job.
# Comments cannot waive a finding (-nosec): .otfabric/sast-baseline.json does.
set -uo pipefail
out=$1
: "${GOSEC_BIN:=gosec}"
rm -f "$out/gosec.json" "$out/gosec.exit"

if [ ! -f go.mod ]; then
  echo "no go.mod in $PWD" > "$out/gosec.error"
  echo 2 > "$out/gosec.exit"
  exit 0
fi

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
