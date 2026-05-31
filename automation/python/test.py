#!/usr/bin/env python3
"""Quick connectivity test — verifies Python environment and basic network access."""

import socket
import sys


def check_dns(hostname="google.com"):
    try:
        socket.gethostbyname(hostname)
        return True, hostname
    except socket.gaierror as e:
        return False, str(e)


def check_python_version(min_major=3, min_minor=10):
    v = sys.version_info
    ok = (v.major, v.minor) >= (min_major, min_minor)
    return ok, f"{v.major}.{v.minor}.{v.micro}"


def main():
    print("Environment check\n" + "=" * 40)

    ok, version = check_python_version()
    status = "OK" if ok else "FAIL"
    print(f"Python version : [{status}] {version}")

    ok, detail = check_dns()
    status = "OK" if ok else "FAIL"
    print(f"DNS resolution : [{status}] {detail}")

    print("=" * 40)


if __name__ == "__main__":
    main()
