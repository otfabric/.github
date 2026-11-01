# Reusable Go Workflows

Shared [reusable workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows) for Go projects across the **otfabric** organisation.

The `OTFABRIC_READ_TOKEN` secret gives access to private `github.com/otfabric/*` modules. In `go-ci.yml` it is needed when a module has private dependencies, and by the policy job when `.otfabric/policy.yaml` exists. The token must be able to read `otfabric/engineering`.

**Permissions.** The organisation's default `GITHUB_TOKEN` is read-only, and a caller must grant at least what a called workflow requests, or the run fails at startup with no job started. Grant `contents: read` and `id-token: write` for `go-ci.yml` (Codecov OIDC), and `contents: write` for the release workflows.

**Versions.** `v3` turns on govulncheck, tests `cmd/`, uses atomic coverage and starts the matrix at the go directive. `v2` and `v2.1.0` were moved to the same commit by the maintainer on 2026-10-30, so they have these defaults too.

**Selftest.** [`selftest.yml`](selftest.yml) tests these workflows on the fixtures in `testdata/` on every change. Add a case when you change behaviour.

## Workflows

Reusable workflows share whole pipelines (the caller's job is `uses:` one of these). For building blocks that run as steps inside a repository's own jobs, see the composite actions in [`actions/`](../../actions/README.md).

| Workflow | Purpose |
|----------|---------|
| [`go-ci.yml`](go-ci.yml) | Lint, static analysis, coverage, and multi-version test matrix |
| [`go-package-release.yml`](go-package-release.yml) | Semver-tagged release for Go libraries / packages |
| [`go-binary-release.yml`](go-binary-release.yml) | Cross-compiled binary release with SHA-256 checksums |

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

## Release notes via RELEASE.md

Both release workflows support an optional `RELEASE.md` file in the repo root. When a section matching the new tag is found, its content is used as the GitHub Release body. Otherwise a commit-log changelog is generated automatically.

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

## Required secrets

| Secret | Scope | Purpose |
|--------|-------|---------|
| `OTFABRIC_READ_TOKEN` | All workflows | PAT with read access to private `github.com/otfabric/*` modules, including `otfabric/engineering` |

The workflows also use the automatic `GITHUB_TOKEN` for creating releases and uploading assets. No additional configuration is needed for that.
