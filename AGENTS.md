# AGENTS.md — otfabric/.github

## What this is

The organisation's shared GitHub configuration: the reusable workflows `go-ci.yml`, `go-package-release.yml` and `go-binary-release.yml`, the composite actions for the `*-interop` repositories, the organisation profile page, and the selftest of the workflows. There is no product and no Go module of its own; the Go code under `testdata/` is fixtures. Every OT Fabric repository depends on this one, so a mistake here reaches all of them. Profile: **infrastructure**.

## Organisation standards

This repository follows **otfabric/engineering policy 1.1**, profile **infrastructure** (`.otfabric/policy.yaml`, mode `enforce`). Organisation skills come from the `otfabric` plugin (maintainer's user settings). Local exceptions: `.otfabric/exceptions.yaml` (none today). Where this file and the organisation standards disagree, this file wins for this repository — say so in your report.

## Where the truth lives

| Question | Source |
|---|---|
| What each workflow does, its inputs, permissions, versions | `.github/workflows/README.md` |
| The composite actions | `actions/README.md` |
| What the workflows are tested against | `.github/workflows/selftest.yml`, `testdata/`, `scripts/selftest/` |
| Why the selftest exists | ADR-0008 in otfabric/engineering |
| The organisation profile page | `profile/README.md` |

## Hard rules

1. Callers pin workflows by tag (`@v3.2.0`, or the floating `@v2`, `@v3`) but actions by `@main`: a merge reaches every interop repository's next run of an action, and the next tag reaches every Go repository. Treat a merge as a release.
2. A change to an input, default, job name or permission of a shared workflow is a change for every caller. Keep behaviour unchanged unless the maintainer asked for the change.
3. A behaviour change adds a selftest case. A failing case runs the exact step script, extracted from the workflow by `scripts/selftest/extract-step.py`, never a copy.
4. Tools stay pinned to exact versions; shared workflows stay on least-privilege `permissions`.
5. `go-ci.yml` runs its policy job at the repository root and fails a same-repository run without `OTFABRIC_READ_TOKEN` once `.otfabric/policy.yaml` exists. So every selftest job that leaves `run-policy` on passes the token.
6. Selftest runs on pull requests only for the paths it lists, and always on push to `main`. A green pull request says nothing about Selftest when it touched none of them: think about what `main` will do.

## Commands

| When you change… | Run |
|---|---|
| anything | `go run ./cmd/otfabric-policy check <this repository>` from otfabric/engineering |
| `go-ci.yml` policy steps | `scripts/selftest/policy.sh` |
| release notes extraction | `scripts/selftest/release-notes.sh` |
| a workflow | the Selftest workflow, on the pull request |

There is no Makefile.

## Definition of Done

- Selftest green on the pull request, and a case added for new behaviour.
- `.github/workflows/README.md` or `actions/README.md` updated in the same change.
- Failing or skipped steps reported explicitly.

## Git and releases

Work on a branch and open a PR. Do not push to `main`, create or move tags, or change organisation settings unless the maintainer asks for it in the session. Tags, including the floating `v2` and `v3`, are the maintainer's.
