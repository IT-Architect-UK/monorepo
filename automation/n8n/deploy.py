#!/usr/bin/env python3
"""
Sync workflow definitions in workflows/ to an n8n instance.

The repository is the source of truth. Each JSON file here is matched to a
workflow on the instance *by name*, updated if it exists and created if it does
not, then activated.

Matching on name rather than id is deliberate: ids are assigned by whichever
instance created the workflow, so an id-based sync would only ever work against
the one instance that produced the file. Name-based matching means the same
file deploys to a client's instance as easily as to ours.

Usage:
    N8N_BASE_URL=https://n8n.example.com \
    N8N_API_KEY=... \
    python3 deploy.py [--dry-run]

Exits non-zero on any failure, so CI fails loudly rather than reporting success
over a half-applied change.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

WORKFLOW_DIR = Path(__file__).parent / "workflows"

# Only these keys are accepted by POST/PUT /workflows. Anything else in the
# file — id, versionId, meta, tags, pinData — is either read-only or rejected
# outright, so it is stripped rather than sent and argued about.
SENDABLE = ("name", "nodes", "connections", "settings")


def call(method: str, path: str, body=None):
    base = os.environ["N8N_BASE_URL"].rstrip("/")
    req = urllib.request.Request(
        f"{base}/api/v1{path}",
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "X-N8N-API-KEY": os.environ["N8N_API_KEY"],
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:500]
        raise SystemExit(f"n8n API {method} {path} failed: {e.code} {detail}")
    except urllib.error.URLError as e:
        raise SystemExit(f"Cannot reach n8n at {base}: {e.reason}")


def existing_by_name() -> dict:
    """Every workflow on the instance, keyed by name. Paginates: the default
    page size is small and a silent truncation would look like 'not found' and
    create a duplicate."""
    found, cursor = {}, None
    while True:
        query = "/workflows?limit=100"
        if cursor:
            query += f"&cursor={cursor}"
        page = call("GET", query)
        for wf in page.get("data", []):
            found[wf["name"]] = wf
        cursor = page.get("nextCursor")
        if not cursor:
            return found


def main() -> int:
    dry_run = "--dry-run" in sys.argv

    files = sorted(WORKFLOW_DIR.glob("*.json"))
    if not files:
        print("No workflow files found — nothing to do.")
        return 0

    for var in ("N8N_BASE_URL", "N8N_API_KEY"):
        if not os.environ.get(var):
            raise SystemExit(f"{var} is not set.")

    remote = existing_by_name()
    print(f"{len(remote)} workflow(s) already on the instance\n")

    for path in files:
        local = json.loads(path.read_text())
        name = local["name"]
        payload = {k: local[k] for k in SENDABLE if k in local}

        match = remote.get(name)
        verb = "update" if match else "create"
        print(f"{path.name}: {verb} '{name}'")

        if dry_run:
            continue

        if match:
            wf_id = match["id"]
            call("PUT", f"/workflows/{wf_id}", payload)
        else:
            wf_id = call("POST", "/workflows", payload)["id"]

        # Activate every time. A workflow that exists but is not active looks
        # deployed and does nothing, which is the worst of both.
        call("POST", f"/workflows/{wf_id}/activate")
        print(f"  ✔ {verb}d and activated ({wf_id})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
