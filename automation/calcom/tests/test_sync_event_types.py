"""Unit tests for automation/calcom/sync-event-types.py — no network, no Cal.com.

The script's only side effects are HTTP calls through its call() function and
reads of the service catalogue; both are replaced here, so the plan it builds
(create / update / leave alone) and the writes it makes with --apply are
checked against a synthetic catalogue and a synthetic Cal.com account.
"""
import importlib.util
import json
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("sync_event_types", HERE.parent / "sync-event-types.py")
sync = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sync)

CATALOGUE = {
    "bookingFeeGbp": 5,
    "services": [
        {"slug": "pc-health-check", "name": "PC health check", "durationMinutes": 60,
         "bookable": True, "priceIncVat": 49},
        {"slug": "m365-setup", "name": "Microsoft 365 setup", "durationMinutes": 90,
         "bookable": True, "priceExVat": 120, "unit": "per user", "location": "video"},
        {"slug": "remote-support-session", "name": "Remote support", "durationMinutes": 30,
         "bookable": True, "existing": True},
        {"slug": "not-bookable", "name": "Quote only", "durationMinutes": 0, "bookable": False},
    ],
}


class FakeCal:
    def __init__(self, existing):
        self.existing = existing
        self.calls = []

    def __call__(self, method, url, key, body=None):
        self.calls.append((method, url, body))
        if method == "GET":
            return {"data": self.existing}
        if method == "POST":
            return {"data": {"id": 999}}
        return {}


@pytest.fixture
def env(tmp_path, monkeypatch):
    (tmp_path / "projects/web/itsurgery/src/_data").mkdir(parents=True)
    (tmp_path / "projects/web/itsurgery/src/_data/catalogue.json").write_text(json.dumps(CATALOGUE))
    monkeypatch.setattr(sync, "repo_root", lambda: tmp_path)
    monkeypatch.setenv("CALCOM_API_KEY", "cal_test")
    def run(existing, apply=False):
        api = FakeCal(existing)
        monkeypatch.setattr(sync, "call", api)
        monkeypatch.setattr(sys, "argv", ["sync-event-types.py"] + (["--apply"] if apply else []))
        sync.main()
        return api
    return run


def test_description_home_price_includes_vat_and_fee():
    d = sync.description({"priceIncVat": 49}, 5)
    assert d.startswith("Fixed price £49.")
    assert "£5 booking fee" in d


def test_description_business_price_ex_vat_with_unit():
    d = sync.description({"priceExVat": 120, "unit": "per user"}, 5)
    assert d.startswith("Fixed price £120 ex VAT per user.")


def test_dry_run_plans_but_writes_nothing(env, capsys):
    api = env(existing=[{"id": 1, "slug": "remote-support-session", "title": "Remote support",
                         "lengthInMinutes": 30, "locations": [{"type": "attendeeAddress"}],
                         "useDestinationCalendarEmail": True},
                        {"id": 2, "slug": "somebody-elses", "title": "Leave me", "lengthInMinutes": 15}])
    out = capsys.readouterr().out
    assert [m for m, _, _ in api.calls] == ["GET"], "dry run must not write"
    assert "CREATE  pc-health-check" in out and "CREATE  m365-setup" in out
    assert "ok      remote-support-session" in out
    assert "leave   somebody-elses" in out
    assert "would create 2, update 0" in out


def test_apply_creates_with_slug_and_never_deletes(env):
    api = env(existing=[], apply=True)
    posts = [(u, b) for m, u, b in api.calls if m == "POST"]
    assert {b["slug"] for _, b in posts} == {"pc-health-check", "m365-setup", "remote-support-session"}
    assert not any(m == "DELETE" for m, _, _ in api.calls)
    m365 = next(b for _, b in posts if b["slug"] == "m365-setup")
    assert m365["lengthInMinutes"] == 90
    assert m365["locations"] == [{"type": "integration", "integration": "cal-video"}]
    assert m365["useDestinationCalendarEmail"] is True
    assert "£120 ex VAT per user" in m365["description"]
    home = next(b for _, b in posts if b["slug"] == "pc-health-check")
    assert home["locations"] == [{"type": "attendeeAddress"}]
    assert not any(k in m365 for k in ("price", "currency", "metadata")), "never asks Cal.com to charge"


def test_apply_patches_only_drifted_fields(env):
    api = env(existing=[{"id": 7, "slug": "pc-health-check", "title": "PC health check",
                         "lengthInMinutes": 45,          # catalogue says 60
                         "description": sync.description(CATALOGUE["services"][0], 5),
                         "locations": [{"type": "attendeeAddress"}],
                         "useDestinationCalendarEmail": True}], apply=True)
    patches = [(u, b) for m, u, b in api.calls if m == "PATCH"]
    assert patches == [(f"{sync.API}/7", {"lengthInMinutes": 60})]


def test_existing_flag_keeps_hand_written_description(env):
    api = env(existing=[{"id": 3, "slug": "remote-support-session", "title": "Remote support",
                         "lengthInMinutes": 30, "description": "Written by hand, keep me.",
                         "locations": [{"type": "attendeeAddress"}],
                         "useDestinationCalendarEmail": True}], apply=True)
    assert not any(m == "PATCH" for m, _, _ in api.calls)


def test_bookable_flag_gates_the_plan(env, capsys):
    env(existing=[])
    assert "not-bookable" not in capsys.readouterr().out


# ------------------------------------------------- the real catalogue file ---
def test_real_catalogue_bookable_services_are_complete():
    root = Path(__file__).resolve().parents[3]
    cat = json.loads((root / "projects/web/itsurgery/src/_data/catalogue.json").read_text())
    assert isinstance(cat["bookingFeeGbp"], (int, float))
    slugs = []
    for svc in cat["services"]:
        if not svc.get("bookable"):
            continue
        for key in ("slug", "name", "durationMinutes"):
            assert svc.get(key), f"{svc.get('slug', svc)} lacks {key}"
        assert svc["durationMinutes"] > 0
        assert svc.get("existing") or "priceIncVat" in svc or "priceExVat" in svc, \
            f"{svc['slug']} has no price for its description"
        slugs.append(svc["slug"])
    assert len(slugs) == len(set(slugs)), "slugs must be unique (they are the Cal.com match key)"
