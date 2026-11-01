import ssl

import requests


def vulnerable(ctx):
    # ruleid: otfabric-python-tls-verification-disabled
    requests.get("https://device.example", verify=False)
    # ruleid: otfabric-python-tls-verification-disabled
    ssl._create_unverified_context()
    # ruleid: otfabric-python-tls-verification-disabled
    ctx.verify_mode = ssl.CERT_NONE


def safe(ctx):
    # ok: otfabric-python-tls-verification-disabled
    requests.get("https://device.example", verify="ca.pem")
    # ok: otfabric-python-tls-verification-disabled
    ctx.verify_mode = ssl.CERT_REQUIRED
