#!/usr/bin/env bash
# ruleid: otfabric-shell-world-writable
chmod 777 /var/lib/app
# ruleid: otfabric-shell-world-writable
chmod -R a+w /etc/app
# ok: otfabric-shell-world-writable
chmod 750 /var/lib/app
# ok: otfabric-shell-world-writable
chmod g+w /var/lib/app
