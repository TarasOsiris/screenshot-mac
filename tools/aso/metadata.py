# -*- coding: utf-8 -*-
"""Subtitle and promotional text for Screenshot Bro, per locale.

Verbatim atoms that survive every locale untouched: App Store, Google Play,
App Store Connect, MCP, iPad, Screenshot Bro.
"""

LATIN_SUBTITLE = "App Store & Play Screenshots"

# Latin-script locales keep the English subtitle: developers in every market we
# swept search the English phrase, and "App Store"/"Google Play" are never
# translated anyway. Non-Latin locales get the local script with those two
# product names left Latin, which is how developers write them there too.
SUBTITLE = {
    "en-US": LATIN_SUBTITLE, "en-GB": LATIN_SUBTITLE, "de-DE": LATIN_SUBTITLE,
    "fr-FR": LATIN_SUBTITLE, "es-ES": LATIN_SUBTITLE, "it": LATIN_SUBTITLE,
    "nl-NL": LATIN_SUBTITLE, "sv": LATIN_SUBTITLE, "da": LATIN_SUBTITLE,
    "no": LATIN_SUBTITLE, "fi": LATIN_SUBTITLE, "pt-PT": LATIN_SUBTITLE,
    "pt-BR": LATIN_SUBTITLE, "pl": LATIN_SUBTITLE, "tr": LATIN_SUBTITLE,
    "id": LATIN_SUBTITLE, "vi": LATIN_SUBTITLE,
    "ja": "App Store・Google Play 用画像",
    "ko": "App Store·Google Play 스크린샷",
    "zh-Hans": "App Store 与 Google Play 截图",
    "zh-Hant": "App Store 與 Google Play 截圖",
    "ru": "Скриншоты для App Store и Play",
    "uk": "Скриншоти для App Store і Play",
    "ar-SA": "لقطات شاشة App Store و Play",
    "he": "צילומי מסך ל-App Store ו-Play",
    "th": "ภาพหน้าจอ App Store & Play",
}

# macOS promo mentions MCP (a macOS-only feature). See PROMO_IOS for the iOS train.
PROMO_MAC = {
    "en-US": "Build App Store and Google Play screenshots, localize them into every market, and upload directly to App Store Connect. Automate it all from your AI assistant via MCP.",
    "en-GB": "Build App Store and Google Play screenshots, localise them into every market, and upload directly to App Store Connect. Automate it all from your AI assistant via MCP.",
    "de-DE": "Erstelle Screenshots für App Store und Google Play, lokalisiere sie für jeden Markt und lade sie direkt zu App Store Connect hoch – automatisiert per MCP.",
    "fr-FR": "Créez vos captures App Store et Google Play, localisez-les pour chaque marché et envoyez-les directement vers App Store Connect – le tout automatisable via MCP.",
    "es-ES": "Crea capturas para App Store y Google Play, localízalas para cada mercado y súbelas directamente a App Store Connect. Todo automatizable desde tu asistente con MCP.",
    "it": "Crea screenshot per App Store e Google Play, localizzali per ogni mercato e caricali direttamente su App Store Connect. Tutto automatizzabile via MCP.",
    "nl-NL": "Maak screenshots voor de App Store en Google Play, lokaliseer ze voor elke markt en upload ze direct naar App Store Connect. Volledig automatiseerbaar via MCP.",
    "sv": "Skapa skärmbilder för App Store och Google Play, lokalisera dem för varje marknad och ladda upp direkt till App Store Connect. Kan automatiseras via MCP.",
    "da": "Lav screenshots til App Store og Google Play, oversæt dem til hvert marked, og upload dem direkte til App Store Connect. Kan automatiseres via MCP.",
    "no": "Lag skjermbilder for App Store og Google Play, lokaliser dem for hvert marked, og last dem opp direkte til App Store Connect. Kan automatiseres via MCP.",
    "fi": "Luo kuvakaappaukset App Storeen ja Google Playhin, lokalisoi ne jokaiselle markkinalle ja lataa ne suoraan App Store Connectiin. Automatisoitavissa MCP:n kautta.",
    "pt-PT": "Crie capturas para a App Store e o Google Play, localize-as para cada mercado e envie-as diretamente para o App Store Connect. Tudo automatizável através de MCP.",
    "pt-BR": "Crie capturas para a App Store e o Google Play, localize-as para cada mercado e envie direto para o App Store Connect. Tudo automatizável via MCP.",
    "pl": "Twórz zrzuty ekranu do App Store i Google Play, lokalizuj je na każdy rynek i wysyłaj prosto do App Store Connect. Wszystko zautomatyzujesz przez MCP.",
    "tr": "App Store ve Google Play ekran görüntüleri oluşturun, her pazar için yerelleştirin ve doğrudan App Store Connect'e yükleyin. Tümü MCP ile otomatikleştirilebilir.",
    "id": "Buat screenshot untuk App Store dan Google Play, lokalkan untuk setiap pasar, dan unggah langsung ke App Store Connect. Semua bisa diotomatiskan lewat MCP.",
    "vi": "Tạo ảnh chụp màn hình cho App Store và Google Play, bản địa hóa cho từng thị trường và tải thẳng lên App Store Connect. Tự động hóa hoàn toàn qua MCP.",
    "ja": "App Store と Google Play のスクリーンショットを作成し、各国向けにローカライズして、App Store Connect へ直接アップロード。MCP で AI アシスタントから自動化できます。",
    "ko": "App Store와 Google Play 스크린샷을 만들고, 시장별로 현지화하고, App Store Connect에 바로 업로드하세요. MCP로 AI 어시스턴트에서 자동화할 수 있습니다.",
    "zh-Hans": "制作 App Store 与 Google Play 截图，按市场本地化，并直接上传到 App Store Connect。可通过 MCP 从 AI 助手中自动完成。",
    "zh-Hant": "製作 App Store 與 Google Play 截圖，依市場在地化，並直接上傳至 App Store Connect。可透過 MCP 從 AI 助理自動完成。",
    "ru": "Создавайте скриншоты для App Store и Google Play, локализуйте их для каждого рынка и загружайте прямо в App Store Connect. Всё автоматизируется через MCP.",
    "uk": "Створюйте скриншоти для App Store і Google Play, локалізуйте їх для кожного ринку та завантажуйте просто в App Store Connect. Усе автоматизується через MCP.",
    "ar-SA": "أنشئ لقطات شاشة لـ App Store و Google Play، وترجمها لكل سوق، وارفعها مباشرة إلى App Store Connect. ويمكن أتمتة ذلك عبر MCP.",
    "he": "צרו צילומי מסך ל-App Store ול-Google Play, תרגמו אותם לכל שוק והעלו ישירות ל-App Store Connect. הכול ניתן לאוטומציה דרך MCP.",
    "th": "สร้างภาพหน้าจอสำหรับ App Store และ Google Play แปลให้ทุกตลาด และอัปโหลดตรงไปยัง App Store Connect ทำอัตโนมัติได้ผ่าน MCP",
}

# MCP is macOS-only (MCPServerService is entirely #if os(macOS)) — the iOS
# listing must not advertise it.
_IOS_TAIL = {
    "en-US": "Build App Store and Google Play screenshots, localize them into every market, and upload them directly to App Store Connect — right from your iPad.",
    "en-GB": "Build App Store and Google Play screenshots, localise them into every market, and upload them directly to App Store Connect — right from your iPad.",
    "de-DE": "Erstelle Screenshots für App Store und Google Play, lokalisiere sie für jeden Markt und lade sie direkt zu App Store Connect hoch – vom iPad aus.",
    "fr-FR": "Créez vos captures App Store et Google Play, localisez-les pour chaque marché et envoyez-les directement vers App Store Connect – depuis votre iPad.",
    "es-ES": "Crea capturas para App Store y Google Play, localízalas para cada mercado y súbelas directamente a App Store Connect, desde tu iPad.",
    "it": "Crea screenshot per App Store e Google Play, localizzali per ogni mercato e caricali direttamente su App Store Connect, dal tuo iPad.",
    "nl-NL": "Maak screenshots voor de App Store en Google Play, lokaliseer ze voor elke markt en upload ze direct naar App Store Connect – vanaf je iPad.",
    "sv": "Skapa skärmbilder för App Store och Google Play, lokalisera dem för varje marknad och ladda upp direkt till App Store Connect – från din iPad.",
    "da": "Lav screenshots til App Store og Google Play, oversæt dem til hvert marked, og upload dem direkte til App Store Connect – fra din iPad.",
    "no": "Lag skjermbilder for App Store og Google Play, lokaliser dem for hvert marked, og last dem opp direkte til App Store Connect – fra iPaden din.",
    "fi": "Luo kuvakaappaukset App Storeen ja Google Playhin, lokalisoi ne jokaiselle markkinalle ja lataa ne suoraan App Store Connectiin – suoraan iPadilta.",
    "pt-PT": "Crie capturas para a App Store e o Google Play, localize-as para cada mercado e envie-as diretamente para o App Store Connect – a partir do seu iPad.",
    "pt-BR": "Crie capturas para a App Store e o Google Play, localize-as para cada mercado e envie direto para o App Store Connect – direto do seu iPad.",
    "pl": "Twórz zrzuty ekranu do App Store i Google Play, lokalizuj je na każdy rynek i wysyłaj prosto do App Store Connect – prosto z iPada.",
    "tr": "App Store ve Google Play ekran görüntüleri oluşturun, her pazar için yerelleştirin ve doğrudan App Store Connect'e yükleyin – iPad'inizden.",
    "id": "Buat screenshot untuk App Store dan Google Play, lokalkan untuk setiap pasar, dan unggah langsung ke App Store Connect — dari iPad Anda.",
    "vi": "Tạo ảnh chụp màn hình cho App Store và Google Play, bản địa hóa cho từng thị trường và tải thẳng lên App Store Connect — ngay trên iPad.",
    "ja": "App Store と Google Play のスクリーンショットを作成し、各国向けにローカライズして、App Store Connect へ直接アップロード。iPad だけで完結します。",
    "ko": "App Store와 Google Play 스크린샷을 만들고, 시장별로 현지화하고, App Store Connect에 바로 업로드하세요. iPad만으로 끝납니다.",
    "zh-Hans": "制作 App Store 与 Google Play 截图，按市场本地化，并直接上传到 App Store Connect — 在 iPad 上即可完成。",
    "zh-Hant": "製作 App Store 與 Google Play 截圖，依市場在地化，並直接上傳至 App Store Connect — 在 iPad 上即可完成。",
    "ru": "Создавайте скриншоты для App Store и Google Play, локализуйте их для каждого рынка и загружайте прямо в App Store Connect — с iPad.",
    "uk": "Створюйте скриншоти для App Store і Google Play, локалізуйте їх для кожного ринку та завантажуйте просто в App Store Connect — з iPad.",
    "ar-SA": "أنشئ لقطات شاشة لـ App Store و Google Play، وترجمها لكل سوق، وارفعها مباشرة إلى App Store Connect — من الـ iPad مباشرة.",
    "he": "צרו צילומי מסך ל-App Store ול-Google Play, תרגמו אותם לכל שוק והעלו ישירות ל-App Store Connect — היישר מה-iPad.",
    "th": "สร้างภาพหน้าจอสำหรับ App Store และ Google Play แปลให้ทุกตลาด และอัปโหลดตรงไปยัง App Store Connect ได้จาก iPad",
}
PROMO_IOS = _IOS_TAIL

VERBATIM = ["App Store", "Google Play", "App Store Connect"]
LIMITS = {"subtitle": 30, "promo": 170}
