#!/usr/bin/env python3
"""
social.py — social posting from a pre-approved content pool
(Darren, 2026-08-31: 3 posts a day at 09:00 / 13:00 / 20:00 UTC, drafts
approved in bulk on the dashboard's Social tab; 2026-09-09: the same
content to X and Instagram, formatted for each).

Each collect run:
  1. SEED — every source post in data/social/posts.json becomes one row PER
     PLATFORM in the social_posts table, inserted as a draft when its id is
     missing (never overwrites: the dashboard may hold Darren's edits):
       fb-YYYYMM-NNN  Facebook, the body as written
       x-YYYYMM-NNN   X, the post's `x_body` (≤ 280 chars incl. CTA_X) — an
                      explicit field, written by hand where the Facebook
                      text does not fit; `x_body: null` = no X version
       ig-YYYYMM-NNN  Instagram, the post's `ig_caption` (derived: body
                      without the URL CTA, then IG_CTA and hashtags)
     Unposted Facebook rows written under an older CTA / wording are
     migrated in place (migrate()).
  2. IMAGES — Instagram feed posts need an image: a 1080×1080 card per
     source post is rendered once (Pillow) into site/social/<fb id>.jpg,
     committed with the run and served by Netlify.
  3. POST — per platform, if the current hour is a slot and nothing has
     been posted on that platform in this slot yet today, take the oldest
     APPROVED row of that platform and publish it. Facebook: Graph API page
     token then POST /{page}/feed. X: POST api.x.com/2/tweets, OAuth 1.0a
     user context. Instagram: Graph API media container → poll → publish.
     Outcome written back to the row and to the audit log; a failed attempt
     is retried by the :30 run in the same hour; after MAX_ATTEMPTS the row
     is marked failed. Approving a row on one platform never approves it on
     another.

House rules enforced at post time, whatever the row says: the body must end
with that platform's CTA, must not quote earnings without the demand caveat,
and must fit the platform (X 280, Instagram 2 200, Facebook 2 000). The
Facebook CTA carries the short app link (worlddepin.io/app — both store
buttons and QR codes); raw store URLs in a body are swapped for it.

Gates (all repo variables; absent = dry-run, logs what it would post, marks
nothing):
  Facebook   SOCIAL_POSTING_ENABLED + META_TOKEN or WHATSAPP_TOKEN (the
             system-user token; it carries pages_manage_posts) + FB_PAGE_ID
  X          SOCIAL_X_ENABLED + secrets X_API_KEY, X_API_SECRET,
             X_ACCESS_TOKEN, X_ACCESS_SECRET (a developer app on the World
             DePIN account with Read+Write; the read-only X_BEARER_TOKEN
             cannot post)
  Instagram  SOCIAL_INSTAGRAM_ENABLED + the Meta token above with
             instagram_basic + instagram_content_publish + IG_USER_ID (the
             Business account linked to the Page); SOCIAL_IMAGE_BASE
             overrides where the cards are served from
"""
import base64
import hashlib
import hmac
import json
import os
import pathlib
import re
import secrets
import sys
import textwrap
import time
import urllib.error
import urllib.parse
import urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import audit  # noqa: E402
import templates as tp  # noqa: E402

GRAPH = "https://graph.facebook.com/v21.0"
X_API = "https://api.x.com/2/tweets"
PAGE_ID_DEFAULT = "1035628859639187"          # facebook.com/WorldDePIN
SLOTS_UTC = (9, 13, 20)
MAX_ATTEMPTS = 3
PLATFORMS = ("facebook", "x", "instagram")
PREFIX = {"facebook": "fb", "x": "x", "instagram": "ig"}
# Instagram was dropped on 2026-09-09 (there is no World DePIN Instagram
# account — only @itsurgery.me, the wrong brand). The publisher and the
# card renderer stay for the day an account exists; until then no ig- rows
# are seeded and any already seeded are retired so the Drafts count is
# not padded by 42 rows nobody will approve.
SEEDED_PLATFORMS = ("facebook", "x")
RETIRE_NOTE = {"instagram": "retired 2026-09-09: no World DePIN Instagram account"}

CTA = "Get the app: worlddepin.io/app · Free licence: worlddepin.io · hello@worlddepin.io"
CTA_X = "Free licence + app: worlddepin.io"
IG_CTA = "Free licence + app — link in bio. worlddepin.io"
IG_HASHTAGS = "#DePIN #UnityNodes #WorldDePIN #PassiveIncome"
MAX_LEN = {"facebook": 2000, "x": 280, "instagram": 2200}
IMAGE_BASE_DEFAULT = "https://dashboard.worlddepin.io/social"
# Earlier house CTAs. A draft/approved Facebook row still ending with one of
# these is migrated to CTA at seed time (text substitution only — Darren's
# edits to the rest of the body survive). Posted rows are history and never
# touched.
OLD_CTAS = ("Interested? Visit worlddepin.io or email hello@worlddepin.io",)
# The one short link for the app (both store buttons + QR codes). Raw store
# URLs in a post body are swapped for it — Darren, 2026-09-04: the store
# links must be easy to find from every post.
APP_LINK = "worlddepin.io/app"
STORE_URLS = ("https://play.google.com/store/apps/details?id=io.unitynodes.unityapp",
              "https://apps.apple.com/app/unity-network-app/id6755482738",
              "https://apps.apple.com/us/app/unity-network-app/id6755482738")
EARNINGS_LINE = "$0.10"
CAVEAT_WORDS = ("demand", "not guaranteed", "aren't guaranteed", "isn't guaranteed")
# Wording that promised a hard cap. Since the 2026-09-01 onboarding gate, 5
# is the ENTRY batch: an activated ULO may ask for more, a batch at a time,
# and more than 5 at once goes to Darren. Applied by migrate() so the rows
# already seeded to Supabase are corrected too (handoff 2026-09-09).
WORDING_FIXES = (
    ("3. You can run up to 5 devices on one account.",
     "3. You can start with up to 5 devices on one account — more once they're running."),
    ("Yes — up to 5 devices per account, one licence each.",
     "Yes — start with up to 5 devices per account, one licence each, and ask for more once they're live."),
    ("One free licence per device, up to 5 per person.",
     "One free licence per device; start with up to 5 and ask for more once they're running."),
    ("Up to 5 licences per person, all free.",
     "Start with up to 5 licences per person, all free — more once they're running."),
)


def migrate(body: str) -> str:
    """Bring an older Facebook body up to the current house style: current
    CTA, short app link instead of raw store URLs, no hard-cap wording.
    Idempotent; unchanged text is returned as-is so callers can compare."""
    b = (body or "").rstrip()
    for old in OLD_CTAS:
        if b.endswith(old):
            b = b[:-len(old)].rstrip() + "\n\n" + CTA
    for u in STORE_URLS:
        b = b.replace(u, APP_LINK)
    for old, new in WORDING_FIXES:
        b = b.replace(old, new)
    # "(Android: worlddepin.io/app · iOS: worlddepin.io/app)" reads silly
    b = b.replace(f"(Android: {APP_LINK} · iOS: {APP_LINK})", f"({APP_LINK} — Android and iPhone)")
    b = b.replace(f"Android: {APP_LINK} · iOS: {APP_LINK}", f"{APP_LINK} (Android and iPhone)")
    return b


def house_rules(body: str, platform: str = "facebook"):
    """Returns None when the body passes, else the reason it must not go out."""
    b = (body or "").strip()
    if not b:
        return "empty body"
    if platform == "x":
        if not b.endswith(CTA_X):
            return "must end with the X CTA"
    elif platform == "instagram":
        if IG_CTA not in b:
            return "must carry the Instagram CTA (link in bio)"
        if len(re.findall(r"#\w+", b.splitlines()[-1])) < 3:
            return "must end with a line of 3–5 hashtags"
    elif not b.endswith(CTA):
        return "must end with the CTA"
    if EARNINGS_LINE in b and not any(w in b.lower() for w in CAVEAT_WORDS):
        return "earnings figure without the demand caveat"
    if len(b) > MAX_LEN.get(platform, 2000):
        return f"too long for {platform} ({len(b)} > {MAX_LEN.get(platform, 2000)})"
    return None


# --------------------------------------------------------- per-platform text ---

def core_text(body: str) -> str:
    """The Facebook body without its CTA line."""
    b = (body or "").rstrip()
    for cta in (CTA,) + OLD_CTAS:
        if b.endswith(cta):
            return b[:-len(cta)].rstrip()
    return b


def x_body(post: dict):
    """The X version: the explicit `x_body` when the source post carries one
    (None means "no X version"), else the Facebook text plus CTA_X when
    that fits in 280 — never a truncation."""
    if "x_body" in post:
        return post["x_body"]
    cand = core_text(post.get("body")) + "\n\n" + CTA_X
    return cand if house_rules(cand, "x") is None else None


def ig_caption(post: dict):
    """The Instagram caption: the explicit `ig_caption` when present, else
    the Facebook text without its URL CTA, then the link-in-bio CTA and
    the hashtags. URLs are not clickable on Instagram, hence the bio."""
    if "ig_caption" in post:
        return post["ig_caption"]
    return core_text(post.get("body")) + "\n\n" + IG_CTA + "\n\n" + IG_HASHTAGS


def platform_rows(post: dict, platforms=SEEDED_PLATFORMS):
    """(id, platform, body) for every platform this source post goes to."""
    num = post["id"].split("-", 1)[1]           # YYYYMM-NNN
    out = []
    if "facebook" in platforms:
        out.append((post["id"], "facebook", migrate(post["body"])))
    xb = x_body(post)
    if "x" in platforms and xb:
        out.append((f"x-{num}", "x", xb.strip()))
    if "instagram" in platforms:
        out.append((f"ig-{num}", "instagram", ig_caption(post).strip()))
    return out


def source_id(row_id: str) -> str:
    """fb-… id of the source post behind any platform row id."""
    return "fb-" + row_id.split("-", 1)[1]


# ------------------------------------------------------------------ graph ---

def _graph(method, path, token, params=None, data=None):
    q = dict(params or {}, access_token=token)
    url = f"{GRAPH}/{path}?{urllib.parse.urlencode(q)}"
    body = urllib.parse.urlencode(data).encode() if data else None
    req = urllib.request.Request(url, data=body, method=method)
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "ignore")[:300]
        try:
            raw = json.loads(raw).get("error", {}).get("message", raw)
        except Exception:  # noqa: BLE001
            pass
        raise RuntimeError(f"HTTP {e.code}: {raw}") from e


def publish_default(token, page_id, message):
    """Page access token, then the post. Returns the Facebook post id."""
    page = _graph("GET", page_id, token, {"fields": "access_token"})
    ptoken = page.get("access_token")
    if not ptoken:
        raise RuntimeError("no page access token returned — check pages_manage_posts")
    out = _graph("POST", f"{page_id}/feed", ptoken, data={"message": message})
    return out.get("id") or "?"


def publish_instagram(token, ig_user_id, image_url, caption, _sleep=time.sleep):
    """Container → poll until FINISHED → publish. Returns the media id."""
    made = _graph("POST", f"{ig_user_id}/media", token,
                  data={"image_url": image_url, "caption": caption})
    cid = made.get("id")
    if not cid:
        raise RuntimeError(f"no container id returned: {made}")
    for _ in range(15):
        st = _graph("GET", cid, token, {"fields": "status_code,status"})
        code = st.get("status_code")
        if code == "FINISHED":
            break
        if code == "ERROR":
            raise RuntimeError(f"container failed: {st.get('status') or st}")
        _sleep(2)
    else:
        raise RuntimeError("container never reached FINISHED")
    out = _graph("POST", f"{ig_user_id}/media_publish", token, data={"creation_id": cid})
    return out.get("id") or "?"


# ---------------------------------------------------------------------- X ---

def _pct(s):
    return urllib.parse.quote(str(s), safe="~-._")


def oauth1_header(method, url, ck, cs, tk, ts, nonce=None, ts_now=None):
    """OAuth 1.0a Authorization header (HMAC-SHA1) for a JSON-body request:
    only the oauth_* parameters are signed, as api.x.com expects."""
    p = {"oauth_consumer_key": ck, "oauth_nonce": nonce or secrets.token_hex(16),
         "oauth_signature_method": "HMAC-SHA1",
         "oauth_timestamp": str(ts_now or int(time.time())),
         "oauth_token": tk, "oauth_version": "1.0"}
    base = "&".join([method.upper(), _pct(url),
                     _pct("&".join(f"{_pct(k)}={_pct(v)}" for k, v in sorted(p.items())))])
    key = f"{_pct(cs)}&{_pct(ts)}".encode()
    p["oauth_signature"] = base64.b64encode(hmac.new(key, base.encode(), hashlib.sha1).digest()).decode()
    return "OAuth " + ", ".join(f'{_pct(k)}="{_pct(v)}"' for k, v in sorted(p.items()))


def x_credentials(env):
    keys = ("X_API_KEY", "X_API_SECRET", "X_ACCESS_TOKEN", "X_ACCESS_SECRET")
    vals = [env.get(k) or "" for k in keys]
    return tuple(vals) if all(vals) else None


def publish_x(creds, text):
    """POST /2/tweets. Returns the tweet id."""
    ck, cs, tk, ts = creds
    req = urllib.request.Request(
        X_API, data=json.dumps({"text": text}).encode(), method="POST",
        headers={"Authorization": oauth1_header("POST", X_API, ck, cs, tk, ts),
                 "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            out = json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "ignore")[:300]
        raise RuntimeError(f"HTTP {e.code}: {raw}") from e
    return (out.get("data") or {}).get("id") or "?"


# ------------------------------------------------------------------ images ---

FONT_CANDIDATES = ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                   "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                   "/System/Library/Fonts/Supplemental/Arial Bold.ttf")


def headline(post: dict) -> str:
    """The card's text: `headline` if given, else the first sentence."""
    h = (post.get("headline") or "").strip()
    if h:
        return h
    core = core_text(post.get("body")).replace("\n", " ")
    m = re.match(r"(.{20,180}?[.!?])(\s|$)", core)
    return (m.group(1) if m else core[:180]).strip()


def render_card(post: dict, path: pathlib.Path):
    """1080×1080 dark card: wordmark, headline in large type, footer."""
    from PIL import Image, ImageDraw, ImageFont
    W = H = 1080
    img = Image.new("RGB", (W, H), (11, 11, 16))
    d = ImageDraw.Draw(img)
    fontfile = next((f for f in FONT_CANDIDATES if pathlib.Path(f).exists()), None)
    def font(size):
        try:
            return ImageFont.truetype(fontfile, size) if fontfile else ImageFont.load_default()
        except Exception:  # noqa: BLE001
            return ImageFont.load_default()
    yellow, white, grey = (255, 230, 0), (248, 249, 253), (148, 163, 184)
    d.rectangle([0, 0, W, 14], fill=yellow)
    d.text((80, 70), "WORLD DePIN", font=font(44), fill=yellow)
    d.text((80, 128), "Unity Nodes · free licences", font=font(30), fill=grey)
    text = headline(post)
    size = 72 if len(text) <= 80 else 60 if len(text) <= 120 else 50
    f = font(size)
    lines = textwrap.wrap(text, width=int(920 / (size * 0.52)))
    lh = int(size * 1.25)
    y = max(240, (H - lh * len(lines)) // 2 - 40)
    for line in lines:
        d.text((80, y), line, font=f, fill=white)
        y += lh
    d.rectangle([0, H - 14, W, H], fill=yellow)
    d.text((80, H - 120), "worlddepin.io · free licence", font=font(36), fill=yellow)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "JPEG", quality=88)


def ensure_images(root, posts=None) -> int:
    """One card per source post under site/social/<fb id>.jpg; only missing
    ones are rendered (idempotent). Returns how many were made."""
    posts = posts if posts is not None else json.loads(
        (root / "data" / "social" / "posts.json").read_text(encoding="utf-8"))
    try:
        import PIL  # noqa: F401
    except ImportError:
        print("[social] Pillow not installed — Instagram cards not rendered (pip install pillow)")
        return 0
    made = 0
    for p in posts:
        path = root / "site" / "social" / f"{p['id']}.jpg"
        if not path.exists():
            render_card(p, path)
            made += 1
    if made:
        print(f"[social] rendered {made} Instagram card(s) into site/social/")
    return made


# ------------------------------------------------------------------- seed ---

def seed(root, url, key):
    p = root / "data" / "social" / "posts.json"
    if not p.exists():
        return 0
    drafts = json.loads(p.read_text(encoding="utf-8"))
    rows = tp._req(url, key, "GET", "social_posts?select=id,platform,status,body")
    have = {r["id"] for r in rows}
    new = []
    for d in drafts:
        for rid, platform, body in platform_rows(d):
            if rid not in have:
                new.append({"id": rid, "platform": platform, "topic": d.get("topic"),
                            "body": body, "status": "draft"})
    if new:
        tp._req(url, key, "POST", "social_posts", new, prefer="return=minimal")
        by = {}
        for n in new:
            by[n["platform"]] = by.get(n["platform"], 0) + 1
        print(f"[social] seeded {len(new)} new draft(s) for approval: "
              + ", ".join(f"{k} {v}" for k, v in by.items()))
    # Unposted Facebook rows written under an older house style get the
    # current CTA, the short app link and the wording fixes; everything
    # else in the body is left alone.
    moved = 0
    for r in rows:
        if r.get("status") not in ("draft", "approved") or (r.get("platform") or "facebook") != "facebook":
            continue
        b = migrate(r.get("body"))
        if b != (r.get("body") or "").rstrip():
            tp._req(url, key, "PATCH", f"social_posts?id=eq.{r['id']}", {"body": b},
                    prefer="return=minimal")
            moved += 1
    if moved:
        print(f"[social] {moved} unposted row(s) brought up to the current CTA / wording")
    # Rows for a platform we no longer seed (Instagram) are retired, not
    # deleted — the table is the audit trail.
    retired = 0
    for r in rows:
        plat = r.get("platform") or "facebook"
        if plat in SEEDED_PLATFORMS or r.get("status") not in ("draft", "approved"):
            continue
        tp._req(url, key, "PATCH", f"social_posts?id=eq.{r['id']}",
                {"status": "retired", "error": RETIRE_NOTE.get(plat, f"retired: {plat} not in use")},
                prefer="return=minimal")
        retired += 1
    if retired:
        print(f"[social] retired {retired} row(s) for platforms not in use")
    return len(new)


# ------------------------------------------------------------------- post ---

def slot_due(rows, now, platform="facebook"):
    """The current slot hour, if nothing has been posted on this platform in
    it today."""
    if now.hour not in SLOTS_UTC:
        return None
    for r in rows:
        if (r.get("platform") or "facebook") != platform:
            continue
        if r.get("status") == "posted" and (r.get("posted_at") or "")[:13] == now.isoformat()[:13]:
            return None
    return now.hour


def _gate(env, platform):
    """(enabled, publisher-ready, why-not) for a platform."""
    if platform == "facebook":
        on = (env.get("SOCIAL_POSTING_ENABLED") or "").lower() == "true"
        tok = env.get("META_TOKEN") or env.get("WHATSAPP_TOKEN") or ""
        return on, bool(tok), ("SOCIAL_POSTING_ENABLED is off" if not on else "no Meta token")
    if platform == "x":
        on = (env.get("SOCIAL_X_ENABLED") or "").lower() == "true"
        return on, x_credentials(env) is not None, ("SOCIAL_X_ENABLED is off" if not on
                                                     else "X_API_KEY / X_API_SECRET / X_ACCESS_TOKEN / X_ACCESS_SECRET not all set")
    on = (env.get("SOCIAL_INSTAGRAM_ENABLED") or "").lower() == "true"
    tok = env.get("META_TOKEN") or env.get("WHATSAPP_TOKEN") or ""
    ready = bool(tok) and bool(env.get("IG_USER_ID"))
    return on, ready, ("SOCIAL_INSTAGRAM_ENABLED is off" if not on else "no Meta token / IG_USER_ID")


def post_one(root, url, key, env, now, _publish=None, platform="facebook",
             _publish_x=None, _publish_ig=None):
    rows = tp._req(url, key, "GET", "social_posts?select=*&order=created_at,id")
    slot = slot_due(rows, now, platform)
    if slot is None:
        return None
    pool = [r for r in rows if r.get("status") == "approved"
            and (r.get("platform") or "facebook") == platform]
    if not pool:
        print(f"[social] {platform}: slot {slot:02d}:00 — nothing approved to post (pool empty)")
        return None
    r = pool[0]
    why = house_rules(r.get("body"), platform)
    image_url = None
    if platform == "instagram" and not why:
        sid = source_id(r["id"])
        if not (root / "site" / "social" / f"{sid}.jpg").exists():
            why = f"no image card for {sid} (site/social/{sid}.jpg)"
        image_url = f"{(env.get('SOCIAL_IMAGE_BASE') or IMAGE_BASE_DEFAULT).rstrip('/')}/{sid}.jpg"
    if why:
        tp._req(url, key, "PATCH", f"social_posts?id=eq.{r['id']}",
                {"status": "failed", "error": f"house rules: {why}"}, prefer="return=minimal")
        print(f"[social] {r['id']} blocked — {why}")
        return post_one(root, url, key, env, now, _publish, platform, _publish_x, _publish_ig)
    enabled, ready, reason = _gate(env, platform)
    if not enabled or not ready:
        print(f"[social] DRY_RUN {platform} slot {slot:02d}:00 would post {r['id']} ({r.get('topic')}) — {reason}")
        return None
    text = r["body"].strip()
    try:
        if platform == "facebook":
            token = env.get("META_TOKEN") or env.get("WHATSAPP_TOKEN") or ""
            post_id = (_publish or publish_default)(token, env.get("FB_PAGE_ID") or PAGE_ID_DEFAULT, text)
        elif platform == "x":
            post_id = (_publish_x or publish_x)(x_credentials(env), text)
        else:
            token = env.get("META_TOKEN") or env.get("WHATSAPP_TOKEN") or ""
            post_id = (_publish_ig or publish_instagram)(token, env.get("IG_USER_ID"), image_url, text)
    except Exception as e:  # noqa: BLE001
        attempts = int(r.get("attempts") or 0) + 1
        patch = {"attempts": attempts, "error": f"{type(e).__name__}: {str(e)[:200]}"}
        if attempts >= MAX_ATTEMPTS:
            patch["status"] = "failed"
        tp._req(url, key, "PATCH", f"social_posts?id=eq.{r['id']}", patch, prefer="return=minimal")
        print(f"[social] FAILED {r['id']} on {platform} (attempt {attempts}): {patch['error']}")
        return None
    tp._req(url, key, "PATCH", f"social_posts?id=eq.{r['id']}",
            {"status": "posted", "posted_at": now.isoformat(), "post_id": post_id,
             "error": None, "attempts": int(r.get("attempts") or 0) + 1},
            prefer="return=minimal")
    audit.record(root, url, key, "collector:social", "posted", "post", r["id"], None,
                 {"platform": platform, "post_id": post_id, "topic": r.get("topic")},
                 f"slot {slot:02d}:00 UTC — approved by {r.get('approved_by') or '?'}", now)
    print(f"[social] POSTED {r['id']} -> {platform} {post_id} (pool left: {len(pool) - 1})")
    return post_id


def run(root, env, now):
    """Loud but never fatal."""
    url = (env.get("SUPABASE_URL") or "").rstrip("/")
    key = env.get("SUPABASE_SECRET_KEY") or ""
    if not url or not key:
        return
    try:
        seed(root, url, key)
    except Exception as e:  # noqa: BLE001
        print(f"[social] seed SKIPPED: {type(e).__name__}: {str(e)[:160]}")
    if "instagram" in SEEDED_PLATFORMS:
        try:
            ensure_images(root)
        except Exception as e:  # noqa: BLE001
            print(f"[social] images SKIPPED: {type(e).__name__}: {str(e)[:160]}")
    for platform in SEEDED_PLATFORMS:
        try:
            post_one(root, url, key, env, now, platform=platform)
        except Exception as e:  # noqa: BLE001
            print(f"[social] {platform} SKIPPED: {type(e).__name__}: {str(e)[:160]}")
