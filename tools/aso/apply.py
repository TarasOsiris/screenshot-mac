#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Push ASO metadata to App Store Connect and verify by read-back.

  python3 tools/aso/apply.py version <versionId> <MAC_OS|IOS> [--dry-run]
      keywords + promotional text on that version's localizations
  python3 tools/aso/apply.py subtitle [--dry-run]
      subtitle on the app-level record (locked while a submission is in review)
  python3 tools/aso/apply.py descriptions <versionId> <MAC_OS|IOS> [--dry-run]
      the 10 added locales' descriptions on that version's localizations
"""
import json, subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import keywords as K, metadata as M

ASC = os.path.expanduser(
    "~/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb")
APP_ID = "6760177675"

# A version pulled back from review is DEVELOPER_REJECTED, not
# PREPARE_FOR_SUBMISSION — both are editable.
EDITABLE_VERSION_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                           "REJECTED", "METADATA_REJECTED"}


def asc(method, path, body=None):
    cmd = ["ruby", ASC, method, path] + ([json.dumps(body)] if body else [])
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    head, _, rest = out.partition("\n")
    code = int(head.split()[1])
    try:
        return code, json.loads(rest) if rest.strip() else {}
    except json.JSONDecodeError:
        return code, {"raw": rest}


def apply_version(version_id, platform, dry):
    code, d = asc("GET", f"/v1/appStoreVersions/{version_id}"
                         f"/appStoreVersionLocalizations?limit=200")
    assert code == 200, f"list failed: {code} {d}"
    promo = M.PROMO_MAC if platform == "MAC_OS" else M.PROMO_IOS
    ok = fail = 0
    for loc in sorted(d["data"], key=lambda x: x["attributes"]["locale"]):
        name = loc["attributes"]["locale"]
        if name not in K.EXTRA:
            print(f"  {name:9} SKIP (no plan for this locale)"); continue
        kw, _ = K.field(name, platform)
        want = {"keywords": kw, "promotionalText": promo[name]}
        if dry:
            print(f"  {name:9} would set kw={len(kw)}/100 promo={len(want['promotionalText'])}/170")
            continue
        code, _ = asc("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}",
                      {"data": {"type": "appStoreVersionLocalizations",
                                "id": loc["id"], "attributes": want}})
        # A 2xx is not verification — read the field back and compare.
        rcode, rd = asc("GET", f"/v1/appStoreVersionLocalizations/{loc['id']}")
        got = rd.get("data", {}).get("attributes", {}) if rcode == 200 else {}
        good = got.get("keywords") == kw and got.get("promotionalText") == want["promotionalText"]
        print(f"  {name:9} PATCH {code} verify={'OK' if good else 'MISMATCH'} kw={len(kw)}/100")
        ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"\n  verified {ok}, failed {fail}")
    return fail


def apply_descriptions(version_id, platform, dry):
    """Descriptions for the 10 locales added in Aug 2026, verified by read-back.

    Every text is re-reviewed against this version's own en-US row immediately
    before the write: the API creates a version without inheriting localized copy
    the way the web UI does, so a new release can silently be back on English.
    """
    import descriptions as D
    code, v = asc("GET", f"/v1/appStoreVersions/{version_id}")
    assert code == 200, f"version read failed: {code} {v}"
    state = v["data"]["attributes"]["appVersionState"]
    if state not in EDITABLE_VERSION_STATES:
        print(f"REFUSING: version is {state} — appStoreVersionLocalizations are")
        print("editable only while their version is. These ride the next release.")
        return 1
    code, d = asc("GET", f"/v1/appStoreVersions/{version_id}"
                         f"/appStoreVersionLocalizations?limit=200")
    rows = {x["attributes"]["locale"]: x for x in d["data"]}
    en_us = (rows.get("en-US") or {}).get("attributes", {}).get("description")
    if not en_us:
        print("no en-US description on this version — nothing to translate from")
        return 1
    ok = fail = 0
    for locale in D.LOCALES:
        row = rows.get(locale)
        if not row:
            print(f"  {locale:9} SKIP (locale absent from this version — run finish.py)")
            continue
        want = D.text_for(platform, locale, en_us)
        problems = D.review(platform, locale, want, en_us)
        if problems:
            for problem in problems:
                print(f"  {locale:9} BLOCKED {problem}")
            fail += 1
            continue
        if dry:
            print(f"  {locale:9} would set description {len(want)}/{D.LIMIT}")
            continue
        code, _ = asc("PATCH", f"/v1/appStoreVersionLocalizations/{row['id']}",
                      {"data": {"type": "appStoreVersionLocalizations",
                                "id": row["id"], "attributes": {"description": want}}})
        rcode, rd = asc("GET", f"/v1/appStoreVersionLocalizations/{row['id']}")
        got = rd.get("data", {}).get("attributes", {}).get("description") if rcode == 200 else None
        good = got == want
        print(f"  {locale:9} PATCH {code} verify={'OK' if good else 'MISMATCH'} "
              f"{len(want)}/{D.LIMIT}")
        ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"\n  verified {ok}, failed {fail}")
    return fail


def apply_subtitle(dry):
    code, infos = asc("GET", f"/v1/apps/{APP_ID}/appInfos")
    assert code == 200
    editable = [i for i in infos["data"]
                if i["attributes"]["state"] not in ("READY_FOR_DISTRIBUTION",)]
    if not editable:
        print("no editable appInfo"); return 1
    info = editable[0]
    state = info["attributes"]["state"]
    if state in ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"):
        print(f"REFUSING: appInfo is {state} — a submission is in review.")
        print("Editing the shared name/subtitle now risks Metadata Rejected.")
        print("Re-run once the review completes.")
        return 1
    code, d = asc("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=200")
    ok = fail = 0
    for loc in sorted(d["data"], key=lambda x: x["attributes"]["locale"]):
        name = loc["attributes"]["locale"]
        if name not in M.SUBTITLE:
            print(f"  {name:9} SKIP (no plan)"); continue
        want = M.SUBTITLE[name]
        if dry:
            print(f"  {name:9} would set subtitle {len(want)}/30  {want}"); continue
        code, _ = asc("PATCH", f"/v1/appInfoLocalizations/{loc['id']}",
                      {"data": {"type": "appInfoLocalizations", "id": loc["id"],
                                "attributes": {"subtitle": want}}})
        rcode, rd = asc("GET", f"/v1/appInfoLocalizations/{loc['id']}")
        got = rd.get("data", {}).get("attributes", {}).get("subtitle") if rcode == 200 else None
        good = got == want
        print(f"  {name:9} PATCH {code} verify={'OK' if good else 'MISMATCH'}  {want}")
        ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"\n  verified {ok}, failed {fail}")
    return fail


def check():
    """Preflight: name + subtitle + keywords must not overlap. Run before submitting."""
    code, infos = asc("GET", f"/v1/apps/{APP_ID}/appInfos")
    info = next(i for i in infos["data"]
                if i["attributes"]["state"] != "READY_FOR_DISTRIBUTION")
    code, il = asc("GET", f"/v1/appInfos/{info['id']}/appInfoLocalizations?limit=200")
    subs = {x["attributes"]["locale"]: (x["attributes"]["name"], x["attributes"]["subtitle"])
            for x in il["data"]}
    code, vs = asc("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=20"
                          "&fields[appStoreVersions]=versionString,platform,appVersionState")
    bad = 0
    for v in vs["data"]:
        if v["attributes"]["appVersionState"] != "PREPARE_FOR_SUBMISSION":
            continue
        vstr, plat = v["attributes"]["versionString"], v["attributes"]["platform"]
        print(f"\n  version {vstr} ({plat})")
        code, d = asc("GET", f"/v1/appStoreVersions/{v['id']}"
                             f"/appStoreVersionLocalizations?limit=200")
        for x in sorted(d["data"], key=lambda y: y["attributes"]["locale"]):
            loc = x["attributes"]["locale"]
            kw = x["attributes"].get("keywords") or ""
            name, sub = subs.get(loc, ("", ""))
            surface = {w.strip(".,:&-").lower()
                       for w in f"{name} {sub}".split() if len(w.strip(".,:&-")) > 2}
            dupes = sorted({t.strip().lower() for t in kw.split(",")} & surface)
            if dupes:
                print(f"    {loc:9} DUPLICATE across surfaces: {', '.join(dupes)}")
                bad += 1
    if bad == 0:
        print("\n  no duplicate tokens across name/subtitle/keywords — safe to submit")
    else:
        print(f"\n  {bad} locale(s) waste keyword budget. Run finish.py first.")
    return bad


if __name__ == "__main__":
    dry = "--dry-run" in sys.argv
    if sys.argv[1] == "version":
        sys.exit(1 if apply_version(sys.argv[2], sys.argv[3], dry) else 0)
    elif sys.argv[1] == "descriptions":
        sys.exit(1 if apply_descriptions(sys.argv[2], sys.argv[3], dry) else 0)
    elif sys.argv[1] == "subtitle":
        sys.exit(1 if apply_subtitle(dry) else 0)
    elif sys.argv[1] == "check":
        sys.exit(1 if check() else 0)
