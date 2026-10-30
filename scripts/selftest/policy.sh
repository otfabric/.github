#!/usr/bin/env bash
# Run the policy steps of go-ci.yml on the fixtures, with go stubbed: the real
# checker needs OTFABRIC_READ_TOKEN, and this has to pass on fork pull requests.
# The scripts are taken from the workflow, not copied.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
wf=.github/workflows/go-ci.yml
python3 scripts/selftest/extract-step.py "$wf" "Decide whether the policy check runs" > "$tmp/gate.sh"
python3 scripts/selftest/extract-step.py "$wf" "otfabric-policy" > "$tmp/check.sh"

# gate <dir> <want exit> <want run output> VAR=value...
gate() {
  local dir=$1 want_exit=$2 want_run=$3 got=0
  shift 3
  : > "$tmp/out"
  (cd "$dir" && env EVENT=push HEAD_REPO= REPO=otfabric/x ACTOR=someone TOKEN= \
    GITHUB_OUTPUT="$tmp/out" "$@" bash "$tmp/gate.sh") > "$tmp/log" || got=$?
  [ "$got" = "$want_exit" ] || { echo "gate $*: exit $got, want $want_exit"; cat "$tmp/log"; exit 1; }
  [ "$(cat "$tmp/out")" = "$want_run" ] || { echo "gate $*: output '$(cat "$tmp/out")', want '$want_run'"; exit 1; }
}

repo=testdata/go-ci/policy
fork=(EVENT=pull_request HEAD_REPO=someone/x)
same=(EVENT=pull_request HEAD_REPO=otfabric/x)

gate testdata/go-ci/lowcov 0 run=false
gate testdata/go-ci/lowcov 0 run=false TOKEN=t
gate "$repo" 0 run=true TOKEN=t
gate "$repo" 0 run=true TOKEN=t "${same[@]}"
gate "$repo" 0 run=false "${fork[@]}"
gate "$repo" 0 run=false "${fork[@]}" TOKEN=t
gate "$repo" 0 run=false ACTOR='dependabot[bot]'
gate "$repo" 0 run=true ACTOR='dependabot[bot]' TOKEN=t
gate "$repo" 1 ""
grep -q '::error::OTFABRIC_READ_TOKEN' "$tmp/log"
gate "$repo" 1 "" "${same[@]}"
echo "policy gate: all cases match"

# The stub reports like the checker, and exits with STUB_EXIT.
mkdir "$tmp/bin"
cat > "$tmp/bin/go" <<'STUB'
#!/usr/bin/env bash
echo "pwd=$PWD args=$* GOWORK=$GOWORK GOPRIVATE=$GOPRIVATE"
exit "$STUB_EXIT"
STUB
chmod +x "$tmp/bin/go"

# check <want exit> <stub exit>
check() {
  local got=0
  : > "$tmp/summary"
  (cd "$repo" && env PATH="$tmp/bin:$PATH" STUB_EXIT="$2" VERSION=v9.9.9 GOWORK=off \
    GOPRIVATE=github.com/otfabric/engineering GITHUB_STEP_SUMMARY="$tmp/summary" \
    bash "$tmp/check.sh") > /dev/null || got=$?
  [ "$got" = "$1" ] || { echo "check: exit $got, want $1"; exit 1; }
  want="pwd=$root/$repo args=run github.com/otfabric/engineering/cmd/otfabric-policy@v9.9.9 check -format markdown . GOWORK=off GOPRIVATE=github.com/otfabric/engineering"
  [ "$(cat "$tmp/summary")" = "$want" ] || { echo "summary: $(cat "$tmp/summary")"; exit 1; }
}

check 0 0
check 1 1
check 3 3
echo "policy check: exit code and summary match"
