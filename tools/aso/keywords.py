# -*- coding: utf-8 -*-
"""Keyword fields for Screenshot Bro, per locale per platform.

Design (see tools/aso/RESEARCH.md):
  NAME     "Screenshot Bro: Mockup Maker"    -> screenshot bro mockup maker
  SUBTITLE "App Screenshots & Localization"  -> app screenshots localization
Apple combines tokens across name+subtitle+keywords, so the keyword field must
never repeat those words. Everything here is a token Apple can only get from
the keyword field.

`store` and `app` head the list because the 2026-09-01 rejection took "App
Store" out of the subtitle. Apple still forms "app store screenshots" by
combining them with the name's `screenshot` — the query survives, at keyword
weight instead of subtitle weight.
"""

import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import metadata as M

NAME = "Screenshot Bro: Mockup Maker"


def _reserved(locale):
    """Words the name and this locale's subtitle already supply.

    Substring, not word-split: Japanese, Chinese and Thai subtitles have no
    spaces, so splitting them yields one useless token and every CJK keyword
    looks free when it is not. Containment catches 画像 inside
    アプリ画像の作成とローカライズ, and costs nothing on Latin scripts because
    every token here is a whole word.
    """
    text = f"{NAME} {M.SUBTITLE[locale]}".lower()
    return lambda token: token.lower() in text

# Proven English dev vocabulary — searched in every storefront we swept.
# `google` was here until the 2026-09-01 2.3.10 rejection took every Google Play
# reference out of the listing; a keyword field is metadata Apple reads too.
CORE = ["store", "app", "generator", "device", "frames", "connect",
        "preview", "template", "design"]

# Locale -> extra tokens, highest value first. Trimmed to fit 100 chars.
# Non-Latin locales lead with their own script: no other surface can supply
# those tokens, and CORE's "store,app" would otherwise crowd them out.
# Every locale whose research found no local-language demand carries this verbatim;
# see RESEARCH.md Finding 5 and the note below.
EN_TAIL = ["localization", "aso", "editor", "android", "indie"]

EXTRA = {
    "en-US":   EN_TAIL,
    "en-GB":   EN_TAIL,
    "en-AU":   EN_TAIL,
    "en-CA":   EN_TAIL,
    "de-DE":   ["localization", "aso", "editor", "android", "vorlage", "entwickler"],
    "fr-FR":   ["localization", "aso", "editor", "android", "maquette", "capture"],
    "fr-CA":   EN_TAIL,
    "es-ES":   ["localization", "aso", "editor", "android", "maqueta", "captura", "plantilla"],
    "es-MX":   EN_TAIL,
    "it":      ["localization", "aso", "editor", "android", "schermate", "anteprima"],
    "nl-NL":   ["localization", "aso", "editor", "android", "sjabloon"],
    "sv":      ["localization", "aso", "editor", "android", "mall", "skärmdump"],
    "da":      ["localization", "aso", "editor", "android", "skabelon"],
    "no":      ["localization", "aso", "editor", "android", "mal", "skjermbilde"],
    "fi":      ["localization", "aso", "editor", "android", "malli"],
    "pt-PT":   ["localization", "aso", "editor", "android", "captura", "modelo"],
    "pt-BR":   ["localization", "aso", "editor", "android", "captura", "tela", "modelo"],
    "pl":      ["localization", "aso", "editor", "android", "zrzut", "ekranu", "szablon"],
    "tr":      ["localization", "aso", "editor", "android", "ekran", "şablon"],
    "id":      ["localization", "aso", "editor", "android", "tangkapan", "layar", "aplikasi"],
    "vi":      ["localization", "aso", "editor", "android", "ảnh", "màn hình", "ứng dụng"],

    # Added 2026-09-09. All twelve carry the en-US tail verbatim: RESEARCH.md
    # Finding 5 swept every one of their storefronts and not a single
    # local-language phrase autosuggested, while the English one returned the
    # full category field. There is no local vocabulary to spend budget on, so
    # the strongest English tokens are also the right ones. `el` is Greek script
    # and still English here for the same reason — script is not the criterion.
    "cs":     EN_TAIL,
    "sk":     EN_TAIL,
    "hu":     EN_TAIL,
    "ro":     EN_TAIL,
    "hr":     EN_TAIL,
    "el":     EN_TAIL,
    "ca":     EN_TAIL,
    "sl-SI":  EN_TAIL,
    "ru":      ["мокап", "генератор", "скриншот", "localization", "aso", "editor", "android"],
    "uk":      ["мокап", "скриншот", "знімок", "localization", "aso", "editor", "android"],
    "th":      ["ภาพหน้าจอ", "แอป", "localization", "aso", "editor", "android"],
    # added 2026-09-10 — India, Pakistan, Bangladesh, Malaysia. English for the
    # same reason as the `el` block above: these storefronts search developer
    # tooling in English, so a local-script keyword field would spend the whole
    # 100-char budget on tokens nobody types. Their descriptions are translated.
    "ms":     EN_TAIL,
    "hi":     EN_TAIL,
    "mr-IN":  EN_TAIL,
    "bn-BD":  EN_TAIL,
    "gu-IN":  EN_TAIL,
    "ta-IN":  EN_TAIL,
    "te-IN":  EN_TAIL,
    "kn-IN":  EN_TAIL,
    "ml-IN":  EN_TAIL,
    "ur-PK":  EN_TAIL,
    "ja":      ["モックアップ", "ストア", "画像", "作成", "素材", "localization", "aso", "editor", "android"],
    "ko":      ["스크린샷", "앱스토어", "목업", "제작", "localization", "aso", "editor", "android"],
    "zh-Hans": ["应用截图", "上架", "生成器", "制作", "工具", "localization", "aso", "editor", "android"],
    "zh-Hant": ["應用截圖", "上架", "製作", "工具", "產生器", "localization", "aso", "editor", "android"],
    "ar-SA":   ["لقطة", "شاشة", "تطبيق", "متجر", "localization", "aso", "editor", "android"],
    "he":      ["צילום", "מסך", "אפליקציה", "localization", "aso", "editor", "android"],
}

# Packed last: real queries, but weaker than anything above. They exist to spend
# the budget the shortened subtitle handed back rather than ship a 90/100 field.
TAIL = ["marketing", "listing", "publish"]

LIMIT = 100


def field(locale, platform):
    """Build the keyword field, packing tokens until the 100-char budget runs out."""
    tokens = CORE + EXTRA[locale] + TAIL
    if platform == "IOS":
        # "aso" autosuggests to ASOS the retailer on the iOS store — wrong intent,
        # unwinnable SERP. On the Mac store "aso" returns a genuine ASO-tool field.
        tokens = [t for t in tokens if t != "aso"]
    is_reserved = _reserved(locale)
    out, dropped = [], []
    for t in tokens:
        if is_reserved(t):
            dropped.append(f"{t}(reserved)")
            continue
        candidate = ",".join(out + [t])
        if len(candidate) <= LIMIT:
            out.append(t)
        else:
            dropped.append(t)
    return ",".join(out), dropped


if __name__ == "__main__":
    for plat in ("MAC_OS", "IOS"):
        print(f"===== {plat}")
        for loc in EXTRA:
            f, dropped = field(loc, plat)
            note = f"   DROPPED: {','.join(dropped)}" if dropped else ""
            print(f"  {loc:8} {len(f):3}/100  {f}{note}")
