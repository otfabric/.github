#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Shared helpers of the Upstream workflow of the otfabric *-interop repositories.

    upstream.py row     --out DIR --component C [--kind K] [--source S] [--pinned P]
                        [--latest L] [--update yes|no|error] [--detail D]
                        [--test-outcome O] [--test-result R] [--test-cached yes|no]
                        [--known K]
    upstream.py images  --out DIR [--root .]
    upstream.py report  --rows DIR --needs JSON [--notes FILE] [--title T]

`row` writes one row of the pin-vs-latest table as JSON. `images` writes one
row per base image that the repository pins by digest (Dockerfiles, compose
and YAML files) and compares that digest with the one its tag points to now.
`report` renders every row as a Markdown table into the Job Summary and opens,
updates, comments on or closes the tracking issue. Pins are never changed.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

STATE_RE = re.compile(r"<!-- upstream-state: (.*?) -->")


# ---------------------------------------------------------------- row

def slug(text):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", text).strip("-").lower() or "row"


def write_row(out, row):
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, "row-%s.json" % slug(row["kind"] + "-" + row["component"]))
    with open(path, "w") as f:
        json.dump(row, f)
    return path


def cmd_row(a):
    update = (a.update or "").strip().lower()
    if a.detail and update not in ("yes", "no"):
        status = "error"
    else:
        status = {"yes": "behind", "no": "current"}.get(update, "error")
    detail = a.detail or ("" if status != "error" else "the upstream lookup did not finish")
    write_row(a.out, {
        "component": a.component, "kind": a.kind, "source": a.source or "",
        "pinned": a.pinned or "", "latest": a.latest or "", "status": status,
        "detail": detail, "test_outcome": a.test_outcome or "",
        "test_result": a.test_result or "", "test_cached": a.test_cached == "yes",
        "known": a.known or "",
    })


# ---------------------------------------------------------------- images

REF_RE = re.compile(r"((?:[a-z0-9][a-z0-9.-]*(?::[0-9]+)?/)?[a-z0-9][a-z0-9._/-]*:[A-Za-z0-9._-]+)@(sha256:[0-9a-f]{64})")


def tracked_files(root):
    out = subprocess.run(["git", "-C", root, "ls-files"], capture_output=True, text=True, check=True).stdout
    for path in out.splitlines():
        base = os.path.basename(path)
        if "Dockerfile" in base or base.endswith((".yml", ".yaml", ".dockerfile")):
            yield path


def substitute(line, args):
    return re.sub(r"\$\{(\w+)(?::?-[^}]*)?\}|\$(\w+)",
                  lambda m: args.get(m.group(1) or m.group(2), m.group(0)), line)


def pinned_refs(root):
    """{image:tag -> {digest -> [files]}} of every digest-pinned reference."""
    refs = {}
    for path in tracked_files(root):
        try:
            text = open(os.path.join(root, path), encoding="utf-8").read()
        except (UnicodeDecodeError, OSError):
            continue
        lines = text.splitlines()
        if "Dockerfile" in os.path.basename(path) or path.endswith(".dockerfile"):
            args, expanded = {}, []
            for line in lines:
                m = re.match(r"^\s*ARG\s+(\w+)=(\S+)", line, re.I)
                if m:
                    args[m.group(1)] = m.group(2).strip("\"'")
                expanded.append(substitute(line, args) if re.match(r"^\s*FROM\s", line, re.I) else line)
            lines = expanded
        for line in lines:
            if line.lstrip().startswith("#"):
                continue
            for m in REF_RE.finditer(line):
                # docker.io/library/x, mirror.gcr.io/library/x and x are one image.
                name = re.sub(r"^(?:docker\.io/|index\.docker\.io/|mirror\.gcr\.io/)?(?:library/)?", "", m.group(1))
                refs.setdefault(name, {}).setdefault(m.group(2), set()).add(path)
    return refs


def registry_of(name):
    first = name.split("/")[0]
    if "/" in name and ("." in first or ":" in first or first == "localhost"):
        return None, first  # explicit registry: ghcr.io, mcr.microsoft.com, quay.io, ...
    return "dockerhub", "Docker Hub"


def lookup(name):
    """Current index digest and the digests of its platform manifests."""
    kind, _ = registry_of(name)
    candidates = [name]
    if kind == "dockerhub":
        path = name if "/" in name else "library/" + name
        mirror = os.environ.get("BASE_REGISTRY", "mirror.gcr.io/library").rstrip("/")
        mirror_root = mirror[:-len("/library")] if mirror.endswith("/library") else mirror
        candidates = [mirror_root + "/" + path, "docker.io/" + path]
    err = ""
    for ref in candidates:
        for attempt in range(3):
            p = subprocess.run(["docker", "buildx", "imagetools", "inspect", ref, "--format", "{{json .Manifest}}"],
                               capture_output=True, text=True, timeout=180)
            if p.returncode == 0:
                m = json.loads(p.stdout)
                return m["digest"], {c.get("digest") for c in m.get("manifests") or []}
            err = (p.stderr.strip().splitlines() or ["inspect failed"])[-1][-160:]
    raise RuntimeError(err)


def short(digest):
    return digest.split(":")[-1][:12]


def cmd_images(a):
    refs = pinned_refs(a.root)
    for name in sorted(refs):
        _, registry = registry_of(name)
        for digest, files in sorted(refs[name].items()):
            where = sorted(files)
            source = "%s · %d file%s" % (registry, len(where), "" if len(where) == 1 else "s")
            row = {"component": name, "kind": "base image", "source": source,
                   "pinned": "@" + short(digest), "latest": "", "status": "error", "detail": "",
                   "test_outcome": "", "test_result": "", "test_cached": False,
                   "known": "", "files": where}
            try:
                current, platforms = lookup(name)
                row["latest"] = "@" + short(current)
                if digest == current or digest in platforms:
                    row["status"] = "current"
                else:
                    row["status"] = "behind"
                    row["detail"] = "tag moved, new digest " + current
            except Exception as e:  # report, do not fail the whole check
                row["detail"] = str(e)
            row["component"] = name if len(refs[name]) == 1 else "%s (%s)" % (name, short(digest))
            write_row(a.out, row)
            print("%-60s %-8s %s" % (row["component"], row["status"], row["detail"]))
    if not refs:
        print("No digest-pinned image references found.")


# ---------------------------------------------------------------- report

STATUS = {"behind": "⬆️ **behind**", "current": "✅ current", "error": "⚠️ error"}
ORDER = {"behind": 0, "error": 1, "current": 2}


def esc(text):
    return str(text).replace("|", "\\|").replace("\n", " ")


def code(text):
    return "`%s`" % esc(text) if text else "—"


def test_cell(r):
    o = r.get("test_outcome")
    if r["kind"] == "base image" and not o:
        return "—"
    if not o or o == "skipped":
        return "—" if r["status"] != "behind" else "not run"
    icon = {"success": "✅", "failure": "❌"}.get(o, "⚪")
    cell = "%s %s" % (icon, o)
    if r.get("test_result"):
        cell += "<br>" + esc(r["test_result"])
    if r.get("test_cached"):
        cell += "<br><sub>(cached)</sub>"
    return cell


def table(rows):
    lines = ["| Component | Kind | Source | Pinned | Latest | Status | Candidate test | Known bugs |",
             "|---|---|---|---|---|---|---|---|"]
    for r in rows:
        status = STATUS[r["status"]]
        if r.get("detail"):
            status += "<br><sub>%s</sub>" % esc(r["detail"])
        lines.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
            esc(r["component"]), esc(r["kind"]), esc(r["source"]) or "—", code(r["pinned"]),
            code(r["latest"]), status, test_cell(r), esc(r.get("known") or "") or "—"))
    return "\n".join(lines) + "\n"


def gh(*args, check=True):
    p = subprocess.run(["gh"] + list(args), capture_output=True, text=True)
    if check and p.returncode != 0:
        sys.exit("gh %s: %s" % (" ".join(args[:2]), p.stderr.strip()))
    return p.stdout


def cmd_report(a):
    rows = []
    for path in sorted(glob.glob(os.path.join(a.rows, "**", "row-*.json"), recursive=True)):
        with open(path) as f:
            rows.append(json.load(f))
    rows.sort(key=lambda r: (ORDER[r["status"]], r["kind"] == "base image", r["component"].lower()))
    needs = json.loads(a.needs or "{}")
    broken = sorted(n for n, j in needs.items() if j.get("result") not in ("success", "skipped"))
    behind = [r for r in rows if r["status"] == "behind"]
    errors = [r for r in rows if r["status"] == "error"]
    complete = not broken and not errors and bool(rows)
    run_url = "%s/%s/actions/runs/%s" % (os.environ.get("GITHUB_SERVER_URL", "https://github.com"),
                                         os.environ.get("GITHUB_REPOSITORY", ""), os.environ.get("GITHUB_RUN_ID", ""))
    notes = open(a.notes).read().strip() if a.notes and os.path.exists(a.notes) else ""

    headline = "**%d behind**, %d error%s, %d current" % (
        len(behind), len(errors), "" if len(errors) == 1 else "s", len(rows) - len(behind) - len(errors))
    body = ["## Upstream check: " + headline, "",
            "Pins were **not** changed. Every row is a pin of this repository compared with the "
            "latest upstream release, commit or base-image digest.", ""]
    if broken:
        body += ["> [!WARNING]", "> Job%s %s did not succeed: the table may be incomplete." % (
            "s" if len(broken) > 1 else "", ", ".join("`%s`" % b for b in broken)), ""]
    body += [table(rows) if rows else "_No rows: every job failed before writing one._\n"]
    if notes:
        body += ["", notes]
    summary = "\n".join(body) + "\n"
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as f:
            f.write(summary)
    print(summary)

    if a.no_issue:
        return 0 if complete else 1
    title = a.title
    found = json.loads(gh("issue", "list", "--state", "open", "--search", '"%s" in:title' % title,
                          "--json", "number,title,body"))
    issue = next((i for i in found if i["title"] == title), None)
    state = sorted("%s@%s" % (r["component"], r["latest"]) for r in behind)
    if behind:
        gh("label", "create", "upstream", "--color", "0E8A16",
           "--description", "Upstream release or base image newer than the pin", check=False)
        text = "\n".join([
            "The daily [Upstream workflow](%s) found pins of this repository behind the latest upstream." % run_url,
            "", table(rows), notes, "",
            "_Updated by every run of the Upstream workflow; a comment is added when a new upstream "
            "version shows up, and the issue is closed once every pin is current._",
            "<!-- upstream-state: %s -->" % json.dumps(state)]) + "\n"
        with open("upstream-issue.md", "w") as f:
            f.write(text)
        if issue:
            m = STATE_RE.search(issue.get("body") or "")
            before = set(json.loads(m.group(1))) if m else set()
            gh("issue", "edit", str(issue["number"]), "--body-file", "upstream-issue.md", "--add-label", "upstream")
            new = [r for r in behind if "%s@%s" % (r["component"], r["latest"]) not in before]
            if new:
                with open("upstream-comment.md", "w") as f:
                    f.write("New upstream version%s found by [this run](%s):\n\n%s" % (
                        "s" if len(new) > 1 else "", run_url, table(new)))
                gh("issue", "comment", str(issue["number"]), "--body-file", "upstream-comment.md")
            print("Updated issue #%s." % issue["number"])
        else:
            print(gh("issue", "create", "--title", title, "--label", "upstream", "--body-file", "upstream-issue.md"))
    elif issue and complete:
        gh("issue", "close", str(issue["number"]), "--comment",
           "Every pin is the latest upstream again ([run](%s))." % run_url)
        print("Closed issue #%s." % issue["number"])
    return 0 if complete else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("row")
    r.add_argument("--out", required=True)
    r.add_argument("--component", required=True)
    for opt in ("source", "pinned", "latest", "update", "detail", "test-outcome", "test-result",
                "test-cached", "known"):
        r.add_argument("--" + opt, default="")
    r.add_argument("--kind", default="library")
    i = sub.add_parser("images")
    i.add_argument("--out", required=True)
    i.add_argument("--root", default=".")
    p = sub.add_parser("report")
    p.add_argument("--rows", required=True)
    p.add_argument("--needs", default="{}")
    p.add_argument("--notes")
    p.add_argument("--title", default="Upstream releases: pins behind the latest")
    p.add_argument("--no-issue", action="store_true")
    a = ap.parse_args()
    return {"row": cmd_row, "images": cmd_images, "report": cmd_report}[a.cmd](a) or 0


if __name__ == "__main__":
    sys.exit(main())
