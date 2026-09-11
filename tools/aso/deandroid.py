# -*- coding: utf-8 -*-
"""Strip every Android and Pixel reference from the live App Store descriptions.

Apple rejected 4.14 (iOS) on 2026-09-11 under **2.3.10 — Accurate Metadata**:
"Revise the app's description and What's New text to remove Android references."

This overturns the call `degoogle.py` recorded two weeks earlier. That pass kept
`Android` and `Pixel` on the theory that naming a device frame the app really
draws is 2.3.10's own functionality carve-out, and removed only the words Apple
had named. Review has now named Android too, so the theory is dead: **any**
third-party platform word is treated as a competitor reference regardless of
whether the app implements it. The device frames themselves are untouched — this
is a metadata edit, not a feature removal.

The What's New half of the notice is boilerplate: the 4.14 release notes are one
English text in all 48 locales and contain no Android reference. Nothing to strip.

Same shape as `degoogle.py`, and for the same reason — only ~20 of the 96 live
texts (48 locales x 2 platform trains) exist in this repo, so the transform runs
against the **live** text and every edit is a pure deletion. No re-translation,
which would throw away copy that is already reviewed and correct. `descriptions.py`
carries the matching edit for the locales it does store, and its `BANNED_PLATFORM`
review now fails any text that names Android or Pixel.

  python3 tools/aso/deandroid.py <version-id> [--dry-run]

Re-running is a no-op: the fragments are gone, so nothing matches. It is kept as
the record of exactly which words left the listing.
"""
import json
import re
import subprocess
import sys

LIMIT = 4000

# Locale -> (old, new). Two deletions per locale: the device enumeration in the
# third paragraph, and the device-frame bullet. Both keep iPhone, iPad and Mac
# and drop the Android/Pixel items, re-joining the list in that language's own
# grammar (a bare token deletion would leave dangling commas and conjunctions).
# fr-CA and pl coordinate "phones and tablets" under one Android, so their
# paragraph rule removes four references rather than five.
RULES = {
 "en-US": [
  ("for iPhone, iPad, Mac, Android phones, Android tablets, and Pixel layouts.",
   "for iPhone, iPad, and Mac."),
  ("- Add device frames for iPhone, iPad, Mac, Android, Pixel, and abstract layouts",
   "- Add device frames for iPhone, iPad, Mac, and abstract layouts"),
 ],
 "en-GB": [
  ("for iPhone, iPad, Mac, Android phones, Android tablets, and Pixel layouts.",
   "for iPhone, iPad, and Mac."),
  ("- Add device frames for iPhone, iPad, Mac, Android, Pixel, and abstract layouts",
   "- Add device frames for iPhone, iPad, Mac, and abstract layouts"),
 ],
 "en-AU": [
  ("for iPhone, iPad, Mac, Android phones, Android tablets, and Pixel layouts.",
   "for iPhone, iPad, and Mac."),
  ("- Add device frames for iPhone, iPad, Mac, Android, Pixel, and abstract layouts",
   "- Add device frames for iPhone, iPad, Mac, and abstract layouts"),
 ],
 "en-CA": [
  ("for iPhone, iPad, Mac, Android phones, Android tablets, and Pixel layouts.",
   "for iPhone, iPad, and Mac."),
  ("- Add device frames for iPhone, iPad, Mac, Android, Pixel, and abstract layouts",
   "- Add device frames for iPhone, iPad, Mac, and abstract layouts"),
 ],
 "de-DE": [
  ("iPhone, iPad, Mac, Android-Smartphones, Android-Tablets und Pixel-Layouts.",
   "iPhone, iPad und Mac."),
  ("iPhone, iPad, Mac, Android, Pixel und abstrakte", "iPhone, iPad, Mac und abstrakte"),
 ],
 "fr-FR": [
  ("iPhone, iPad, Mac, téléphones Android, tablettes Android et mises en page Pixel.",
   "iPhone, iPad et Mac."),
  ("iPhone, iPad, Mac, Android, Pixel et des mises en page abstraites",
   "iPhone, iPad, Mac et des mises en page abstraites"),
 ],
 "fr-CA": [
  ("iPhone, iPad, Mac, téléphones et tablettes Android et mises en page Pixel.",
   "iPhone, iPad et Mac."),
  ("iPhone, iPad, Mac, Android, Pixel et des mises en page abstraites",
   "iPhone, iPad, Mac et des mises en page abstraites"),
 ],
 "es-ES": [
  ("iPhone, iPad, Mac, teléfonos Android, tablets Android y diseños Pixel.",
   "iPhone, iPad y Mac."),
  ("iPhone, iPad, Mac, Android, Pixel y diseños abstractos",
   "iPhone, iPad, Mac y diseños abstractos"),
 ],
 "es-MX": [
  ("iPhone, iPad, Mac, celulares Android, tabletas Android y diseños Pixel.",
   "iPhone, iPad y Mac."),
  ("iPhone, iPad, Mac, Android, Pixel y diseños abstractos",
   "iPhone, iPad, Mac y diseños abstractos"),
 ],
 "it": [
  ("iPhone, iPad, Mac, telefoni Android, tablet Android e layout Pixel.",
   "iPhone, iPad e Mac."),
  ("iPhone, iPad, Mac, Android, Pixel e layout astratti",
   "iPhone, iPad, Mac e layout astratti"),
 ],
 "nl-NL": [
  ("iPhone, iPad, Mac, Android-telefoons, Android-tablets en Pixel-indelingen.",
   "iPhone, iPad en Mac."),
  ("iPhone, iPad, Mac, Android, Pixel en abstracte", "iPhone, iPad, Mac en abstracte"),
 ],
 "sv": [
  ("iPhone, iPad, Mac, Android-telefoner, Android-surfplattor och Pixel-layouter.",
   "iPhone, iPad och Mac."),
  ("iPhone, iPad, Mac, Android, Pixel och abstrakta", "iPhone, iPad, Mac och abstrakta"),
 ],
 "da": [
  ("iPhone, iPad, Mac, Android-telefoner, Android-tablets og Pixel-layouts.",
   "iPhone, iPad og Mac."),
  ("iPhone, iPad, Mac, Android, Pixel og abstrakte", "iPhone, iPad, Mac og abstrakte"),
 ],
 "no": [
  ("iPhone, iPad, Mac, Android-telefoner, Android-nettbrett og Pixel-oppsett.",
   "iPhone, iPad og Mac."),
  ("iPhone, iPad, Mac, Android, Pixel og abstrakte", "iPhone, iPad, Mac og abstrakte"),
 ],
 "fi": [
  ("iPhone-, iPad-, Mac-, Android-puhelimille, Android-tableteille ja Pixel-asetteluille.",
   "iPhone-, iPad- ja Mac-asetteluille."),
  ("iPhonelle, iPadille, Macille, Androidille, Pixelille ja abstrakteille",
   "iPhonelle, iPadille, Macille ja abstrakteille"),
 ],
 "pt-PT": [
  ("iPhone, iPad, Mac, telemóveis Android, tablets Android e disposições Pixel.",
   "iPhone, iPad e Mac."),
  ("iPhone, iPad, Mac, Android, Pixel e disposições abstratas",
   "iPhone, iPad, Mac e disposições abstratas"),
 ],
 "pt-BR": [
  ("iPhone, iPad, Mac, celulares Android, tablets Android e layouts do Pixel.",
   "iPhone, iPad e Mac."),
  ("iPhone, iPad, Mac, Android, Pixel e layouts abstratos",
   "iPhone, iPad, Mac e layouts abstratos"),
 ],
 "pl": [
  ("iPhone'a, iPada, Maca, telefonów i tabletów z Androidem oraz układów Pixel.",
   "iPhone'a, iPada i Maca."),
  ("iPhone, iPad, Mac, Android, Pixel i układy abstrakcyjne",
   "iPhone, iPad, Mac i układy abstrakcyjne"),
 ],
 "tr": [
  ("iPhone, iPad, Mac, Android telefonlar, Android tabletler ve Pixel düzenleri için",
   "iPhone, iPad ve Mac düzenleri için"),
  ("iPhone, iPad, Mac, Android, Pixel ve soyut", "iPhone, iPad, Mac ve soyut"),
 ],
 "id": [
  ("iPhone, iPad, Mac, ponsel Android, tablet Android, dan tata letak Pixel.",
   "iPhone, iPad, dan Mac."),
  ("iPhone, iPad, Mac, Android, Pixel, dan tata letak abstrak",
   "iPhone, iPad, Mac, dan tata letak abstrak"),
 ],
 "ms": [
  ("iPhone, iPad, Mac, telefon Android, tablet Android, dan susun atur Pixel.",
   "iPhone, iPad, dan Mac."),
  ("iPhone, iPad, Mac, Android, Pixel, dan susun atur abstrak",
   "iPhone, iPad, Mac, dan susun atur abstrak"),
 ],
 "vi": [
  ("iPhone, iPad, Mac, điện thoại Android, máy tính bảng Android và bố cục Pixel.",
   "iPhone, iPad và Mac."),
  ("iPhone, iPad, Mac, Android, Pixel và bố cục trừu tượng",
   "iPhone, iPad, Mac và bố cục trừu tượng"),
 ],
 "cs": [
  ("iPhone, iPad, Mac, telefony s Androidem, tablety s Androidem a rozvržení Pixel.",
   "iPhone, iPad a Mac."),
  ("iPhone, iPad, Mac, Android, Pixel i abstraktní", "iPhone, iPad, Mac i abstraktní"),
 ],
 "sk": [
  ("iPhone, iPad, Mac, telefóny s Androidom, tablety s Androidom aj rozloženia pre Pixel.",
   "iPhone, iPad a Mac."),
  # descriptions.py's stored macOS text coordinates the two nouns under one Androidom.
  ("iPhone, iPad, Mac, telefóny a tablety s Androidom aj rozloženia pre Pixel.",
   "iPhone, iPad a Mac."),
  ("iPhone, iPad, Mac, Android, Pixel a abstraktné", "iPhone, iPad, Mac a abstraktné"),
 ],
 "hu": [
  ("iPhone-ra, iPadre, Macre, Android-telefonokra, Android-tabletekre és Pixel-elrendezésekhez.",
   "iPhone-ra, iPadre és Macre."),
  ("iPhone, iPad, Mac, Android, Pixel és absztrakt", "iPhone, iPad, Mac és absztrakt"),
 ],
 "ro": [
  ("iPhone, iPad, Mac, telefoane Android, tablete Android și machete Pixel.",
   "iPhone, iPad și Mac."),
  ("iPhone, iPad, Mac, Android, Pixel și machete abstracte",
   "iPhone, iPad, Mac și machete abstracte"),
 ],
 "hr": [
  ("iPhone, iPad, Mac, Android telefone, Android tablete i Pixel rasporede.",
   "iPhone, iPad i Mac."),
  ("iPhone, iPad, Mac, Android, Pixel i apstraktne", "iPhone, iPad, Mac i apstraktne"),
 ],
 "el": [
  ("iPhone, iPad, Mac, τηλέφωνα Android, tablet Android και διατάξεις Pixel.",
   "iPhone, iPad και Mac."),
  ("iPhone, iPad, Mac, Android, Pixel και αφηρημένες",
   "iPhone, iPad, Mac και αφηρημένες"),
 ],
 "ca": [
  ("iPhone, iPad, Mac, telèfons Android, tauletes Android i disposicions Pixel.",
   "iPhone, iPad i Mac."),
  ("iPhone, iPad, Mac, Android, Pixel i disposicions abstractes",
   "iPhone, iPad, Mac i disposicions abstractes"),
 ],
 "sl-SI": [
  ("iPhone, iPad, Mac, telefone Android, tablice Android in postavitve za Pixel.",
   "iPhone, iPad in Mac."),
  ("iPhone, iPad, Mac, Android, Pixel in abstraktne", "iPhone, iPad, Mac in abstraktne"),
 ],
 "ru": [
  ("iPhone, iPad, Mac, Android-смартфонов, Android-планшетов и раскладок Pixel.",
   "iPhone, iPad и Mac."),
  ("iPhone, iPad, Mac, Android, Pixel и абстрактные", "iPhone, iPad, Mac и абстрактные"),
 ],
 "uk": [
  ("iPhone, iPad, Mac, смартфонів Android, планшетів Android і розкладок Pixel.",
   "iPhone, iPad і Mac."),
  ("iPhone, iPad, Mac, Android, Pixel і абстрактні", "iPhone, iPad, Mac і абстрактні"),
 ],
 "th": [
  ("iPhone, iPad, Mac, โทรศัพท์ Android, แท็บเล็ต Android และเลย์เอาต์ Pixel เริ่มจาก",
   "iPhone, iPad และ Mac เริ่มจาก"),
  ("iPhone, iPad, Mac, Android, Pixel และเลย์เอาต์แบบนามธรรม",
   "iPhone, iPad, Mac และเลย์เอาต์แบบนามธรรม"),
 ],
 "hi": [
  ("iPhone, iPad, Mac, Android फ़ोन, Android टैबलेट और Pixel लेआउट के लिए",
   "iPhone, iPad और Mac लेआउट के लिए"),
  ("iPhone, iPad, Mac, Android, Pixel और एब्स्ट्रैक्ट",
   "iPhone, iPad, Mac और एब्स्ट्रैक्ट"),
 ],
 "mr-IN": [
  ("iPhone, iPad, Mac, Android फोन, Android टॅबलेट आणि Pixel मांडणीसाठी",
   "iPhone, iPad आणि Mac मांडणीसाठी"),
  ("iPhone, iPad, Mac, Android, Pixel आणि अमूर्त", "iPhone, iPad, Mac आणि अमूर्त"),
 ],
 "bn-BD": [
  ("iPhone, iPad, Mac, Android ফোন, Android ট্যাবলেট এবং Pixel লেআউটের জন্য",
   "iPhone, iPad এবং Mac লেআউটের জন্য"),
  ("iPhone, iPad, Mac, Android, Pixel এবং বিমূর্ত", "iPhone, iPad, Mac এবং বিমূর্ত"),
 ],
 "gu-IN": [
  ("iPhone, iPad, Mac, Android ફોન, Android ટૅબ્લેટ અને Pixel લેઆઉટ માટે",
   "iPhone, iPad અને Mac લેઆઉટ માટે"),
  ("iPhone, iPad, Mac, Android, Pixel અને અમૂર્ત", "iPhone, iPad, Mac અને અમૂર્ત"),
 ],
 "ta-IN": [
  ("iPhone, iPad, Mac, Android தொலைபேசிகள், Android டேப்லெட்டுகள் மற்றும் Pixel தளவமைப்புகளுக்கு",
   "iPhone, iPad மற்றும் Mac தளவமைப்புகளுக்கு"),
  ("iPhone, iPad, Mac, Android, Pixel மற்றும் சுருக்கத்",
   "iPhone, iPad, Mac மற்றும் சுருக்கத்"),
 ],
 "te-IN": [
  ("iPhone, iPad, Mac, Android ఫోన్‌లు, Android టాబ్లెట్‌లు, Pixel లేఅవుట్‌ల కోసం",
   "iPhone, iPad, Mac లేఅవుట్‌ల కోసం"),
  ("iPhone, iPad, Mac, Android, Pixel, నైరూప్య", "iPhone, iPad, Mac, నైరూప్య"),
 ],
 "kn-IN": [
  ("iPhone, iPad, Mac, Android ಫೋನ್‌ಗಳು, Android ಟ್ಯಾಬ್ಲೆಟ್‌ಗಳು, Pixel ವಿನ್ಯಾಸಗಳಿಗಾಗಿ",
   "iPhone, iPad, Mac ವಿನ್ಯಾಸಗಳಿಗಾಗಿ"),
  ("iPhone, iPad, Mac, Android, Pixel ಮತ್ತು ಅಮೂರ್ತ", "iPhone, iPad, Mac ಮತ್ತು ಅಮೂರ್ತ"),
 ],
 "ml-IN": [
  ("iPhone, iPad, Mac, Android ഫോണുകൾ, Android ടാബ്‌ലെറ്റുകൾ, Pixel ലേഔട്ടുകൾ എന്നിവയ്ക്കായി",
   "iPhone, iPad, Mac ലേഔട്ടുകൾ എന്നിവയ്ക്കായി"),
  ("iPhone, iPad, Mac, Android, Pixel, അമൂർത്ത", "iPhone, iPad, Mac, അമൂർത്ത"),
 ],
 "ur-PK": [
  ("iPhone، iPad، Mac، Android فونز، Android ٹیبلٹس اور Pixel لے آؤٹس کے لیے",
   "iPhone، iPad اور Mac لے آؤٹس کے لیے"),
  ("iPhone، iPad، Mac، Android، Pixel اور تجریدی", "iPhone، iPad، Mac اور تجریدی"),
 ],
 "ja": [
  ("iPhone、iPad、Mac、Android スマートフォン、Android タブレット、Pixel 向けレイアウト",
   "iPhone、iPad、Mac 向けレイアウト"),
  ("iPhone、iPad、Mac、Android、Pixel、抽象レイアウト", "iPhone、iPad、Mac、抽象レイアウト"),
 ],
 "ko": [
  ("iPhone, iPad, Mac, Android 휴대폰, Android 태블릿, Pixel 레이아웃을 위한",
   "iPhone, iPad, Mac 레이아웃을 위한"),
  ("iPhone, iPad, Mac, Android, Pixel용 기기 프레임", "iPhone, iPad, Mac용 기기 프레임"),
 ],
 "zh-Hans": [
  ("iPhone、iPad、Mac、Android 手机、Android 平板和 Pixel 布局构建",
   "iPhone、iPad 和 Mac 布局构建"),
  ("iPhone、iPad、Mac、Android、Pixel 及抽象布局", "iPhone、iPad、Mac 及抽象布局"),
 ],
 "zh-Hant": [
  ("iPhone、iPad、Mac、Android 手機、Android 平板與 Pixel 版面打造",
   "iPhone、iPad 與 Mac 版面打造"),
  ("iPhone、iPad、Mac、Android、Pixel 及抽象版面", "iPhone、iPad、Mac 及抽象版面"),
 ],
 "ar-SA": [
  (" و Mac وهواتف Android والأجهزة اللوحية Android وتخطيطات Pixel.", " و Mac."),
  (" و Mac و Android و Pixel والتخطيطات", " و Mac والتخطيطات"),
 ],
 "he": [
  ("iPhone, iPad, Mac, טלפוני Android, טאבלטי Android ופריסות Pixel.",
   "iPhone, iPad ו-Mac."),
  ("iPhone, iPad, Mac, Android, Pixel ופריסות מופשטות",
   "iPhone, iPad, Mac ופריסות מופשטות"),
 ],
}

# "Pixel" is a product name here, never the unit — no locale's copy says "pixels".
BANNED = re.compile(r"android|pixel", re.I)


def scrub(locale, text):
    """Apply this locale's deletions. Returns (new_text, problems)."""
    for old, new in RULES[locale]:
        text = text.replace(old, new)
    problems = []
    leftover = [l for l in text.split("\n") if BANNED.search(l)]
    if leftover:
        problems.append(f"still names Android/Pixel: {leftover[0][:120]}")
    if len(text) > LIMIT:
        problems.append(f"description {len(text)}/{LIMIT}")
    if "\n\n\n" in text or text.rstrip() != text:
        problems.append("deletion left a blank line or trailing space")
    return text, problems


def asc(*args):
    p = subprocess.run(["asc", *args], capture_output=True, text=True)
    out = (p.stdout or "").strip()
    if p.returncode != 0:
        raise SystemExit(f"asc {' '.join(args)} failed:\n{out}\n{p.stderr.strip()}")
    return json.loads(out) if out else {}


def localizations(version_id):
    payload = asc("localizations", "list", "--version", version_id, "--paginate")
    return payload["data"] if isinstance(payload, dict) else payload


def run(version_id, dry):
    ok = fail = skip = 0
    for row in sorted(localizations(version_id), key=lambda x: x["attributes"]["locale"]):
        locale = row["attributes"]["locale"]
        text = row["attributes"].get("description") or ""
        if not BANNED.search(text):
            print(f"  {locale:9} already clean"); skip += 1; continue
        if locale not in RULES:
            print(f"  {locale:9} BLOCKED no rules"); fail += 1; continue
        want, problems = scrub(locale, text)
        if problems:
            for problem in problems:
                print(f"  {locale:9} BLOCKED {problem}")
            fail += 1
            continue
        if dry:
            print(f"  {locale:9} would set {len(text)} -> {len(want)}"); continue
        asc("localizations", "update", "--version", version_id, "--locale", locale,
            "--description", want)
        got = {x["attributes"]["locale"]: x["attributes"].get("description")
               for x in localizations(version_id)}.get(locale)
        good = got == want
        print(f"  {locale:9} verify={'OK' if good else 'MISMATCH'} {len(want)}/{LIMIT}")
        ok, fail = (ok + 1, fail) if good else (ok, fail + 1)
    print(f"\n  verified {ok}, already clean {skip}, failed {fail}")
    return fail


if __name__ == "__main__":
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    sys.exit(1 if run(sys.argv[1], "--dry-run" in sys.argv) else 0)
