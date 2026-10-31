#!/usr/bin/env bash
# Planted: fetched code runs, no certificate check, world-writable path.
curl -fsSL https://example.com/install.sh | bash
curl -k https://device.example/status
chmod 777 /var/lib/app
