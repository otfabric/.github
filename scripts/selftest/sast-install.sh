#!/usr/bin/env bash
# install.sh on a copy of the bundle with wrong pins: each must fail and leave
# no scanner behind. Needs the network, like the real install.
set -uo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# bad <what> <tool> <sed expression on versions.env>
bad() {
  local copy=$tmp/$1
  mkdir -p "$copy"
  cp -R sast "$copy/sast"
  sed -i.bak "$3" "$copy/sast/versions.env"
  if bash "$copy/sast/install.sh" "$2" "$copy/tools" > "$copy/log" 2>&1; then
    cat "$copy/log"
    echo "FAIL: $1: the install passed"
    exit 1
  fi
  [ ! -x "$copy/tools/$2" ] || { echo "FAIL: $1: left a scanner behind"; exit 1; }
}

bad opengrep-digest opengrep 's/^OPENGREP_SHA256=.*/OPENGREP_SHA256=0000000000000000000000000000000000000000000000000000000000000000/'
bad opengrep-version opengrep 's/^OPENGREP_VERSION=.*/OPENGREP_VERSION=v0.0.0-missing/'
bad gosec-version gosec 's/^GOSEC_VERSION=.*/GOSEC_VERSION=v2.0.0-missing/'
if bash sast/install.sh nonsense "$tmp/x" > /dev/null 2>&1; then
  echo "FAIL: an unknown tool installed"
  exit 1
fi
echo "failed installs fail"
