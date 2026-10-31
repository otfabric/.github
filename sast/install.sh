#!/usr/bin/env bash
# Install a pinned scanner into <dir>: install.sh gosec|opengrep <dir>
# go install checks gosec against the Go checksum database; opengrep is checked
# against the SHA-256 in versions.env. The rules are files of this bundle: CI
# downloads none. Any failure here fails the job.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=sast/versions.env
. "$here/versions.env"
tool=$1
dir=$2
mkdir -p "$dir"
dir=$(cd "$dir" && pwd)

case "$tool" in
gosec)
  # Away from the caller's module, so its go.mod cannot change what is built.
  cd "$dir"
  CGO_ENABLED=0 GOBIN="$dir" GOWORK=off GOFLAGS= GOPRIVATE= GONOSUMDB= GOPROXY=https://proxy.golang.org \
    go install "${GOSEC_MODULE}@${GOSEC_VERSION}"
  ;;
opengrep)
  curl --fail --silent --show-error --location --retry 3 \
    --output "$dir/opengrep.download" \
    "https://github.com/opengrep/opengrep/releases/download/${OPENGREP_VERSION}/${OPENGREP_ASSET}"
  echo "${OPENGREP_SHA256}  $dir/opengrep.download" | sha256sum --check --quiet
  chmod +x "$dir/opengrep.download"
  mv "$dir/opengrep.download" "$dir/opengrep"
  ;;
*)
  echo "install.sh: unknown tool $tool" >&2
  exit 2
  ;;
esac
