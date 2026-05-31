#!/usr/bin/env python3
"""
Infrastructure Health Check
Performs concurrent TCP port checks and HTTP/HTTPS endpoint checks across a
list of hosts, then prints a colour-coded summary table and optional JSON report.

Prerequisites:
    pip install requests

Usage:
    python3 infrastructure-health-check.py --config hosts.yaml
    python3 infrastructure-health-check.py --config hosts.yaml --output report.json
    python3 infrastructure-health-check.py --host 10.0.0.1 --port 22 443

Config file format (YAML or JSON):
    hosts:
      - name: "Web Server"
        host: "10.0.0.10"
        checks:
          - {type: tcp,  port: 22}
          - {type: tcp,  port: 443}
          - {type: http, url: "https://10.0.0.10/health", expected_status: 200}

Environment variables:
    HEALTH_CHECK_TIMEOUT  — TCP/HTTP timeout in seconds (default: 5)
"""

import argparse
import json
import os
import socket
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone

try:
    import requests
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

TIMEOUT = int(os.environ.get("HEALTH_CHECK_TIMEOUT", 5))

ANSI_GREEN  = "\033[92m"
ANSI_RED    = "\033[91m"
ANSI_YELLOW = "\033[93m"
ANSI_RESET  = "\033[0m"

STATUS_OK   = f"{ANSI_GREEN}OK{ANSI_RESET}"
STATUS_FAIL = f"{ANSI_RED}FAIL{ANSI_RESET}"
STATUS_WARN = f"{ANSI_YELLOW}WARN{ANSI_RESET}"


def check_tcp(host, port):
    start = time.monotonic()
    try:
        with socket.create_connection((host, port), timeout=TIMEOUT):
            elapsed = (time.monotonic() - start) * 1000
            return {"status": "ok", "latency_ms": round(elapsed, 1)}
    except (socket.timeout, ConnectionRefusedError, OSError) as e:
        return {"status": "fail", "error": str(e)}


def check_http(url, expected_status=200):
    if not REQUESTS_AVAILABLE:
        return {"status": "warn", "error": "requests library not installed"}
    start = time.monotonic()
    try:
        resp = requests.get(url, timeout=TIMEOUT, verify=False, allow_redirects=True)
        elapsed = (time.monotonic() - start) * 1000
        ok = resp.status_code == expected_status
        return {
            "status": "ok" if ok else "warn",
            "http_status": resp.status_code,
            "latency_ms": round(elapsed, 1),
        }
    except requests.RequestException as e:
        return {"status": "fail", "error": str(e)}


def run_check(target_name, check):
    check_type = check.get("type", "tcp")
    if check_type == "tcp":
        result = check_tcp(check["host"], check["port"])
        label = f"TCP {check['host']}:{check['port']}"
    elif check_type == "http":
        result = check_http(check["url"], check.get("expected_status", 200))
        label = f"HTTP {check['url']}"
    else:
        result = {"status": "warn", "error": f"Unknown check type: {check_type}"}
        label = check_type

    return {"target": target_name, "label": label, "check_type": check_type, **result}


def load_config(path):
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    try:
        import json
        return json.loads(content)
    except json.JSONDecodeError:
        pass
    try:
        import yaml
        return yaml.safe_load(content)
    except Exception:
        pass
    raise ValueError(f"Could not parse config file: {path} (must be JSON or YAML)")


def build_checks_from_args(host, ports):
    return {
        "hosts": [
            {
                "name": host,
                "host": host,
                "checks": [{"type": "tcp", "host": host, "port": int(p)} for p in ports],
            }
        ]
    }


def flatten_checks(config):
    checks = []
    for target in config.get("hosts", []):
        for check in target.get("checks", []):
            entry = dict(check)
            if entry.get("type") == "tcp" and "host" not in entry:
                entry["host"] = target["host"]
            checks.append((target["name"], entry))
    return checks


def format_result(r):
    if r["status"] == "ok":
        status_str = STATUS_OK
    elif r["status"] == "warn":
        status_str = STATUS_WARN
    else:
        status_str = STATUS_FAIL

    detail = ""
    if "latency_ms" in r:
        detail = f"{r['latency_ms']} ms"
    if "http_status" in r:
        detail += f"  HTTP {r['http_status']}"
    if "error" in r:
        detail = r["error"]

    return f"  [{status_str}]  {r['label']:<55} {detail}"


def main():
    parser = argparse.ArgumentParser(description="Infrastructure Health Check")
    parser.add_argument("--config", help="Path to YAML/JSON config file")
    parser.add_argument("--host",   help="Single host to check (use with --port)")
    parser.add_argument("--port",   nargs="+", help="Port(s) to check on --host")
    parser.add_argument("--output", help="Write JSON report to this file")
    args = parser.parse_args()

    if args.config:
        config = load_config(args.config)
    elif args.host and args.port:
        config = build_checks_from_args(args.host, args.port)
    else:
        parser.print_help()
        sys.exit(1)

    checks = flatten_checks(config)
    if not checks:
        print("No checks defined.")
        sys.exit(1)

    print(f"\nInfrastructure Health Check — {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')}")
    print(f"Running {len(checks)} check(s) with {TIMEOUT}s timeout...\n")

    results = []
    with ThreadPoolExecutor(max_workers=20) as executor:
        futures = {executor.submit(run_check, name, check): (name, check) for name, check in checks}
        for future in as_completed(futures):
            result = future.result()
            results.append(result)
            print(format_result(result))

    ok   = sum(1 for r in results if r["status"] == "ok")
    warn = sum(1 for r in results if r["status"] == "warn")
    fail = sum(1 for r in results if r["status"] == "fail")

    print(f"\n{'='*70}")
    print(f"  Results: {ANSI_GREEN}{ok} OK{ANSI_RESET}  {ANSI_YELLOW}{warn} WARN{ANSI_RESET}  {ANSI_RED}{fail} FAIL{ANSI_RESET}  (total: {len(results)})")
    print(f"{'='*70}\n")

    if args.output:
        report = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "summary": {"ok": ok, "warn": warn, "fail": fail, "total": len(results)},
            "results": results,
        }
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=2)
        print(f"Report written to: {args.output}")

    sys.exit(0 if fail == 0 else 1)


if __name__ == "__main__":
    main()
