# Composite actions

Building blocks that run as **steps inside a repository's own jobs**. Use them
where the repositories share some steps but their jobs differ. Where a whole
pipeline is the same everywhere, use a reusable workflow instead
([`.github/workflows/`](../.github/workflows/README.md)).

## Required check of a PR workflow

`otfabric/.github/actions/required-gate@v3.7.0` is the last job of a
repository's `pr.yml` and the only check a ruleset requires (see
[PR workflow and the required check](../.github/workflows/README.md#pr-workflow-and-the-required-check)).
Pin it by release tag, like the workflows it goes with.

```yaml
  required:
    name: OT Fabric Required Checks
    needs: [changes, docs, ci, interop]
    if: always()
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: otfabric/.github/actions/required-gate@v3.7.0
        with:
          needs: ${{ toJSON(needs) }}
          required: changes docs
          required-for-code: ci interop
```

| Input | Default | Description |
|-------|---------|-------------|
| `needs` | *(required)* | `${{ toJSON(needs) }}` of the gate job |
| `required` | *(required)* | Job ids that must succeed on every pull request; includes `changes-job` |
| `required-for-code` | `""` | Job ids that must succeed when the pull request is not documentation only, and be skipped (or succeed) when it is |
| `changes-job` | `changes` | The job that calls `pr-changes.yml`; its `full` output decides |

The gate fails on a failed, cancelled, unexpectedly skipped or malformed
result, on a listed job that is not in `needs`, on a job in `needs` that is
in neither list, and when the classification is missing or is neither
`"true"` nor `"false"`. Its job summary has one row per job. The logic is
[`required-gate/gate.py`](required-gate/gate.py), standard library only;
`scripts/selftest/required-gate.sh` runs it on every outcome.

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
