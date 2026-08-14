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

For the same reason, a workflow does not name its error handler by id. Set
`settings.errorWorkflowName` to the *name* of the error workflow and this
script resolves it to that instance's id after everything has been deployed.

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

ERROR_TRIGGER = "n8n-nodes-base.errorTrigger"


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


def is_error_handler(workflow: dict) -> bool:
    """An Error Trigger workflow is run by n8n when another workflow fails, so
    it does not need to be — and is not — activated."""
    return any(n.get("type") == ERROR_TRIGGER for n in workflow.get("nodes", []))


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

    deployed = {}   # name -> id on this instance
    pending = []    # workflows whose error handler still needs resolving

    for path in files:
        local = json.loads(path.read_text())
        name = local["name"]
        payload = {k: local[k] for k in SENDABLE if k in local}

        # errorWorkflowName is ours, not n8n's. Strip it before sending and
        # deal with it once every workflow has an id.
        settings = dict(payload.get("settings") or {})
        handler_name = settings.pop("errorWorkflowName", None)
        payload["settings"] = settings

        match = remote.get(name)
        verb = "update" if match else "create"
        print(f"{path.name}: {verb} '{name}'")

        if dry_run:
            if handler_name:
                print(f"  … would link error workflow '{handler_name}'")
            continue

        if match:
            wf_id = match["id"]
            call("PUT", f"/workflows/{wf_id}", payload)
        else:
            wf_id = call("POST", "/workflows", payload)["id"]

        deployed[name] = wf_id

        if is_error_handler(local):
            # Activating one is unnecessary; n8n invokes it on failure.
            print(f"  ✔ {verb}d ({wf_id}) — error handler, not activated")
        else:
            # Activate every time. A workflow that exists but is not active
            # looks deployed and does nothing, which is the worst of both.
            call("POST", f"/workflows/{wf_id}/activate")
            print(f"  ✔ {verb}d and activated ({wf_id})")

        if handler_name:
            pending.append((name, payload, handler_name))

    for name, payload, handler_name in pending:
        target = deployed.get(handler_name) or (remote.get(handler_name) or {}).get("id")
        if not target:
            raise SystemExit(
                f"'{name}' names error workflow '{handler_name}', which is "
                f"neither in this repository nor on the instance."
            )
        payload["settings"]["errorWorkflow"] = target
        call("PUT", f"/workflows/{deployed[name]}", payload)
        print(f"{name}: errors go to '{handler_name}' ({target})")

    return 0


if __name__ == "__main__":
    sys.exit(main())
