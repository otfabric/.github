#!/usr/bin/env python3
"""Normalise scanner output, apply .otfabric/sast-baseline.json, report and gate.

  sast_gate.py evaluate   reports → findings.json, status.json, SARIF, summary.md
  sast_gate.py check-scan      exit 3 when a scan did not complete (enforcing modes)
  sast_gate.py check-findings  exit 1 when a finding blocks
  sast_gate.py baseline        record current findings as triage debt

Exit codes match otfabric-policy: 1 for findings, 3 for anything that means the
result cannot be trusted. Output carries no source lines: a finding of a secret
must not copy the secret into a report. Standard library only.
"""
import argparse
import datetime
import hashlib
import json
import os
import re
import sys

SCHEMA = 1
LEVELS = {"low": 0, "medium": 1, "high": 2}
MODES = ("report", "baseline", "enforce")
STATES = ("baseline", "false-positive", "accepted-risk")
REVIEW_DAYS = 183  # docs/exceptions: reviewed date + 6 months
# Types of opengrep error that mean a rule did not finish on a file. Partial
# parsing is expected in workflow templates and only noted.
OPENGREP_INCOMPLETE_TYPES = ("Timeout", "OutOfMemory", "StackOverflow", "Fatal error", "Rule parse error", "Invalid rule schema")
RECORD_FIELDS = {"fingerprint", "tool", "rule", "path", "state", "justification", "owner", "reviewed", "expires", "reconsider", "ref"}


def read_text(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read().strip()
    except OSError:
        return ""


def read_json(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f), None
    except OSError as e:
        return None, f"no report: {e.strerror}"
    except ValueError as e:
        return None, f"report is not JSON: {e}"


def source_line(root, rel, line):
    """The whitespace-normalised source line, from inside root only."""
    real_root = os.path.realpath(root)
    full = os.path.realpath(os.path.join(root, rel))
    if not full.startswith(real_root + os.sep):
        return ""
    try:
        with open(full, encoding="utf-8", errors="replace") as f:
            for i, text in enumerate(f, 1):
                if i == line:
                    return " ".join(text.split())
    except OSError:
        pass
    return ""


def relative(root, path, module_dir):
    """A repository-relative path with forward slashes."""
    if not os.path.isabs(path):
        path = os.path.join(root, module_dir, path) if module_dir else os.path.join(root, path)
    return os.path.relpath(os.path.realpath(path), os.path.realpath(root)).replace(os.sep, "/")


def parse_gosec(path, root, module_dir):
    """Findings and (status, reason, files) of a gosec report."""
    out_dir = os.path.dirname(path)
    code = read_text(os.path.join(out_dir, "gosec.exit"))
    error = read_text(os.path.join(out_dir, "gosec.error"))
    if code != "0":
        return [], ("incomplete", f"gosec exit {code or 'missing'}: {error[:300]}", 0)
    data, err = read_json(path)
    if err:
        return [], ("incomplete", f"gosec {err}", 0)
    if not isinstance(data, dict) or not isinstance(data.get("Stats"), dict) or not isinstance(data.get("Issues"), list):
        return [], ("incomplete", "gosec report has an unknown shape", 0)
    findings = []
    for i in data["Issues"]:
        line = int(str(i.get("line", "0")).split("-")[0] or 0)
        rel = relative(root, i.get("file", ""), "")
        findings.append({
            "tool": "gosec",
            "rule": i.get("rule_id", "?"),
            "severity": str(i.get("severity", "")).lower(),
            "confidence": str(i.get("confidence", "")).lower(),
            "cwe": f"CWE-{i['cwe']['id']}" if i.get("cwe", {}).get("id") else "",
            "path": rel,
            "line": line,
            "message": i.get("details", ""),
        })
    files = int(data["Stats"].get("files", 0))
    errors = data.get("Golang errors") or {}
    if errors:
        first = next(iter(errors))
        return findings, ("incomplete", f"gosec could not type-check {len(errors)} file(s), first {relative(root, first, '')}", files)
    if files == 0:
        return findings, ("incomplete", "gosec scanned no files", 0)
    return findings, ("completed", "", files)


def load_overrides(catalog):
    """rule id → confidence from the upstream catalog (file stem = rule id)."""
    overrides = {}
    for raw in read_text(catalog).splitlines():
        parts = raw.split()
        if parts and not raw.startswith("#") and len(parts) > 1 and parts[1].startswith("confidence="):
            stem = os.path.basename(parts[0]).rsplit(".", 1)[0]
            overrides[stem] = parts[1].split("=", 1)[1].lower()
    return overrides


def error_type(e):
    t = e.get("type")
    return t[0] if isinstance(t, list) and t else str(t)


def parse_opengrep(path, root, overrides):
    out_dir = os.path.dirname(path)
    code = read_text(os.path.join(out_dir, "opengrep.exit"))
    error = read_text(os.path.join(out_dir, "opengrep.error"))
    if code != "0":
        return [], ("incomplete", f"opengrep exit {code or 'missing'}: {error[:300]}", 0), 0
    data, err = read_json(path)
    if err:
        return [], ("incomplete", f"opengrep {err}", 0), 0
    if not isinstance(data, dict) or not isinstance(data.get("results"), list) or not isinstance(data.get("paths"), dict):
        return [], ("incomplete", "opengrep report has an unknown shape", 0), 0
    sev = {"ERROR": "high", "WARNING": "medium", "INFO": "low"}
    findings = []
    for r in data["results"]:
        extra = r.get("extra", {})
        meta = extra.get("metadata", {}) or {}
        # The check id starts with the path of the rule file: only the last
        # part is stable from one machine to the next.
        rule = str(r.get("check_id", "?")).rsplit(".", 1)[-1]
        cwe = meta.get("cwe")
        cwe = cwe[0] if isinstance(cwe, list) and cwe else cwe or ""
        findings.append({
            "tool": "opengrep",
            "rule": rule,
            "severity": sev.get(extra.get("severity"), "low"),
            "confidence": overrides.get(rule, str(meta.get("confidence", "low")).lower()),
            "cwe": str(cwe).split(":")[0],
            "path": relative(root, r.get("path", ""), ""),
            "line": int(r.get("start", {}).get("line", 0)),
            "message": " ".join(str(extra.get("message", "")).split()),
        })
    files = len(data["paths"].get("scanned") or [])
    errors = data.get("errors") or []
    fatal = [e for e in errors if e.get("level") == "error" or error_type(e) in OPENGREP_INCOMPLETE_TYPES]
    if fatal:
        return findings, ("incomplete", f"opengrep reported {len(fatal)} error(s), first: {error_type(fatal[0])}: {str(fatal[0].get('message', ''))[:200]}", files), len(errors) - len(fatal)
    if files == 0:
        return findings, ("incomplete", "opengrep scanned no files", 0), 0
    return findings, ("completed", "", files), len(errors)


def fingerprint(findings, root):
    """Stable across moved lines: rule, path, source text, nth such occurrence."""
    seen = {}
    for f in sorted(findings, key=lambda x: (x["tool"], x["rule"], x["path"], x["line"])):
        text = source_line(root, f["path"], f["line"])
        key = (f["tool"], f["rule"], f["path"], text)
        n = seen.get(key, 0)
        seen[key] = n + 1
        digest = hashlib.sha256("\0".join([f["rule"], f["path"], text, str(n)]).encode()).hexdigest()[:20]
        f["fingerprint"] = f"{f['tool']}/{f['rule']}/{digest}"


def validate_record(r, today):
    """What is wrong with a record, in the terms of docs/exceptions."""
    if not isinstance(r, dict):
        return ["not an object"]
    errs = [f"unknown field {k}" for k in r if k not in RECORD_FIELDS]
    for k in ("fingerprint", "tool", "rule", "path", "state", "justification", "owner", "reviewed", "ref"):
        if not str(r.get(k, "")).strip():
            errs.append(f"missing {k}")
    if not r.get("expires") and not r.get("reconsider"):
        errs.append("missing expires or reconsider")
    if r.get("state") not in STATES and r.get("state"):
        errs.append(f"unknown state {r['state']}")
    if r.get("state") == "baseline" and not r.get("expires"):
        errs.append("state baseline needs expires: debt gets looked at again")
    for k in ("reviewed", "expires"):
        if r.get(k):
            try:
                datetime.date.fromisoformat(str(r[k]))
            except ValueError:
                errs.append(f"{k} {r[k]!r} is not YYYY-MM-DD")
    return errs


def load_baseline(path, today):
    """(records by fingerprint, config errors, expired records)."""
    if not os.path.exists(path):
        return {}, [], []
    data, err = read_json(path)
    if err:
        return {}, [f"{path}: {err}"], []
    if not isinstance(data, dict) or data.get("schema") != SCHEMA or not isinstance(data.get("findings"), list):
        return {}, [f"{path}: needs schema {SCHEMA} and a findings list"], []
    records, errors, expired = {}, [], []
    for n, r in enumerate(data["findings"], 1):
        errs = validate_record(r, today)
        if errs:
            errors.append(f"{path}: record {n}: {', '.join(errs)}")
            continue
        fp = r["fingerprint"]
        if fp in records:
            errors.append(f"{path}: record {n}: duplicate fingerprint {fp}")
            continue
        if r.get("expires") and datetime.date.fromisoformat(r["expires"]) < today:
            expired.append(r)
            continue
        records[fp] = r
    return records, errors, expired


def annotation_text(s, limit=300):
    """Text that cannot end or extend a workflow command."""
    return str(s)[:limit].replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A").replace(":", "%3A").replace(",", "%2C")


def cell(s, limit=160):
    """Text that stays one inert cell of a Markdown table."""
    s = re.sub(r"[\x00-\x1f\x7f]+", " ", str(s))[:limit]
    return re.sub(r"([\\`*_{}\[\]<>|#!])", r"\\\1", s)


def apply_baseline(findings, records, args):
    used = set()
    for f in findings:
        f["in_threshold"] = (
            LEVELS.get(f["severity"], 0) >= LEVELS[args.block_severity]
            and LEVELS.get(f["confidence"], 0) >= LEVELS[args.block_confidence]
        )
        rec = records.get(f["fingerprint"])
        if rec:
            used.add(f["fingerprint"])
        if not f["in_threshold"]:
            f["disposition"] = rec["state"] if rec else "below-threshold"
            f["blocking"] = False
        elif rec:
            f["disposition"] = rec["state"]
            f["blocking"] = args.mode == "enforce" and rec["state"] == "baseline"
        else:
            f["disposition"] = "new"
            f["blocking"] = args.mode != "report"
    return used


def sarif(tool, version, findings, version_uri):
    rules = {}
    results = []
    sev = {"high": 8.0, "medium": 5.0, "low": 2.0}
    level = {"high": "error", "medium": "warning", "low": "note"}
    for f in findings:
        if f["rule"] not in rules:
            rules[f["rule"]] = {
                "id": f["rule"],
                "shortDescription": {"text": f["message"][:200] or f["rule"]},
                "properties": {"security-severity": str(sev.get(f["severity"], 2.0)), "tags": ["security", f["cwe"]] if f["cwe"] else ["security"]},
            }
        result = {
            "ruleId": f["rule"],
            "level": level.get(f["severity"], "note"),
            "message": {"text": f["message"] or f["rule"]},
            "locations": [{"physicalLocation": {"artifactLocation": {"uri": f["path"]}, "region": {"startLine": max(f["line"], 1)}}}],
            "partialFingerprints": {"otfabric/v1": f["fingerprint"]},
            "baselineState": "new" if f["disposition"] in ("new", "below-threshold") else "unchanged",
            "properties": {"confidence": f["confidence"], "disposition": f["disposition"]},
        }
        if f["disposition"] in ("false-positive", "accepted-risk"):
            result["suppressions"] = [{"kind": "external", "justification": f["disposition"]}]
        results.append(result)
    return {
        "$schema": "https://json.schemastore.org/sarif-2.1.0.json",
        "version": "2.1.0",
        "runs": [{"tool": {"driver": {"name": tool, "semanticVersion": version.lstrip("v"), "informationUri": version_uri, "rules": list(rules.values())}}, "results": results}],
    }


def write_json(path, data):
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")


def versions(path):
    out = {}
    for raw in read_text(path).splitlines():
        if "=" in raw and not raw.startswith("#"):
            k, v = raw.split("=", 1)
            out[k] = v
    return out


def rules_digest(bundle):
    h = hashlib.sha256()
    for name in ("sast/versions.env", "sast/opengrep/upstream.txt"):
        h.update(read_text(os.path.join(bundle, name)).encode())
    rules = os.path.join(bundle, "sast/opengrep/rules")
    if os.path.isdir(rules):
        for name in sorted(os.listdir(rules)):
            if name.endswith(".yaml"):
                h.update(read_text(os.path.join(rules, name)).encode())
    return h.hexdigest()


def evaluate(args):
    today = datetime.date.fromisoformat(args.today) if args.today else datetime.date.today()
    root = os.path.abspath(args.root)
    os.makedirs(args.out, exist_ok=True)
    module_dir = "" if args.module_dir in ("", ".") else args.module_dir
    ver = versions(os.path.join(args.bundle, "sast/versions.env"))

    tools, findings, notes = {}, [], []
    if args.gosec:
        got, (status, reason, files) = parse_gosec(os.path.join(args.out, "gosec.json"), root, module_dir)
        findings += got
        tools["gosec"] = {"status": status, "reason": reason, "files": files, "version": ver.get("GOSEC_VERSION", ""), "module_dir": args.module_dir}
    else:
        tools["gosec"] = {"status": "disabled", "reason": "", "files": 0}
    if args.opengrep:
        overrides = load_overrides(os.path.join(args.bundle, "sast/opengrep/upstream.txt"))
        got, (status, reason, files), partial = parse_opengrep(os.path.join(args.out, "opengrep.json"), root, overrides)
        findings += got
        tools["opengrep"] = {"status": status, "reason": reason, "files": files, "version": ver.get("OPENGREP_VERSION", ""), "rules_commit": ver.get("OPENGREP_RULES_SHA", "")}
        if partial:
            notes.append(f"opengrep could not fully parse {partial} file(s)")
    else:
        tools["opengrep"] = {"status": "disabled", "reason": "", "files": 0}

    fingerprint(findings, root)
    records, config_errors, expired = load_baseline(os.path.join(root, args.baseline), today)
    used = apply_baseline(findings, records, args)
    stale = sorted(fp for fp in records if fp not in used)
    review_due = sorted(r["fingerprint"] for r in records.values() if (today - datetime.date.fromisoformat(r["reviewed"])).days > REVIEW_DAYS)
    findings.sort(key=lambda f: (not f["blocking"], f["disposition"] != "new", f["tool"], f["rule"], f["path"], f["line"]))

    enabled = [t for t in tools.values() if t["status"] != "disabled"]
    complete = bool(enabled) and all(t["status"] == "completed" for t in enabled) and not config_errors
    blocking = [f for f in findings if f["blocking"]]
    new = [f for f in findings if f["disposition"] == "new"]
    status = {
        "schema": SCHEMA,
        "commit": args.commit,
        "mode": args.mode,
        "thresholds": {"severity": args.block_severity, "confidence": args.block_confidence},
        "rules_digest": rules_digest(args.bundle),
        "bundle_ref": args.bundle_ref,
        "scan_status": "completed" if complete else "incomplete",
        "finding_status": "blocked" if blocking else "new" if new else "clean",
        "tools": tools,
        "counts": {
            "total": len(findings),
            "blocking": len(blocking),
            "new_in_threshold": len(new),
            "baselined": sum(f["disposition"] == "baseline" for f in findings),
            "false_positive": sum(f["disposition"] == "false-positive" for f in findings),
            "accepted_risk": sum(f["disposition"] == "accepted-risk" for f in findings),
            "below_threshold": sum(f["disposition"] == "below-threshold" for f in findings),
        },
        "baseline": {"config_errors": config_errors, "expired": [r["fingerprint"] for r in expired], "stale": stale, "review_due": review_due},
        "notes": notes,
    }
    write_json(os.path.join(args.out, "findings.json"), {"schema": SCHEMA, "commit": args.commit, "findings": findings})
    write_json(os.path.join(args.out, "status.json"), status)
    for tool, uri in (("gosec", "https://github.com/securego/gosec"), ("opengrep", "https://github.com/opengrep/opengrep")):
        if tools[tool]["status"] != "disabled":
            write_json(os.path.join(args.out, f"{tool}.sarif"), sarif(tool, tools[tool]["version"], [f for f in findings if f["tool"] == tool], uri))
    # The raw reports hold source lines. They stay out of the published artifact.
    if not args.keep_raw:
        for name in ("gosec.json", "opengrep.json"):
            try:
                os.remove(os.path.join(args.out, name))
            except OSError:
                pass

    write_summary(os.path.join(args.out, "summary.md"), status, findings)
    for f in blocking[:10]:
        print(f"::error file={annotation_text(f['path'])},line={f['line']},title={annotation_text(f['tool'] + ' ' + f['rule'])}::{annotation_text(f['message'])}")
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as out:
            out.write(f"scan-status={status['scan_status']}\nfinding-status={status['finding_status']}\n")
    return 0


def write_summary(path, status, findings):
    c = status["counts"]
    lines = ["## SAST", "", f"Mode **{status['mode']}**, blocks at severity ≥ {status['thresholds']['severity']} and confidence ≥ {status['thresholds']['confidence']}.", ""]
    lines += [f"**Scan: {status['scan_status']}.** **Findings: {status['finding_status']}.**", ""]
    lines += ["| Tool | Scan | Files | Note |", "|---|---|---|---|"]
    for name, t in status["tools"].items():
        lines.append(f"| {name} | {t['status']} | {t['files']} | {cell(t['reason'])} |")
    lines += ["", f"{c['total']} findings: {c['blocking']} blocking, {c['new_in_threshold']} new at the threshold, {c['baselined']} baselined, {c['false_positive']} false positives, {c['accepted_risk']} accepted risks, {c['below_threshold']} below the threshold.", ""]
    top = [f for f in findings if f["in_threshold"] and f["disposition"] in ("new", "baseline")][:25]
    if top:
        lines += ["| Tool | Rule | Where | Disposition |", "|---|---|---|---|"]
        for f in top:
            lines.append(f"| {f['tool']} | {cell(f['rule'])} | {cell(f['path'])}:{f['line']} | {f['disposition']} |")
        lines.append("")
    b = status["baseline"]
    for title, items in (("Invalid baseline", b["config_errors"]), ("Expired records", b["expired"]), ("Records that match nothing", b["stale"]), ("Records due for review", b["review_due"])):
        if items:
            lines.append(f"**{title}:** " + "; ".join(cell(i, 200) for i in items[:10]))
            lines.append("")
    for note in status["notes"]:
        lines += [cell(note), ""]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def load_status(args):
    data, err = read_json(os.path.join(args.out, "status.json"))
    if err:
        print(f"::error::SAST produced no status: {err}. Nothing can be said about this commit.")
        sys.exit(3)
    return data


def check_scan(args):
    s = load_status(args)
    problems = [f"{n}: {t['reason']}" for n, t in s["tools"].items() if t["status"] == "incomplete"] + s["baseline"]["config_errors"]
    if not any(t["status"] != "disabled" for t in s["tools"].values()):
        problems.append("no scanner was enabled")
    if s["scan_status"] == "completed":
        print("Scan completed: " + ", ".join(f"{n} {t['files']} files" for n, t in s["tools"].items() if t["status"] == "completed"))
        return 0
    text = annotation_text("; ".join(problems), 600)
    if s["mode"] == "report":
        print(f"::warning title=SAST scan incomplete::This commit was NOT fully scanned. {text}")
        return 0
    print(f"::error title=SAST scan incomplete::This is a scanner failure, not a finding. This commit was NOT fully scanned. {text}")
    return 3


def check_findings(args):
    s = load_status(args)
    c = s["counts"]
    if s["baseline"]["expired"]:
        print(f"::warning title=SAST baseline::{len(s['baseline']['expired'])} expired record(s) no longer apply: triage them again")
    if c["blocking"]:
        print(f"::error title=SAST findings::{c['blocking']} finding(s) block in mode {s['mode']}. Fix them, or record them in .otfabric/sast-baseline.json.")
        return 1
    if c["new_in_threshold"]:
        print(f"::notice title=SAST findings::{c['new_in_threshold']} finding(s) would block outside mode {s['mode']}")
    print(f"Findings: {c['blocking']} blocking of {c['total']}")
    return 0


def baseline(args):
    data, err = read_json(args.findings)
    if err:
        sys.exit(f"{args.findings}: {err}")
    path = args.baseline
    current = {"schema": SCHEMA, "findings": []}
    if os.path.exists(path):
        current, err = read_json(path)
        if err:
            sys.exit(f"{path}: {err}")
    known = {r["fingerprint"] for r in current["findings"]}
    today = args.today or datetime.date.today().isoformat()
    added = 0
    for f in data["findings"]:
        if f["in_threshold"] and f["disposition"] == "new" and f["fingerprint"] not in known:
            current["findings"].append({
                "fingerprint": f["fingerprint"], "tool": f["tool"], "rule": f["rule"], "path": f["path"],
                "state": "baseline",
                "justification": "Present at adoption; not yet triaged.",
                "owner": args.owner, "reviewed": today, "expires": args.expires, "ref": args.ref,
            })
            added += 1
    current["findings"].sort(key=lambda r: (r["path"], r["rule"], r["fingerprint"]))
    write_json(path, current)
    print(f"{path}: {added} record(s) added, {len(current['findings'])} in total")
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="command", required=True)
    e = sub.add_parser("evaluate")
    e.add_argument("--out", required=True)
    e.add_argument("--root", default=".")
    e.add_argument("--bundle", required=True)
    e.add_argument("--module-dir", default=".")
    e.add_argument("--mode", default="report", choices=MODES)
    e.add_argument("--block-severity", default="high", choices=list(LEVELS))
    e.add_argument("--block-confidence", default="high", choices=list(LEVELS))
    e.add_argument("--baseline", default=".otfabric/sast-baseline.json")
    e.add_argument("--gosec", type=lambda v: v == "true", default=True)
    e.add_argument("--opengrep", type=lambda v: v == "true", default=True)
    e.add_argument("--commit", default="")
    e.add_argument("--bundle-ref", default="")
    e.add_argument("--today", default="")
    e.add_argument("--keep-raw", action="store_true")
    for name in ("check-scan", "check-findings"):
        sub.add_parser(name).add_argument("--out", required=True)
    b = sub.add_parser("baseline")
    b.add_argument("--findings", required=True)
    b.add_argument("--baseline", default=".otfabric/sast-baseline.json")
    b.add_argument("--owner", required=True)
    b.add_argument("--expires", required=True)
    b.add_argument("--ref", required=True)
    b.add_argument("--today", default="")
    args = p.parse_args()
    return {"evaluate": evaluate, "check-scan": check_scan, "check-findings": check_findings, "baseline": baseline}[args.command](args)


if __name__ == "__main__":
    sys.exit(main())
