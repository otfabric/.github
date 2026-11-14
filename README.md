# otfabric/.github

Shared GitHub configuration of the OT Fabric organisation.

| Path | What |
|---|---|
| [`.github/workflows/`](.github/workflows/README.md) | Reusable workflows: `go-ci.yml`, `docs-check.yml`, `pr-changes.yml`, `go-package-release.yml`, `go-binary-release.yml` |
| [`actions/`](actions/README.md) | Composite actions: `required-gate` (the required check of a PR workflow), and the upstream check of the `*-interop` repositories |
| `profile/` | The organisation profile page |
| `scripts/selftest/`, `testdata/` | Selftest of the workflows (`selftest.yml`) |

Reference a workflow by release tag: `@v3.1.0`, or the floating `@v2` / `@v3`. `v1` is an old workflow tag.
