# -*- coding: utf-8 -*-
"""Subtitle and promotional text for Screenshot Bro, per locale.

Rewritten after the 2026-09-01 rejection of iOS 4.9 (see RESEARCH.md
"2026-09-01 — the subtitle was rejected"). Apple cited 5.2.5 for "App Store"
in the subtitle and 2.3.10 for "Play"; both surfaces are now clean.

`App Store Connect` survives in promotional text: it is the real name of the
real service the app uploads to, which is accurate metadata rather than a
trademark borrowed for search. `check()` enforces exactly that distinction.
"""

LATIN_SUBTITLE = "App Screenshots & Localization"

# Latin-script locales keep the English subtitle: developers in every market we
# swept search the English phrase (RESEARCH.md finding 3). Non-Latin locales get
# the local script, which is what those developers type.
SUBTITLE = {
    "en-US": LATIN_SUBTITLE, "en-GB": LATIN_SUBTITLE, "de-DE": LATIN_SUBTITLE,
    "fr-FR": LATIN_SUBTITLE, "es-ES": LATIN_SUBTITLE, "it": LATIN_SUBTITLE,
    "nl-NL": LATIN_SUBTITLE, "sv": LATIN_SUBTITLE, "da": LATIN_SUBTITLE,
    "no": LATIN_SUBTITLE, "fi": LATIN_SUBTITLE, "pt-PT": LATIN_SUBTITLE,
    "pt-BR": LATIN_SUBTITLE, "pl": LATIN_SUBTITLE, "tr": LATIN_SUBTITLE,
    "id": LATIN_SUBTITLE, "vi": LATIN_SUBTITLE,
    "ja": "アプリ画像の作成とローカライズ",
    "ko": "앱 스크린샷 제작 및 현지화",
    "zh-Hans": "应用截图制作与本地化",
    "zh-Hant": "應用截圖製作與在地化",
    "ru": "Скриншоты и локализация",
    "uk": "Скриншоти і локалізація",
    "ar-SA": "لقطات شاشة التطبيقات والتوطين",
    "he": "צילומי מסך ולוקליזציה",
    "th": "ภาพหน้าจอแอปและการแปลภาษา",
}

# macOS promo mentions MCP (a macOS-only feature). See PROMO_IOS for the iOS train.
PROMO_MAC = {
    "en-US": "Build a complete screenshot set, localize it into every market, and upload directly to App Store Connect. Automate it all from your AI assistant via MCP.",
    "en-GB": "Build a complete screenshot set, localise it into every market, and upload directly to App Store Connect. Automate it all from your AI assistant via MCP.",
    "de-DE": "Erstelle einen kompletten Screenshot-Satz, lokalisiere ihn für jeden Markt und lade ihn direkt zu App Store Connect hoch – automatisiert per MCP.",
    "fr-FR": "Créez un jeu complet de captures, localisez-le pour chaque marché et envoyez-le directement vers App Store Connect – le tout automatisable via MCP.",
    "es-ES": "Crea un set completo de capturas, localízalo para cada mercado y súbelo directamente a App Store Connect. Todo automatizable desde tu asistente con MCP.",
    "it": "Crea un set completo di screenshot, localizzalo per ogni mercato e caricalo direttamente su App Store Connect. Tutto automatizzabile via MCP.",
    "nl-NL": "Maak een complete set screenshots, lokaliseer ze voor elke markt en upload ze direct naar App Store Connect. Volledig automatiseerbaar via MCP.",
    "sv": "Skapa en komplett uppsättning skärmbilder, lokalisera dem för varje marknad och ladda upp direkt till App Store Connect. Kan automatiseras via MCP.",
    "da": "Lav et komplet sæt screenshots, oversæt dem til hvert marked, og upload dem direkte til App Store Connect. Kan automatiseres via MCP.",
    "no": "Lag et komplett sett med skjermbilder, lokaliser dem for hvert marked, og last dem opp direkte til App Store Connect. Kan automatiseres via MCP.",
    "fi": "Luo täydellinen kuvakaappaussarja, lokalisoi se jokaiselle markkinalle ja lataa se suoraan App Store Connectiin. Automatisoitavissa MCP:n kautta.",
    "pt-PT": "Crie um conjunto completo de capturas, localize-as para cada mercado e envie-as diretamente para o App Store Connect. Tudo automatizável através de MCP.",
    "pt-BR": "Crie um conjunto completo de capturas, localize-as para cada mercado e envie direto para o App Store Connect. Tudo automatizável via MCP.",
    "pl": "Twórz kompletne zestawy zrzutów ekranu, lokalizuj je na każdy rynek i wysyłaj prosto do App Store Connect. Wszystko zautomatyzujesz przez MCP.",
    "tr": "Eksiksiz bir ekran görüntüsü seti oluşturun, her pazar için yerelleştirin ve doğrudan App Store Connect'e yükleyin. Tümü MCP ile otomatikleştirilebilir.",
    "id": "Buat satu set screenshot lengkap, lokalkan untuk setiap pasar, dan unggah langsung ke App Store Connect. Semua bisa diotomatiskan lewat MCP.",
    "vi": "Tạo trọn bộ ảnh chụp màn hình, bản địa hóa cho từng thị trường và tải thẳng lên App Store Connect. Tự động hóa hoàn toàn qua MCP.",
    "ja": "アプリのスクリーンショットを一式作成し、各国向けにローカライズして、App Store Connect へ直接アップロード。MCP で AI アシスタントから自動化できます。",
    "ko": "스크린샷 세트를 만들고, 시장별로 현지화하고, App Store Connect에 바로 업로드하세요. MCP로 AI 어시스턴트에서 자동화할 수 있습니다.",
    "zh-Hans": "制作整套应用截图，按市场本地化，并直接上传到 App Store Connect。可通过 MCP 从 AI 助手中自动完成。",
    "zh-Hant": "製作整套應用截圖，依市場在地化，並直接上傳至 App Store Connect。可透過 MCP 從 AI 助理自動完成。",
    "ru": "Создавайте полный набор скриншотов, локализуйте их для каждого рынка и загружайте прямо в App Store Connect. Всё автоматизируется через MCP.",
    "uk": "Створюйте повний набір скриншотів, локалізуйте їх для кожного ринку та завантажуйте просто в App Store Connect. Усе автоматизується через MCP.",
    "ar-SA": "أنشئ مجموعة كاملة من لقطات الشاشة، وترجمها لكل سوق، وارفعها مباشرة إلى App Store Connect. ويمكن أتمتة ذلك عبر MCP.",
    "he": "צרו סט מלא של צילומי מסך, תרגמו אותם לכל שוק והעלו ישירות ל-App Store Connect. הכול ניתן לאוטומציה דרך MCP.",
    "th": "สร้างชุดภาพหน้าจอครบชุด แปลให้ทุกตลาด และอัปโหลดตรงไปยัง App Store Connect ทำอัตโนมัติได้ผ่าน MCP",
}

# MCP is macOS-only (MCPServerService is entirely #if os(macOS)) — the iOS
# listing must not advertise it.
PROMO_IOS = {
    "en-US": "Build a complete screenshot set, localize it into every market, and upload it directly to App Store Connect — right from your iPad.",
    "en-GB": "Build a complete screenshot set, localise it into every market, and upload it directly to App Store Connect — right from your iPad.",
    "de-DE": "Erstelle einen kompletten Screenshot-Satz, lokalisiere ihn für jeden Markt und lade ihn direkt zu App Store Connect hoch – vom iPad aus.",
    "fr-FR": "Créez un jeu complet de captures, localisez-le pour chaque marché et envoyez-le directement vers App Store Connect – depuis votre iPad.",
    "es-ES": "Crea un set completo de capturas, localízalo para cada mercado y súbelo directamente a App Store Connect, desde tu iPad.",
    "it": "Crea un set completo di screenshot, localizzalo per ogni mercato e caricalo direttamente su App Store Connect, dal tuo iPad.",
    "nl-NL": "Maak een complete set screenshots, lokaliseer ze voor elke markt en upload ze direct naar App Store Connect – vanaf je iPad.",
    "sv": "Skapa en komplett uppsättning skärmbilder, lokalisera dem för varje marknad och ladda upp direkt till App Store Connect – från din iPad.",
    "da": "Lav et komplet sæt screenshots, oversæt dem til hvert marked, og upload dem direkte til App Store Connect – fra din iPad.",
    "no": "Lag et komplett sett med skjermbilder, lokaliser dem for hvert marked, og last dem opp direkte til App Store Connect – fra iPaden din.",
    "fi": "Luo täydellinen kuvakaappaussarja, lokalisoi se jokaiselle markkinalle ja lataa se suoraan App Store Connectiin – suoraan iPadilta.",
    "pt-PT": "Crie um conjunto completo de capturas, localize-as para cada mercado e envie-as diretamente para o App Store Connect – a partir do seu iPad.",
    "pt-BR": "Crie um conjunto completo de capturas, localize-as para cada mercado e envie direto para o App Store Connect – direto do seu iPad.",
    "pl": "Twórz kompletne zestawy zrzutów ekranu, lokalizuj je na każdy rynek i wysyłaj prosto do App Store Connect – prosto z iPada.",
    "tr": "Eksiksiz bir ekran görüntüsü seti oluşturun, her pazar için yerelleştirin ve doğrudan App Store Connect'e yükleyin – iPad'inizden.",
    "id": "Buat satu set screenshot lengkap, lokalkan untuk setiap pasar, dan unggah langsung ke App Store Connect — dari iPad Anda.",
    "vi": "Tạo trọn bộ ảnh chụp màn hình, bản địa hóa cho từng thị trường và tải thẳng lên App Store Connect — ngay trên iPad.",
    "ja": "アプリのスクリーンショットを一式作成し、各国向けにローカライズして、App Store Connect へ直接アップロード。iPad だけで完結します。",
    "ko": "스크린샷 세트를 만들고, 시장별로 현지화하고, App Store Connect에 바로 업로드하세요. iPad만으로 끝납니다.",
    "zh-Hans": "制作整套应用截图，按市场本地化，并直接上传到 App Store Connect — 在 iPad 上即可完成。",
    "zh-Hant": "製作整套應用截圖，依市場在地化，並直接上傳至 App Store Connect — 在 iPad 上即可完成。",
    "ru": "Создавайте полный набор скриншотов, локализуйте их для каждого рынка и загружайте прямо в App Store Connect — с iPad.",
    "uk": "Створюйте повний набір скриншотів, локалізуйте їх для кожного ринку та завантажуйте просто в App Store Connect — з iPad.",
    "ar-SA": "أنشئ مجموعة كاملة من لقطات الشاشة، وترجمها لكل سوق، وارفعها مباشرة إلى App Store Connect — من الـ iPad مباشرة.",
    "he": "צרו סט מלא של צילומי מסך, תרגמו אותם לכל שוק והעלו ישירות ל-App Store Connect — היישר מה-iPad.",
    "th": "สร้างชุดภาพหน้าจอครบชุด แปลให้ทุกตลาด และอัปโหลดตรงไปยัง App Store Connect ได้จาก iPad",
}

VERBATIM = ["App Store Connect"]
LIMITS = {"subtitle": 30, "promo": 170}

# 5.2.5 bans Apple's marks from the subtitle; 2.3.10 bans the competitor
# platform. Matched case-insensitively against every locale, in Latin and in
# the local script, because a translated subtitle is still metadata Apple reads.
SUBTITLE_BANNED = ["app store", "appstore", "google play", "googleplay", "google",
                   "iphone", "ipad", "macbook", "apple", "android", "play store",
                   "متجر التطبيقات", "앱스토어", "应用商店", "應用商店",
                   "アップストア", "App Store", "гугл", "плей"]


def check():
    """Every subtitle fits, and carries no term Apple rejected. Returns problems."""
    problems = []
    for locale, text in SUBTITLE.items():
        if len(text) > LIMITS["subtitle"]:
            problems.append(f"{locale}: subtitle {len(text)}/{LIMITS['subtitle']}")
        low = text.lower()
        for banned in SUBTITLE_BANNED:
            if banned.lower() in low:
                problems.append(f"{locale}: subtitle contains banned term {banned!r}")
    for name, promo in (("MAC_OS", PROMO_MAC), ("IOS", PROMO_IOS)):
        for locale, text in promo.items():
            if len(text) > LIMITS["promo"]:
                problems.append(f"{locale} {name}: promo {len(text)}/{LIMITS['promo']}")
            # "App Store Connect" is the service; a bare "App Store" is the mark.
            if "app store" in text.lower().replace("app store connect", ""):
                problems.append(f"{locale} {name}: promo names App Store outside Connect")
            if "google play" in text.lower():
                problems.append(f"{locale} {name}: promo names Google Play")
        missing = set(SUBTITLE) - set(promo)
        if missing:
            problems.append(f"{name}: no promo for {sorted(missing)}")
    return problems


if __name__ == "__main__":
    import sys
    for locale in sorted(SUBTITLE):
        print(f"  {locale:9} {len(SUBTITLE[locale]):2}/30  {SUBTITLE[locale]}")
    found = check()
    for p in found:
        print("  FAIL", p)
    print(f"\n  {len(SUBTITLE)} subtitles, {len(found)} problem(s)")
    sys.exit(1 if found else 0)
