# Reusable Go Workflows

Shared [reusable workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows) for Go projects across the **otfabric** organisation.

All repositories are private. Every workflow requires the `OTFABRIC_READ_TOKEN` secret for access to private `github.com/otfabric/*` modules.

## Workflows

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
    uses: otfabric/.github/.github/workflows/go-ci.yml@main
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
    uses: otfabric/.github/.github/workflows/go-package-release.yml@main
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
    uses: otfabric/.github/.github/workflows/go-binary-release.yml@main
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
    uses: otfabric/.github/.github/workflows/go-package-release.yml@main
    with:
      bump: ${{ inputs.bump }}
    secrets:
      OTFABRIC_READ_TOKEN: ${{ secrets.OTFABRIC_READ_TOKEN }}

  binary:
    needs: package
    uses: otfabric/.github/.github/workflows/go-binary-release.yml@main
    with:
      bump: none
      binary-name: myapp
      main-path: ./cmd/myapp
      run-tests: false
    secrets:
      OTFABRIC_READ_TOKEN: ${{ secrets.OTFABRIC_READ_TOKEN }}
```

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
| `go-versions` | `["1.23","1.24","1.25","1.26"]` | Go versions for the test matrix |
| `golangci-lint-version` | `v2.1.6` | Pinned linter version |
| `test-exclude-regex` | `(/examples($\|/)\|/cmd($\|/))` | Packages to skip during testing |
| `codecov-name` | `""` | Set to enable Codecov upload |

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
| `OTFABRIC_READ_TOKEN` | All workflows | PAT with read access to private `github.com/otfabric/*` modules |

The workflows also use the automatic `GITHUB_TOKEN` for creating releases and uploading assets. No additional configuration is needed for that.
