#!/usr/bin/env python3
"""
templates.py — the one table where Supabase is the source of truth.

Darren edits communication templates on the dashboard's Templates tab, so
the collector must never overwrite them. Each run it does two things:

  seed()    inserts any template file from data/templates/ whose id is not
            in the database yet (Prefer: ignore-duplicates), so new templates
            added in the repo appear — and edited ones are left alone.
  backup()  reads every live row and writes data/templates_live.json, so git
            history keeps every version Darren has ever saved.

Both are failure-tolerant: an outage costs a backup cycle, never a run.
"""
import json
import pathlib
import urllib.request

TIMEOUT = 45
SKIP = {"README.md", "whatsapp-templates.md"}  # not seeded; whatsapp is phase 2


def parse(path: pathlib.Path) -> dict:
    """Front-matter + body -> row. Files without front matter are snippets."""
    text = path.read_text(encoding="utf-8")
    row = {"id": path.stem, "channel": "email", "subject": None,
           "from_addr": None, "note": None, "body": text.strip()}
    if text.startswith("---"):
        head, _, body = text[3:].partition("\n---")
        row["body"] = body.strip()
        for line in head.strip().splitlines():
            k, _, v = line.partition(":")
            v = v.strip().strip('"')
            if k.strip() == "subject":
                row["subject"] = v
            elif k.strip() == "from":
                row["from_addr"] = v
            elif k.strip() == "note":
                row["note"] = v
            elif k.strip() == "channel":
                row["channel"] = v
    else:
        row["channel"] = "snippet"
    return row


def _req(url, key, method, path, body=None, prefer=None):
    headers = {"apikey": key, "Authorization": f"Bearer {key}",
               "Content-Type": "application/json"}
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(f"{url}/rest/v1/{path}", method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers=headers)
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read() or b"null")


def seed(root: pathlib.Path, url: str, key: str) -> int:
    """Insert templates that don't exist yet. NEVER updates existing rows."""
    rows = [parse(p) for p in sorted((root / "data" / "templates").glob("*.md"))
            if p.name not in SKIP]
    if not rows:
        return 0
    _req(url, key, "POST", "templates?on_conflict=id", rows,
         prefer="resolution=ignore-duplicates,return=minimal")
    return len(rows)


def backup(root: pathlib.Path, url: str, key: str) -> int:
    """Write the live rows to git so every saved edit stays in history."""
    rows = _req(url, key, "GET", "templates?select=*&order=id")
    (root / "data" / "templates_live.json").write_text(
        json.dumps(rows, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return len(rows)


def sync(root: pathlib.Path, url: str, key: str) -> None:
    """Seed-then-backup, loudly but never fatally."""
    if not url or not key:
        print("[templates] SKIPPED: no Supabase credentials")
        return
    try:
        n = seed(root, url, key)
        m = backup(root, url, key)
        print(f"[templates] {n} seeded-if-missing, {m} live rows backed up")
    except Exception as e:  # noqa: BLE001 — must never break collection
        print(f"[templates] SKIPPED: {type(e).__name__}: {str(e)[:160]}")
