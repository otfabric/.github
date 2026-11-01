# OT Fabric Opengrep rule set

The version is `OPENGREP_RULESET_VERSION` in `../versions.env`. Every finding's report names it. A new rule, or one that finds more, is a minor version: it can block repositories in `enforce`. A rule that finds less, or a fix to a message, is a patch.

## 1.0.0

First version, written in this repository with a vulnerable and a safe fixture per rule. Packs `core` (TLS, secrets, authentication, command construction, paths, file permissions, GitHub Actions) and `protocol` (lengths from the wire, unbounded reads, resource use in loops, WebSocket origins). It replaces the 22 rules of `opengrep/opengrep-rules` used during the pilot, whose licence (LGPL-2.1 with the Commons Clause) is not an open-source licence.
