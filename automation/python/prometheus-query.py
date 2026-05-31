#!/usr/bin/env python3
"""
Prometheus Metrics Query Tool
Executes instant or range queries against a Prometheus API endpoint and outputs
results as a formatted table or JSON. Useful for spot-checking alert thresholds,
generating ad-hoc reports, or scripting metric-based decisions in pipelines.

Prerequisites:
    pip install requests tabulate

Usage:
    # Instant query
    python3 prometheus-query.py --url http://prometheus:9090 \
        --query 'up{job="node"}'

    # Range query (last 1 hour, 5m step)
    python3 prometheus-query.py --url http://prometheus:9090 \
        --query 'node_cpu_seconds_total' \
        --range 1h --step 5m

    # Output JSON
    python3 prometheus-query.py --url http://prometheus:9090 \
        --query 'up' --format json

    # Common useful queries (pass as --query argument):
    #   up                                          — scrape target status
    #   node_memory_MemAvailable_bytes              — free memory
    #   100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
    #                                               — CPU usage %
    #   node_filesystem_avail_bytes{mountpoint="/"}  — root disk free

Environment variables:
    PROMETHEUS_URL    — base URL (overrides --url)
    PROMETHEUS_TOKEN  — Bearer token for authenticated endpoints
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone

try:
    import requests
except ImportError:
    print("ERROR: requests not installed. Run: pip install requests")
    sys.exit(1)

try:
    from tabulate import tabulate
    TABULATE_AVAILABLE = True
except ImportError:
    TABULATE_AVAILABLE = False


def parse_duration(s):
    """Convert a duration string like 1h, 30m, 2d into seconds."""
    units = {"s": 1, "m": 60, "h": 3600, "d": 86400, "w": 604800}
    if s[-1] in units:
        return int(s[:-1]) * units[s[-1]]
    return int(s)


def build_headers(token=None):
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def instant_query(base_url, query, headers):
    url = f"{base_url.rstrip('/')}/api/v1/query"
    resp = requests.get(url, params={"query": query}, headers=headers, timeout=30)
    resp.raise_for_status()
    return resp.json()


def range_query(base_url, query, start, end, step, headers):
    url = f"{base_url.rstrip('/')}/api/v1/query_range"
    params = {
        "query": query,
        "start": start,
        "end": end,
        "step": step,
    }
    resp = requests.get(url, params=params, headers=headers, timeout=60)
    resp.raise_for_status()
    return resp.json()


def format_labels(labels):
    return ", ".join(f'{k}="{v}"' for k, v in sorted(labels.items()) if k != "__name__")


def print_instant(data, output_format):
    result = data.get("data", {}).get("result", [])
    if not result:
        print("No data returned.")
        return

    if output_format == "json":
        print(json.dumps(result, indent=2))
        return

    rows = []
    for r in result:
        metric = r.get("metric", {})
        name = metric.get("__name__", "")
        labels = format_labels({k: v for k, v in metric.items() if k != "__name__"})
        ts, value = r["value"]
        ts_str = datetime.fromtimestamp(float(ts), tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        rows.append([name, labels, ts_str, value])

    headers = ["Metric", "Labels", "Timestamp (UTC)", "Value"]
    if TABULATE_AVAILABLE:
        print(tabulate(rows, headers=headers, tablefmt="github"))
    else:
        print("\t".join(headers))
        for row in rows:
            print("\t".join(str(c) for c in row))

    print(f"\n{len(rows)} series returned.")


def print_range(data, output_format):
    result = data.get("data", {}).get("result", [])
    if not result:
        print("No data returned.")
        return

    if output_format == "json":
        print(json.dumps(result, indent=2))
        return

    for series in result:
        metric = series.get("metric", {})
        name = metric.get("__name__", "(metric)")
        labels = format_labels({k: v for k, v in metric.items() if k != "__name__"})
        print(f"\n{name}{{{labels}}}")

        rows = []
        for ts, value in series.get("values", []):
            ts_str = datetime.fromtimestamp(float(ts), tz=timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
            rows.append([ts_str, value])

        headers = ["Timestamp (UTC)", "Value"]
        if TABULATE_AVAILABLE:
            print(tabulate(rows, headers=headers, tablefmt="simple"))
        else:
            for ts_str, val in rows:
                print(f"  {ts_str}  {val}")

    print(f"\n{len(result)} series returned.")


def main():
    parser = argparse.ArgumentParser(description="Prometheus Metrics Query Tool")
    parser.add_argument("--url",   default=os.environ.get("PROMETHEUS_URL"), help="Prometheus base URL")
    parser.add_argument("--query", required=True, help="PromQL query expression")
    parser.add_argument("--range", dest="range_duration", help="Query a time range (e.g. 1h, 30m, 2d)")
    parser.add_argument("--step",  default="1m", help="Range query step interval (default: 1m)")
    parser.add_argument("--format", dest="output_format", choices=["table", "json"], default="table",
                        help="Output format (default: table)")
    args = parser.parse_args()

    if not args.url:
        print("ERROR: Prometheus URL required. Use --url or set PROMETHEUS_URL.")
        sys.exit(1)

    token = os.environ.get("PROMETHEUS_TOKEN")
    headers = build_headers(token)

    print(f"Prometheus: {args.url}")
    print(f"Query:      {args.query}")

    if args.range_duration:
        end_ts   = datetime.now(timezone.utc).timestamp()
        start_ts = end_ts - parse_duration(args.range_duration)
        step_sec = parse_duration(args.step)
        print(f"Range:      last {args.range_duration} (step {args.step})\n")
        data = range_query(args.url, args.query, start_ts, end_ts, step_sec, headers)
        print_range(data, args.output_format)
    else:
        data = instant_query(args.url, args.query, headers)
        print_instant(data, args.output_format)


if __name__ == "__main__":
    main()
