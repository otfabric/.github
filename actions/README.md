# Composite actions

Building blocks that run as **steps inside a repository's own jobs**. Use them
where the repositories share some steps but their jobs differ. Where a whole
pipeline is the same everywhere, use a reusable workflow instead
([`.github/workflows/`](../.github/workflows/README.md)).

## Upstream check (`*-interop` repositories)

Every `*-interop` repository has a daily `Upstream` workflow
(`.github/workflows/upstream.yml`). It compares the repository's pins with the
latest upstream and keeps one tracking issue, "Upstream releases: pins behind
the latest", up to date. Each repository writes its own candidate jobs (how to
build and test a stack differs per repository) and uses these actions for the
shared parts:

| Action | Purpose |
|--------|---------|
| `otfabric/.github/actions/upstream-images@main` | One row per base image pinned by digest (Dockerfiles, YAML): has its tag moved? |
| `otfabric/.github/actions/upstream-row@main` | One row for a library / commit / tool pin (pin, latest, candidate test) |
| `otfabric/.github/actions/upstream-candidate@main` | Builds and tests a candidate once per pin → latest pair (cached across daily runs) |
| `otfabric/.github/actions/upstream-report@main` | Table in the Job Summary; opens / updates / comments on / closes the issue (needs `issues: write`) |

A row is a JSON file `row-*.json` in an artifact named `upstream-row-*` with the fields
`component, kind, source, pinned, latest, status (current|behind|info|error), detail,
test_outcome, test_result, test_cached, known`. A repository may also write rows
itself, with `upstream-lib/upstream.py row ...` or its own script.

Examples: [modbus-interop](https://github.com/otfabric/modbus-interop/blob/main/.github/workflows/upstream.yml)
(matrix with candidate tests), [canopen-interop](https://github.com/otfabric/canopen-interop/blob/main/.github/workflows/upstream.yml)
(pins only, rows written by its own script).
