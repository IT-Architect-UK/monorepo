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


# Fields we set ourselves. Anything else n8n attaches on read — ids,
# timestamps, versionId, default settings — is none of our business and
# comparing it would fail every run until somebody switched the check off.
VERIFIED_NODE_FIELDS = (
    "type", "typeVersion", "parameters", "credentials", "onError", "disabled",
)


def _clean_connections(conns: dict) -> dict:
    """Drop empty output slots so a trailing [] does not read as a difference."""
    out = {}
    for src, spec in (conns or {}).items():
        outputs = [o for o in spec.get("main", [])]
        while outputs and not outputs[-1]:
            outputs.pop()
        out[src] = [[{"node": c["node"], "index": c.get("index", 0)} for c in o] for o in outputs]
    return out


def drift(sent: dict, live: dict) -> list:
    """Everything the instance disagrees with us about, in plain English.

    Only what we asserted is checked. A green deploy has to mean 'the live
    workflow matches this repository' — before this existed it meant no more
    than 'the API accepted the request', and a node silently failed to deploy
    for five days behind a series of green ticks.
    """
    problems = []

    live_nodes = {n["name"]: n for n in live.get("nodes", [])}
    for node in sent.get("nodes", []):
        name = node["name"]
        there = live_nodes.get(name)
        if there is None:
            problems.append(f"node '{name}' is missing from the live workflow")
            continue
        for field in VERIFIED_NODE_FIELDS:
            if field not in node:
                continue
            if there.get(field) != node[field]:
                problems.append(
                    f"node '{name}' field '{field}': sent {node[field]!r}, "
                    f"live {there.get(field)!r}"
                )

    extra = set(live_nodes) - {n["name"] for n in sent.get("nodes", [])}
    for name in sorted(extra):
        problems.append(f"node '{name}' exists live but not in this repository")

    if _clean_connections(sent.get("connections")) != _clean_connections(live.get("connections")):
        problems.append("connections differ from the repository")

    live_settings = live.get("settings") or {}
    for key, value in (sent.get("settings") or {}).items():
        if live_settings.get(key) != value:
            problems.append(
                f"setting '{key}': sent {value!r}, live {live_settings.get(key)!r}"
            )

    return problems


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
    sent = {}       # name -> (id, payload) — what we asserted, for the read-back

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
        sent[name] = payload

        # Activate every time, error handlers included. The Error Trigger docs
        # say an error workflow does not need publishing; on n8n 2.x that is
        # wrong — an unpublished workflow does not run, so the handler stayed
        # silent through a real failure and no alert was sent.
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
        sent[name] = payload
        print(f"{name}: errors go to '{handler_name}' ({target})")

    # --- read back and prove it ------------------------------------------
    print()
    failures = 0
    for name, payload in sent.items():
        live = call("GET", f"/workflows/{deployed[name]}")
        problems = drift(payload, live)
        if problems:
            failures += 1
            print(f"DRIFT  {name}")
            for p in problems:
                print(f"       {p}")
        else:
            print(f"verified  {name}")

    if failures:
        raise SystemExit(
            f"\n{failures} workflow(s) do not match this repository. The API "
            f"accepted the change but the instance is serving something else — "
            f"do not trust a green deploy until this is resolved."
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
