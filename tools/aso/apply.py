#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Push ASO metadata to App Store Connect and verify by read-back.

  python3 tools/aso/apply.py version <versionId> <MAC_OS|IOS> [--dry-run]
      keywords + promotional text on that version's localizations
  python3 tools/aso/apply.py subtitle [--dry-run]
      subtitle on the app-level record (locked while a submission is in review)
"""
import json, subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import keywords as K, metadata as M

ASC = os.path.expanduser(
    "~/.claude/plugins/cache/vibe-aso-marketplace/vibe-aso/0.1.0/skills/vibe-aso/scripts/asc.rb")
APP_ID = "6760177675"


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
    elif sys.argv[1] == "subtitle":
        sys.exit(1 if apply_subtitle(dry) else 0)
    elif sys.argv[1] == "check":
        sys.exit(1 if check() else 0)
