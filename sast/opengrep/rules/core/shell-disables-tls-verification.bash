#!/usr/bin/env bash
# ruleid: otfabric-shell-disables-tls-verification
curl -k https://device.example/status
# ruleid: otfabric-shell-disables-tls-verification
curl --silent --insecure https://device.example/status
# ruleid: otfabric-shell-disables-tls-verification
wget --no-check-certificate https://device.example/status
# ok: otfabric-shell-disables-tls-verification
curl --cacert ca.pem https://device.example/status
