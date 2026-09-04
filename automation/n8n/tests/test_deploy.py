"""Unit tests for automation/n8n/deploy.py — no network, no n8n.

Every call to the n8n API goes through deploy.call(); the tests replace it
with a fake that records requests and serves canned responses, so the sync
logic (match by name, create/update, activate, error-handler linking,
read-back drift) is exercised exactly as it runs in CI, minus the instance.
"""
import importlib.util
import json
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("deploy", HERE.parent / "deploy.py")
deploy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(deploy)


# ---------------------------------------------------------------- helpers ---
class FakeApi:
    """Stands in for deploy.call(). Serves pages of workflows, hands out ids on
    POST, stores PUT bodies, and returns what was stored on GET."""

    def __init__(self, existing=None, page_size=100):
        self.calls = []
        self.store = {}          # id -> workflow body as the instance holds it
        self.next_id = 100
        self.page_size = page_size
        for wf in existing or []:
            self.store[wf["id"]] = dict(wf)

    def __call__(self, method, path, body=None):
        self.calls.append((method, path, body))
        if method == "GET" and path.startswith("/workflows?"):
            items = sorted(self.store.values(), key=lambda w: w["id"])
            start = 0
            if "cursor=" in path:
                start = int(path.split("cursor=")[1])
            page = items[start:start + self.page_size]
            out = {"data": page}
            if start + self.page_size < len(items):
                out["nextCursor"] = str(start + self.page_size)
            return out
        if method == "GET":
            return dict(self.store[path.rsplit("/", 1)[1]])
        if method == "POST" and path == "/workflows":
            wf_id = str(self.next_id); self.next_id += 1
            self.store[wf_id] = {"id": wf_id, **body}
            return {"id": wf_id}
        if method == "POST" and path.endswith("/activate"):
            self.store[path.split("/")[2]]["active"] = True
            return {}
        if method == "PUT":
            wf_id = path.rsplit("/", 1)[1]
            self.store[wf_id] = {"id": wf_id, **body}
            return {}
        raise AssertionError(f"unexpected call {method} {path}")


def workflow(name, nodes=None, settings=None, connections=None):
    return {
        "name": name,
        "nodes": nodes if nodes is not None else [
            {"name": "Start", "type": "n8n-nodes-base.manualTrigger", "typeVersion": 1,
             "parameters": {}}],
        "connections": connections or {},
        "settings": settings or {},
    }


@pytest.fixture
def workflow_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(deploy, "WORKFLOW_DIR", tmp_path)
    monkeypatch.setenv("N8N_BASE_URL", "https://n8n.test")
    monkeypatch.setenv("N8N_API_KEY", "k")
    def write(wf, filename=None):
        (tmp_path / (filename or f"{wf['name']}.json")).write_text(json.dumps(wf))
    return write


# --------------------------------------------------------- pure functions ---
def test_clean_connections_drops_trailing_empty_outputs_only():
    conns = {"A": {"main": [[{"node": "B", "index": 0}], [], []]}}
    assert deploy._clean_connections(conns) == {"A": [[{"node": "B", "index": 0}]]}
    # An empty slot BETWEEN outputs is meaningful and must survive.
    conns = {"A": {"main": [[], [{"node": "C"}]]}}
    assert deploy._clean_connections(conns) == {"A": [[], [{"node": "C", "index": 0}]]}


def test_drift_is_empty_when_live_matches_sent_plus_instance_noise():
    sent = workflow("w", settings={"executionOrder": "v1"})
    live = json.loads(json.dumps(sent))
    live["id"] = "9"; live["versionId"] = "abc"; live["nodes"][0]["id"] = "n1"
    live["settings"]["callerPolicy"] = "workflowsFromSameOwner"   # n8n default
    assert deploy.drift(sent, live) == []


def test_drift_reports_missing_extra_changed_nodes_connections_and_settings():
    sent = workflow("w",
        nodes=[{"name": "A", "type": "t", "typeVersion": 1, "parameters": {"x": 1},
                "credentials": {"api": {"id": "c1", "name": "Old label"}}},
               {"name": "B", "type": "t", "typeVersion": 1, "parameters": {}}],
        connections={"A": {"main": [[{"node": "B", "index": 0}]]}},
        settings={"errorWorkflow": "5"})
    live = {"nodes": [
                {"name": "A", "type": "t", "typeVersion": 2, "parameters": {"x": 1},
                 "credentials": {"api": {"id": "c1", "name": "Renamed in UI"}}},
                {"name": "Z", "type": "t", "typeVersion": 1, "parameters": {}}],
            "connections": {}, "settings": {"errorWorkflow": "7"}}
    problems = deploy.drift(sent, live)
    assert "node 'B' is missing from the live workflow" in problems
    assert "node 'Z' exists live but not in this repository" in problems
    assert any("node 'A' field 'typeVersion'" in p for p in problems)
    assert not any("credentials" in p for p in problems), "credential rename must not count"
    assert "connections differ from the repository" in problems
    assert any("setting 'errorWorkflow'" in p for p in problems)


# ------------------------------------------------------------- pagination ---
def test_existing_by_name_follows_every_page(monkeypatch):
    api = FakeApi([{"id": str(i), "name": f"w{i}"} for i in range(7)], page_size=3)
    monkeypatch.setattr(deploy, "call", api)
    found = deploy.existing_by_name()
    assert set(found) == {f"w{i}" for i in range(7)}
    assert sum(1 for m, p, _ in api.calls if m == "GET") == 3


# ------------------------------------------------------------------ main ---
def test_main_creates_updates_activates_and_verifies(workflow_dir, monkeypatch, capsys):
    api = FakeApi([{"id": "1", "name": "existing", **workflow("existing")}])
    monkeypatch.setattr(deploy, "call", api)
    workflow_dir(workflow("existing", settings={"executionOrder": "v1"}))
    workflow_dir(workflow("brand-new"))
    monkeypatch.setattr(sys, "argv", ["deploy.py"])

    assert deploy.main() == 0
    methods = [(m, p) for m, p, _ in api.calls]
    assert ("PUT", "/workflows/1") in methods,  "matched by name -> updated"
    assert ("POST", "/workflows") in methods,   "unknown name -> created"
    assert ("POST", "/workflows/1/activate") in methods
    assert ("POST", "/workflows/100/activate") in methods
    out = capsys.readouterr().out
    assert "verified  existing" in out and "verified  brand-new" in out


def test_main_strips_unsendable_keys(workflow_dir, monkeypatch):
    api = FakeApi(); monkeypatch.setattr(deploy, "call", api)
    wf = workflow("w"); wf.update({"id": "old", "versionId": "v", "tags": [1], "pinData": {}})
    workflow_dir(wf); monkeypatch.setattr(sys, "argv", ["deploy.py"])
    deploy.main()
    body = next(b for m, p, b in api.calls if m == "POST" and p == "/workflows")
    assert set(body) <= set(deploy.SENDABLE)


def test_main_links_error_workflow_by_name_after_deploy(workflow_dir, monkeypatch):
    api = FakeApi(); monkeypatch.setattr(deploy, "call", api)
    workflow_dir(workflow("z-main", settings={"errorWorkflowName": "a-handler"}))
    workflow_dir(workflow("a-handler"))
    monkeypatch.setattr(sys, "argv", ["deploy.py"])
    assert deploy.main() == 0
    main_id = next(i for i, w in api.store.items() if w["name"] == "z-main")
    handler_id = next(i for i, w in api.store.items() if w["name"] == "a-handler")
    live = api.store[main_id]
    assert live["settings"]["errorWorkflow"] == handler_id
    assert "errorWorkflowName" not in live["settings"], "our key never reaches n8n"


def test_main_fails_when_error_workflow_name_is_unknown(workflow_dir, monkeypatch):
    api = FakeApi(); monkeypatch.setattr(deploy, "call", api)
    workflow_dir(workflow("w", settings={"errorWorkflowName": "nope"}))
    monkeypatch.setattr(sys, "argv", ["deploy.py"])
    with pytest.raises(SystemExit, match="neither in this repository nor on the instance"):
        deploy.main()


def test_main_dry_run_makes_no_writes(workflow_dir, monkeypatch, capsys):
    api = FakeApi(); monkeypatch.setattr(deploy, "call", api)
    workflow_dir(workflow("w", settings={"errorWorkflowName": "h"}))
    monkeypatch.setattr(sys, "argv", ["deploy.py", "--dry-run"])
    assert deploy.main() == 0
    assert all(m == "GET" for m, _, _ in api.calls)
    assert "would link error workflow 'h'" in capsys.readouterr().out


def test_main_fails_loudly_on_drift(workflow_dir, monkeypatch, capsys):
    api = FakeApi(); monkeypatch.setattr(deploy, "call", api)
    workflow_dir(workflow("w"))
    monkeypatch.setattr(sys, "argv", ["deploy.py"])
    real_get = api.__call__
    def lossy(method, path, body=None):
        out = real_get(method, path, body)
        if method == "GET" and not path.startswith("/workflows?"):
            out["nodes"] = []           # the instance "lost" our node
        return out
    monkeypatch.setattr(deploy, "call", lossy)
    with pytest.raises(SystemExit, match="do not match this repository"):
        deploy.main()
    assert "node 'Start' is missing from the live workflow" in capsys.readouterr().out


def test_main_requires_credentials(workflow_dir, monkeypatch):
    workflow_dir(workflow("w"))
    monkeypatch.delenv("N8N_API_KEY")
    monkeypatch.setattr(sys, "argv", ["deploy.py"])
    with pytest.raises(SystemExit, match="N8N_API_KEY is not set"):
        deploy.main()


# ------------------------------------------------ the real workflow files ---
REAL_DIR = HERE.parent / "workflows"
REAL_FILES = sorted(REAL_DIR.glob("*.json"))


@pytest.mark.parametrize("path", REAL_FILES, ids=[p.name for p in REAL_FILES])
def test_real_workflow_file_is_deployable(path):
    wf = json.loads(path.read_text())
    assert wf.get("name"), "workflow needs a name (it is the sync key)"
    assert isinstance(wf.get("nodes"), list) and wf["nodes"]
    names = [n["name"] for n in wf["nodes"]]
    assert len(names) == len(set(names)), "node names must be unique for drift checks"
    for src, spec in (wf.get("connections") or {}).items():
        assert src in names, f"connection from unknown node {src!r}"
        for output in spec.get("main", []):
            for c in output:
                assert c["node"] in names, f"connection to unknown node {c['node']!r}"


def test_real_error_workflow_names_resolve_within_repo():
    names = {json.loads(p.read_text())["name"] for p in REAL_FILES}
    for p in REAL_FILES:
        handler = (json.loads(p.read_text()).get("settings") or {}).get("errorWorkflowName")
        if handler:
            assert handler in names, f"{p.name} names error workflow {handler!r} not in repo"
