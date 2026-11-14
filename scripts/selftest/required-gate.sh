#!/usr/bin/env bash
# Run the gate of actions/required-gate (gate.py, the file action.yml runs) on
# synthetic needs contexts: every way a mandatory job can fail to succeed, the
# documentation-only and code pull requests, and a broken caller. Then every
# combination of results, to show that the gate never passes when a mandatory
# job did not succeed.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
gate=actions/required-gate/gate.py

# needs <changes result>:<full> <job>=<result>...  ->  a needs context
needs() {
  python3 -I - "$@" <<'PY'
import json, sys
changes, full = sys.argv[1].split(":", 1)
out = {"changes": {"result": changes, "outputs": {} if full == "-" else {"full": full, "reason": "synthetic"}}}
for arg in sys.argv[2:]:
    job, result = arg.split("=", 1)
    out[job] = {"result": result, "outputs": {}}
print(json.dumps(out))
PY
}

# run <name> <want exit> <want text or -> <needs json> [VAR=value...]
run() {
  local name=$1 want=$2 text=$3 json=$4 got=0
  shift 4
  : > "$tmp/summary"
  env NEEDS_JSON="$json" REQUIRED="changes docs" REQUIRED_FOR_CODE="ci interop" CHANGES_JOB=changes \
    GITHUB_STEP_SUMMARY="$tmp/summary" "$@" python3 -I "$gate" > "$tmp/log" 2>&1 || got=$?
  if [ "$got" != "$want" ]; then
    echo "FAIL $name: exit $got, want $want"; cat "$tmp/log"; exit 1
  fi
  if [ "$text" != - ] && ! grep -qF -- "$text" "$tmp/log"; then
    echo "FAIL $name: no '$text' in the log"; cat "$tmp/log"; exit 1
  fi
  grep -q '^### OT Fabric Required Checks: ' "$tmp/summary" || { echo "FAIL $name: no summary"; exit 1; }
  echo "ok   $name"
}

ok_code=$(needs success:true docs=success ci=success interop=success)
run "code PR, all succeed"                0 "All required checks passed" "$ok_code"
run "docs-only PR, code jobs skipped"     0 "All required checks passed" "$(needs success:false docs=success ci=skipped interop=skipped)"
run "docs-only PR, code jobs succeeded"   0 - "$(needs success:false docs=success ci=success interop=success)"
run "code PR, a mandatory job failed"     1 "ci: failure" "$(needs success:true docs=success ci=failure interop=success)"
run "code PR, a mandatory job cancelled"  1 "interop: cancelled" "$(needs success:true docs=success ci=success interop=cancelled)"
run "code PR, a mandatory job skipped"    1 "ci: skipped unexpectedly" "$(needs success:true docs=success ci=skipped interop=success)"
run "docs-only PR, docs skipped"          1 "docs: skipped unexpectedly" "$(needs success:false docs=skipped ci=skipped interop=skipped)"
run "docs-only PR, docs failed"           1 "docs: failure" "$(needs success:false docs=failure ci=skipped interop=skipped)"
run "docs-only PR, docs cancelled"        1 "docs: cancelled" "$(needs success:false docs=cancelled ci=skipped interop=skipped)"
run "docs-only PR, a code job failed"     1 "ci: failure" "$(needs success:false docs=success ci=failure interop=skipped)"
run "classification job failed"           1 "changes: failure" "$(needs failure:- docs=success ci=skipped interop=skipped)"
run "classification job cancelled"        1 "ci: skipped unexpectedly" "$(needs cancelled:- docs=success ci=skipped interop=skipped)"
run "classification without output"       1 "classification unavailable" "$(needs success:- docs=success ci=skipped interop=skipped)"
run "classification malformed"            1 "full='maybe'" "$(needs success:maybe docs=success ci=success interop=success)"
run "a mandatory job never reported"      1 "interop: missing: never reported" "$(needs success:true docs=success ci=success)"
run "a malformed result"                  1 "ci: malformed result" "$(needs success:true docs=success ci=neutral interop=success)"
run "a result that is not an object"      1 "ci: malformed result" '{"changes":{"result":"success","outputs":{"full":"true"}},"docs":{"result":"success"},"ci":"success","interop":{"result":"success"}}'
run "a result of the wrong type"          1 "ci: malformed result" '{"changes":{"result":"success","outputs":{"full":"true"}},"docs":{"result":"success"},"ci":{"result":true},"interop":{"result":"success"}}'
run "a job with no expectation"           1 "lint is in needs but in neither" "$(needs success:true docs=success ci=success interop=success lint=success)"
run "needs is not JSON"                   1 "needs is not JSON" "{not json"
run "needs is empty"                      1 "needs is not JSON" ""
run "needs is not an object"              1 "needs is not a JSON object" "[]"
run "no required jobs"                    1 "no job is listed in required" "$ok_code" REQUIRED=
run "changes-job not required"            1 "must be listed in required" "$ok_code" REQUIRED=docs REQUIRED_FOR_CODE="changes ci interop"
run "a job in both lists"                 1 "listed in both" "$ok_code" REQUIRED="changes docs ci" REQUIRED_FOR_CODE="ci interop"
run "comma and newline separated ids"     0 - "$ok_code" REQUIRED=$'changes,\ndocs' REQUIRED_FOR_CODE="ci, interop"
run "another changes job id"              0 - '{"classify":{"result":"success","outputs":{"full":"false"}},"docs":{"result":"success"}}' \
  CHANGES_JOB=classify REQUIRED="classify docs" REQUIRED_FOR_CODE=
run "a newline in an output stays on its line" 1 - \
  '{"changes":{"result":"success","outputs":{"full":"x\n::notice::injected"}},"docs":{"result":"success"}}' REQUIRED_FOR_CODE=
if grep -q '^::notice::injected' "$tmp/log"; then echo "FAIL: an output started a workflow command"; exit 1; fi

# Every combination: the gate passes exactly when it should.
python3 -I - "$gate" <<'PY'
import itertools, json, os, subprocess, sys
gate = sys.argv[1]
R = ["success", "failure", "cancelled", "skipped"]
n = 0
for changes, full, docs, ci, interop in itertools.product(R, ["true", "false", ""], R, R, R):
    needs = {"changes": {"result": changes, "outputs": {"full": full} if full else {}},
             "docs": {"result": docs}, "ci": {"result": ci}, "interop": {"result": interop}}
    env = dict(os.environ, NEEDS_JSON=json.dumps(needs), REQUIRED="changes docs",
               REQUIRED_FOR_CODE="ci interop", CHANGES_JOB="changes", GITHUB_STEP_SUMMARY=os.devnull)
    got = subprocess.run([sys.executable, "-I", gate], env=env, capture_output=True).returncode == 0
    code_ok = {"true": ci == interop == "success",
               "false": {ci, interop} <= {"skipped", "success"}}.get(full, False)
    want = changes == "success" and docs == "success" and code_ok
    if got != want:
        sys.exit(f"FAIL combination {needs}: passed={got}, want {want}")
    n += 1
print(f"ok   all {n} combinations: no pass without every expected result")
PY
echo "required gate: all cases match"
