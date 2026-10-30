#!/usr/bin/env python3
"""Print the `run: |` script of a named step of a workflow, so selftests
exercise the exact shell the shared workflows run instead of a copy.

Usage: extract-step.py <workflow.yml> <step name>
Standard library only.
"""
import sys
import textwrap

path, step = sys.argv[1:3]
lines = open(path).read().split("\n")
for i, line in enumerate(lines):
    if line.strip() == f"- name: {step}":
        break
else:
    sys.exit(f"no step {step!r} in {path}")
indent = len(lines[i]) - len(lines[i].lstrip())
for j in range(i + 1, len(lines)):
    text = lines[j]
    if text.strip() and len(text) - len(text.lstrip()) <= indent:
        sys.exit(f"step {step!r} has no run block")
    if text.strip() == "run: |":
        run_indent = len(text) - len(text.lstrip())
        body = []
        for line in lines[j + 1 :]:
            if line.strip() and len(line) - len(line.lstrip()) <= run_indent:
                break
            body.append(line)
        print(textwrap.dedent("\n".join(body)).rstrip())
        sys.exit(0)
sys.exit(f"step {step!r} has no run block")
