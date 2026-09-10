#!/usr/bin/env python3
"""
build.py — render the World DePIN operations dashboard shell.

Reads dashboard/template.html (the whole page: HTML, CSS and vanilla JS with
inline-SVG charts) and writes site/index.html with the /*__DATA__*/ marker
replaced by a small config payload — the Supabase URL and publishable key,
and the REVOKE_ENABLED flag. No operational data is baked in: the page
signs in and reads everything from Supabase live.
"""
import json
import os
import pathlib
import sys
from datetime import datetime, timezone

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
OUT = ROOT / "site"
sys.path.insert(0, str(ROOT / "collector"))
import social  # noqa: E402 — the house CTA, so the Social tab agrees with the poster


def load(name, default=None):
    p = DATA / name
    if not p.exists():
        return default
    return json.loads(p.read_text(encoding="utf-8"))


def jsonl(path):
    p = ROOT / path
    if not p.exists():
        return []
    rows = []
    for line in p.read_text(encoding="utf-8").splitlines():
        try:
            rows.append(json.loads(line))
        except Exception:  # noqa: BLE001, PERF203
            continue
    return rows


def age_days(iso):
    if not iso:
        return None
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return round((datetime.now(timezone.utc) - dt).total_seconds() / 86400, 1)
    except Exception:  # noqa: BLE001
        return None


def build():
    # The page is a SHELL. No operational data — and no personal data — is
    # baked in; everything is fetched from Supabase after sign-in, under row
    # level security. This is deliberate: a page that contains nothing cannot
    # leak anything, whatever happens to the deploy pipeline or the edge gate
    # in front of it. It also makes the built file independent of data, so
    # collect commits stop producing a new page.
    payload = {
        "revoke_enabled": os.environ.get("REVOKE_ENABLED", "").lower() == "true",
        # One source of truth for the Facebook house CTA: collector/social.py.
        # A copy in the page drifted on 2026-09-09 and blocked every Approve.
        "social_cta": social.CTA,
        "social_cta_x": social.CTA_X,
        "social_cta_ig": social.IG_CTA,
        "social_max_len": social.MAX_LEN,
        # The publishable key is designed to sit in a web page: it grants
        # nothing on its own — anon holds no privileges and every table is
        # behind RLS.
        "supabase": {
            "url": os.environ.get("SUPABASE_URL", ""),
            "key": os.environ.get("SUPABASE_PUBLISHABLE_KEY", ""),
        },
        # Empty skeleton so every view renders before data arrives.
        "licences": {"licenses": [], "total": 0, "online": 0, "updated_at": None},
        "contacts": [], "pipeline": [], "rewards": {}, "aggregate": [],
        "events": [], "rules": {}, "unlinked": 0,
        "revocations": {"queue": []}, "alias_sync": {"pending": []}, "devices": [],
    }

    # Netlify's build is the copy actually served; without these the deployed
    # page cannot sign anyone in. Fail loudly, not quietly.
    if not payload["supabase"]["url"] or not payload["supabase"]["key"]:
        print("[build] WARNING: SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY not set — "
              "this shell cannot sign in or show anything")

    OUT.mkdir(exist_ok=True)
    template = TEMPLATE_FILE.read_text(encoding="utf-8")
    html = template.replace("/*__DATA__*/", json.dumps(payload, separators=(",", ":")))
    (OUT / "index.html").write_text(html, encoding="utf-8")
    print(f"[build] site/index.html — shell, {len(html)} bytes, no data baked in")


# The page itself lives in template.html — plain HTML/CSS/JS that editors and
# linters understand. The only thing build() does to it is fill the
# /*__DATA__*/ marker with the tiny config payload above.
TEMPLATE_FILE = pathlib.Path(__file__).resolve().parent / "template.html"


if __name__ == "__main__":
    build()
