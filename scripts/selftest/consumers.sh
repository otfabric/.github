#!/usr/bin/env bash
# Cases of the consumers job of go-package-release.yml: each consumer is
# cloned, pointed at the candidate with a temporary replace, and built, vetted
# and tested; a failure names the consumer, its revision and the error. The
# exact step scripts run on fixture repositories cloned over file://, offline.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
wf="$root/.github/workflows/go-package-release.yml"
sel="$root/scripts/selftest"
work=$(mktemp -d)
cleanup() { chmod -R u+w "$work" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

for s in "Fetch consumers" "Build and test consumers"; do
  python3 "$sel/extract-step.py" "$wf" "$s" > "$work/$s.sh"
done

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
export GOPROXY=off GOSUMDB=off GOFLAGS= GOWORK=off GOTOOLCHAIN=local GOMODCACHE="$work/modcache"

# The candidate: F changed signature (a break), G added.
cand="$work/candidate"
mkdir -p "$cand"
printf 'module example.com/lib\n\ngo 1.23\n' > "$cand/go.mod"
printf 'package lib\n\nfunc F(x int) int { return x }\n\nfunc G() int { return 2 }\n' > "$cand/lib.go"

remote() { # owner/repo dir go-source [module-path-required]
  local r="$work/remotes/$1"
  mkdir -p "$r/$2"
  git -C "$r" init -q -b main 2> /dev/null || true
  {
    printf 'module example.com/%s\n\ngo 1.23\n' "$(basename "$1")"
    [ -z "${4:-}" ] || printf '\nrequire (\n\t%s v1.0.0\n)\n' "$4"
  } > "$r/$2/go.mod"
  printf '%s\n' "$3" > "$r/$2/main.go"
  git -C "$r" add -A && git -C "$r" commit -q -m fixture
}
remote otfabric/good . 'package main

import "example.com/lib"

func main() { println(lib.G()) }' example.com/lib
remote otfabric/broken . 'package main

import "example.com/lib"

func main() { println(lib.F()) }' example.com/lib
remote otfabric/mono tools 'package main

import "example.com/lib"

func main() { println(lib.F(1)) }' example.com/lib
remote otfabric/unrelated . 'package main

func main() {}'
git -C "$work/remotes/otfabric/good" rev-parse HEAD > "$work/good.rev"
git -C "$work/remotes/otfabric/broken" rev-parse HEAD > "$work/broken.rev"

fail=0
consumers() { # case consumer-list -> fetch-exit build-exit; results in $res
  local out="$work/out/$1"
  mkdir -p "$out/tmp"
  res="$out/tmp/consumer-results.jsonl"
  fetch=0 build=0
  (env RUNNER_TEMP="$out/tmp" TOKEN= CONSUMERS="$2" MODULE_DIR=. CANDIDATE="$cand" \
    CONSUMER_BASE_URL="file://$work/remotes" bash --noprofile --norc -eo pipefail "$work/Fetch consumers.sh") \
    > "$out/log" 2>&1 || fetch=$?
  if [ "$fetch" = 0 ]; then
    (env RUNNER_TEMP="$out/tmp" CANDIDATE_SHA=0123456789abcdef GITHUB_STEP_SUMMARY="$out/summary.md" \
      bash --noprofile --norc -eo pipefail "$work/Build and test consumers.sh") >> "$out/log" 2>&1 || build=$?
  fi
  log="$out/log"
}
check() { # case description python-expression over rows (results), log
  if python3 -c '
import json, os, sys
f, log = sys.argv[1], open(sys.argv[2]).read()
rows = {r["repository"]: r for r in map(json.loads, open(f))} if os.path.exists(f) else {}
good, broken = open(sys.argv[4]).read().strip(), open(sys.argv[5]).read().strip()
sys.exit(0 if eval(sys.argv[3]) else 1)' "$res" "$log" "$3" "$work/good.rev" "$work/broken.rev"; then
    echo "ok   $1: $2"
  else
    echo "FAIL $1: $2"
    sed 's/^/    | /' "$log"
    [ -f "$res" ] && sed 's/^/    | /' "$res"
    fail=1
  fi
}

consumers mixed 'otfabric/good
# a comment line
otfabric/broken
otfabric/mono:tools
otfabric/unrelated
otfabric/missing
../evil
otfabric/mono:../../x'
[ "$fetch" = 0 ] && [ "$build" = 1 ] && echo "ok   mixed: fetch passes, build step fails" ||
  { echo "FAIL mixed: fetch exit $fetch, build exit $build; want 0, 1"; sed 's/^/    | /' "$log"; fail=1; }
check mixed "good consumer passes at its revision" 'rows["otfabric/good"]["status"] == "pass" and rows["otfabric/good"]["revision"] == good and rows["otfabric/good"]["requires"] == "v1.0.0"'
check mixed "broken consumer: repository, revision, requirement and compile error" 'rows["otfabric/broken"]["status"] == "failed" and rows["otfabric/broken"]["revision"] == broken and rows["otfabric/broken"]["requires"] == "v1.0.0" and any("not enough arguments" in l for l in rows["otfabric/broken"]["log_tail"])'
check mixed "the error annotation names consumer and revision" '"::error::consumer otfabric/broken@" + broken in log and "requires example.com/lib v1.0.0" in log'
check mixed "consumer in a subdirectory" 'rows["otfabric/mono"]["status"] == "pass" and rows["otfabric/mono"]["dir"] == "tools"'
check mixed "a repository that does not require the module fails" 'rows["otfabric/unrelated"]["status"] == "does not require example.com/lib"'
check mixed "a clone failure is reported, not skipped" 'rows["otfabric/missing"]["status"] == "clone failed"'
check mixed "path escapes are refused" 'rows["../evil"]["status"] == "invalid entry" and rows["otfabric/mono:../../x"]["status"] == "invalid entry"'
check mixed "the replace stays in the temporary clone" 'b"replace" not in open(sys.argv[1].rsplit("/", 1)[0] + "/../../../remotes/otfabric/good/go.mod", "rb").read()'
check mixed "summary table lists every consumer" 'len([l for l in open(os.path.dirname(sys.argv[2]) + "/summary.md") if l.startswith("| ") and not l.startswith("| Consumer")]) == 7'
check mixed "every result names the candidate revision" 'all(r["candidate"] == "0123456789abcdef" for r in rows.values())'

consumers passing 'otfabric/good
otfabric/mono:tools'
[ "$fetch" = 0 ] && [ "$build" = 0 ] && echo "ok   passing: all consumers pass, the job passes" ||
  { echo "FAIL passing: fetch exit $fetch, build exit $build; want 0, 0"; sed 's/^/    | /' "$log"; fail=1; }

consumers empty '# nothing but a comment'
[ "$fetch" = 1 ] && echo "ok   empty: a consumers input without a consumer fails" ||
  { echo "FAIL empty: fetch exit $fetch; want 1"; sed 's/^/    | /' "$log"; fail=1; }

# The job: consumer code never runs with credentials or write access.
if python3 - "$wf" <<'EOF'; then
import re, sys
text = open(sys.argv[1]).read()
job = text.split("\n  consumers:\n", 1)[1].split("\n  release-package:\n", 1)[0]
problems = []
if not re.search(r"^    permissions:\n      contents: read$", job, re.M):
    problems.append("the job is not read-only")
if "persist-credentials: false" not in job:
    problems.append("the checkout keeps credentials")
if "git config --global" in job:
    problems.append("the job writes a global git config")
steps = dict(zip(re.findall(r"^      - name: (.+)$", job, re.M), re.split(r"^      - name: .+$", job, flags=re.M)[1:]))
with_secret = [n for n, b in steps.items() if "secrets." in b]
if with_secret != ["Fetch consumers"]:
    problems.append(f"secrets reach {with_secret}, want only Fetch consumers")
fetch = steps["Fetch consumers"]
if re.search(r"go (build|vet|test)\b", fetch):
    problems.append("Fetch consumers runs consumer code")
build = steps["Build and test consumers"]
for cmd in ("go build", "go vet", "go test"):
    if not re.search(r"GOPROXY=off GOFLAGS=-mod=mod " + cmd, build):
        problems.append(f"{cmd} is not offline")
for p in problems:
    print("FAIL job:", p)
sys.exit(1 if problems else 0)
EOF
  echo "ok   job: read-only, no persisted or global credentials, the token only in the fetch step, consumer code runs offline"
else
  fail=1
fi
exit $fail
