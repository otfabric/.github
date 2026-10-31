"""Certificates checked, no shell."""
import subprocess

import requests


def run(host):
    subprocess.run(["ping", host], check=True)
    return requests.get("https://device.example", verify="ca.pem", timeout=5)
