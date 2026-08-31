#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Run once the in-flight review clears.

  python3 tools/aso/finish.py [--dry-run]

1. Writes the new subtitle to every existing locale (refuses while a submission
   is in review — editing the shared name/subtitle then risks Metadata Rejected).
2. Creates the 10 added locales: app-level record (name/subtitle/privacy URL)
   plus a version localization (description/keywords/promo) on each editable
   version. New locales get the English description — identical to the fallback
   Apple already shows them, so no regression; the win is their own keyword
   field and subtitle. Translating those 10 descriptions is optional follow-up.
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import keywords as K, metadata as M
from apply import asc, apply_subtitle, APP_ID

NEW_LOCALES = ["en-GB", "pt-BR", "ru", "pl", "tr", "uk", "id", "vi", "th", "zh-Hant"]
PRIVACY_URL = "https://screenshotbro.app/privacy"
APP_NAME = "Screenshot Bro: Mockup Maker"


# A version pulled back from review is DEVELOPER_REJECTED, not
# PREPARE_FOR_SUBMISSION — both are editable and both need the new locales.
EDITABLE_VERSION_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                           "REJECTED", "METADATA_REJECTED"}


def editable_versions():
    code, d = asc("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=20"
                         "&fields[appStoreVersions]=versionString,platform,appVersionState")
    return [(v["id"], v["attributes"]["platform"], v["attributes"]["versionString"])
            for v in d["data"]
            if v["attributes"]["appVersionState"] in EDITABLE_VERSION_STATES]


def english_source(version_id):
    """This version's own en-US description and release notes.

    Read per version, never hardcoded: the macOS and iOS trains carry different
    descriptions (iOS must not advertise the macOS-only MCP server) and
    different release notes.
    """
    code, d = asc("GET", f"/v1/appStoreVersions/{version_id}"
                         f"/appStoreVersionLocalizations?limit=200")
    for x in d["data"]:
        if x["attributes"]["locale"] == "en-US":
            a = x["attributes"]
            return a["description"], (a.get("whatsNew") or "")
    raise SystemExit(f"no en-US localization on {version_id}")


def add_locales(dry):
    code, infos = asc("GET", f"/v1/apps/{APP_ID}/appInfos")
    info = next(i for i in infos["data"]
                if i["attributes"]["state"] != "READY_FOR_DISTRIBUTION")
    state = info["attributes"]["state"]
    if state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
        print(f"REFUSING to add locales: appInfo is {state}."); return 1
    code, existing = asc("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=200")
    have = {x["attributes"]["locale"] for x in existing["data"]}
    fail = 0
    for loc in NEW_LOCALES:
        if loc in have:
            print(f"  {loc:9} app-level already exists"); continue
        if dry:
            print(f"  {loc:9} would create app-level: {M.SUBTITLE[loc]}"); continue
        c, r = asc("POST", "/v1/appInfoLocalizations", {"data": {
            "type": "appInfoLocalizations",
            "attributes": {"locale": loc, "name": APP_NAME,
                           "subtitle": M.SUBTITLE[loc], "privacyPolicyUrl": PRIVACY_URL},
            "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})
        ok = c in (200, 201)
        print(f"  {loc:9} app-level POST {c} {'OK' if ok else r}")
        fail += 0 if ok else 1

    for vid, platform, vstr in editable_versions():
        print(f"\n  version {vstr} ({platform})")
        desc, whats_new = english_source(vid)
        promo = M.PROMO_MAC if platform == "MAC_OS" else M.PROMO_IOS
        c, ex = asc("GET", f"/v1/appStoreVersions/{vid}/appStoreVersionLocalizations?limit=200")
        existing = {x["attributes"]["locale"]: x for x in ex["data"]}
        for loc in NEW_LOCALES:
            kw, _ = K.field(loc, platform)
            attrs = {"description": desc, "keywords": kw,
                     "promotionalText": promo[loc], "whatsNew": whats_new}
            row = existing.get(loc)
            if dry:
                verb = "fill" if row else "create"
                print(f"    {loc:9} would {verb} version-level kw={len(kw)}/100"); continue
            if row:
                # Creating the app-level locale makes App Store Connect auto-add an
                # EMPTY version localization, so this is a fill, not a skip — an
                # empty description blocks submission outright.
                c, r = asc("PATCH", f"/v1/appStoreVersionLocalizations/{row['id']}",
                           {"data": {"type": "appStoreVersionLocalizations",
                                     "id": row["id"], "attributes": attrs}})
            else:
                c, r = asc("POST", "/v1/appStoreVersionLocalizations", {"data": {
                    "type": "appStoreVersionLocalizations",
                    "attributes": {"locale": loc, **attrs},
                    "relationships": {"appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": vid}}}}})
            rid = row["id"] if row else (r.get("data", {}) or {}).get("id")
            good = False
            if c in (200, 201) and rid:
                rc, rd = asc("GET", f"/v1/appStoreVersionLocalizations/{rid}")
                got = rd.get("data", {}).get("attributes", {}) if rc == 200 else {}
                good = all(got.get(k) == v for k, v in attrs.items())
            print(f"    {loc:9} {c} verify={'OK' if good else 'MISMATCH'} kw={len(kw)}/100")
            fail += 0 if good else 1
    return fail


if __name__ == "__main__":
    dry = "--dry-run" in sys.argv
    print("== subtitles on existing locales")
    f1 = apply_subtitle(dry)
    print("\n== add new locales")
    f2 = add_locales(dry)
    sys.exit(1 if (f1 or f2) else 0)
