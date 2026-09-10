#!/usr/bin/env python3
"""
audit.py — change history for every record the dashboard shows
(Darren, 2026-08-31: "a log ... that records any changes to records so we
have history available even if a device, license, ULO or group is modified").

Two sources feed ONE log (Supabase `audit_log` + metrics/YYYY-MM/audit.jsonl):

  1. EXPLICIT records — modules that act on purpose call `record(...)` with
     who did it (a dashboard user's email, or "collector:<module>"), what
     they did, and the before/after values. Actions, expiry, onboarding,
     revocations and the group sync all do this.

  2. The DIFF PASS at the end of every collect run — `diff_pass(...)`
     compares the tracked fields of every device, licence, ULO and group
     against the state saved by the previous run and records anything that
     changed without an explicit record this run (actor "collector"). So a
     change made by ANY code path — or by a manual edit to the JSON, or on
     the portal itself — still leaves a trace. The first run only seeds the
     baseline (no flood of "created" rows for 1,350 licences).

Entity ids: device/licence = licence key, ulo = WD ref, group = group name.
Never raises: a logging failure must not break collection.
"""
import json
import os
import pathlib
from datetime import datetime, timezone

import templates as tp

STATE_FILE = "audit_state.json"
TRACK = {
    "device": ("owner_ref", "alias", "source", "notes"),
    "licence": ("pool_status", "lease_code", "alias", "device"),
    "ulo": ("name", "email", "phone", "phone_type", "status", "offboarding_mode",
            "licenses_issued", "lease_codes_issued", "notes"),
}
_RUN_LOGGED: set = set()      # (entity, entity_id) explicitly recorded this run


def _now():
    return datetime.now(timezone.utc)


def record(root, url, key, actor, action, entity, entity_id,
           before=None, after=None, detail=None, now=None):
    """One audit row -> Supabase audit_log + git JSONL. Never raises."""
    now = now or _now()
    row = {"at": now.isoformat(), "actor": actor or "collector", "action": action,
           "entity": entity, "entity_id": entity_id, "before": before, "after": after,
           "detail": detail}
    _RUN_LOGGED.add((entity, entity_id))
    try:
        mdir = root / "metrics" / now.isoformat()[:7]
        mdir.mkdir(parents=True, exist_ok=True)
        with open(mdir / "audit.jsonl", "a", encoding="utf-8") as f:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")
    except Exception as e:  # noqa: BLE001
        print(f"[audit] jsonl append failed: {type(e).__name__}: {str(e)[:120]}")
    url = (url or os.environ.get("SUPABASE_URL") or "").rstrip("/")
    key = key or os.environ.get("SUPABASE_SECRET_KEY") or ""
    if url and key:
        try:
            tp._req(url, key, "POST", "audit_log", [row], prefer="return=minimal")
        except Exception as e:  # noqa: BLE001
            print(f"[audit] db insert failed: {type(e).__name__}: {str(e)[:120]}")
    return row


# ---------------------------------------------------------------- snapshot --

def _pick(rec, fields):
    return {f: rec.get(f) for f in fields if rec.get(f) not in (None, "", [], {})}


def snapshot(root, groups=None):
    """Tracked fields of every record, keyed by entity -> id -> {field: value}."""
    out = {"device": {}, "licence": {}, "ulo": {}, "group": {}}
    dpath = root / "data" / "devices.json"
    if dpath.exists():
        for k, r in (json.loads(dpath.read_text(encoding="utf-8")).get("devices") or {}).items():
            out["device"][k] = _pick(r, TRACK["device"])
    lpath = root / "data" / "licenses.json"
    if lpath.exists():
        raw = json.loads(lpath.read_text(encoding="utf-8"))
        for r in (raw.get("licenses", raw) if isinstance(raw, dict) else raw):
            out["licence"][r["license_key"]] = _pick(r, TRACK["licence"])
    cpath = root / "data" / "contacts.json"
    if cpath.exists():
        raw = json.loads(cpath.read_text(encoding="utf-8"))
        for c in (raw.get("contacts", raw) if isinstance(raw, dict) else raw):
            if c.get("ref"):
                out["ulo"][c["ref"]] = _pick(c, TRACK["ulo"])
    if groups is not None:
        out["group"] = {n: {"members": sorted(ids)} for n, ids in groups.items()}
    return out


def _load_state(root):
    p = root / "data" / STATE_FILE
    if not p.exists():
        return None
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return None


def _save_state(root, snap, now):
    (root / "data" / STATE_FILE).write_text(
        json.dumps({"updated_at": now.isoformat(), "state": snap}, ensure_ascii=False,
                   sort_keys=True), encoding="utf-8")


def diff_pass(root, url, key, now=None, groups=None):
    """Record every tracked change since the previous run that no module
    recorded explicitly. Returns the number of rows written."""
    now = now or _now()
    prev = _load_state(root)
    cur = snapshot(root, groups)
    if groups is None and prev:
        cur["group"] = (prev.get("state") or {}).get("group") or {}
    if prev is None:
        _save_state(root, cur, now)
        print("[audit] baseline saved — change tracking starts next run")
        return 0
    old = prev.get("state") or {}
    n = 0
    for entity, items in cur.items():
        was = old.get(entity) or {}
        for eid in sorted(set(items) | set(was)):
            if (entity, eid) in _RUN_LOGGED:
                continue
            a, b = was.get(eid), items.get(eid)
            if a == b:
                continue
            if a is None:
                record(root, url, key, "collector", "created", entity, eid,
                       None, b, "appeared in this run's data", now)
            elif b is None:
                record(root, url, key, "collector", "removed", entity, eid,
                       a, None, "gone from this run's data", now)
            else:
                changed = [f for f in set(a) | set(b) if a.get(f) != b.get(f)]
                record(root, url, key, "collector", "changed", entity, eid,
                       {f: a.get(f) for f in changed}, {f: b.get(f) for f in changed},
                       "changed by the collector or on the portal: " + ", ".join(sorted(changed)),
                       now)
            n += 1
    _save_state(root, cur, now)
    if n:
        print(f"[audit] {n} unattributed change(s) recorded by the diff pass")
    return n


def run_diff(root, url, key, now=None, groups=None):
    """Loud but never fatal."""
    try:
        return diff_pass(root, url, key, now, groups)
    except Exception as e:  # noqa: BLE001
        print(f"[audit] SKIPPED: {type(e).__name__}: {str(e)[:160]}")
        return 0
