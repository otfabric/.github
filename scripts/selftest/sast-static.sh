#!/usr/bin/env bash
# What sast.yml must never do, read from the workflow itself: the token reaches
# one step and nothing writes.
set -euo pipefail
cd "$(dirname "$0")/../.."
python3 - <<'PY'
import re

text = open(".github/workflows/sast.yml").read()
assert text.count("secrets.") == 1, "the token appears in one place"
step = text[text.rindex("- name:", 0, text.index("secrets.")):]
step = step[:step.index("- name:", 1)]
assert "Fetch Go dependencies" in step, "the token belongs to the dependency fetch"
assert "go mod download" in step and "run-gosec.sh" not in step and "run-opengrep.sh" not in step, "and to no scanner"
assert not re.search(r"\$GITHUB_ENV|\$GITHUB_PATH|git config", step), "and does not outlive the step"
perms = re.findall(r"^\s*permissions:\n((?:\s+\S+: \S+\n)+)", text, re.M)
assert perms and all(p.split() == ["contents:", "read"] for p in perms), perms
assert "pull_request_target" not in text
assert text.count("uses: actions/checkout@") == text.count("persist-credentials: false") == 2, "no checkout keeps credentials"
assert "*.json" not in text and "gosec.json" not in text, "raw reports hold source lines and stay out of the artifact"
for name in ("go-ci.yml",):
    ci = open(f".github/workflows/{name}").read()
    job = ci[ci.index("\n  sast:\n"):]
    assert "contents: read" in job and "write" not in job.split("uses:")[0], "go-ci gives the job read access only"
PY
echo "the token reaches one step; nothing writes"
