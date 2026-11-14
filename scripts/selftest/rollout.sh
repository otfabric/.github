#!/usr/bin/env bash
# Run scripts/rollout/pr-workflow.py on the fixtures in testdata/rollout: a
# repository it can prepare, one it must refuse, and one it prepares once a
# person has lifted a refusal. Dry runs write nothing, --write produces the
# PR workflow layout, a second run changes nothing.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
tool=(python3 -I scripts/rollout/pr-workflow.py)
cp -R testdata/rollout/ready testdata/rollout/manual testdata/rollout/assisted "$tmp/"
fail() { echo "FAIL $*"; exit 1; }

# Dry run: the plan and the new pr.yml, no file touched.
"${tool[@]}" apply "$tmp/ready" > "$tmp/dry" || fail "dry run exited non-zero"
grep -q "ready (protocol-library): ready" "$tmp/dry" || fail "dry run: not ready"
grep -q "code-paths (Go code reads these; check them): README.md" "$tmp/dry" || fail "dry run: README.md not suggested"
[ ! -e "$tmp/ready/.github/workflows/pr.yml" ] || fail "dry run wrote pr.yml"
diff -r testdata/rollout/ready "$tmp/ready" > /dev/null || fail "dry run changed a file"
echo "ok   dry run writes nothing"

"${tool[@]}" apply "$tmp/ready" --ref v9.9.9 --write > /dev/null
wf="$tmp/ready/.github/workflows"
on() { awk '/^on:/{p=1;next} p&&/^[^ #]/{p=0} p' "$wf/$1" | tr -d ' ' | grep -v '^$' | paste -sd, -; }
[ "$(on ci.yml)" = "workflow_call:,workflow_dispatch:" ] || fail "ci.yml on: $(on ci.yml)"
[ "$(on interop.yml)" = "workflow_call:,workflow_dispatch:" ] || fail "interop.yml on: $(on interop.yml)"
[ "$(on docs.yml)" = "push:,branches:[main],workflow_call:,workflow_dispatch:" ] || fail "docs.yml on: $(on docs.yml)"
cmp -s testdata/rollout/ready/.github/workflows/nightly.yml "$wf/nightly.yml" || fail "nightly.yml changed"
strip_on() { awk '/^on:/{p=1;next} p&&/^[^ #]/{p=0} !p' "$1"; }
for f in ci.yml interop.yml docs.yml; do
  diff <(strip_on "testdata/rollout/ready/.github/workflows/$f") <(strip_on "$wf/$f") > /dev/null \
    || fail "$f: more than the on: block changed"
done
echo "ok   triggers rewritten, jobs and nightly untouched"

pr="$wf/pr.yml"
grep -qx "  pull_request:" "$pr" || fail "pr.yml: no pull_request trigger"
if grep -qE "^ +paths(-ignore)?:" "$pr"; then fail "pr.yml has a path filter"; fi
grep -qx "    name: OT Fabric Required Checks" "$pr" || fail "pr.yml: gate name"
grep -qx "    needs: \[changes, docs, ci, interop\]" "$pr" || fail "pr.yml: gate needs: $(grep -m1 'needs: \[' "$pr")"
grep -qx "    if: always()" "$pr" || fail "pr.yml: gate condition"
grep -qx "          required: changes docs" "$pr" || fail "pr.yml: required"
grep -qx "          required-for-code: ci interop" "$pr" || fail "pr.yml: required-for-code"
grep -q "pr-changes.yml@v9.9.9" "$pr" && grep -q "required-gate@v9.9.9" "$pr" || fail "pr.yml: --ref not used"
grep -qx "        README.md" "$pr" || fail "pr.yml: code-paths"
[ "$(grep -c "if: needs.changes.outputs.full == 'true'" "$pr")" = 2 ] || fail "pr.yml: heavy jobs not conditional"
if sed -n '/^  interop:/,/^$/p' "$pr" | grep -q "secrets: inherit"; then fail "pr.yml: interop gets secrets it does not use"; fi
sed -n '/^  ci:/,/^$/p' "$pr" | grep -qx "      id-token: write" || fail "pr.yml: ci permissions"
echo "ok   pr.yml has the gate, every job and its permissions"

cp -R "$tmp/ready" "$tmp/again"
"${tool[@]}" apply "$tmp/again" --write | grep -q ": migrated" || fail "second run: not migrated"
diff -r "$tmp/ready" "$tmp/again" > /dev/null || fail "second run changed a file"
echo "ok   a second run changes nothing"

got=0
"${tool[@]}" apply "$tmp/manual" --write > "$tmp/manual.log" || got=$?
[ "$got" = 3 ] || fail "manual: exit $got, want 3"
grep -q "concurrency group has no name of its own" "$tmp/manual.log" && grep -q "reads github\.ref" "$tmp/manual.log" || fail "manual: reasons"
diff -r testdata/rollout/manual "$tmp/manual" > /dev/null || fail "manual: a file was written"
echo "ok   a repository that needs a person is refused, untouched"

# A schedule, dispatch inputs, a named concurrency group, a job that asks for
# more permissions, a path filter and a workflow for other branches only.
a="$tmp/assisted"; awf="$a/.github/workflows"
got=0
"${tool[@]}" apply "$a" --write > "$tmp/assisted.log" || got=$?
[ "$got" = 3 ] || fail "assisted without flags: exit $got, want 3"
grep -q "fixtures.yml: a \`paths:\` filter" "$tmp/assisted.log" || fail "assisted: path filter not refused"
if grep -q "ci.yml:" "$tmp/assisted.log"; then fail "assisted: ci.yml refused: $(grep 'ci.yml:' "$tmp/assisted.log")"; fi
diff -r testdata/rollout/assisted "$a" > /dev/null || fail "assisted: a refused run wrote a file"
echo "ok   a path filter is refused until a person lifts it"

"${tool[@]}" apply "$a" --write --paths-as-code fixtures.yml --code-path 'docs/reference/*' > "$tmp/assisted.log" \
  || fail "assisted with --paths-as-code: $(cat "$tmp/assisted.log")"
wf="$awf"
[ "$(on ci.yml)" = 'schedule:,-cron:"173***",workflow_call:,inputs:,version:,description:"Imagetagtotest",type:string,default:"",mode:,description:Whichstacks,type:string,default:fast,soak:,type:boolean,default:false,workflow_dispatch:,inputs:,version:,description:"Imagetagtotest",default:"",mode:,description:Whichstacks,type:choice,options:,-all,-fast,default:fast,soak:,type:boolean' ] \
  || fail "assisted ci.yml on: $(on ci.yml)"
[ "$(on fixtures.yml)" = "workflow_call:,workflow_dispatch:" ] || fail "assisted fixtures.yml on: $(on fixtures.yml)"
[ "$(on policy.yml)" = "push:,branches:[main],workflow_call:,workflow_dispatch:" ] || fail "assisted policy.yml on: $(on policy.yml)"
cmp -s testdata/rollout/assisted/.github/workflows/soak.yml "$awf/soak.yml" || fail "assisted: soak.yml (other branches only) changed"
apr="$awf/pr.yml"
sed -n '/^  ci:/,/^$/p' "$apr" | grep -qx "      issues: write" || fail "assisted pr.yml: the ci job does not grant issues: write"
sed -n '/^  ci:/,/^$/p' "$apr" | grep -qx "      contents: read" || fail "assisted pr.yml: the ci job does not grant contents: read"
grep -qx "        docs/reference/\*" "$apr" || fail "assisted pr.yml: --code-path missing"
grep -qx "          required: changes policy" "$apr" || fail "assisted pr.yml: required: $(grep 'required:' "$apr")"
grep -qx "          required-for-code: ci fixtures" "$apr" || fail "assisted pr.yml: required-for-code"
sed -n '/^  policy:/,/^$/p' "$apr" | grep -qx "    secrets: inherit" || fail "assisted pr.yml: policy without secrets"
if grep -q "soak" "$apr"; then fail "assisted pr.yml calls soak.yml"; fi
echo "ok   schedule kept, dispatch inputs repeated, job permissions granted, flags applied"

mkdir "$tmp/ws"
for r in ready manual; do cp -R "testdata/rollout/$r" "$tmp/ws/$r"; mkdir "$tmp/ws/$r/.git"; done
"${tool[@]}" plan "$tmp/ws" > "$tmp/plan.md"
grep -q "| protocol-library | 0 | 1 | 0 | 0 | 0 |" "$tmp/plan.md" || fail "plan: protocol-library row"
grep -q "| unknown | 0 | 0 | 1 | 0 | 0 |" "$tmp/plan.md" || fail "plan: unknown row"
"${tool[@]}" plan "$tmp/ws" --format json | python3 -I -c 'import json,sys; d=json.load(sys.stdin); assert {r["repo"]: r["status"] for r in d} == {"ready": "ready", "manual": "manual"}, d'
echo "ok   plan counts by profile"
echo "rollout: all cases match"
