# Rollout of the PR workflow

`pr-workflow.py` moves repositories to the PR workflow
([`.github/workflows/README.md`](../../.github/workflows/README.md#pr-workflow-and-the-required-check)):
heavy validation once per pull request revision, one required check, `OT Fabric
Required Checks`. It plans for the whole organisation and prepares one
repository at a time. It never commits, pushes, opens a pull request or
touches a ruleset. Standard library only; `scripts/selftest/rollout.sh` tests it.

## Plan

```bash
# A fresh workspace: one shallow clone per repository (otfabric/engineering).
scripts/audit-inventory.sh /tmp/otfabric-ws
python3 scripts/rollout/pr-workflow.py plan /tmp/otfabric-ws > plan.md
python3 scripts/rollout/pr-workflow.py plan /tmp/otfabric-ws --profile cli --format json
```

Per repository, from its `.otfabric/policy.yaml` profile and its workflow files:

| Status | Meaning |
|---|---|
| `migrated` | `pr.yml` uses `required-gate` |
| `ready` | every workflow is a known pattern: `apply` can prepare it |
| `manual` | a person decides; the notes say why |
| `no-ci` | no workflow runs on push or pull request: nothing to gate |
| `excepted` | listed in [`exceptions.txt`](exceptions.txt), with the reason |

Workflows are sorted into:

- **heavy**: `push`/`pull_request` workflows. They become `workflow_call` + `workflow_dispatch` and run in `pr.yml` unless the change is documentation only.
- **light**: `docs-check.yml` callers and `policy.yml`. They keep the push to the default branch and run on every pull request.
- **kept**: schedule-only, dispatch-only, tag-push releases, pushes of other branches only (`soak/**`), code scanning, workflows that are already reusable.

What a converted workflow keeps:

- **A `schedule` trigger** stays next to `workflow_call`.
- **`workflow_dispatch` inputs** stay, and are repeated under `workflow_call` with their defaults (a `choice` becomes a `string`), so a called run behaves like a dispatch without arguments. `inputs.<name>` reads both.
- **A concurrency group with a name of its own** (`ci-${{ github.ref }}`) stays: in a called run the ref is the pull request's, and the name keeps it apart from the other called workflows.
- **Permissions:** the calling job in `pr.yml` grants the workflow's own permissions joined with those its jobs ask for. A called job may not ask for more than its caller grants, whether or not its `if:` lets it run.
- **Expressions that mean the same once called:** the guard against forks and Dependabot, and `github.event_name == 'schedule'`, `'workflow_dispatch'` or `'pull_request'`.

A repository is `manual` when a workflow has:

- triggers other than push, pull_request, schedule and dispatch;
- a required `workflow_dispatch` input without a default, or `github.event.inputs.<name>` (empty once called);
- a `paths:` filter (in `pr.yml` it would run on every code pull request);
- a `concurrency` group without a name of its own (`${{ github.workflow }}-…`: that is the caller's name once called, so two called workflows share the group and one cancels the other), or the same group as another called workflow;
- another expression that reads the event or ref (`github.ref == 'refs/heads/main'`, `github.event_name == 'push'`…), which once the workflow is called is always the caller's `pull_request` event;
- no light check at all.

Two refusals can be lifted per workflow file, after a person has read it:

| Flag | Lifts | Say in the pull request |
|---|---|---|
| `--paths-as-code FILE` | the `paths:` filter: the workflow runs on every pull request that is not documentation only, and no longer on the push to the default branch | what the filter covered |
| `--accept-events FILE` | the event or ref expressions | why each still holds when called |

`--code-path PATTERN` adds a `code-paths` pattern to the suggested ones, for Markdown a workflow generates or checks (`docs/reference/*`).

`plan` also suggests `code-paths`: Markdown that Go code names by a path relative to its package, or embeds. Check each suggestion.

The profile decides what must be gated, not the tool. The tool carries over what each repository already runs. So a website gets no Go CI, and an information model gets no interop.

## Prepare one repository

```bash
cd ../go-cotp && git switch -c ci/pr-required-gate
python3 ../.github/scripts/rollout/pr-workflow.py apply .            # dry run: plan and pr.yml
python3 ../.github/scripts/rollout/pr-workflow.py apply . --write    # rewrites the on: blocks, writes pr.yml
git diff                                                             # only on: blocks and the new pr.yml
(cd ../engineering && go run ./cmd/otfabric-policy check ../go-cotp)
```

Then, by hand:

1. Update the repository's TESTING.md/CONTRIBUTING.md ("When CI runs", as in go-mms), and every sentence that says CI runs "on every push".
   - Move the pins in the same change: `go-ci.yml`, `docs-check.yml` and the release workflows to the tag of `pr-changes.yml`, and the checker to the tag the policy pin needs.
   - otfabric-policy runs in the light check. Set `run-policy: false` on the go-ci calls, or it runs twice on a pull request and never on `main`.
   - A repository-local `policy.yml` must not skip its only job for a fork or Dependabot pull request: a skipped job fails the required check. Skip the steps instead, with a notice, as go-ci and docs-check do.
   - Do not commit what a local build left behind: `go build ./...` writes a binary into a module that holds a single main package.
2. Commit, push, and open a **draft** pull request.
3. On that pull request, check:
   - `OT Fabric Required Checks` reports, with that exact name;
   - its summary lists every job;
   - the push of the branch started no run.
4. Open a disposable stacked pull request that changes one document. It must classify as documentation only and pass, with the heavy jobs skipped. Close it.
5. Mark the pull request ready. The maintainer merges it.

A second `apply` on a prepared repository reports `migrated` and changes nothing. `apply` exits 3 and writes nothing when the repository needs a person.

## Order

Pilot one repository per profile before any broad adoption. Representatives, from the plan of 2026-11-14 (local workspace):

The rollout of 2026-11-14 went through every repository on otfabric.io/projects in dependency order; otfabric/engineering `docs/adoption/pr-only-ci.md` has the result. The table below is the plan it started from.

| Profile | Pilot | Status then |
|---|---|---|
| protocol-library | go-mms, go-iec61850 | prepared by hand (pilot pull requests) |
| foundational-transport | go-cotp | ready |
| cli | a ready `*ctl` | ready (18 of 19) |
| interoperability | a ready `*-interop` | ready (3 of 18); most have tag-push releases or their own concurrency |
| information-model | go-iec61850-model | manual: `nsd.yml` has a `paths:` filter |
| application | iec61850-explorer | manual: own concurrency group |
| website | none | no CI to gate |
| infrastructure | engineering | manual |

Never mass-merge. One pull request per repository, reviewed and merged by the maintainer.

## Requiring the check

A repository joins the required-status-check ruleset only after its PR workflow is merged, and only once `OT Fabric Required Checks` has reported on a pull request after that merge. Otherwise every open pull request waits for a check that never comes. Add repositories to the ruleset by name, one change at a time. The commands are in the Phase 1 report.

## Rollback of one repository

1. Remove the repository from the ruleset's `repository_name.include` (or set the ruleset to `disabled`).
2. Revert the merge of its PR workflow pull request (`git revert -m 1 <merge>`). This restores the `push`/`pull_request` triggers and deletes `pr.yml`.
