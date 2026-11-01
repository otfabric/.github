# SAST bundle

Gosec, Opengrep, the rule set and the gate used by [`sast.yml`](../.github/workflows/sast.yml), and through it by `go-ci.yml` (`run-sast: true`). The decision record is ADR-0011 in otfabric/engineering; the rules a repository is held to are CI-008, CI-009 and GO-014 in its `standards/security.md`.

## Turning it on

A repository runs the scan in its own workflow, `.github/workflows/sast.yml`, separate from CI and started by hand:

```yaml
name: SAST
run-name: "SAST (${{ inputs.mode }}) on ${{ github.ref_name }} by @${{ github.actor }}"

on:
  workflow_dispatch:
    inputs:
      mode:
        description: "report: findings never fail the run. baseline and enforce: see sast/README.md."
        type: choice
        options: [report, baseline, enforce]
        default: report
      block-severity:
        description: "Lowest severity that can fail the run."
        type: choice
        options: [high, medium, low]
        default: high
      block-confidence:
        description: "Lowest confidence that can fail the run."
        type: choice
        options: [high, medium, low]
        default: high

permissions:
  contents: read

jobs:
  sast:
    uses: otfabric/.github/.github/workflows/sast.yml@v3.5.0
    with:
      mode: ${{ inputs.mode }}
      block-severity: ${{ inputs.block-severity }}
      block-confidence: ${{ inputs.block-confidence }}
    secrets:
      OTFABRIC_READ_TOKEN: ${{ secrets.OTFABRIC_READ_TOKEN }}
```

To choose what fails a run, pick a mode and thresholds when you start it. A finding counts only when its severity and its confidence both reach the thresholds, so `medium` and `high` means at least medium severity and high confidence. `report` shows those findings but never fails on them; use `baseline` or `enforce` to fail. A scan that did not complete always fails.

GitHub only offers a manual workflow once the file is on the default branch. After that, start it from the Actions tab or with `gh workflow run sast.yml`, on any branch that has the file.

To make it part of CI later, add triggers to this workflow, or use `run-sast: true` and `sast-mode` on `go-ci.yml` instead of this file.

A repository with no Go module adds `run-gosec: false`. A nested module needs a second call with `module-dir`, `run-opengrep: false` and its own `artifact-name`.

| `mode` | Findings | Scan that did not complete |
|---|---|---|
| `report` | Never fail | Fails (exit 3) |
| `baseline` | Fail at the thresholds with no valid record | Fails (exit 3) |
| `enforce` | As `baseline`, and state `baseline` no longer counts | Fails (exit 3) |

The modes mean what they mean in `.otfabric/policy.yaml`. A finding can block when its severity and its confidence both reach the thresholds, high and high by default (`block-severity`, `block-confidence`). Everything else is reported as `below-threshold` and stays out of the baseline.

## What a run tells you

| Step | Fails with | Means |
|---|---|---|
| Scan completed | exit 3, in every mode | The scan cannot be trusted: a scanner failed, a file did not type-check, a rule did not load or timed out, rule files are missing or changed, nothing was scanned, the baseline is invalid |
| No blocking findings | exit 1 | The scan is fine and found something new |

The results stay with the finished run. Its summary page lists every finding, including those below the threshold and those already recorded, each linked to its line in the scanned commit. If a very large report does not fit there, it says so.

The artifact (`sast-reports`, 30 days) holds `status.json`, `findings.json`, one SARIF file per scanner and `summary.md`. `status.json` records the repository, commit, scan time, each scanner's version, revision and status, and the rule set's version, digest and packs. Each finding in `findings.json` has its fingerprint, rule, severity, confidence, location and `disposition`, the state of its record. Only a `status.json` with `scan_status: completed` for this `commit` shows that a commit was scanned. A skipped job has no artifact and no `scan-status` output. If the module has private dependencies, a fork pull request has no token to fetch them, so its scan fails like its test jobs do. Reports hold no source lines, so a finding of a secret does not copy the secret.

In a public repository anyone signed in to GitHub can read the artifact and job summary. They name a rule and a location in code that is already public. Keep exploit detail out of baseline records and pull requests, and handle a confirmed vulnerability through a private advisory first (`SECURITY.md`).

[`sast-code-scanning.yml`](../.github/workflows/sast-code-scanning.yml) uploads the SARIF files to GitHub code scanning. It is optional, and a job of its own because `security-events: write` has to be granted by the caller.

## Safety

- The job has `contents: read`. The optional token exists only in the environment of the `go mod download` command.
- `scripts/selftest/sast-static.sh` checks the token and permission rules on the workflow itself.
- Nothing from the checkout runs: no build, no tests, `CGO_ENABLED=0`, `GOPROXY=off` during the scan.
- Files in the scanned tree decide nothing: `.semgrepignore`, `.gitignore`, `#nosec` and `nosemgrep` are ignored. Only the baseline, which is reviewed like code, waives a finding.
- Names from the scanned tree are escaped before they reach a workflow command or the summary.

Protect `.otfabric/` with a `CODEOWNERS` entry, so a pull request cannot waive its own finding unnoticed.

## Baseline

`.otfabric/sast-baseline.json` has the fields of [an exception](https://github.com/otfabric/engineering/blob/main/docs/exceptions/README.md) plus what identifies the finding. `otfabric-policy` validates it under rule CI-009, and the gate validates it with no access to private repositories.

```json
{
  "schema": 1,
  "findings": [
    {
      "fingerprint": "gosec/G402/f4c3b7d2a1e09c8b7a65",
      "tool": "gosec",
      "rule": "G402",
      "path": "examples/ven/main.go",
      "state": "accepted-risk",
      "justification": "Only with the explicitly named -insecure flag of an example.",
      "owner": "bartvanbos",
      "reviewed": "2026-10-31",
      "reconsider": "when the example gains another way to skip verification",
      "ref": "docs/adr/0003-example.md"
    }
  ]
}
```

| State | Means | `baseline` mode | `enforce` mode |
|---|---|---|---|
| `baseline` | Debt at adoption, not triaged. Needs `expires` | Passes | Blocks |
| `confirmed` | Confirmed security issue, not fixed yet. Needs `expires` | Passes | Blocks |
| `probable` | Probable issue, under investigation. Needs `expires` | Passes | Blocks |
| `false-positive` | Reviewed, not a weakness | Passes | Passes |
| `accepted-risk` | Reviewed, a weakness the repository accepts, with an owner and a review or expiry date | Passes | Passes |
| `not-applicable` | Reviewed, the rule's concern does not arise here | Passes | Passes |

A record names one fingerprint of one tool and rule. There are no wildcards, and a state, a field or a fingerprint the gate does not know fails the scan. Comments in code waive nothing: this file is the one documented, narrowly scoped suppression, so that a suppression is always reviewed with an owner and an end.

The fingerprint hashes rule, path, source line and occurrence, so it survives moved lines. Editing the line asks for triage again. An expired record stops applying, a record that matches nothing is listed, and a record whose `reviewed` date is over six months old is listed as due. Those lists in the summary and `otfabric-policy scan` are the periodic reevaluation.

To record current findings, run the job or the scripts below, then:

```bash
python3 sast/sast_gate.py baseline --findings findings.json --baseline .otfabric/sast-baseline.json --owner <login> --expires 2027-04-30 --ref <issue>
```

Replace each generated justification when you triage the record.

## Rule catalog

### Gosec

All rules run, on the packages of `module-dir`. `go list` keeps nested modules, `testdata` and hidden directories out; nested modules are named in `status.json` and need their own go-ci call. A tree with no Go code at all and no `go.mod` is `not-applicable`. Go code with no `go.mod` in `module-dir` fails the scan. Gosec does not run through golangci-lint (rule GO-014).

| Rules | Topic | Value for protocol libraries |
|---|---|---|
| G402, G123 | TLS configuration, certificate bypass, resumption | High: reached the threshold on the pilots |
| G401, G405, G501, G502, G505 | Weak cryptography | Report only: OPC UA legacy security policies require some of it |
| G404 | Weak random numbers | Report only: often fine for jitter, wrong for keys and nonces |
| G407 | Fixed IV | High, needs review: both pilot hits were false positives |
| G115 | Integer conversions | Report only: by far the largest group in protocol code (592 of 688 below the threshold on the pilots), high severity and medium confidence. Bounds on wire data are checked by fuzz targets and limit tests |
| G204, G304, G703 | Command and path construction | High for CLIs and applications; G703 hit generators in the pilots, false positives |
| G101 | Hardcoded credentials | Medium: low confidence, so it reports without blocking |
| G301, G302, G306 | File permissions | Report only in libraries |

**Taint rules can flicker.** Gosec's taint rules (G701 to G710, G120) follow data through its callers in an order that changes between runs, so on unchanged code a finding can appear on some runs and not others ([gosec#1814](https://github.com/securego/gosec/issues/1814)). The cause is in Gosec, and `-concurrency 1` does not help. On the pilots it was rare: one finding of about 650, below the threshold, in half of its runs.

- A clean taint result does not prove a path is absent.
- A taint finding that fails a pull request which did not touch that code may be old, not caused by the pull request. Check whether the path exists, then fix or record it. Do not re-run until it passes.
- A recorded finding passes whether it appears or not, so its record can sometimes be listed as matching nothing. Check that it has been absent over several runs before removing it.

### Opengrep rule set (`opengrep/rules/`)

Written here, one file per rule, with a vulnerable and a safe fixture beside it (`opengrep test`, in the selftest). It is under this repository's licence. Each change bumps `OPENGREP_RULESET_VERSION`, adds to [`opengrep/CHANGELOG.md`](opengrep/CHANGELOG.md) and updates the digest in `versions.env`; a scan whose rule files do not match the digest is not completed. CI downloads no rules.

`profile:` in `.otfabric/policy.yaml` picks the packs. `interoperability`, `infrastructure`, `website` and `information-model` run `core`; every other profile, or none, runs `core` and `protocol`. A pull request can edit that file, so protect `.otfabric/` as above.

**Pack `core`**

| Rule | Topic | Severity, confidence | Limit |
|---|---|---|---|
| `otfabric-tls-verify-callback-accepts-all` | Go TLS | high, high | A callback that always passes through a helper is not seen |
| `otfabric-tls-verify-result-ignored` | Go TLS | high, high | Explicit `_` discards only; errcheck reports a bare call |
| `otfabric-python-tls-verification-disabled` | Python TLS | high, high | `requests`, `httpx` and `ssl` as written |
| `otfabric-js-tls-verification-disabled` | JS, TS TLS | high, high | Option written in the call |
| `otfabric-shell-disables-tls-verification` | Shell TLS | medium, high | Shell scripts only; a `run:` block is not parsed as Bash |
| `otfabric-config-disables-tls-verification` | YAML configuration | medium, medium | Keys named for it; cannot tell a test network from production |
| `otfabric-secret-in-log` | Secrets in logs | high, high | Goes by the name of the value, not its content |
| `otfabric-private-key-in-tree` | Secrets | high, high | PEM blocks with a body |
| `otfabric-go-auth-none-accepted` | Authentication shortcut | high, high | golang-jwt names |
| `otfabric-go-secret-compare-not-constant-time` | Authentication | medium, medium | Goes by the name of the value |
| `otfabric-exec-shell-dynamic` | Go commands | high, high | Direct `sh -c` calls; a wrapper function is not seen |
| `otfabric-python-shell-dynamic` | Python commands | high, high | Direct calls |
| `otfabric-js-command-dynamic` | JS, TS commands | high, high | Direct `child_process` calls |
| `otfabric-shell-pipe-to-interpreter` | Unverified download | medium, high | Direct pipes |
| `otfabric-go-http-path-to-file` | Paths | high, high | The request value has to appear in the call; G703 follows taint further |
| `otfabric-shell-world-writable` | File permissions | high, high | Literal modes in shell; Gosec covers Go |
| `otfabric-gha-untrusted-input-in-script` | Workflows | high, high | The usual attacker-controlled contexts |
| `otfabric-gha-pull-request-target-checkout` | Workflows | high, high | Refs that name the pull request head |
| `otfabric-gha-unsecure-commands` | Workflows | high, high | The variable written as true |

**Pack `protocol`**

| Rule | Topic | Severity, confidence | Limit |
|---|---|---|---|
| `otfabric-wire-length-unchecked-make` | Lengths from the wire | high, high | Only a decoded 32- or 64-bit value in the `make` call itself |
| `otfabric-http-body-unbounded-read` | HTTP | high, high | Does not see a limit in middleware, or a body passed to a helper |
| `otfabric-websocket-accepts-any-origin` | HTTP | high, high | Literal always-true functions, gorilla and coder APIs |
| `otfabric-defer-in-unbounded-loop` | Resource safety | high, high | `for { }` only; a defer guarded to run once is a false positive |

**What this cannot establish.** Pattern rules follow no dataflow. Static analysis here cannot show that untrusted network data is bounded, or find resource exhaustion in general. A length moved through a variable, a struct field, a helper or `binary.Read` before an allocation, an index or a recursion is not followed, and a clean scan is no evidence of a bounded decoder. `standards/security.md` ("Input limits") still requires limits in a table, a hardening test for each and fuzz targets (TEST-004, TEST-005). Neither scanner knows a protocol: whether a security mode is correctly negotiated stays with review rules SEC-R01 and PROTO-R01. These gaps are documented rather than covered by noisy rules.

## Pins

| Tool | Pin | How it was verified (2026-10-31) |
|---|---|---|
| Gosec | `v2.30.0`, commit `5eb1d104` | Latest release of securego/gosec, Apache-2.0. `h1:67aF6LHa7SAL6QEc4es857GrXTT50gUqmrl0XPhtDx0=` from sum.golang.org, which `go install` checks. Built with the runner's Go so it reads what that toolchain produces |
| Opengrep | `v1.33.1`, commit `092c80fa` | Latest release of opengrep/opengrep, LGPL-2.1. The release's Sigstore signature of `opengrep_manylinux_x86` checked once with `cosign verify-blob`; its SHA-256 in `versions.env` is checked on every install |
| Rule set | `1.0.0` | Files in this directory, SHA-256 digest in `versions.env` |

`bundle-ref` selects all of this together, so a change reaches a repository only with a workflow release it moves to.

## Running it locally

```bash
export GOSEC_BIN=$(which gosec) OPENGREP_BIN=$(which opengrep)
bash sast/run-gosec.sh /tmp/sast
bash sast/run-opengrep.sh /tmp/sast
python3 sast/sast_gate.py evaluate --out /tmp/sast --bundle . --root . --mode report
```

Run them from the repository under scan, with the paths to this directory adjusted. `install.sh` installs the Linux binaries as CI does.
