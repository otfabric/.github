# Reusable Go Workflows

Shared [reusable workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows) for Go projects across the **otfabric** organisation.

The `OTFABRIC_READ_TOKEN` secret gives access to private `github.com/otfabric/*` modules. In `go-ci.yml` it is needed when a module has private dependencies, and by the policy job when `.otfabric/policy.yaml` exists. The token must be able to read `otfabric/engineering`.

**Permissions.** The organisation's default `GITHUB_TOKEN` is read-only, and a caller must grant at least what a called workflow requests, or the run fails at startup with no job started. Grant `contents: read` and `id-token: write` for `go-ci.yml` (Codecov OIDC), `contents: read` for `docs-check.yml` and `pr-changes.yml`, and `contents: write` for the release workflows.

**Versions.** `v3` turns on govulncheck, tests `cmd/`, uses atomic coverage and starts the matrix at the go directive. `v2` and `v2.1.0` were moved to the same commit by the maintainer on 2026-10-30, so they have these defaults too.

**Selftest.** [`selftest.yml`](selftest.yml) tests these workflows on the fixtures in `testdata/` on every change. Add a case when you change behaviour.

## Workflows

Reusable workflows share whole pipelines (the caller's job is `uses:` one of these). For building blocks that run as steps inside a repository's own jobs, see the composite actions in [`actions/`](../../actions/README.md).

| Workflow | Purpose |
|----------|---------|
| [`go-ci.yml`](go-ci.yml) | Lint, static analysis, coverage, and multi-version test matrix |
| [`go-package-release.yml`](go-package-release.yml) | Semver-tagged release for Go libraries / packages |
| [`go-binary-release.yml`](go-binary-release.yml) | Cross-compiled binary release with SHA-256 checksums |
| [`docs-check.yml`](docs-check.yml) | [docsync](https://github.com/otfabric/docsync) and otfabric-policy, on every push, Markdown-only ones included |
| [`pr-changes.yml`](pr-changes.yml) | Classifies a pull request: documentation only, or full validation; for the PR workflow below |

The required check of a PR workflow is the composite action [`actions/required-gate`](../../actions/README.md#required-check-of-a-pr-workflow).

## Which workflows to use

| Repo type | CI | Release |
|-----------|-----|---------|
| Package only | `go-ci.yml` | `go-package-release.yml` |
| Binary only | `go-ci.yml` | `go-binary-release.yml` |
| Package + Binary | `go-ci.yml` | `go-package-release.yml` then `go-binary-release.yml` (chained) |

## Quick-start examples

### Package-only repo

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
  pull_request:

jobs:
  ci:
    uses: otfabric/.github/.github/workflows/go-ci.yml@v2
    secrets:
      OTFABRIC_READ_TOKEN: ${{ secrets.OTFABRIC_READ_TOKEN }}
```

```yaml
# .github/workflows/release.yml
name: Release
on:
  workflow_dispatch:
    inputs:
      bump:
        description: "Version bump"
        required: true
        type: choice
        options: [patch, minor, major]

jobs:
  release:
    uses: otfabric/.github/.github/workflows/go-package-release.yml@v2
    with:
      bump: ${{ inputs.bump }}
    secrets:
      OTFABRIC_READ_TOKEN: ${{ secrets.OTFABRIC_READ_TOKEN }}
```

### Binary-only repo

```yaml
# .github/workflows/release.yml
name: Release
on:
  workflow_dispatch:
    inputs:
      bump:
        description: "Version bump"
        required: true
        type: choice
        options: [patch, minor, major]

jobs:
  release:
    uses: otfabric/.github/.github/workflows/go-binary-release.yml@v2
    with:
      bump: ${{ inputs.bump }}
      binary-name: myapp
      main-path: ./cmd/myapp
      ldflags: "-s -w -X main.version=${VERSION} -X main.commit=${COMMIT}"
    secrets:
      OTFABRIC_READ_TOKEN: ${{ secrets.OTFABRIC_READ_TOKEN }}
```

### Package + Binary repo (chained)

```yaml
# .github/workflows/release.yml
name: Release
on:
  workflow_dispatch:
    inputs:
      bump:
        description: "Version bump"
        required: true
        type: choice
        options: [patch, minor, major]

jobs:
  package:
    uses: otfabric/.github/.github/workflows/go-package-release.yml@v2
    with:
      bump: ${{ inputs.bump }}
    secrets:
      OTFABRIC_READ_TOKEN: ${{ secrets.OTFABRIC_READ_TOKEN }}

  binary:
    needs: package
    uses: otfabric/.github/.github/workflows/go-binary-release.yml@v2
    with:
      bump: none
      binary-name: myapp
      main-path: ./cmd/myapp
      run-tests: false
    secrets:
      OTFABRIC_READ_TOKEN: ${{ secrets.OTFABRIC_READ_TOKEN }}
```

## CLIs in nested modules

A library that bundles a small CLI keeps it in its own module (`cmd/<tool>/go.mod`), so library consumers do not inherit its dependencies. Pass `module-dir: cmd/<tool>` and `main-path: .` to `go-binary-release.yml`. No `go.work` is needed.

## Go version of release builds

`go-binary-release.yml` builds with the newest patch release of the Go minor version the module declares: `go 1.26.0` (or `go 1.26`) builds with the latest 1.26.x. A `toolchain` line counts when its minor version is newer. The `go` directive stays the floor for users; it does not pin the compiler of the shipped binaries, so a patch release of Go reaches them on the next release.

## API compatibility gate

`go-package-release.yml` checks the exported API of the candidate against the previous published version with a pinned [`gorelease`](https://pkg.go.dev/golang.org/x/exp/cmd/gorelease) before it creates the tag (ADR-0017 and REL-003 in otfabric/engineering). A rejected version stops the job before *Create and push annotated tag*: nothing is tagged or published.

**Previous version.** The highest exact release tag of the module (`vX.Y.Z`, or `<module-dir>/vX.Y.Z` for a nested module) in the major of its module path, compared as semantic versions. Prereleases, moving tags (`v1`, `v1.2`) and other modules' or majors' tags never count. The job fails, and never picks another base, when that tag is not an ancestor of the release commit or its `go.mod` names another module.

| Situation | Base | Result |
|---|---|---|
| A previous version exists | that version | `gorelease -base=<previous> -version=<proposed>` |
| No previous version (first release) | `none` | gorelease checks the module alone; the evidence records no previous version |
| First release of a `/vN` module path | `none` | the version is `vN.0.0` |
| `bump: major` to v2 or later without a `/vN` module path | — | fails: a new major is a module path change |
| `bump: major` from v0 | the v0 version | `v1.0.0`, with the v0 rules below |

**Results.**

| `result` | Meaning | `api-compatibility: enforce` | `report` |
|---|---|---|---|
| `pass` | gorelease accepts the version | release | release |
| `incompatible` | gorelease rejects it (wrong bump, or an incompatible change in v1+), or a v0 rule fails | stop, no tag | warning, release |
| `error` | gorelease did not reach a result: not installed, base not downloadable, dirty tree | stop, no tag | warning, release |

An `error` is never read as a pass and never reported as an incompatibility: the step output and the evidence keep them apart.

**v0.** gorelease accepts any change against a v0 base, so the workflow applies the rules of ADR-0017 to its report: a v0 **patch** must not change the exported API at all; a v0 minor or major with incompatible changes needs a `### Breaking` heading in its `RELEASE.md` section.

**Evidence.** Every run that resolved a version writes `release-evidence.json` (artifact `release-evidence`, and an asset of the GitHub release): commit, module path and directory, previous and proposed version, the gorelease version and result with the listed changes, the Go toolchain, vet, test and race results, consumer results, the recorded exceptions and baseline, the release-notes source, and what the release job does **not** run (coverage, govulncheck, lint, fuzz, interop: go-ci evidence on the same commit).

**Consumers.** `consumers` lists direct dependants to build, vet and test against the candidate before tagging (`owner/repo` or `owner/repo:dir`, one per line). Each is cloned into a temporary directory with a `replace` that is never committed. A separate, read-only job runs them: the read token exists only while cloning and downloading, and consumer code builds and tests offline. Any failure stops the release and names the consumer, its revision, the version it requires and the candidate commit.

**Staged adoption.** `api-compatibility: report` records the result without stopping the release. otfabric/engineering's REL-003 reports a caller in report mode or below v3.8.0 (v3.7.0 has no gate).

## Release notes via RELEASE.md

Both release workflows support an optional `RELEASE.md` file in the repo root (for `go-package-release.yml`, in `module-dir`; a nested module's section heading is its version without the directory prefix, `## v0.3.0`). When a section matching the new tag is found, its content is used as the GitHub Release body. Otherwise a commit-log changelog is generated automatically.

```markdown
## v1.3.0
- Added support for widget streaming
- Improved error handling in the parser
---
## v1.2.0
- Initial public release
---
```

Sections are delimited by `---`. Only the section matching the tag being released is extracted.

## PR workflow and the required check

A repository that adopts it runs its heavy validation once per pull request
revision, and not again on the push of the branch or on the merge to `main`:

| Event | What runs |
|---|---|
| Push to a feature branch | Nothing |
| Pull request opened, synchronized, reopened | `pr.yml`: Docs and Policy always; CI, interop and the other heavy jobs unless the pull request is documentation only; then `OT Fabric Required Checks` |
| Push to `main` (the merge) | `docs.yml` only (docsync and policy, about a minute) |
| Schedule, `workflow_dispatch` | Unchanged: nightly, self-interop; `ci.yml` and `interop.yml` can also be dispatched on any branch |
| Release | Unchanged: the release workflows test the release commit in full |

One workflow, `pr.yml`, runs on every pull request with no path filter, and
its last job is the only required check. The heavy workflows keep their jobs
and become reusable (`on: workflow_call`), so nothing is copied:

```yaml
# .github/workflows/pr.yml
name: PR
on:
  pull_request:

permissions:
  contents: read

# A new revision cancels the run of the previous one; other workflows
# (release, nightly, dispatch) are in other groups.
concurrency:
  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}
  cancel-in-progress: true

jobs:
  changes:
    uses: otfabric/.github/.github/workflows/pr-changes.yml@v3.7.0

  docs:
    uses: ./.github/workflows/docs.yml
    secrets: inherit

  ci:
    needs: changes
    if: needs.changes.outputs.full == 'true'
    permissions:
      contents: read
      id-token: write
    uses: ./.github/workflows/ci.yml
    secrets: inherit

  required:
    name: OT Fabric Required Checks
    needs: [changes, docs, ci]
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: otfabric/.github/actions/required-gate@v3.7.0
        with:
          needs: ${{ toJSON(needs) }}
          required: changes docs
          required-for-code: ci
```

The rules the shape depends on:

- **No path filter on `pr.yml`.** A required check whose workflow a filter
  skipped never reports, and the pull request waits for it forever.
- **The gate has `if: always()`.** It runs when a job failed or the run was
  cancelled, and fails then. A skipped job counts as passed for a required
  check, so the gate must never be skipped; `!cancelled()` would skip it.
- **The gate needs every other job**, and lists each in `required` (must
  succeed on every pull request) or `required-for-code` (must succeed unless
  the pull request is documentation only, and then must be skipped). A job
  in `needs` that is in neither list, or a listed job missing from `needs`,
  fails the gate, so a job cannot be added without an expectation.
- **The gate job is defined in `pr.yml` itself**, so the check is named
  `OT Fabric Required Checks` with no prefix. A gate inside a called
  workflow would report as `<caller job> / <job>`.
- **The heavy jobs depend on `changes`** and run when `full` is `"true"`. If
  `changes` fails they are skipped and the gate fails: rerun the failed jobs.
- **Keep the triggers** to the defaults (`opened`, `synchronize`,
  `reopened`). `edited` would rerun everything on a title change. A pull
  request whose base is changed to `main` gets a run on its next push, or
  close and reopen it.

`pr-changes.yml` classifies the files the pull request's merge commit
changes, compared with its first parent: exactly the tree the jobs test.
Documentation only means every changed file is an added or modified regular
`*.md` file, not in a dot directory, `testdata/` or `vendor/`, not
`AGENTS.md`, `CLAUDE.md` or `GEMINI.md`, and not matched by `code-paths`.
A deletion, a rename, a symlink, any other file, a run that is not a pull
request, or a checkout it cannot verify gives `full: "true"`. List Markdown
that a test or generator reads in `code-paths` (go-iec61850's
`readme_test.go` reads `README.md`):

```yaml
  changes:
    uses: otfabric/.github/.github/workflows/pr-changes.yml@v3.7.0
    with:
      code-paths: |
        README.md
        docs/generated/*.md
```

Patterns are `fnmatch` patterns on the whole path: `*` also matches `/`, so
`*.md` matches every Markdown file and `README.md` only the root one.

### Migrating a repository

1. Make each heavy workflow reusable: replace its `push` and `pull_request`
   triggers with `workflow_call` and `workflow_dispatch`. Its jobs, inputs
   and pins stay as they are.
2. `docs.yml`: keep `push: branches: [main]`, replace `pull_request` with
   `workflow_call`.
3. Add `pr.yml` as above, with one job per reusable workflow and one entry
   for each in the gate. Grant each job the permissions its workflow
   requests (`id-token: write` for go-ci, `packages: read` for GHCR pulls).
4. Open the pull request. It runs `pr.yml` from the branch: check that
   `OT Fabric Required Checks` reports, and that its summary lists every job.
5. Only then require the check, by the exact name, in a ruleset (strict:
   the branch must be up to date with `main`). Never require a job of a
   called workflow or of a workflow with a path filter.

Rollback: restore the previous triggers of the heavy workflows and delete
`pr.yml`; first remove the required check from the ruleset, or every open
pull request waits for it.

## Markdown-only changes (repositories without a PR workflow)

A push or pull request that changes only Markdown needs no build, tests or
interop run. The heavy workflows of a repository skip it:

```yaml
on:
  push:
    branches: [main]
    paths-ignore: ['**/*.md']
  pull_request:
    paths-ignore: ['**/*.md']
```

A workflow that checks a generated Markdown file (for example `OBJECTS.md`)
lists it instead: `paths: ['**', '!**/*.md', 'OBJECTS.md']`. Tag pushes and
`workflow_dispatch` are never filtered.

The documents are still checked: `docs-check.yml` runs on every push and pull
request, with no path filter, so the Docs and Policy checks always report. A
branch protection rule must require those, never a job of a workflow that a
path filter can skip: a skipped required workflow leaves the check pending.

```yaml
# .github/workflows/docs.yml
name: Docs
on:
  push:
    branches: [main]
  pull_request:
permissions:
  contents: read
jobs:
  docs:
    uses: otfabric/.github/.github/workflows/docs-check.yml@v3
    secrets: inherit
```

| Input | Default | Description |
|-------|---------|-------------|
| `module-dir` | `.` | Directory of the Go module docsync checks |
| `docsync-version` | `v0.3.0` | Tag of `otfabric/docsync` to run |
| `mode` | `enforce` | `warn` turns findings into warnings; a docsync error fails in both modes |
| `run-policy` | `true` | Run `otfabric-policy`, as in `go-ci.yml` |
| `policy-version` | `v1.3.0` | Tag of `otfabric/engineering` whose `otfabric-policy` to run |
| `timeout-minutes` | `15` | Job timeout |

With the Policy job here, a repository that calls both can set
`run-policy: false` in `go-ci.yml`.

## Inputs reference

Each workflow's inputs are fully documented with descriptions inside the YAML files themselves. Key inputs worth highlighting:

### go-ci.yml

| Input | Default | Description |
|-------|---------|-------------|
| `go-versions` | `["1.23","1.24","1.25","1.26"]` | Go versions for the test matrix; versions below the go directive are dropped |
| `golangci-lint-version` | `v2.1.6` | Pinned linter version |
| `module-dir` | `.` | Directory of the Go module |
| `run-govulncheck` | `true` | Run govulncheck in its own job on stable Go |
| `govulncheck-version` | `v1.9.0` | Pinned govulncheck version (needs Go >= 1.26) |
| `coverage-min` | `""` | Minimum total coverage in percent; empty = no gate |
| `coverage-mode` | `atomic` | `go test -covermode`; `atomic` matches runs with `-race` |
| `fuzz-time` | `""` | Run every discovered Fuzz target this long, e.g. `10s`; empty = no fuzzing |
| `run-policy` | `true` | Run `otfabric-policy` in its own job when `.otfabric/policy.yaml` exists |
| `policy-version` | `v1.2.0` | Tag of `otfabric/engineering` whose `otfabric-policy` to run |
| `test-exclude-regex` | `/example(s)?($\|/)` | Packages to skip during testing; `cmd/` is tested |
| `coverpkg` | `""` | Optional `-coverpkg` list for merged cross-package coverage (Codecov) |
| `codecov-name` | `""` | Set to enable Codecov upload |

When a repo measures coverage with `go test -coverpkg=...` locally (for example a
`make coverage` target that merges library packages exercised by conformance
tests), pass the same package list as `coverpkg` so Codecov matches that gate.
Leave `coverpkg` empty to keep the default per-package coverage behaviour.

The policy job runs at the repository root on stable Go, without a cache, whatever `module-dir` says. It writes the Markdown report to the job summary; whether findings fail the job is set by the `mode` in `.otfabric/policy.yaml`. A caller that calls `go-ci.yml` twice, as for a nested module, can set `run-policy: false` on the second call.

| Run | Policy job |
|-----|-----------|
| No `.otfabric/policy.yaml` | Skips, with a notice |
| Pull request from a fork | Skips, with a notice |
| Dependabot, no token | Skips, with a notice |
| Any other run, no token | Fails: pass the secret, or set `run-policy: false` |

Fork and Dependabot runs never receive Actions secrets. Any other run without the token has a caller that forgot it, and skipping would turn the gate off unnoticed.

### go-package-release.yml

| Input | Default | Description |
|-------|---------|-------------|
| `bump` | *(required)* | `patch`, `minor`, or `major` |
| `update-major-tag` | `false` | Maintain a moving `v1`-style tag |
| `release-name-prefix` | `""` | Prefix for the GitHub Release title |
| `test-exclude-regex` | `(/examples($\|/)\|/cmd($\|/))` | Packages left out of the release tests (`grep -Ev`) |
| `module-dir` | `.` | Module to release; a nested module's tags carry the directory as prefix (`sub/v0.3.0`) |
| `api-compatibility` | `enforce` | `enforce` stops before tagging on `incompatible` or `error`; `report` records and releases ([API compatibility gate](#api-compatibility-gate)) |
| `gorelease-version` | `v0.0.0-20261014143641-f0251eb4aa3e` | Exact version of `golang.org/x/exp/cmd/gorelease`; never `latest` |
| `gorelease-go-version` | `1.26` | Lowest Go minor that builds that gorelease; the newer of this and the module's `go` line is used |
| `consumers` | `""` | Dependants built, vetted and tested against the candidate before tagging, one `owner/repo[:dir]` per line |

### go-binary-release.yml

| Input | Default | Description |
|-------|---------|-------------|
| `bump` | *(required)* | `patch`, `minor`, `major`, or `none` |
| `binary-name` | *(required)* | Output binary base name |
| `main-path` | *(required)* | Path to the main package |
| `targets` | All 7 OS/arch combos | JSON array of build targets |
| `ldflags` | `""` | Build ldflags with `${VERSION}`, `${TAG}`, `${COMMIT}`, `${BUILD_DATE}` substitution |
| `run-tests` | `true` | Disable when chaining after package release |
| `cgo-enabled` | `false` | Enable CGO for compilation |

## Workflow outputs

Both release workflows expose outputs for downstream chaining:

| Output | Example | Available in |
|--------|---------|--------------|
| `version` | `1.2.3` | Package, Binary |
| `tag` | `v1.2.3` | Package, Binary |
| `previous-tag` | `v1.2.2` | Package, Binary |
| `api-result` | `pass` | Package |

## Required secrets

| Secret | Scope | Purpose |
|--------|-------|---------|
| `OTFABRIC_READ_TOKEN` | All workflows | PAT with read access to private `github.com/otfabric/*` modules, including `otfabric/engineering` |

The workflows also use the automatic `GITHUB_TOKEN` for creating releases and uploading assets. No additional configuration is needed for that.
