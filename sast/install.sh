#!/usr/bin/env bash
# Install a pinned scanner into <dir>: install.sh gosec|opengrep <dir>
# go install checks gosec against the Go checksum database; opengrep is checked
# against the SHA-256 in versions.env, and git checks the rule commit by its id.
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
  GOBIN="$dir" GOWORK=off GOFLAGS= GOPRIVATE= GONOSUMDB= GOPROXY=https://proxy.golang.org \
    go install "${GOSEC_MODULE}@${GOSEC_VERSION}"
  ;;
opengrep)
  curl --fail --silent --show-error --location --retry 3 \
    --output "$dir/opengrep" \
    "https://github.com/opengrep/opengrep/releases/download/${OPENGREP_VERSION}/${OPENGREP_ASSET}"
  echo "${OPENGREP_SHA256}  $dir/opengrep" | sha256sum --check --quiet
  chmod +x "$dir/opengrep"
  git init --quiet "$dir/rules"
  git -C "$dir/rules" fetch --quiet --depth 1 "$OPENGREP_RULES_REPO" "$OPENGREP_RULES_SHA"
  git -C "$dir/rules" -c advice.detachedHead=false checkout --quiet FETCH_HEAD
  ;;
*)
  echo "install.sh: unknown tool $tool" >&2
  exit 2
  ;;
esac
