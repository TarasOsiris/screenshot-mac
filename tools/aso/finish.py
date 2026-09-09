#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Bring every locale up to the current plan.

  python3 tools/aso/finish.py [--dry-run]

1. Writes the subtitle to every existing locale (delegates to apply.py, which
   refuses while a submission is in review).
2. Fills any locale that exists app-level but is empty or stale on an editable
   version — description, keywords, promotional text, release notes.

Step 2 is a no-op whenever every planned locale already exists. It stays because
App Store Connect auto-creates an *empty* version localization whenever an
app-level locale appears, and an empty description blocks submission outright.

Creating a brand-new app-level locale is not something *this* script can do, but
it is not a web-UI-only step either. The `asc` CLI has no app-info localization
create (`asc localizations create` takes --version, so it only makes version
localizations); the REST API does — `POST /v1/appInfoLocalizations` with an
appInfo relationship.

The real constraint is state, not transport. That POST returns 409
ENTITY_ERROR.RELATIONSHIP.INVALID, "A relationship cannot be created in current
state", unless the target appInfo is editable — and the editable appInfo only
exists while a version is in flight. So new locales are added *during* a release,
after the version record exists, not before it. Verified 2026-09-09.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import keywords as K, metadata as M
from apply import (asc, apply_subtitle, editable_app_info, app_info_localizations,
                   version_localizations, versions, EDITABLE_VERSION_STATES)

PLANNED_LOCALES = sorted(M.SUBTITLE)


def english_source(rows):
    """This version's own en-US description and release notes.

    Read per version, never hardcoded: the macOS and iOS trains carry different
    descriptions (iOS must not advertise the macOS-only MCP server) and
    different release notes.
    """
    for x in rows:
        if x["attributes"]["locale"] == "en-US":
            a = x["attributes"]
            return a["description"], (a.get("whatsNew") or "")
    raise SystemExit("no en-US localization on this version")


def _same(got, want):
    """App Store Connect returns an unset text field as null, never "".

    Without this, a version whose release notes are not written yet makes every
    locale compare `None != ""` and the run reports a mismatch for all 38 — while
    the write itself succeeded. That is the normal state of a TestFlight-only
    ship, so the false failure is the common case, not the edge one.
    """
    return (got or "") == (want or "")


def fill_locales(dry):
    info = editable_app_info()
    have = {x["attributes"]["locale"] for x in app_info_localizations(info["id"])}
    missing = [loc for loc in PLANNED_LOCALES if loc not in have]
    if missing:
        print(f"  app-level locales missing: {', '.join(missing)}")
        print("  Create them with POST /v1/appInfoLocalizations against appInfo "
              f"{info['id']} (the asc CLI cannot), then re-run.")
    fail = len(missing)

    for vid, platform, vstr, state in versions():
        if state not in EDITABLE_VERSION_STATES:
            continue
        print(f"\n  version {vstr} ({platform}) [{state}]")
        rows = version_localizations(vid)
        desc, whats_new = english_source(rows)
        promo = M.PROMO_MAC if platform == "MAC_OS" else M.PROMO_IOS
        current = {x["attributes"]["locale"]: x["attributes"] for x in rows}
        for loc in PLANNED_LOCALES:
            if loc not in current:
                print(f"    {loc:9} MISSING at version level")
                fail += 1
                continue
            kw, _ = K.field(loc, platform)
            want = {"description": current[loc].get("description") or desc,
                    "keywords": kw, "promotionalText": promo[loc],
                    "whatsNew": current[loc].get("whatsNew") or whats_new}
            if all(_same(current[loc].get(k), v) for k, v in want.items()):
                continue
            if dry:
                print(f"    {loc:9} would fill "
                      f"{[k for k, v in want.items() if not _same(current[loc].get(k), v)]}")
                continue
            asc("localizations", "update", "--version", vid, "--locale", loc,
                "--description", want["description"], "--keywords", want["keywords"],
                "--promotional-text", want["promotionalText"],
                "--whats-new", want["whatsNew"])
            got = {x["attributes"]["locale"]: x["attributes"]
                   for x in version_localizations(vid)}.get(loc, {})
            good = all(_same(got.get(k), v) for k, v in want.items())
            print(f"    {loc:9} verify={'OK' if good else 'MISMATCH'}")
            fail += 0 if good else 1
    return fail


if __name__ == "__main__":
    dry = "--dry-run" in sys.argv
    print("== subtitles on existing locales")
    f1 = apply_subtitle(dry)
    print("\n== fill locales on editable versions")
    f2 = fill_locales(dry)
    print(f"\n  {f1 + f2} problem(s)")
    sys.exit(1 if (f1 or f2) else 0)
