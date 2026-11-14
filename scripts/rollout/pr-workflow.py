#!/usr/bin/env python3
"""Plan and prepare the move of OT Fabric repositories to the PR workflow.

    pr-workflow.py plan  <workspace> [--profile P] [--format md|json]
    pr-workflow.py apply <repository> [--ref REF] [--write]

plan reads every checkout in a workspace (one directory per repository, as
otfabric/engineering scripts/audit-inventory.sh clones them) and reports, per
profile, which repositories already have the PR workflow, which can be
prepared automatically, which need a person, and why. It changes nothing.

apply prepares one repository: the heavy workflows lose their push and
pull_request triggers and gain workflow_call and workflow_dispatch, the light
ones (docs-check, otfabric-policy) keep the push to the default branch, and a
new .github/workflows/pr.yml calls them all and ends in the gate. Without
--write it prints the plan and the new pr.yml and writes nothing. It refuses
a repository that needs a person, and does nothing to one that already has
the gate, so running it twice is safe. It never commits, pushes or opens a
pull request.

Workflows are read as text, not as YAML, and only the patterns below are
handled; anything else is reported for a person to look at. Standard library
only.
"""
import argparse
import json
import os
import re
import sys

GATE_NAME = "OT Fabric Required Checks"
HERE = os.path.dirname(os.path.abspath(__file__))
SIMPLE_TRIGGERS = {"push", "pull_request", "workflow_dispatch"}
# A converted workflow that reads one of these behaved differently on push
# and pull_request, or on main: it now always runs as the caller's event.
EVENT_EXPRESSIONS = re.compile(
    r"github\.event_name|github\.ref\b|github\.ref_name|github\.head_ref|github\.base_ref"
    r"|github\.event\.(before|after|head_commit|commits|pull_request)")
MD_LITERAL = re.compile(r'"([^"\s]+\.md)"|//go:embed\s+(\S+\.md)')
PROFILE_NOTES = {
    "protocol-library": "Go CI and independent interop are mandatory",
    "foundational-transport": "Go CI is mandatory; interop where a workflow exists",
    "cli": "Go CI is mandatory; interop where a workflow exists",
    "interoperability": "the harness's own build and adapter tests; no go-ci",
    "information-model": "Go CI; no interop",
    "application": "the application's CI",
    "website": "the site's build and checks, if any; no Go CI",
    "infrastructure": "repository specific; decide by hand",
}


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def load_exceptions():
    out = {}
    path = os.path.join(HERE, "exceptions.txt")
    if os.path.exists(path):
        for line in read(path).splitlines():
            line = line.strip()
            if line and not line.startswith("#") and ":" in line:
                repo, reason = line.split(":", 1)
                out[repo.strip()] = reason.strip()
    return out


def profile_of(repo):
    path = os.path.join(repo, ".otfabric", "policy.yaml")
    if os.path.exists(path):
        m = re.search(r"^profile:\s*['\"]?([\w-]+)", read(path), re.M)
        if m:
            return m.group(1)
    return "unknown"


def on_block(text):
    """(start, end, triggers) of the top-level `on:` block; triggers maps a
    trigger name to its body text. None when there is no block form."""
    lines = text.splitlines(keepends=True)
    for i, line in enumerate(lines):
        if re.match(r"^['\"]?on['\"]?:\s*(#.*)?$", line):
            break
        if re.match(r"^['\"]?on['\"]?:\s*\S", line):
            return None  # on: push / on: [push, pull_request]
    else:
        return None
    j = i + 1
    while j < len(lines) and (not lines[j].strip() or lines[j].startswith((" ", "#"))):
        j += 1
    # Leave trailing blank and comment lines to whatever follows.
    while j > i + 1 and (not lines[j - 1].strip() or lines[j - 1].lstrip().startswith("#")):
        j -= 1
    body = lines[i + 1:j]
    indent = min((len(l) - len(l.lstrip()) for l in body if l.strip() and not l.lstrip().startswith("#")), default=2)
    triggers, current = {}, None
    for l in body:
        m = re.match(r"^ {%d}([a-z_]+):" % indent, l)
        if m:
            current = m.group(1)
            triggers[current] = l
        elif current:
            triggers[current] += l
    start = sum(len(l) for l in lines[:i])
    return start, start + sum(len(l) for l in lines[i:j]), triggers


def top_level_block(text, key):
    m = re.search(r"^%s:.*\n((?:[ #].*\n|\n)*)" % key, text, re.M)
    return m.group(0).rstrip() if m else None


def classify_workflow(path, default_branch):
    """A dict: kind (light, heavy, keep, manual), why, and for heavy and light
    the replacement `on:` block."""
    text = read(path)
    name = os.path.basename(path)
    w = {"file": name, "text": text, "notes": []}
    block = on_block(text)
    if block is None:
        w.update(kind="manual", why="no `on:` block in a form this tool reads")
        return w
    _, _, triggers = block
    w["triggers"] = sorted(triggers)
    if "workflow_call" in triggers and "pull_request" not in triggers and "push" not in triggers:
        w.update(kind="keep", why="already reusable; called from elsewhere")
        return w
    if "pull_request" not in triggers and "push" not in triggers:
        w.update(kind="keep", why="not triggered by push or pull_request: " + ", ".join(sorted(triggers)))
        return w
    push = triggers.get("push", "")
    pr = triggers.get("pull_request", "")
    if re.search(r"^\s+tags(-ignore)?:", push, re.M):
        w.update(kind="keep", why="push of tags (a release); left as is")
        return w
    if re.search(r"codeql|github/codeql-action", text):
        w.update(kind="keep", why="code scanning keeps its default-branch analysis; left as is")
        return w
    light = "docs-check.yml@" in text or re.fullmatch(r"policy\.ya?ml", name) is not None
    reasons = []
    extra = set(triggers) - SIMPLE_TRIGGERS
    if extra:
        reasons.append("other triggers: " + ", ".join(sorted(extra)))
    if re.search(r"^\s+inputs:", triggers.get("workflow_dispatch", ""), re.M):
        reasons.append("workflow_dispatch has inputs, which workflow_call would need too")
    for trig in (push, pr):
        if re.search(r"^\s+paths:", trig, re.M):
            reasons.append("a `paths:` filter: in pr.yml it would run on every code pull request")
            break
        if re.search(r"^\s+paths-ignore:", trig, re.M) and not re.search(r"paths-ignore:\s*\[\s*['\"]\*\*/\*\.md['\"]\s*\]", trig):
            reasons.append("a paths-ignore filter other than Markdown")
            break
    if top_level_block(text, "concurrency"):
        reasons.append("its own concurrency group may equal pr.yml's (github.workflow is the caller's name)")
    if not light:
        # run-name is ignored when the workflow is called.
        m = EVENT_EXPRESSIONS.search(re.sub(r"^run-name:.*$", "", text, flags=re.M))
        if m:
            reasons.append(f"reads {m.group(0)}, which is the caller's pull_request event once called")
    if reasons:
        w.update(kind="manual", why="; ".join(reasons))
        return w
    if light:
        w.update(kind="light", on=f"on:\n  push:\n    branches: [{default_branch}]\n  workflow_call:\n  workflow_dispatch:\n")
        w["why"] = "light check: runs on every pull request and every push to " + default_branch
        if "push" not in triggers:
            w["on"] = "on:\n  workflow_call:\n  workflow_dispatch:\n"
    else:
        w.update(kind="heavy", on="on:\n  workflow_call:\n  workflow_dispatch:\n",
                 why="heavy: once per pull request revision, not on branch pushes or main")
    return w


def job_id(name):
    stem = re.sub(r"\.ya?ml$", "", name)
    return re.sub(r"[^A-Za-z0-9_-]", "-", stem).strip("-") or "job"


def permissions_lines(text):
    block = top_level_block(text, "permissions")
    if not block:
        return None
    first, *rest = block.splitlines()
    inline = first.split(":", 1)[1].strip()
    if inline:
        return [f"    permissions: {inline}"]
    return ["    permissions:"] + ["    " + l for l in rest if l.strip() and not l.lstrip().startswith("#")]


def needs_secrets(text):
    return "secrets: inherit" in text or re.search(r"secrets\.(?!GITHUB_TOKEN\b)\w+", text) is not None


def suggest_code_paths(repo):
    """Markdown that Go code names by a literal path relative to its package,
    or embeds: a test or generator reads it, so it counts as code."""
    found = set()
    for root, dirs, files in os.walk(repo):
        dirs[:] = [d for d in dirs if not d.startswith(".") and d not in ("vendor", "node_modules")]
        for f in files:
            if not f.endswith(".go"):
                continue
            try:
                text = read(os.path.join(root, f))
            except (OSError, UnicodeDecodeError):
                continue
            for m in MD_LITERAL.finditer(text):
                rel = m.group(1) or m.group(2)
                path = os.path.normpath(os.path.join(root, rel))
                if os.path.isfile(path) and "testdata" not in path.split(os.sep):
                    found.add(os.path.relpath(path, repo).replace(os.sep, "/"))
    return sorted(found)


def default_branch_of(repo):
    head = os.path.join(repo, ".git", "refs", "remotes", "origin", "HEAD")
    if os.path.isfile(head):
        m = re.search(r"refs/remotes/origin/(\S+)", read(head))
        if m:
            return m.group(1)
    return "main"


def analyse(repo, exceptions):
    name = os.path.basename(os.path.normpath(repo))
    wdir = os.path.join(repo, ".github", "workflows")
    files = sorted(f for f in os.listdir(wdir) if f.endswith((".yml", ".yaml"))) if os.path.isdir(wdir) else []
    r = {"repo": name, "profile": profile_of(repo), "workflows": [], "status": None, "why": []}
    if name in exceptions:
        r.update(status="excepted", why=[exceptions[name]])
        return r
    if "pr.yml" in files and "required-gate@" in read(os.path.join(wdir, "pr.yml")):
        r.update(status="migrated", why=["pr.yml with the gate"])
        return r
    if "pr.yml" in files:
        r.update(status="manual", why=["a pr.yml without the gate exists"])
        return r
    branch = default_branch_of(repo)
    for f in files:
        r["workflows"].append(classify_workflow(os.path.join(wdir, f), branch))
    heavy = [w for w in r["workflows"] if w["kind"] == "heavy"]
    light = [w for w in r["workflows"] if w["kind"] == "light"]
    manual = [w for w in r["workflows"] if w["kind"] == "manual"]
    if not heavy and not light and not manual:
        r.update(status="no-ci", why=["no workflow runs on push or pull_request"])
    elif manual:
        r.update(status="manual", why=[f"{w['file']}: {w['why']}" for w in manual])
    elif not light:
        r.update(status="manual", why=["no light check (docs.yml or policy.yml) to run on every pull request"])
    else:
        r.update(status="ready", why=[])
    if r["profile"] == "protocol-library" and not any("interop" in w["file"] for w in r["workflows"]):
        r["why"].append("protocol-library without an interop workflow")
    if r["profile"] == "unknown":
        r["why"].append("no .otfabric/policy.yaml profile")
    r["code_paths"] = suggest_code_paths(repo) if r["status"] in ("ready", "manual") else []
    return r


def render_pr_yml(r, ref):
    jobs, required, for_code = [], ["changes"], []
    changes = [f"  changes:\n    uses: otfabric/.github/.github/workflows/pr-changes.yml@{ref}\n"]
    if r["code_paths"]:
        changes.append("    with:\n      # Go code reads these Markdown files: they count as code.\n      code-paths: |\n")
        changes += [f"        {p}\n" for p in r["code_paths"]]
    jobs.append("".join(changes))
    for w in r["workflows"]:
        if w["kind"] not in ("light", "heavy"):
            continue
        jid = job_id(w["file"])
        while jid in required + for_code or jid in ("changes", "required"):
            jid += "-wf"
        lines = [f"  {jid}:"]
        if w["kind"] == "heavy":
            lines += ["    needs: changes", "    if: needs.changes.outputs.full == 'true'"]
            for_code.append(jid)
        else:
            required.append(jid)
        perms = permissions_lines(w["text"])
        if perms:
            lines += perms
        lines.append(f"    uses: ./.github/workflows/{w['file']}")
        if needs_secrets(w["text"]):
            lines.append("    secrets: inherit")
        jobs.append("\n".join(lines) + "\n")
    names = ", ".join(required + for_code)
    gate = (f"  required:\n    name: {GATE_NAME}\n    needs: [{names}]\n    if: always()\n"
            f"    runs-on: ubuntu-latest\n    timeout-minutes: 5\n    steps:\n"
            f"      - uses: otfabric/.github/actions/required-gate@{ref}\n        with:\n"
            "          needs: ${{ toJSON(needs) }}\n"
            f"          required: {' '.join(required)}\n")
    if for_code:
        gate += f"          required-for-code: {' '.join(for_code)}\n"
    head = ("# The pull request gate (otfabric/.github PR workflow), generated by\n"
            "# otfabric/.github scripts/rollout/pr-workflow.py. No path filter: the light\n"
            "# checks always run, the heavy ones unless the change is documentation only,\n"
            f'# then "{GATE_NAME}", the only check a ruleset requires.\n'
            "name: PR\non:\n  pull_request:\n\npermissions:\n  contents: read\n\n"
            "concurrency:\n  group: ${{ github.workflow }}-${{ github.event.pull_request.number }}\n"
            "  cancel-in-progress: true\n\njobs:\n")
    return head + "\n".join(jobs) + "\n" + gate


def cmd_plan(args):
    exceptions = load_exceptions()
    repos = []
    for d in sorted(os.listdir(args.workspace)):
        path = os.path.join(args.workspace, d)
        if d.startswith((".", "_")) or not os.path.isdir(os.path.join(path, ".git")):
            continue
        r = analyse(path, exceptions)
        if args.profile and r["profile"] != args.profile:
            continue
        for w in r["workflows"]:
            w.pop("text", None)
            w.pop("on", None)
        repos.append(r)
    if args.format == "json":
        json.dump(repos, sys.stdout, indent=1)
        print()
        return 0
    order = ["migrated", "ready", "manual", "no-ci", "excepted"]
    print(f"# PR workflow rollout plan ({len(repos)} repositories)\n")
    print("| Profile | " + " | ".join(order) + " |\n|---|" + "---:|" * len(order))
    profiles = sorted({r["profile"] for r in repos})
    for p in profiles:
        counts = [sum(1 for r in repos if r["profile"] == p and r["status"] == s) for s in order]
        print(f"| {p} | " + " | ".join(map(str, counts)) + " |")
    for p in profiles:
        print(f"\n## {p}\n\n{PROFILE_NOTES.get(p, '')}\n")
        print("| Repository | Status | Heavy | Light | Kept | Notes |\n|---|---|---|---|---|---|")
        for r in (r for r in repos if r["profile"] == p):
            k = lambda kind: ", ".join(w["file"] for w in r["workflows"] if w["kind"] == kind) or "-"
            notes = "; ".join(r["why"] + ([f"code-paths? {', '.join(r['code_paths'])}"] if r.get("code_paths") else []))
            print(f"| {r['repo']} | {r['status']} | {k('heavy')} | {k('light')} | {k('keep')} | {notes.replace('|', '/')} |")
    return 0


def cmd_apply(args):
    r = analyse(args.repository, load_exceptions())
    print(f"{r['repo']} ({r['profile']}): {r['status']}")
    for why in r["why"]:
        print(f"  - {why}")
    if r["status"] != "ready":
        print("nothing to do" if r["status"] in ("migrated", "no-ci", "excepted") else "needs a person: nothing written")
        return 0 if r["status"] in ("migrated", "no-ci", "excepted") else 3
    wdir = os.path.join(args.repository, ".github", "workflows")
    for w in r["workflows"]:
        if w["kind"] in ("light", "heavy"):
            print(f"  {w['file']}: {w['kind']}, triggers {', '.join(w['triggers'])} -> "
                  f"{', '.join(re.findall(r'^  ([a-z_]+):', w['on'], re.M))}")
        else:
            print(f"  {w['file']}: {w['kind']} ({w['why']})")
    if r["code_paths"]:
        print("  code-paths (Go code reads these; check them): " + ", ".join(r["code_paths"]))
    pr = render_pr_yml(r, args.ref)
    if not args.write:
        print("\n--- .github/workflows/pr.yml (dry run, not written)\n" + pr)
        return 0
    for w in r["workflows"]:
        if w["kind"] in ("light", "heavy"):
            start, end, _ = on_block(w["text"])
            with open(os.path.join(wdir, w["file"]), "w", encoding="utf-8") as f:
                f.write(w["text"][:start] + w["on"] + w["text"][end:])
    with open(os.path.join(wdir, "pr.yml"), "w", encoding="utf-8") as f:
        f.write(pr)
    print("written; review the diff, then branch, commit and open a draft pull request")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("plan")
    p.add_argument("workspace")
    p.add_argument("--profile")
    p.add_argument("--format", choices=["md", "json"], default="md")
    a = sub.add_parser("apply")
    a.add_argument("repository")
    a.add_argument("--ref", default="v3.7.0", help="otfabric/.github ref for pr-changes.yml and required-gate")
    a.add_argument("--write", action="store_true", help="write the files (default: dry run)")
    args = ap.parse_args()
    return cmd_plan(args) if args.cmd == "plan" else cmd_apply(args)


if __name__ == "__main__":
    sys.exit(main())
