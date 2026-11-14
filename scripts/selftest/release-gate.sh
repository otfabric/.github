#!/usr/bin/env bash
# Cases of the release gate of go-package-release.yml (otfabric/engineering
# ADR-0017, REL-003): previous-version resolution, API compatibility with the
# pinned gorelease, the v0 rules and the release evidence. The exact step
# scripts run, in workflow order, on fixture repositories whose "published"
# versions live in a file:// module proxy. Nothing is pushed; fixture tags
# exist only in temporary repositories.
#
# Needs the pinned gorelease (the workflow's gorelease-version default) as
# $GORELEASE or on PATH, and a Go toolchain that runs it.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
wf="$root/.github/workflows/go-package-release.yml"
sel="$root/scripts/selftest"
work=$(mktemp -d)
cleanup() { chmod -R u+w "$work" 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT

pin=$(awk '/^      gorelease-version:/ { f = 1 } f && $1 == "default:" { print $2; exit }' "$wf")
GORELEASE=${GORELEASE:-$(command -v gorelease || true)}
if [ -z "$GORELEASE" ] || [ ! -x "$GORELEASE" ]; then
  echo "FAIL no gorelease: install golang.org/x/exp/cmd/gorelease@$pin and set GORELEASE"
  exit 1
fi
GORELEASE="$(cd "$(dirname "$GORELEASE")" && pwd)/$(basename "$GORELEASE")"
have=$(go version -m "$GORELEASE" | awk '$1 == "mod" && $2 == "golang.org/x/exp" { print $3 }')
[ "$have" = "$pin" ] || { echo "FAIL $GORELEASE is golang.org/x/exp@$have; the workflow pins $pin"; exit 1; }

steps="$work/steps"
mkdir -p "$steps"
for s in "Resolve module" "Determine next version" "Fail if tag already exists" "API compatibility" \
  "Generate release notes" "Check v0 breaking notes" "Write release evidence"; do
  python3 "$sel/extract-step.py" "$wf" "$s" > "$steps/$s.sh"
done

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=selftest GIT_AUTHOR_EMAIL=selftest@example.invalid
export GIT_COMMITTER_NAME=selftest GIT_COMMITTER_EMAIL=selftest@example.invalid
export GOPROXY="file://$work/proxy" GOSUMDB=off GOPRIVATE= GONOPROXY= GONOSUMDB= GOFLAGS= GOWORK=off
export GOTOOLCHAIN=local GOMODCACHE="$work/modcache"
goroot=$(go env GOROOT)
govers=$(go env GOVERSION)

API_F='package fx

// F is part of the API.
func F() int { return 1 }'
API_SAME='package fx

// F is part of the API.
func F() int { return 2 }'
API_ADD='package fx

// F is part of the API.
func F() int { return 1 }

// G is new.
func G() int { return 2 }'
API_BREAK='package fx

// F is part of the API.
func F(x int) int { return x }'

n=0
newrepo() { # sets repo and mp (a module path no other case uses)
  n=$((n + 1))
  repo="$work/r$n"
  mp="example.com/c$n"
  mkdir -p "$repo"
  git -C "$repo" init -q -b main
}
src() { # dir module-path source
  mkdir -p "$repo/$1"
  printf 'module %s\n\ngo 1.23\n' "$2" > "$repo/$1/go.mod"
  printf '%s\n' "$3" > "$repo/$1/fx.go"
}
commit() { git -C "$repo" add -A && git -C "$repo" commit -q -m "$1"; }
tag() { git -C "$repo" tag -a "$1" -m "$1" "${2:-HEAD}"; }
publish() { python3 "$sel/modproxy.py" "$work/proxy" "$repo" "$1" "${2:-.}" "$3" > /dev/null; } # ref dir version

run() { # step cwd env...
  local step=$1 dir=$2
  shift 2
  : > "$out/$step.out"
  echo "## $step" >> "$out/log"
  (cd "$dir" && env "$@" GITHUB_OUTPUT="$out/$step.out" GITHUB_STEP_SUMMARY="$out/summary.md" \
    bash --noprofile --norc -eo pipefail "$steps/$step.sh") >> "$out/log" 2>&1
}
o() { # step key: an output of a step that ran
  [ -f "$out/$1.out" ] || return 0
  sed -n "s/^$2=//p" "$out/$1.out" | tail -1
}

tool=""
api_env=()
gate() { # case module-dir bump mode: the release job's steps, in its order
  local name=$1 dir=$2 bump=$3 mode=$4 mdir
  out="$work/out/$name"
  mkdir -p "$out/tmp"
  : > "$out/log"
  export RUNNER_TEMP="$out/tmp"
  stop=none
  if ! run "Resolve module" "$repo" MODULE_DIR="$dir" GORELEASE_GO=1.26; then
    stop=module
    return
  fi
  mdir=$(o "Resolve module" dir)
  if ! run "Determine next version" "$repo" BUMP="$bump" MODULE_DIR="$mdir" \
    MODULE_PATH="$(o "Resolve module" path)" PREFIX="$(o "Resolve module" prefix)" \
    PATH_MAJOR="$(o "Resolve module" path_major)" SHA="$(git -C "$repo" rev-parse HEAD)"; then
    stop=version
    return
  fi
  if ! run "Fail if tag already exists" "$repo/$mdir" TAG="$(o "Determine next version" tag)"; then
    stop=tagcheck
  elif ! run "API compatibility" "$repo/$mdir" MODE="$mode" BUMP="$bump" \
    BASE="$(o "Determine next version" base)" BASE_MAJOR="$(o "Determine next version" base_major)" \
    VERSION="$(o "Determine next version" version_tag)" GORELEASE="${tool:-$GORELEASE}" \
    GORELEASE_GOROOT="$goroot" "${api_env[@]+"${api_env[@]}"}"; then
    stop=api
  elif ! run "Generate release notes" "$repo/$mdir" PREV_TAG="$(o "Determine next version" previous_tag)" \
    TAG="$(o "Determine next version" version_tag)"; then
    stop=notes
  elif [ "$(o "API compatibility" v0_breaking)" = true ] &&
    ! run "Check v0 breaking notes" "$repo/$mdir" MODE="$mode" VERSION="$(o "Determine next version" version_tag)" \
      NOTES_FILE="$(o "Generate release notes" file)" USED_RELEASE_MD="$(o "Generate release notes" used_release_md)"; then
    stop=v0notes
  fi
  # The evidence step runs whenever the version was resolved, also after a
  # gate failure.
  run "Write release evidence" "$repo/$mdir" GITHUB_WORKSPACE="$repo" REPOSITORY=otfabric/selftest \
    SHA="$(git -C "$repo" rev-parse HEAD)" RUN_URL=https://example.invalid/run WORKFLOW_REF=selftest \
    MODULE_PATH="$(o "Resolve module" path)" MODULE_DIR="$mdir" PREFIX="$(o "Resolve module" prefix)" \
    BUMP="$bump" BASE="$(o "Determine next version" base)" PREV_TAG="$(o "Determine next version" previous_tag)" \
    VERSION="$(o "Determine next version" version_tag)" TAG="$(o "Determine next version" tag)" MODE="$mode" \
    API_RESULT="$(o "API compatibility" result)" API_EXIT="$(o "API compatibility" exit_code)" \
    API_REPORT="$(o "API compatibility" report)" API_OUTCOME="$([ "$stop" = api ] && echo failure || echo success)" \
    V0_BREAKING="$(o "API compatibility" v0_breaking)" V0_DOCUMENTED="$(o "Check v0 breaking notes" documented)" \
    GORELEASE_VERSION="$pin" GORELEASE_GO="$govers" TEST_PACKAGES="$(o "Resolve module" path)" \
    VET_OUTCOME=success TEST_OUTCOME=success RACE_OUTCOME=success \
    TAG_EXISTS_OUTCOME="$([ "$stop" = tagcheck ] && echo failure || echo success)" \
    CONSUMERS_RESULT=skipped NOTES_FROM_RELEASE_MD="$(o "Generate release notes" used_release_md)" ||
    { echo "evidence step failed" >> "$out/log"; stop="$stop+evidence"; }
}

fail=0
expect() { # case want-stop want-api-result want-tag [want-base]
  local api tag base
  api=$(o "API compatibility" result)
  tag=$(o "Determine next version" tag)
  base=$(o "Determine next version" base)
  if [ "$stop" = "$2" ] && [ "$api" = "$3" ] && [ "$tag" = "$4" ] && { [ $# -lt 5 ] || [ "$base" = "$5" ]; }; then
    echo "ok   $1: stops at $stop, api '$api', tag '$tag'${5:+, base $base}"
  else
    echo "FAIL $1: stops at $stop, api '$api', tag '$tag', base '$base'; want $2, '$3', '$4'${5:+, base $5}"
    sed 's/^/    | /' "$out/log"
    fail=1
  fi
}
logged() { # case text: the run's log says text
  if grep -qF -- "$2" "$out/log"; then
    echo "ok   $1: log has '$2'"
  else
    echo "FAIL $1: log lacks '$2'"
    sed 's/^/    | /' "$out/log"
    fail=1
  fi
}
evidence() { # case python-expression over e (the evidence JSON) and head
  local f="$out/tmp/release-evidence.json"
  if [ -f "$f" ] && python3 -c '
import json, sys
e = json.load(open(sys.argv[1])); head = sys.argv[2]
sys.exit(0 if eval(sys.argv[3]) else 1)' "$f" "$(git -C "$repo" rev-parse HEAD)" "$2"; then
    echo "ok   $1: evidence $2"
  else
    echo "FAIL $1: evidence $2"
    [ -f "$f" ] && sed 's/^/    | /' "$f"
    fail=1
  fi
}
v1base() { # a published v1.0.0 with API_F, then the candidate source
  newrepo
  src . "$mp" "$API_F"
  commit base
  tag v1.0.0
  publish v1.0.0 . v1.0.0
  src . "$mp" "$1"
  commit candidate
}
v0base() {
  newrepo
  src . "$mp" "$API_F"
  commit base
  tag v0.1.0
  publish v0.1.0 . v0.1.0
  src . "$mp" "$1"
  commit candidate
}

# --- v1: gorelease decides --------------------------------------------------
v1base "$API_SAME"
gate identical-patch . patch enforce
expect identical-patch none pass v1.0.1 v1.0.0
evidence identical-patch 'e["commit"] == head and e["module"]["path"].startswith("example.com/") and e["previous_version"] == "v1.0.0" and e["proposed_version"] == "v1.0.1" and e["api_compatibility"]["result"] == "pass" and e["tests"]["race"] == "pass" and e["consumers"]["requested"] is False and "coverage" in e["not_run"] and "govulncheck" in e["not_run"]'

v1base "$API_ADD"
gate additive-patch . patch enforce
expect additive-patch api incompatible v1.0.1
logged additive-patch "No tag was created."
evidence additive-patch 'e["api_compatibility"]["result"] == "incompatible" and any("G" in c for c in e["api_compatibility"]["changes"]["compatible"])'

v1base "$API_ADD"
gate additive-minor . minor enforce
expect additive-minor none pass v1.1.0

v1base "$API_BREAK"
gate incompatible-patch . patch enforce
expect incompatible-patch api incompatible v1.0.1

v1base "$API_BREAK"
gate incompatible-minor . minor enforce
expect incompatible-minor api incompatible v1.1.0
evidence incompatible-minor 'e["api_compatibility"]["changes"]["incompatible"] and e["api_compatibility"]["exit_code"] == 1'

v1base "$API_BREAK"
gate incompatible-major-same-path . major enforce
expect incompatible-major-same-path version "" ""
logged incompatible-major-same-path "needs the module path to end in /v2"

v1base "$API_BREAK"
gate report-mode . minor report
expect report-mode none incompatible v1.1.0
logged report-mode "::warning::gorelease rejects v1.1.0 against v1.0.0"

# --- v0: ADR-0017 rules on top of gorelease's report ------------------------
v0base "$API_SAME"
gate v0-identical-patch . patch enforce
expect v0-identical-patch none pass v0.1.1

v0base "$API_ADD"
gate v0-additive-patch . patch enforce
expect v0-additive-patch api incompatible v0.1.1
logged v0-additive-patch "a v0 patch must not change the exported API"

v0base "$API_ADD"
gate v0-additive-minor . minor enforce
expect v0-additive-minor none pass v0.2.0

v0base "$API_BREAK"
gate v0-breaking-undocumented . minor enforce
expect v0-breaking-undocumented v0notes pass v0.2.0
logged v0-breaking-undocumented "needs a '### Breaking' heading"
evidence v0-breaking-undocumented 'e["api_compatibility"]["v0_breaking"] is True and e["api_compatibility"]["v0_breaking_documented"] is False'

v0base "$API_BREAK"
printf '## v0.2.0\n\n### Breaking\n\n- F takes x; callers pass 1.\n\n---\n' > "$repo/RELEASE.md"
commit notes
gate v0-breaking-documented . minor enforce
expect v0-breaking-documented none pass v0.2.0
evidence v0-breaking-documented 'e["api_compatibility"]["v0_breaking_documented"] is True and e["release_notes"]["source"] == "RELEASE.md"'

v0base "$API_BREAK"
printf '## v1.0.0\n\n### Breaking\n\n- F takes x.\n\n---\n' > "$repo/RELEASE.md"
commit notes
gate v0-to-v1 . major enforce
expect v0-to-v1 none pass v1.0.0 v0.1.0

# --- first releases and majors -----------------------------------------------
newrepo
src . "$mp" "$API_F"
commit first
gate first-release . minor enforce
expect first-release none pass v0.1.0 none
evidence first-release 'e["previous_version"] is None and e["api_compatibility"]["base"] == "none"'

newrepo
src . "$mp" "$API_F"
commit base
tag v1.0.0
publish v1.0.0 . v1.0.0
src . "$mp/v2" "$API_BREAK"
commit v2
gate first-v2 . major enforce
expect first-v2 none pass v2.0.0 none

newrepo
src . "$mp/v2" "$API_F"
commit base
tag v2.0.0
publish v2.0.0 . v2.0.0
tag v1.9.0
tag v3.0.0
src . "$mp/v2" "$API_ADD"
commit candidate
gate v2-minor-ignores-other-majors . minor enforce
expect v2-minor-ignores-other-majors none pass v2.1.0 v2.0.0

v1base "$API_ADD"
tag v1.1.0-rc.1
tag v1
tag v1.1
gate prerelease-and-moving-tags . minor enforce
expect prerelease-and-moving-tags none pass v1.1.0 v1.0.0

newrepo
src . "$mp" "$API_F"
commit base
tag v1.9.0
publish v1.9.0 . v1.9.0
src . "$mp" "$API_ADD"
commit v1.10
tag v1.10.0
publish v1.10.0 . v1.10.0
src . "$mp" "$API_ADD"
printf '\n// H is new.\nfunc H() int { return 3 }\n' >> "$repo/fx.go"
commit candidate
gate semver-order . minor enforce
expect semver-order none pass v1.11.0 v1.10.0

# --- a wrong base stops the release; it is never replaced --------------------
v1base "$API_SAME"
git -C "$repo" checkout -q -b side HEAD~1
src . "$mp" "$API_ADD"
commit side
tag v1.1.0
publish v1.1.0 . v1.1.0
git -C "$repo" checkout -q main
gate base-not-ancestor . patch enforce
expect base-not-ancestor version "" ""
logged base-not-ancestor "v1.1.0 is not an ancestor"

newrepo
src . example.com/other "$API_F"
commit base
tag v1.0.0
src . "$mp" "$API_SAME"
commit candidate
gate base-other-module . patch enforce
expect base-other-module version "" ""
logged base-other-module "Refusing to compare with another module"

newrepo
src . "$mp" "$API_F"
commit base
tag v1.0.0
src . "$mp" "$API_SAME"
commit candidate
gate base-unpublished . patch enforce
expect base-unpublished api error v1.0.1 v1.0.0
evidence base-unpublished 'e["api_compatibility"]["result"] == "error" and e["previous_version"] == "v1.0.0"'

# --- nested modules ------------------------------------------------------------
newrepo
src . "$mp" "$API_F"
src sub "$mp/sub" "$API_F"
commit base
tag v1.0.0
tag sub/v0.1.0
publish sub/v0.1.0 sub v0.1.0
tag v1.1.0
src sub "$mp/sub" "$API_ADD"
commit candidate
gate nested sub minor enforce
expect nested none pass sub/v0.2.0 v0.1.0
evidence nested 'e["tag"] == "sub/v0.2.0" and e["module"]["dir"] == "sub" and e["previous_tag"] == "sub/v0.1.0"'

newrepo
src . "$mp" "$API_F"
src tools/sub "$mp/tools/sub" "$API_F"
commit base
tag v1.0.0
gate nested-first ./tools/sub/ patch enforce
expect nested-first none pass tools/sub/v0.0.1 none

newrepo
src . "$mp" "$API_F"
commit base
gate module-dir-escape ../x patch enforce
expect module-dir-escape module "" ""

# --- the tool, not the API -------------------------------------------------------
v1base "$API_SAME"
tool="$work/no-such-gorelease"
gate missing-tool . patch enforce
tool=""
expect missing-tool api error v1.0.1
logged missing-tool "gorelease did not reach a result (exit 127)"

v1base "$API_SAME"
api_env=(GOPROXY=off)
gate tool-failure . patch enforce
expect tool-failure api error v1.0.1
logged tool-failure "module lookup disabled by GOPROXY=off"

v1base "$API_SAME"
gate tool-failure-report . patch report
api_env=()
expect tool-failure-report none error v1.0.1
logged tool-failure-report "::warning::gorelease did not reach a result"

v1base "$API_SAME"
gate invalid-mode . patch warn
expect invalid-mode api "" v1.0.1

v1base "$API_SAME"
gate invalid-bump . huge enforce
expect invalid-bump version "" ""

# --- the job: the gate runs before anything is tagged or published -------------
if python3 - "$wf" <<'EOF'; then
import re, sys
text = open(sys.argv[1]).read()
problems = []
if "@latest" in text:
    problems.append("the workflow installs something @latest")
job = text.split("\n  release-package:\n", 1)[1]
names = re.findall(r"^      - name: (.+)$", job, re.M)
blocks = re.split(r"^      - name: .+$", job, flags=re.M)[1:]
step_if = {n: (re.search(r"^        if: (.+)$", b, re.M) or [None, ""])[1] for n, b in zip(names, blocks)}
coe = {n for n, b in zip(names, blocks) if re.search(r"^        continue-on-error:", b, re.M)}
order = ["Determine next version", "Fail if tag already exists", "API compatibility", "Check v0 breaking notes",
         "Create and push annotated tag", "Update moving major tag", "Create GitHub release"]
idx = [names.index(s) for s in order]
if idx != sorted(idx):
    problems.append(f"step order {order} is not kept: {idx}")
for s in order[:4]:
    if s in coe:
        problems.append(f"{s} has continue-on-error")
for s in order[4:]:
    if re.search(r"always\(\)|failure\(\)|cancelled\(\)", step_if[s]):
        problems.append(f"{s} runs after a failed step ({step_if[s]})")
head = job.split("\n    steps:\n", 1)[0]
gate_if = "    if: ${{ !cancelled() && (needs.consumers.result == 'success' || needs.consumers.result == 'skipped') }}"
if "\n    needs: consumers\n" not in head or gate_if not in head.split("\n"):
    problems.append("release-package does not wait for, or ignores, the consumer job")
if not re.search(r"^      gorelease-version:\n(?:        .*\n)*?        default: v\d+\.\d+\.\d+-\d{14}-[0-9a-f]{12}$", text, re.M):
    problems.append("gorelease-version default is not an exact pseudo-version")
for p in problems:
    print("FAIL job:", p)
sys.exit(1 if problems else 0)
EOF
  echo "ok   job: gate and v0 check run before the tag, the tag steps never run after a failure, consumers gate the job, gorelease pinned"
else
  fail=1
fi
exit $fail
