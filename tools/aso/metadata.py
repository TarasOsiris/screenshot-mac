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
#
# `el` is the one script-vs-search exception. Greek is not Latin, but the Greek
# phrases autosuggest nothing at all (Finding 5), so a Greek subtitle would spend
# all 30 characters on words nobody types. Local search volume is the criterion,
# not the alphabet.
SUBTITLE = {
    "en-US": LATIN_SUBTITLE, "en-GB": LATIN_SUBTITLE, "de-DE": LATIN_SUBTITLE,
    "fr-FR": LATIN_SUBTITLE, "es-ES": LATIN_SUBTITLE, "it": LATIN_SUBTITLE,
    "nl-NL": LATIN_SUBTITLE, "sv": LATIN_SUBTITLE, "da": LATIN_SUBTITLE,
    "no": LATIN_SUBTITLE, "fi": LATIN_SUBTITLE, "pt-PT": LATIN_SUBTITLE,
    "pt-BR": LATIN_SUBTITLE, "pl": LATIN_SUBTITLE, "tr": LATIN_SUBTITLE,
    "id": LATIN_SUBTITLE, "vi": LATIN_SUBTITLE,
    # added 2026-09-09
    "en-AU": LATIN_SUBTITLE, "en-CA": LATIN_SUBTITLE, "es-MX": LATIN_SUBTITLE,
    "fr-CA": LATIN_SUBTITLE, "cs": LATIN_SUBTITLE, "sk": LATIN_SUBTITLE,
    "hu": LATIN_SUBTITLE, "ro": LATIN_SUBTITLE, "hr": LATIN_SUBTITLE,
    "ca": LATIN_SUBTITLE, "sl-SI": LATIN_SUBTITLE, "el": LATIN_SUBTITLE,
    "ja": "アプリ画像の作成とローカライズ",
    "ko": "앱 스크린샷 제작 및 현지화",
    "zh-Hans": "应用截图制作与本地化",
    "zh-Hant": "應用截圖製作與在地化",
    "ru": "Скриншоты и локализация",
    "uk": "Скриншоти і локалізація",
    "ar-SA": "لقطات شاشة التطبيقات والتوطين",
    "he": "צילומי מסך ולוקליזציה",
    "th": "ภาพหน้าจอแอปและการแปลภาษา",
    # added 2026-09-10. These keep the English subtitle for the same reason `el`
    # does — the criterion is local search volume, not the alphabet. Developer
    # tooling in India, Pakistan, Bangladesh and Malaysia is searched for in
    # English; a Devanagari or Tamil subtitle would spend all 30 characters on
    # words nobody types. The descriptions are translated (descriptions.py):
    # a description is read, a subtitle is searched.
    "ms": LATIN_SUBTITLE, "hi": LATIN_SUBTITLE, "mr-IN": LATIN_SUBTITLE,
    "bn-BD": LATIN_SUBTITLE, "gu-IN": LATIN_SUBTITLE, "ta-IN": LATIN_SUBTITLE,
    "te-IN": LATIN_SUBTITLE, "kn-IN": LATIN_SUBTITLE, "ml-IN": LATIN_SUBTITLE,
    "ur-PK": LATIN_SUBTITLE,
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

    # added 2026-09-09
    "en-AU": "Build a complete screenshot set, localise it into every market, and upload directly to App Store Connect. Automate it all from your AI assistant via MCP.",
    "en-CA": "Build a complete screenshot set, localize it into every market, and upload directly to App Store Connect. Automate it all from your AI assistant via MCP.",
    "es-MX": "Arma un set completo de capturas, localízalo para cada mercado y súbelo directo a App Store Connect. Automatiza todo desde tu asistente de IA con MCP.",
    "fr-CA": "Montez une série complète de captures, adaptez-la à chaque marché et téléversez-la dans App Store Connect. Automatisez le tout depuis votre assistant IA via MCP.",
    "cs": "Sestavte kompletní sadu snímků obrazovky, lokalizujte ji do všech trhů a nahrajte přímo do App Store Connect. Vše zautomatizujte ze svého AI asistenta přes MCP.",
    "sk": "Vytvorte kompletnú sadu snímok obrazovky, lokalizujte ju pre všetky trhy a nahrajte do App Store Connect. Všetko zautomatizujte z AI asistenta cez MCP.",
    "hu": "Készíts teljes képernyőkép-sorozatot, lokalizáld minden piacra, és töltsd fel közvetlenül az App Store Connectbe. Automatizáld az egészet AI-asszisztensedből MCP-vel.",
    "ro": "Construiește un set complet de capturi, localizează-l pentru toate piețele și încarcă-l direct în App Store Connect. Automatizează tot din asistentul tău AI, prin MCP.",
    "hr": "Izradite cijeli set snimki zaslona, lokalizirajte ga za svako tržište i prenesite izravno na App Store Connect. Sve automatizirajte AI asistentom preko MCP-a.",
    "el": "Φτιάξτε πλήρες σετ στιγμιοτύπων, προσαρμόστε το σε κάθε αγορά και ανεβάστε το απευθείας στο App Store Connect. Αυτοματοποιήστε τα πάντα μέσω MCP.",
    "ca": "Crea un joc complet de captures, localitza'l a tots els mercats i puja'l directament a App Store Connect. Automatitza-ho tot amb el teu assistent d'IA via MCP.",
    "sl-SI": "Sestavite celoten nabor posnetkov zaslona, ga lokalizirajte za vse trge in naložite v App Store Connect. Vse skupaj avtomatizirajte s pomočnikom AI prek MCP.",
    # added 2026-09-10
    "ms": "Bina set tangkapan skrin yang lengkap, setempatkan untuk setiap pasaran, dan muat naik terus ke App Store Connect. Automasikan semuanya melalui MCP.",
    "hi": "पूरा स्क्रीनशॉट सेट बनाएँ, हर बाज़ार के लिए उसका अनुवाद करें और सीधे App Store Connect पर अपलोड करें। यह सब MCP से अपने-आप कराएँ।",
    "mr-IN": "संपूर्ण स्क्रीनशॉट संच तयार करा, प्रत्येक बाजारपेठेसाठी भाषांतरित करा आणि थेट App Store Connect वर अपलोड करा. हे सर्व MCP द्वारे स्वयंचलित करा.",
    "bn-BD": "সম্পূর্ণ স্ক্রিনশট সেট তৈরি করুন, প্রতিটি বাজারের জন্য অনুবাদ করুন এবং সরাসরি App Store Connect-এ আপলোড করুন। পুরোটা MCP দিয়ে স্বয়ংক্রিয় করুন।",
    "gu-IN": "આખો સ્ક્રીનશોટ સેટ બનાવો, દરેક બજાર માટે ભાષાંતર કરો અને સીધા App Store Connect પર અપલોડ કરો. આ બધું MCP વડે આપમેળે કરાવો.",
    "ta-IN": "முழு ஸ்கிரீன்ஷாட் தொகுப்பை உருவாக்கி, ஒவ்வொரு சந்தைக்கும் மொழிபெயர்த்து, நேரடியாக App Store Connect-க்கு பதிவேற்றுங்கள். அனைத்தையும் MCP வழியாக தானியக்கமாக்குங்கள்.",
    "te-IN": "పూర్తి స్క్రీన్‌షాట్ సెట్ రూపొందించండి, ప్రతి మార్కెట్ కోసం అనువదించండి, నేరుగా App Store Connect కు అప్‌లోడ్ చేయండి. అంతా MCP తో ఆటోమేట్ చేయండి.",
    "kn-IN": "ಪೂರ್ಣ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸೆಟ್ ರಚಿಸಿ, ಪ್ರತಿ ಮಾರುಕಟ್ಟೆಗೆ ಅನುವಾದಿಸಿ, ನೇರವಾಗಿ App Store Connect ಗೆ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ. ಎಲ್ಲವನ್ನೂ MCP ಮೂಲಕ ಸ್ವಯಂಚಾಲಿತಗೊಳಿಸಿ.",
    "ml-IN": "പൂർണ്ണ സ്ക്രീൻഷോട്ട് സെറ്റ് ഉണ്ടാക്കുക, ഓരോ വിപണിക്കും വിവർത്തനം ചെയ്യുക, നേരിട്ട് App Store Connect-ലേക്ക് അപ്‌ലോഡ് ചെയ്യുക. എല്ലാം MCP വഴി യാന്ത്രികമാക്കുക.",
    "ur-PK": "مکمل اسکرین شاٹ سیٹ بنائیں، ہر مارکیٹ کے لیے ترجمہ کریں اور براہِ راست App Store Connect پر اپ لوڈ کریں۔ یہ سب MCP کے ذریعے خودکار کریں۔",
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

    # added 2026-09-09
    "en-AU": "Build a complete screenshot set, localise it into every market, and upload it directly to App Store Connect — right from your iPad.",
    "en-CA": "Build a complete screenshot set, localize it into every market, and upload it directly to App Store Connect — right from your iPad.",
    "es-MX": "Arma un set completo de capturas, localízalo para cada mercado y súbelo directo a App Store Connect, desde tu iPad.",
    "fr-CA": "Montez une série complète de captures, adaptez-la à chaque marché et téléversez-la directement dans App Store Connect — depuis votre iPad.",
    "cs": "Sestavte kompletní sadu snímků obrazovky, lokalizujte ji do všech trhů a nahrajte ji rovnou do App Store Connect — přímo z iPadu.",
    "sk": "Vytvorte kompletnú sadu snímok obrazovky, lokalizujte ju pre všetky trhy a nahrajte ju do App Store Connect — priamo z iPadu.",
    "hu": "Készíts teljes képernyőkép-sorozatot, lokalizáld minden piacra, és töltsd fel közvetlenül az App Store Connectbe — egyenesen az iPadedről.",
    "ro": "Construiește un set complet de capturi, localizează-l pentru toate piețele și încarcă-l direct în App Store Connect — chiar de pe iPad.",
    "hr": "Izradite cijeli set snimki zaslona, lokalizirajte ga za svako tržište i prenesite ga izravno na App Store Connect — ravno s vašeg iPada.",
    "el": "Φτιάξτε πλήρες σετ στιγμιοτύπων, προσαρμόστε το σε κάθε αγορά και ανεβάστε το απευθείας στο App Store Connect — από το iPad σας.",
    "ca": "Crea un joc complet de captures, localitza'l a tots els mercats i puja'l directament a App Store Connect, des del teu iPad.",
    "sl-SI": "Sestavite celoten nabor posnetkov zaslona, ga lokalizirajte za vse trge in ga naložite neposredno v App Store Connect – kar z iPada.",
    # added 2026-09-10
    "ms": "Bina set tangkapan skrin yang lengkap, setempatkan untuk setiap pasaran, dan muat naik terus ke App Store Connect — terus dari iPad anda.",
    "hi": "पूरा स्क्रीनशॉट सेट बनाएँ, हर बाज़ार के लिए उसका अनुवाद करें और सीधे App Store Connect पर अपलोड करें — अपने iPad से ही।",
    "mr-IN": "संपूर्ण स्क्रीनशॉट संच तयार करा, प्रत्येक बाजारपेठेसाठी भाषांतरित करा आणि थेट App Store Connect वर अपलोड करा — तुमच्या iPad वरूनच.",
    "bn-BD": "সম্পূর্ণ স্ক্রিনশট সেট তৈরি করুন, প্রতিটি বাজারের জন্য অনুবাদ করুন এবং সরাসরি App Store Connect-এ আপলোড করুন — আপনার iPad থেকেই।",
    "gu-IN": "આખો સ્ક્રીનશોટ સેટ બનાવો, દરેક બજાર માટે ભાષાંતર કરો અને સીધા App Store Connect પર અપલોડ કરો — તમારા iPad પરથી જ.",
    "ta-IN": "முழு ஸ்கிரீன்ஷாட் தொகுப்பை உருவாக்கி, ஒவ்வொரு சந்தைக்கும் மொழிபெயர்த்து, நேரடியாக App Store Connect-க்கு பதிவேற்றுங்கள் — உங்கள் iPad-இலிருந்தே.",
    "te-IN": "పూర్తి స్క్రీన్‌షాట్ సెట్ రూపొందించండి, ప్రతి మార్కెట్ కోసం అనువదించండి, నేరుగా App Store Connect కు అప్‌లోడ్ చేయండి — మీ iPad నుంచే.",
    "kn-IN": "ಪೂರ್ಣ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸೆಟ್ ರಚಿಸಿ, ಪ್ರತಿ ಮಾರುಕಟ್ಟೆಗೆ ಅನುವಾದಿಸಿ, ನೇರವಾಗಿ App Store Connect ಗೆ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ — ನಿಮ್ಮ iPad ನಿಂದಲೇ.",
    "ml-IN": "പൂർണ്ണ സ്ക്രീൻഷോട്ട് സെറ്റ് ഉണ്ടാക്കുക, ഓരോ വിപണിക്കും വിവർത്തനം ചെയ്യുക, നേരിട്ട് App Store Connect-ലേക്ക് അപ്‌ലോഡ് ചെയ്യുക — നിങ്ങളുടെ iPad-ൽ നിന്ന് തന്നെ.",
    "ur-PK": "مکمل اسکرین شاٹ سیٹ بنائیں، ہر مارکیٹ کے لیے ترجمہ کریں اور براہِ راست App Store Connect پر اپ لوڈ کریں — اپنے iPad سے ہی۔",
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
