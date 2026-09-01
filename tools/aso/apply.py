#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Push ASO metadata to App Store Connect and verify by read-back.

  python3 tools/aso/apply.py check                    preflight: no token spent twice
  python3 tools/aso/apply.py subtitle [--dry-run]     app-level subtitle, every locale
  python3 tools/aso/apply.py version <versionId> <MAC_OS|IOS> [--dry-run]
                                                      keywords + promotional text
  python3 tools/aso/apply.py descriptions <versionId> <MAC_OS|IOS> [--dry-run]

Transport is the `asc` CLI (credentials in the system keychain, `asc auth
status` to check). It replaced the vibe-aso plugin's asc.rb, whose
~/.vibe-aso/config.json no longer exists on this machine.
"""
import json, subprocess, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import keywords as K, metadata as M

APP_ID = "6760177675"

# A version pulled back from review is DEVELOPER_REJECTED, not
# PREPARE_FOR_SUBMISSION — both are editable.
EDITABLE_VERSION_STATES = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                           "REJECTED", "METADATA_REJECTED"}

# States in which the shared name/subtitle record must not be touched. Editing
# it mid-review is a classic Metadata Rejected trigger.
LOCKED_APP_INFO_STATES = {"WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE"}


def asc(*args):
    """Run the asc CLI and parse its JSON. Raises with stderr on failure."""
    p = subprocess.run(["asc", *args], capture_output=True, text=True)
    out = (p.stdout or "").strip()
    if p.returncode != 0:
        raise SystemExit(f"asc {' '.join(args)} failed:\n{out}\n{p.stderr.strip()}")
    return json.loads(out) if out else {}


def rows(payload):
    return payload["data"] if isinstance(payload, dict) else payload


def editable_app_info():
    """The pending appInfo — the one carrying edits, not the live listing."""
    infos = rows(asc("apps", "info", "list", "--app", APP_ID))
    pending = [i for i in infos if i["attributes"]["state"] != "READY_FOR_DISTRIBUTION"]
    if not pending:
        raise SystemExit("no editable appInfo — nothing is pending")
    return pending[0]


def app_info_localizations(app_info_id):
    return rows(asc("localizations", "list", "--app", APP_ID,
                    "--app-info", app_info_id, "--type", "app-info", "--paginate"))


def version_localizations(version_id):
    return rows(asc("localizations", "list", "--version", version_id, "--paginate"))


def versions():
    return [(v["id"], v["attributes"]["platform"], v["attributes"]["versionString"],
             v["attributes"]["appVersionState"])
            for v in rows(asc("versions", "list", "--app", APP_ID, "--paginate"))]


def apply_subtitle(dry):
    info = editable_app_info()
    state = info["attributes"]["state"]
    if state in LOCKED_APP_INFO_STATES:
        print(f"REFUSING: appInfo is {state} — a submission is in review.")
        print("Editing the shared name/subtitle now risks Metadata Rejected.")
        print("Cancel the submission or wait for the verdict, then re-run.")
        return 1
    problems = M.check()
    if problems:
        for p in problems:
            print("  BLOCKED", p)
        return len(problems)
    ok = fail = 0
    for loc in sorted(app_info_localizations(info["id"]),
                      key=lambda x: x["attributes"]["locale"]):
        name = loc["attributes"]["locale"]
        if name not in M.SUBTITLE:
            print(f"  {name:9} SKIP (no plan)"); continue
        want = M.SUBTITLE[name]
        if loc["attributes"].get("subtitle") == want:
            print(f"  {name:9} already {want}"); ok += 1; continue
        if dry:
            print(f"  {name:9} would set subtitle {len(want)}/30  {want}"); continue
        asc("localizations", "update", "--app", APP_ID, "--app-info", info["id"],
            "--type", "app-info", "--locale", name, "--subtitle", want)
        # A 2xx is not verification — read the field back and compare.
        got = {x["attributes"]["locale"]: x["attributes"].get("subtitle")
               for x in app_info_localizations(info["id"])}.get(name)
        good = got == want
        print(f"  {name:9} verify={'OK' if good else 'MISMATCH'}  {want}")
        ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"\n  verified {ok}, failed {fail}")
    return fail


def apply_version(version_id, platform, dry):
    promo = M.PROMO_MAC if platform == "MAC_OS" else M.PROMO_IOS
    problems = M.check()
    if problems:
        for p in problems:
            print("  BLOCKED", p)
        return len(problems)
    ok = fail = 0
    for loc in sorted(version_localizations(version_id),
                      key=lambda x: x["attributes"]["locale"]):
        name = loc["attributes"]["locale"]
        if name not in K.EXTRA:
            print(f"  {name:9} SKIP (no plan for this locale)"); continue
        kw, _ = K.field(name, platform)
        want = {"keywords": kw, "promotionalText": promo[name]}
        if all(loc["attributes"].get(k) == v for k, v in want.items()):
            print(f"  {name:9} already current kw={len(kw)}/100"); ok += 1; continue
        if dry:
            print(f"  {name:9} would set kw={len(kw)}/100 promo={len(want['promotionalText'])}/170")
            continue
        asc("localizations", "update", "--version", version_id, "--locale", name,
            "--keywords", kw, "--promotional-text", want["promotionalText"])
        got = {x["attributes"]["locale"]: x["attributes"]
               for x in version_localizations(version_id)}.get(name, {})
        good = all(got.get(k) == v for k, v in want.items())
        print(f"  {name:9} verify={'OK' if good else 'MISMATCH'} kw={len(kw)}/100")
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
    state = dict((v[0], v[3]) for v in versions()).get(version_id)
    if state not in EDITABLE_VERSION_STATES:
        print(f"REFUSING: version is {state} — appStoreVersionLocalizations are")
        print("editable only while their version is. These ride the next release.")
        return 1
    current = {x["attributes"]["locale"]: x for x in version_localizations(version_id)}
    en_us = (current.get("en-US") or {}).get("attributes", {}).get("description")
    if not en_us:
        print("no en-US description on this version — nothing to translate from")
        return 1
    ok = fail = 0
    for locale in D.LOCALES:
        row = current.get(locale)
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
            print(f"  {locale:9} would set description {len(want)}/{D.LIMIT}"); continue
        asc("localizations", "update", "--version", version_id, "--locale", locale,
            "--description", want)
        got = {x["attributes"]["locale"]: x["attributes"].get("description")
               for x in version_localizations(version_id)}.get(locale)
        good = got == want
        print(f"  {locale:9} verify={'OK' if good else 'MISMATCH'} {len(want)}/{D.LIMIT}")
        ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"\n  verified {ok}, failed {fail}")
    return fail


def check():
    """Name + subtitle + keywords must not overlap, and nothing Apple rejected
    may be back in a subtitle. Run before submitting."""
    bad = len(M.check())
    for p in M.check():
        print(f"  COMPLIANCE {p}")
    info = editable_app_info()
    subs = {x["attributes"]["locale"]: (x["attributes"]["name"], x["attributes"]["subtitle"])
            for x in app_info_localizations(info["id"])}
    for vid, plat, vstr, state in versions():
        if state not in EDITABLE_VERSION_STATES:
            continue
        print(f"\n  version {vstr} ({plat}) [{state}]")
        for x in sorted(version_localizations(vid), key=lambda y: y["attributes"]["locale"]):
            loc = x["attributes"]["locale"]
            kw = x["attributes"].get("keywords") or ""
            name, sub = subs.get(loc, ("", ""))
            surface = f"{name} {sub}".lower()
            dupes = sorted(t for t in {t.strip().lower() for t in kw.split(",") if t.strip()}
                           if t in surface)
            if dupes:
                print(f"    {loc:9} DUPLICATE across surfaces: {', '.join(dupes)}")
                bad += 1
    if bad == 0:
        print("\n  clean: no banned term in any subtitle, no token spent twice")
    else:
        print(f"\n  {bad} problem(s)")
    return bad


if __name__ == "__main__":
    dry = "--dry-run" in sys.argv
    cmd = sys.argv[1]
    if cmd == "version":
        sys.exit(1 if apply_version(sys.argv[2], sys.argv[3], dry) else 0)
    elif cmd == "descriptions":
        sys.exit(1 if apply_descriptions(sys.argv[2], sys.argv[3], dry) else 0)
    elif cmd == "subtitle":
        sys.exit(1 if apply_subtitle(dry) else 0)
    elif cmd == "check":
        sys.exit(1 if check() else 0)
    else:
        raise SystemExit(__doc__)
