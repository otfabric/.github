import os
import subprocess


def vulnerable(cmd, host):
    # ruleid: otfabric-python-shell-dynamic
    subprocess.call(cmd, shell=True)
    # ruleid: otfabric-python-shell-dynamic
    subprocess.run(f"ping {host}", shell=True, check=True)
    # ruleid: otfabric-python-shell-dynamic
    os.system("ping " + host)


def safe(host):
    # ok: otfabric-python-shell-dynamic
    subprocess.run(["ping", host], check=True)
    # ok: otfabric-python-shell-dynamic
    subprocess.run("ip link show", shell=True, check=True)
