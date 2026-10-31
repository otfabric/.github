# SAST bundle

Gosec, Opengrep, the rule catalog and the gate used by [`sast.yml`](../.github/workflows/sast.yml), and through it by `go-ci.yml` (`run-sast: true`). The decision record is ADR-0011 in otfabric/engineering; the rules a repository is held to are CI-008, CI-009 and GO-014 in its `standards/security.md`.

## Turning it on

```yaml
jobs:
  ci:
    uses: otfabric/.github/.github/workflows/go-ci.yml@v3
    with:
      run-sast: true
      sast-mode: report
    secrets: inherit
```

A repository with no Go module calls `sast.yml` with `run-gosec: false`. A second `go-ci` call for a nested module sets `sast-run-opengrep: false` and its own `sast-artifact-name`.

| `mode` | Findings | Scan that did not complete |
|---|---|---|
| `report` | Never fail | Warning, and `scan-status: incomplete` |
| `baseline` | Fail at the thresholds with no valid record | Fails (exit 3) |
| `enforce` | As `baseline`, and state `baseline` no longer counts | Fails (exit 3) |

The modes mean what they mean in `.otfabric/policy.yaml`. A finding can block when its severity and its confidence both reach the thresholds, high and high by default (`block-severity`, `block-confidence`). Everything else is reported as `below-threshold` and stays out of the baseline.

## What a run tells you

| Step | Fails with | Means |
|---|---|---|
| Scan completed | exit 3 | The scan cannot be trusted: a scanner failed, a file did not type-check, a rule did not load or timed out, nothing was scanned, the baseline is invalid |
| No blocking findings | exit 1 | The scan is fine and found something new |

The artifact (`sast-reports`, 30 days) holds `status.json`, `findings.json`, one SARIF file per scanner and `summary.md`. Only a `status.json` with `scan_status: completed` for this `commit` shows that a commit was scanned. A skipped job has no artifact and no `scan-status` output. Reports hold no source lines, so a finding of a secret does not copy the secret.

In a public repository anyone signed in to GitHub can read the artifact and job summary. They name a rule and a location in code that is already public. Keep exploit detail out of baseline records and pull requests, and handle a confirmed vulnerability through a private advisory first (`SECURITY.md`).

[`sast-code-scanning.yml`](../.github/workflows/sast-code-scanning.yml) uploads the SARIF files to GitHub code scanning. It is optional, and a job of its own because `security-events: write` has to be granted by the caller.

## Safety

- The job has `contents: read`. The optional token exists only in the environment of the `go mod download` command.
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
| `false-positive` | Reviewed, not a weakness | Passes | Passes |
| `accepted-risk` | Reviewed, a weakness the repository accepts | Passes | Passes |

The fingerprint hashes rule, path, source line and occurrence, so it survives moved lines. Editing the line asks for triage again. An expired record stops applying, a record that matches nothing is listed, and a record whose `reviewed` date is over six months old is listed as due. Those lists in the summary and `otfabric-policy scan` are the periodic reevaluation.

To record current findings, run the job or the scripts below, then:

```bash
python3 sast/sast_gate.py baseline --findings findings.json --baseline .otfabric/sast-baseline.json --owner <login> --expires 2027-04-30 --ref <issue>
```

Replace each generated justification when you triage the record.

## Rule catalog

### Gosec

All rules run. Those reaching high severity and high confidence on the pilots: G402 (TLS configuration), G123 (TLS callback and session resumption), G407 (fixed IV), G703 (path traversal, taint). G115 (integer conversion, high severity and medium confidence) is by far the largest group in protocol code and stays below the threshold; bounds on wire data are checked by fuzz targets and limit tests.

### Custom Opengrep rules (`opengrep/rules/`)

Each has a vulnerable and a safe fixture beside it, run by `opengrep test` in the selftest. They cover what Gosec does not.

| Rule | Topic | Severity, confidence | Limit |
|---|---|---|---|
| `otfabric-tls-verify-callback-accepts-all` | TLS | high, high | A callback that always passes through a helper is not seen |
| `otfabric-tls-verify-result-ignored` | TLS | high, high | Explicit `_` discards only; errcheck reports a bare call |
| `otfabric-shell-disables-tls-verification` | TLS | medium, high | Shell scripts only; a `run:` block in a workflow is not parsed as Bash by this rule |
| `otfabric-secret-in-log` | Secrets | high, high | Goes by the name of the value, not its content |
| `otfabric-exec-shell-dynamic` | Command injection | high, high | Direct `sh -c` calls; a command line built elsewhere and passed as a constant-looking variable is reported, a wrapper function is not |
| `otfabric-shell-world-writable` | File permissions | high, high | Literal modes in shell; Gosec G301, G302 and G306 cover Go |
| `otfabric-wire-length-unchecked-make` | Parser | high, high | Only a decoded 32- or 64-bit value in the `make` call itself |
| `otfabric-http-body-unbounded-read` | HTTP | high, high | Does not see a limit set in middleware, or a body passed to a helper |
| `otfabric-websocket-accepts-any-origin` | HTTP | high, high | Literal always-true functions, gorilla and coder APIs |
| `otfabric-defer-in-unbounded-loop` | Resource safety | high, high | `for { }` only; a defer guarded to run once is a false positive |

**What this cannot establish.** Static analysis here cannot show that untrusted network data is bounded. A length moved through a variable, a struct field, a helper or `binary.Read` before an allocation, an index or a recursion is not followed, and a clean scan is no evidence of a bounded decoder. `standards/security.md` ("Input limits") still requires limits in a table, a hardening test for each and fuzz targets (TEST-004, TEST-005). Neither scanner knows a protocol: whether a security mode is correctly negotiated stays with review rule SEC-R01 and PROTO-R01.

### Upstream Opengrep rules (`opengrep/upstream.txt`)

Fetched at the pinned commit, tested for existence in the selftest, never copied here. opengrep-rules is LGPL-2.1 with the Commons Clause and states that its rules are meant for research, testing and benchmarking. Using them in our own CI, unmodified and unredistributed, fits that; replacing them is one file should that change. Most keep their upstream confidence and so report without blocking. Exceptions are in the file.

Rules left out after measuring all 389 candidates (Go, Bash, workflows, secrets) on the pilots: audit-only rules whose confidence is low (`use-of-unsafe-block`, `import-text-template`, `use-filepath-join`, `generic-api-key`), and rules Gosec already covers with type information (`missing-ssl-minversion`, `math-random-used`, `use-of-sha1`).

## Pins

| Tool | Pin | How it was verified (2026-10-31) |
|---|---|---|
| Gosec | `v2.30.0` | Latest release of securego/gosec. `h1:67aF6LHa7SAL6QEc4es857GrXTT50gUqmrl0XPhtDx0=` from sum.golang.org, which `go install` checks. Built with the runner's Go so it reads what that toolchain produces |
| Opengrep | `v1.33.1` | Latest release of opengrep/opengrep. SHA-256 of `opengrep_manylinux_x86` in `versions.env`, checked on every install |
| opengrep-rules | `f1d2b562…` | Head of main; git checks the commit by its id |

`bundle-ref` selects all of this together, so a change reaches a repository only with a workflow release it moves to.

## Running it locally

```bash
export GOSEC_BIN=$(which gosec) OPENGREP_BIN=$(which opengrep)
bash sast/run-gosec.sh /tmp/sast
bash sast/run-opengrep.sh /tmp/sast /path/to/opengrep-rules
python3 sast/sast_gate.py evaluate --out /tmp/sast --bundle . --root . --mode report
```

Run them from the repository under scan, with the paths to this directory adjusted. `install.sh` installs the Linux binaries as CI does.
