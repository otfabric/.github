#!/usr/bin/env python3
"""Publish one version of a module from a fixture git repository to a local
file:// module proxy (GOPROXY=file://<dir>), so selftests can stand in for a
published release without the network or a real tag push.

Usage: modproxy.py <proxy-dir> <repo> <git-ref> <module-dir> <version>
The module path is read from <module-dir>/go.mod at <git-ref>. Nested modules
(subdirectories with their own go.mod) are left out of the zip, as the go
command does. Standard library only; fixture module paths are lower case, so
no path escaping is needed.
"""
import io
import json
import pathlib
import subprocess
import sys
import tarfile
import zipfile

proxy, repo, ref, moddir, version = sys.argv[1:6]
moddir = moddir.strip("/") or "."
prefix = "" if moddir == "." else moddir + "/"
tar = subprocess.run(["git", "-C", repo, "archive", "--format=tar", ref],
                     check=True, capture_output=True).stdout
files = {}
with tarfile.open(fileobj=io.BytesIO(tar)) as t:
    for m in t.getmembers():
        if m.isfile() and m.name.startswith(prefix):
            files[m.name[len(prefix):]] = t.extractfile(m).read()
gomod = files["go.mod"]
path = next(l.split()[1].strip('"') for l in gomod.decode().splitlines() if l.startswith("module "))
nested = {n.rsplit("/", 1)[0] + "/" for n in files if n.endswith("/go.mod")}
root = pathlib.Path(proxy, path, "@v")
root.mkdir(parents=True, exist_ok=True)
(root / f"{version}.mod").write_bytes(gomod)
(root / f"{version}.info").write_text(json.dumps({"Version": version, "Time": "2026-01-01T00:00:00Z"}))
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w") as z:
    for name, data in sorted(files.items()):
        if any(name.startswith(d) for d in nested):
            continue
        z.writestr(f"{path}@{version}/{name}", data)
(root / f"{version}.zip").write_bytes(buf.getvalue())
listing = root / "list"
versions = set(listing.read_text().split()) if listing.exists() else set()
listing.write_text("\n".join(sorted(versions | {version})) + "\n")
print(f"published {path}@{version}")
