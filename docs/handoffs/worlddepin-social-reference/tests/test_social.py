#!/usr/bin/env python3
"""Facebook posting: seeding drafts (never overwriting), slot logic (one post
per slot, retries within the hour), pool order, house rules, dry-run gate,
publish success/failure bookkeeping, audit row."""
import json, pathlib, sys, tempfile
from datetime import datetime, timezone

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent / "collector"))
import audit
import social
import templates as tp

fails, checks = [], 0
def check(n, c, extra=""):
    global checks; checks += 1
    if not c: fails.append(f"{n}{' — ' + str(extra) if extra else ''}")

CTA = social.CTA
ENV_ON = {"SUPABASE_URL": "http://x", "SUPABASE_SECRET_KEY": "k",
          "SOCIAL_POSTING_ENABLED": "true", "WHATSAPP_TOKEN": "tok"}
ENV_OFF = {"SUPABASE_URL": "http://x", "SUPABASE_SECRET_KEY": "k", "WHATSAPP_TOKEN": "tok"}
T = lambda h, d=1: datetime(2026, 9, d, h, 0, tzinfo=timezone.utc)

TABLE, PATCHES, POSTS, PUBLISHED = [], [], [], []
def fake_req(url, key, method, path, body=None, prefer=None):
    if method == "GET":
        if path == "social_posts?select=id":
            return [{"id": r["id"]} for r in TABLE]
        return sorted((dict(r) for r in TABLE), key=lambda r: (r.get("created_at") or "", r["id"]))
    if method == "POST" and path == "social_posts":
        TABLE.extend(body); POSTS.append(body); return None
    if method == "PATCH":
        pid = path.split("id=eq.")[1]
        PATCHES.append((pid, body))
        for r in TABLE:
            if r["id"] == pid: r.update(body)
        return None
    if path == "audit_log":
        PUBLISHED.append(("audit", body[0])); return None
    return None
tp._req = fake_req
def ok_publish(token, page, msg):
    PUBLISHED.append(("fb", page, msg)); return f"{page}_999"
def bad_publish(token, page, msg):
    raise RuntimeError("HTTP 400: (#200) permissions")

def reset(rows):
    TABLE.clear(); TABLE.extend(rows); PATCHES.clear(); POSTS.clear(); PUBLISHED.clear()
    audit._RUN_LOGGED.clear()

def row(i, status="approved", **kw):
    r = {"id": f"fb-202609-{i:03d}", "platform": "facebook", "topic": "t", "status": status,
         "body": f"Post {i}. Runs on a spare phone.\n\n{CTA}", "created_at": f"2026-08-31T00:00:{i:02d}+00:00",
         "attempts": 0}
    r.update(kw); return r

# --- house rules --------------------------------------------------------------
check("CTA required", social.house_rules("Nice post without ending") == "must end with the CTA")
check("earnings need the caveat", "caveat" in social.house_rules(f"Earn $0.10 a day!\n\n{CTA}"))
check("earnings with caveat pass", social.house_rules(f"Around $0.10 a day, scales with network demand — not guaranteed.\n\n{CTA}") is None)
check("clean post passes", social.house_rules(f"Hello.\n\n{CTA}") is None)
drafts = json.loads((pathlib.Path(__file__).resolve().parent.parent / "data" / "social" / "posts.json").read_text())
check("every shipped draft passes the house rules", len(drafts) >= 42
      and all(social.house_rules(d["body"]) is None for d in drafts))
check("draft ids unique", len({d["id"] for d in drafts}) == len(drafts))

# --- migration to the current house style (Darren, 2026-09-04) ------------------
OLD = social.OLD_CTAS[0]
check("old CTA -> current CTA", social.migrate(f"Body.\n\n{OLD}") == f"Body.\n\n{CTA}")
check("raw store URLs -> short app link",
      social.migrate(f"Get it: {social.STORE_URLS[0]} or {social.STORE_URLS[1]}\n\n{CTA}")
      == f"Get it: {social.APP_LINK} or {social.APP_LINK}\n\n{CTA}")
check("android/ios pair collapses", social.migrate(f"app (Android: {social.STORE_URLS[0]} · iOS: {social.STORE_URLS[1]}).\n\n{OLD}")
      == f"app ({social.APP_LINK} — Android and iPhone).\n\n{CTA}")
check("current body is left exactly as is", social.migrate(f"Fine.\n\n{CTA}") == f"Fine.\n\n{CTA}")
check("edits elsewhere in the body survive", social.migrate(f"Darren's own words here.\n\n{OLD}").startswith("Darren's own words here."))
check("CTA names the app link", social.APP_LINK in CTA and social.house_rules(f"x\n\n{CTA}") is None)
for old, new in social.WORDING_FIXES:
    check(f"hard-cap wording rewritten: {old[:30]}", social.migrate(f"{old}\n\n{CTA}") == f"{new}\n\n{CTA}")
check("shipped drafts carry no hard-cap wording",
      not any(old in d["body"] for d in drafts for old, _ in social.WORDING_FIXES))

# --- X and Instagram variants (handoff 2026-09-09, phases 2 and 3) -----------
CTA_X = social.CTA_X
short = {"id": "fb-202609-900", "topic": "t", "body": f"Short one.\n\n{CTA}"}
long_ = {"id": "fb-202609-901", "topic": "t", "body": ("Long. " * 60).strip() + f"\n\n{CTA}"}
explicit = {"id": "fb-202609-902", "topic": "t", "body": f"Whatever.\n\n{CTA}", "x_body": f"Hand-written.\n\n{CTA_X}"}
none = {"id": "fb-202609-903", "topic": "t", "body": f"Whatever.\n\n{CTA}", "x_body": None}
check("x: short posts derive automatically", social.x_body(short) == f"Short one.\n\n{CTA_X}")
check("x: a long post is never truncated — no X version", social.x_body(long_) is None)
check("x: explicit x_body wins", social.x_body(explicit) == f"Hand-written.\n\n{CTA_X}")
check("x: explicit null = skip X", social.x_body(none) is None
      and [p for _, p, _ in social.platform_rows(none)] == ["facebook"])
check("x house rules: CTA_X, 280", social.house_rules(f"a\n\n{CTA_X}", "x") is None
      and social.house_rules("a" * 260 + f"\n\n{CTA_X}", "x").startswith("too long")
      and social.house_rules(f"a\n\n{CTA}", "x") == "must end with the X CTA")
check("earnings caveat applies on X too",
      social.house_rules(f"Earn $0.10!\n\n{CTA_X}", "x") == "earnings figure without the demand caveat")
ig = social.ig_caption(short)
check("instagram: no URL CTA, link-in-bio line, hashtags last",
      ig == f"Short one.\n\n{social.IG_CTA}\n\n{social.IG_HASHTAGS}" and social.house_rules(ig, "instagram") is None)
check("instagram house rules: CTA + hashtag line", social.house_rules(f"a\n\n{social.IG_CTA}", "instagram").startswith("must end with a line")
      and social.house_rules("a\n\n#one #two #three", "instagram").startswith("must carry"))
check("every shipped draft yields valid rows on every platform",
      all(social.house_rules(b, p) is None for d in drafts for _, p, b in social.platform_rows(d)))
check("shipped X variants stay within 280 with the CTA", all(len(social.x_body(d)) <= 280 for d in drafts if social.x_body(d)))
check("source id from a platform row id", social.source_id("ig-202609-007") == "fb-202609-007"
      and social.source_id("x-202609-007") == "fb-202609-007")
check("card headline = first sentence", social.headline(short) == "Short one." and social.headline({"headline": "H", "body": "x"}) == "H")

# OAuth 1.0a: deterministic signature for a fixed nonce/timestamp (RFC 5849 §3.4)
hdr = social.oauth1_header("POST", social.X_API, "ck", "cs", "tk", "ts", nonce="n0nce", ts_now=1700000000)
check("oauth header carries the parameters and a base64 HMAC-SHA1 signature",
      hdr.startswith("OAuth ") and 'oauth_consumer_key="ck"' in hdr and 'oauth_nonce="n0nce"' in hdr
      and 'oauth_signature_method="HMAC-SHA1"' in hdr and 'oauth_timestamp="1700000000"' in hdr
      and 'oauth_token="tk"' in hdr and "oauth_signature=" in hdr
      and hdr == social.oauth1_header("POST", social.X_API, "ck", "cs", "tk", "ts", nonce="n0nce", ts_now=1700000000))
check("x credentials need all four", social.x_credentials({"X_API_KEY": "a", "X_API_SECRET": "b", "X_ACCESS_TOKEN": "c"}) is None
      and social.x_credentials({"X_API_KEY": "a", "X_API_SECRET": "b", "X_ACCESS_TOKEN": "c", "X_ACCESS_SECRET": "d"}) == ("a", "b", "c", "d"))

# per-platform slots and posting: independent pools, own gates, own dry-run
def xrow(i, status="approved", **kw):
    r = row(i, status, **kw); r["id"] = f"x-202609-{i:03d}"; r["platform"] = "x"; r["body"] = f"Post {i} on X.\n\n{CTA_X}"; return r
def igrow(i, status="approved", **kw):
    r = row(i, status, **kw); r["id"] = f"ig-202609-{i:03d}"; r["platform"] = "instagram"
    r["body"] = f"Post {i} on IG.\n\n{social.IG_CTA}\n\n{social.IG_HASHTAGS}"; return r
XENV = dict(ENV_ON, SOCIAL_X_ENABLED="true", X_API_KEY="a", X_API_SECRET="b", X_ACCESS_TOKEN="c", X_ACCESS_SECRET="d",
            SOCIAL_INSTAGRAM_ENABLED="true", IG_USER_ID="17841400000")
XPUB, IGPUB = [], []
def ok_x(creds, text): XPUB.append((creds, text)); return "1700000000000000001"
def ok_ig(token, uid, image_url, caption): IGPUB.append((uid, image_url, caption)); return "17900000000000001"
root2 = pathlib.Path(tempfile.mkdtemp()); (root2 / "site" / "social").mkdir(parents=True)
(root2 / "site" / "social" / "fb-202609-001.jpg").write_bytes(b"jpg")
reset([row(1, "posted", posted_at="2026-09-01T13:02:00+00:00"), xrow(1), igrow(1)])
check("a Facebook post this slot does not block X", social.slot_due(TABLE, T(13), "x") == 13
      and social.slot_due(TABLE, T(13), "facebook") is None)
pid = social.post_one(root2, "http://x", "k", XENV, T(13), platform="x", _publish_x=ok_x)
check("x posted from its own pool with its own credentials", pid == "1700000000000000001"
      and XPUB[0][0] == ("a", "b", "c", "d") and XPUB[0][1].endswith(CTA_X)
      and dict(PATCHES)["x-202609-001"]["status"] == "posted")
pid = social.post_one(root2, "http://x", "k", XENV, T(13), platform="instagram", _publish_ig=ok_ig)
check("instagram posted with the card URL for its source post", pid == "17900000000000001"
      and IGPUB[0] == ("17841400000", "https://dashboard.worlddepin.io/social/fb-202609-001.jpg", TABLE[2]["body"].strip()))
check("audit rows name the platform", [e[1]["after"]["platform"] for e in PUBLISHED if e[0] == "audit"] == ["x", "instagram"])
reset([xrow(2), igrow(2)])
XPUB.clear(); IGPUB.clear()
check("x dry-run without its switch", social.post_one(root2, "http://x", "k", ENV_ON, T(9), platform="x", _publish_x=ok_x) is None and not XPUB and not PATCHES)
check("x dry-run with the switch but no keys",
      social.post_one(root2, "http://x", "k", dict(ENV_ON, SOCIAL_X_ENABLED="true"), T(9), platform="x", _publish_x=ok_x) is None and not XPUB)
pid = social.post_one(root2, "http://x", "k", XENV, T(9), platform="instagram", _publish_ig=ok_ig)
check("instagram without a card is blocked, not posted", pid is None and not IGPUB
      and TABLE[1]["status"] == "failed" and "no image card" in TABLE[1]["error"])
reset([row(3), xrow(3)])
social.post_one(root2, "http://x", "k", XENV, T(20), platform="facebook", _publish=ok_publish)
check("approving/posting facebook leaves the X row alone", TABLE[0]["status"] == "posted" and TABLE[1]["status"] == "approved")

# Instagram container flow against a fake Graph
calls = []
def fake_graph(method, path, token, params=None, data=None):
    calls.append((method, path, data or params))
    if path.endswith("/media"): return {"id": "C1"}
    if path == "C1": return {"status_code": "FINISHED" if len([c for c in calls if c[1] == "C1"]) >= 2 else "IN_PROGRESS"}
    if path.endswith("/media_publish"): return {"id": "M1"}
    return {}
og = social._graph; social._graph = fake_graph
try:
    mid = social.publish_instagram("tok", "IGU", "https://x/y.jpg", "cap", _sleep=lambda s: None)
finally:
    social._graph = og
check("instagram: container, poll until FINISHED, publish", mid == "M1"
      and [c[1] for c in calls] == ["IGU/media", "C1", "C1", "IGU/media_publish"]
      and calls[0][2] == {"image_url": "https://x/y.jpg", "caption": "cap"} and calls[-1][2] == {"creation_id": "C1"})

# cards: rendered once, only when missing
with tempfile.TemporaryDirectory() as td:
    r3 = pathlib.Path(td); (r3 / "data" / "social").mkdir(parents=True)
    (r3 / "data" / "social" / "posts.json").write_text(json.dumps([short, long_]))
    made = social.ensure_images(r3)
    jpg = r3 / "site" / "social" / "fb-202609-900.jpg"
    check("instagram cards rendered as JPEG, idempotent", made == 2 and jpg.exists()
          and jpg.read_bytes()[:2] == b"\xff\xd8" and social.ensure_images(r3) == 0)

# --- the dashboard must use the poster's CTA, never a copy of its own ---------
TEMPLATE = (pathlib.Path(__file__).resolve().parent.parent / "dashboard" / "template.html").read_text()
check("dashboard takes the CTA from build.py (D.social_cta)", "D.social_cta" in TEMPLATE)
check("no stale CTA literal in the dashboard", all(old not in TEMPLATE for old in social.OLD_CTAS))
check("dashboard fallback matches the poster", f"'{CTA}'" in TEMPLATE)
BUILD = (pathlib.Path(__file__).resolve().parent.parent / "dashboard" / "build.py").read_text()
check("build.py bakes social.CTA in", "social_cta" in BUILD and "social.CTA" in BUILD)

# --- seeding -------------------------------------------------------------------
with tempfile.TemporaryDirectory() as td:
    root = pathlib.Path(td); (root / "data" / "social").mkdir(parents=True)
    (root / "data" / "social" / "posts.json").write_text(json.dumps(
        [{"id": "fb-1", "topic": "a", "body": "A\n\n" + CTA}, {"id": "fb-2", "topic": "b", "body": "B\n\n" + CTA}]))
    reset([{"id": "fb-1", "status": "approved", "body": "EDITED", "topic": "a"}])
    n = social.seed(root, "http://x", "k")
    ids = [r["id"] for r in POSTS[0]]
    check("seed adds only missing ids as drafts, one row per seeded platform (no Instagram)",
          n == 3 and ids == ["x-1", "fb-2", "x-2"]
          and all(r["status"] == "draft" for r in POSTS[0]))
    check("X rows carry their own CTA", next(r for r in POSTS[0] if r["id"] == "x-2")["body"].endswith(CTA_X))
    check("instagram rows only when asked for",
          [p for _, p, _ in social.platform_rows({"id": "fb-3", "body": f"B\n\n{CTA}"}, ("facebook", "x", "instagram"))]
          == ["facebook", "x", "instagram"])
    check("seed never overwrites an existing row", TABLE[0]["body"] == "EDITED")
    check("seed idempotent", social.seed(root, "http://x", "k") == 0)
    # ig- rows already seeded before Instagram was dropped are retired, once
    reset([{"id": "ig-1", "status": "draft", "platform": "instagram", "body": "x", "topic": "a"},
           {"id": "ig-2", "status": "posted", "platform": "instagram", "body": "x", "topic": "a"},
           {"id": "fb-1", "status": "draft", "platform": "facebook", "body": f"A\n\n{CTA}", "topic": "a"},
           {"id": "x-1", "status": "draft", "platform": "x", "body": f"A\n\n{CTA_X}", "topic": "a"},
           {"id": "fb-2", "status": "draft", "platform": "facebook", "body": f"B\n\n{CTA}", "topic": "b"},
           {"id": "x-2", "status": "draft", "platform": "x", "body": f"B\n\n{CTA_X}", "topic": "b"}])
    social.seed(root, "http://x", "k")
    check("instagram drafts retired with a note, posted history untouched, nothing re-seeded",
          TABLE[0]["status"] == "retired" and "no World DePIN Instagram" in TABLE[0]["error"]
          and TABLE[1]["status"] == "posted" and not POSTS)
    n1 = len(PATCHES)
    check("retiring is idempotent", social.seed(root, "http://x", "k") == 0 and len(PATCHES) == n1)
    # unposted rows still on an old CTA are migrated in place; posted ones are history
    reset([{"id": "fb-1", "status": "draft", "body": f"Darren edited this.\n\n{OLD}", "topic": "a"},
           {"id": "fb-2", "status": "approved", "body": f"B {social.STORE_URLS[0]}\n\n{OLD}", "topic": "b"},
           {"id": "fb-3", "status": "posted", "body": f"Gone out.\n\n{OLD}", "topic": "c"}])
    social.seed(root, "http://x", "k")
    bodies = {r["id"]: r["body"] for r in TABLE}
    check("draft/approved rows migrated, edits kept",
          bodies["fb-1"] == f"Darren edited this.\n\n{CTA}" and bodies["fb-2"] == f"B {social.APP_LINK}\n\n{CTA}")
    check("posted row untouched", bodies["fb-3"] == f"Gone out.\n\n{OLD}")
    n0 = len(PATCHES)
    check("migration is idempotent", social.seed(root, "http://x", "k") == 0 and len(PATCHES) == n0
          and bodies == {r["id"]: r["body"] for r in TABLE})

# --- slots ----------------------------------------------------------------------
check("not a slot hour", social.slot_due([], T(10)) is None)
check("slot hour due", social.slot_due([], T(13)) == 13)
check("already posted this slot", social.slot_due([row(1, "posted", posted_at="2026-09-01T13:02:00+00:00")], T(13)) is None)
check("posted in an earlier slot does not block", social.slot_due([row(1, "posted", posted_at="2026-09-01T09:02:00+00:00")], T(13)) == 13)
check("yesterday's post does not block", social.slot_due([row(1, "posted", posted_at="2026-08-31T13:02:00+00:00")], T(13)) == 13)

# --- posting --------------------------------------------------------------------
root = pathlib.Path(tempfile.mkdtemp())
reset([row(2), row(1), row(3, "draft")])
pid = social.post_one(root, "http://x", "k", ENV_ON, T(9), _publish=ok_publish)
fb = [e for e in PUBLISHED if e[0] == "fb"]
check("oldest approved post published", pid == "1035628859639187_999"
      and fb[0][2].startswith("Post 1."))
check("default page id", fb[0][1] == social.PAGE_ID_DEFAULT)
patched = dict(PATCHES)
check("row marked posted with post id", patched["fb-202609-001"]["status"] == "posted"
      and patched["fb-202609-001"]["post_id"].endswith("_999"))
check("audit row for the post", any(e[0] == "audit" and e[1]["entity"] == "post" and e[1]["action"] == "posted"
                                    for e in PUBLISHED))
check("second call in the same slot posts nothing", social.post_one(root, "http://x", "k", ENV_ON, T(9), _publish=ok_publish) is None)

reset([row(1)])
check("dry-run when switch is off", social.post_one(root, "http://x", "k", ENV_OFF, T(9), _publish=ok_publish) is None
      and not PATCHES and not PUBLISHED)
reset([row(1)])
check("no token -> nothing posted", social.post_one(root, "http://x", "k",
      dict(ENV_ON, WHATSAPP_TOKEN=""), T(9), _publish=ok_publish) is None and not PUBLISHED)

reset([row(1, "draft")])
check("drafts are never posted", social.post_one(root, "http://x", "k", ENV_ON, T(20), _publish=ok_publish) is None
      and not PUBLISHED)

# failure: attempts counted, status kept until MAX_ATTEMPTS
reset([row(1)])
for i in range(social.MAX_ATTEMPTS):
    social.post_one(root, "http://x", "k", ENV_ON, T(13), _publish=bad_publish)
statuses = [b.get("status") for _, b in PATCHES]
check("failures retried then marked failed", TABLE[0]["attempts"] == social.MAX_ATTEMPTS
      and TABLE[0]["status"] == "failed" and statuses[:-1] == [None] * (social.MAX_ATTEMPTS - 1))

# house-rule breach on an approved row: marked failed, next approved one goes out
reset([row(1, body="Edited by hand, CTA lost"), row(2)])
pid = social.post_one(root, "http://x", "k", ENV_ON, T(20), _publish=ok_publish)
fb = [e for e in PUBLISHED if e[0] == "fb"]
check("rule-breaking post blocked, next one published",
      TABLE[0]["status"] == "failed" and "house rules" in TABLE[0]["error"] and pid and fb[0][2].startswith("Post 2."))

print(f"test_social: {checks - len(fails)}/{checks} passed")
for f in fails: print("  FAIL:", f)
sys.exit(1 if fails else 0)
