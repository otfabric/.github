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
- **kept**: schedule, dispatch, tag-push releases, code scanning, workflows that are already reusable.

A repository is `manual` when a workflow has:

- other triggers;
- `workflow_dispatch` inputs;
- a `paths:` filter (in `pr.yml` it would run on every code pull request);
- its own `concurrency` group (`github.workflow` is the caller's name, so a group of the same form deadlocks);
- an expression that reads the event or ref (`github.ref`, `github.event_name`, `github.event.pull_request`…), which once the workflow is called is always the caller's `pull_request` event.

`plan` also suggests `code-paths`: Markdown that Go code names by a path relative to its package, or embeds.

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

1. Update the repository's TESTING.md/CONTRIBUTING.md ("When CI runs", as in go-mms).
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
