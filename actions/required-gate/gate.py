#!/usr/bin/env python3
"""OT Fabric Required Checks: the verdict of a repository's PR workflow.

Run by action.yml with the needs context of the gate job as NEEDS_JSON, the
job ids of REQUIRED and REQUIRED_FOR_CODE, and CHANGES_JOB, the job that
called pr-changes.yml. Exits 1, with an ::error:: line per problem and a table
in the job summary, unless every expected result is there:

- every job in REQUIRED (CHANGES_JOB among them) succeeded;
- CHANGES_JOB reported full "true" or "false", nothing else;
- full "true": every job in REQUIRED_FOR_CODE succeeded;
- full "false": every job in REQUIRED_FOR_CODE was skipped (or succeeded);
- every job in needs has one of these expectations, and every job named in
  them is in needs.

Failed, cancelled, unexpectedly skipped, missing and malformed results fail.
Standard library only.
"""
import json
import os
import re
import sys

RESULTS = {"success", "failure", "cancelled", "skipped"}
errors, rows = [], []


def ids(text):
    return list(dict.fromkeys(t for t in re.split(r"[\s,]+", text or "") if t))


def printable(text):
    # Job ids and outputs come from the caller; none may end a line early in
    # a workflow command or the summary.
    return "".join(ch if ch.isprintable() else "?" for ch in str(text))


def result_of(needs, job):
    if job not in needs:
        return None
    entry = needs[job]
    if not isinstance(entry, dict):
        return f"malformed ({entry!r})"
    r = entry.get("result")
    return r if isinstance(r, str) and r in RESULTS else f"malformed ({r!r})"


def check(needs, job, expected, allowed):
    r = result_of(needs, job)
    if r is None:
        verdict = "missing: never reported"
    elif r in allowed:
        verdict = "ok"
    elif r == "skipped":
        verdict = "skipped unexpectedly"
    elif r.startswith("malformed"):
        verdict = "malformed result"
    else:
        verdict = r
    rows.append((job, expected, r or "-", verdict))
    if verdict != "ok":
        errors.append(f"{job}: {verdict} (expected {expected})")


def report(classification):
    passed = not errors
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as s:
            s.write(f"### OT Fabric Required Checks: {'passed' if passed else 'failed'}\n\n")
            s.write(f"Classification: {printable(classification)}\n\n")
            if rows:
                s.write("| Job | Expected | Result | Verdict |\n|---|---|---|---|\n")
                for row in rows:
                    s.write("| " + " | ".join(printable(c).replace("|", "\\|") for c in row) + " |\n")
                s.write("\n")
            for e in errors:
                s.write(f"- {printable(e)}\n")
    for e in errors:
        print(f"::error title=OT Fabric Required Checks::{printable(e)}")
    if not passed:
        sys.exit(1)
    print("All required checks passed.")
    sys.exit(0)


def main():
    required = ids(os.environ.get("REQUIRED"))
    for_code = ids(os.environ.get("REQUIRED_FOR_CODE"))
    changes = os.environ.get("CHANGES_JOB", "").strip()

    try:
        needs = json.loads(os.environ.get("NEEDS_JSON") or "")
    except ValueError as e:
        needs = None
        errors.append(f"needs is not JSON ({e})")
    if needs is not None and not isinstance(needs, dict):
        errors.append("needs is not a JSON object")
        needs = None
    if not required:
        errors.append("no job is listed in required")
    if not changes or changes not in required:
        errors.append(f"changes-job '{changes}' must be listed in required")
    for job in sorted(set(required) & set(for_code)):
        errors.append(f"{job} is listed in both required and required-for-code")
    if needs is None:
        report("unavailable")

    # Every job the gate depends on has an expectation, and every
    # expectation names a job the gate depends on (check reports the rest).
    for job in sorted(set(needs) - set(required) - set(for_code)):
        errors.append(f"{job} is in needs but in neither required nor required-for-code")

    entry = needs.get(changes) if isinstance(needs.get(changes), dict) else {}
    outputs = entry.get("outputs") if isinstance(entry.get("outputs"), dict) else {}
    full = outputs.get("full")
    mode, classification = None, "unavailable"
    if entry.get("result") == "success":
        if full == "true":
            mode, classification = "code", "full validation"
        elif full == "false":
            mode, classification = "docs", "documentation only"
        else:
            errors.append(f"classification unavailable: {changes} reported full={full!r}")
    reason = outputs.get("reason")
    if isinstance(reason, str) and reason:
        classification += f": {reason}"

    for job in required:
        check(needs, job, "success", {"success"})
    for job in for_code:
        if mode == "code":
            check(needs, job, "success", {"success"})
        elif mode == "docs":
            check(needs, job, "skipped (documentation only)", {"skipped", "success"})
        else:
            check(needs, job, "a classification", set())
    report(classification)


if __name__ == "__main__":
    main()
