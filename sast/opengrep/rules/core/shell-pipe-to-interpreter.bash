#!/usr/bin/env bash
# ruleid: otfabric-shell-pipe-to-interpreter
curl -fsSL https://example.com/install.sh | bash
# ruleid: otfabric-shell-pipe-to-interpreter
wget -qO- https://example.com/install.sh | sh
# ok: otfabric-shell-pipe-to-interpreter
curl -fsSL -o install.sh https://example.com/install.sh
# ok: otfabric-shell-pipe-to-interpreter
curl -fsSL https://example.com/data.json | jq .
