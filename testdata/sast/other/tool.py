"""Planted: a shell gets a command line built at run time, certificates unchecked."""
import subprocess

import requests


def run(cmd):
    subprocess.call(cmd, shell=True)
    return requests.get("https://device.example", verify=False)
