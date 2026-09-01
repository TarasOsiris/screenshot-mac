#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Bring every locale up to the current plan.

  python3 tools/aso/finish.py [--dry-run]

1. Writes the subtitle to every existing locale (delegates to apply.py, which
   refuses while a submission is in review).
2. Fills any locale that exists app-level but is empty or stale on an editable
   version — description, keywords, promotional text, release notes.

The 10 locales added in Aug 2026 are all present, so step 2 is normally a no-op.
It stays because App Store Connect auto-creates an *empty* version localization
whenever an app-level locale appears, and an empty description blocks submission
outright.

Creating a brand-new app-level locale is not scriptable here: the `asc` CLI has
no app-info localization create, and that is the only transport with working
credentials on this machine. Add it in App Store Connect (App Information ▸ the
language selector), then re-run this to fill it.
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


def fill_locales(dry):
    info = editable_app_info()
    have = {x["attributes"]["locale"] for x in app_info_localizations(info["id"])}
    missing = [loc for loc in PLANNED_LOCALES if loc not in have]
    if missing:
        print(f"  app-level locales missing: {', '.join(missing)}")
        print("  Add them in App Store Connect ▸ App Information, then re-run.")
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
            if all(current[loc].get(k) == v for k, v in want.items()):
                continue
            if dry:
                print(f"    {loc:9} would fill {[k for k, v in want.items() if current[loc].get(k) != v]}")
                continue
            asc("localizations", "update", "--version", vid, "--locale", loc,
                "--description", want["description"], "--keywords", want["keywords"],
                "--promotional-text", want["promotionalText"],
                "--whats-new", want["whatsNew"])
            got = {x["attributes"]["locale"]: x["attributes"]
                   for x in version_localizations(vid)}.get(loc, {})
            good = all(got.get(k) == v for k, v in want.items())
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
