# -*- coding: utf-8 -*-
"""Keyword fields for Screenshot Bro, per locale per platform.

Design (see tools/aso/RESEARCH.md):
  NAME     "Screenshot Bro: Mockup Maker"  -> tokens: screenshot bro mockup maker
  SUBTITLE "App Store & Play Screenshots"  -> tokens: app store play screenshots
Apple combines tokens across name+subtitle+keywords, so the keyword field must
never repeat those eight words. Everything here is a token Apple can only get
from the keyword field.
"""

import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import metadata as M

NAME = "Screenshot Bro: Mockup Maker"


def _reserved(locale):
    """Words the name and this locale's subtitle already supply.

    Derived, not hardcoded: the CJK subtitles carry "Google Play" while the
    Latin one does not, so "google" is free budget in one and wasted in the
    other. Recomputing from the real strings keeps that honest.
    """
    text = f"{NAME} {M.SUBTITLE[locale]}"
    parts = re.split(r"[\s·・&/|,:.\-]+", text)
    return {w.lower() for w in parts if len(w) > 2}

# Proven English dev vocabulary — searched in every storefront we swept.
CORE = ["generator", "device", "frames", "google", "connect", "preview",
        "template", "design"]

# Locale -> extra tokens, highest value first. Trimmed to fit 100 chars.
EXTRA = {
    "en-US":   ["localization", "aso", "editor", "android", "indie"],
    "en-GB":   ["localization", "aso", "editor", "android", "indie"],
    "de-DE":   ["localization", "aso", "editor", "android", "vorlage", "entwickler"],
    "fr-FR":   ["localization", "aso", "editor", "android", "maquette", "capture"],
    "es-ES":   ["localization", "aso", "editor", "android", "maqueta", "captura", "plantilla"],
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
    "ru":      ["localization", "aso", "editor", "android", "мокап", "генератор", "скриншот"],
    "uk":      ["localization", "aso", "editor", "android", "мокап", "скриншот", "знімок"],
    "th":      ["localization", "aso", "editor", "android", "ภาพหน้าจอ", "แอป"],
    "ja":      ["モックアップ", "ストア", "画像", "作成", "素材", "localization", "aso", "editor", "android"],
    "ko":      ["스크린샷", "앱스토어", "목업", "제작", "localization", "aso", "editor", "android"],
    "zh-Hans": ["应用截图", "上架", "生成器", "制作", "工具", "localization", "aso", "editor", "android"],
    "zh-Hant": ["應用截圖", "上架", "製作", "工具", "產生器", "localization", "aso", "editor", "android"],
    "ar-SA":   ["localization", "aso", "editor", "android", "لقطة", "شاشة", "تطبيق", "متجر"],
    "he":      ["localization", "aso", "editor", "android", "צילום", "מסך", "אפליקציה"],
}

LIMIT = 100


def field(locale, platform):
    """Build the keyword field, packing tokens until the 100-char budget runs out."""
    tokens = CORE + EXTRA[locale]
    if platform == "IOS":
        # "aso" autosuggests to ASOS the retailer on the iOS store — wrong intent,
        # unwinnable SERP. On the Mac store "aso" returns a genuine ASO-tool field.
        tokens = [t for t in tokens if t != "aso"]
    reserved = _reserved(locale)
    out, dropped = [], []
    for t in tokens:
        if t.lower() in reserved:
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
