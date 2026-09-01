# -*- coding: utf-8 -*-
"""Strip every Google Play reference from the live App Store descriptions.

Apple rejected 4.9 (iOS) on 2026-09-01 under **2.3.10 — Accurate Metadata**:
"Revise the app's description to remove Google Play references." The description
named the competing store seven times per locale, in 26 locales on each of the
two platform trains.

Only ~10 of those 52 texts exist in this repo (`descriptions.py`); the other 16
locales were written straight to App Store Connect in Aug 2026 and live nowhere
else. So the transform runs against the **live** text rather than a stored copy,
and every edit is a pure deletion of the Google Play fragment — no re-translation,
which would have thrown away copy that is already reviewed and correct.

`Android` and `Pixel` stay: they name device frames the app actually draws, which
is the functionality 2.3.10 explicitly carves out, and Apple's notice named only
Google Play.

  python3 tools/aso/degoogle.py <version-id> <MAC_OS|IOS> [--dry-run]

Re-running is a no-op: the fragments are gone, so nothing matches. It is kept as
the record of exactly which words left the listing.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

APP_ID = "6760177675"
LIMIT = 4000

# Locale -> (old, new). Applied to whichever platform's text contains the old
# fragment; a rule that matches nothing is skipped, and the audit below fails the
# locale if any "google" survives. Ordered so a broader rule never eats a
# narrower one.
RULES = {
 "en-US": [
  ("for the App Store and Google Play. Design", "for the App Store. Design"),
  ("built specifically for App Store and Google Play screenshots.",
   "built specifically for App Store screenshots."),
  ("App Store Connect uploads, Google Play uploads, batch exports",
   "App Store Connect uploads, batch exports"),
  ("in one project for App Store, Google Play, websites,",
   "in one project for the App Store, websites,"),
  ("- Create App Store screenshots and Google Play screenshots from one project",
   "- Create App Store screenshots from one project"),
  ("\n- Upload store listing screenshots directly to Google Play", ""),
  ("Google Play screenshot maker, ", ""),
  ("App Store Connect uploader, Google Play screenshot uploader, or MCP-ready",
   "App Store Connect uploader, or MCP-ready"),
  ("App Store Connect uploader, or Google Play screenshot uploader, Screenshot Bro",
   "or an App Store Connect uploader, Screenshot Bro"),
 ],
 "ar-SA": [
  ("App Store و Google Play. صمّم", "App Store. صمّم"),
  ("App Store و Google Play. أنشئ", "App Store. أنشئ"),
  ("إلى App Store Connect، وعمليات الرفع إلى Google Play، والتصدير",
   "إلى App Store Connect، والتصدير"),
  ("من أجل App Store وGoogle Play والمواقع", "من أجل App Store والمواقع"),
  ("لأجل App Store و Google Play والمواقع", "لأجل App Store والمواقع"),
  ("- أنشئ لقطات شاشة App Store ولقطات شاشة Google Play من مشروع واحد",
   "- أنشئ لقطات شاشة App Store من مشروع واحد"),
  ("\n- ارفع لقطات شاشة قائمة المتجر مباشرةً إلى Google Play", ""),
  ("أو أداة لصنع لقطات شاشة Google Play، ", ""),
  ("أو أداة صنع لقطات شاشة Google Play، ", ""),
  ("أو أداة رفع لقطات شاشة إلى Google Play، ", ""),
  ("أو أداة رفع لقطات شاشة Google Play، ", ""),
 ],
 "da": [
  ("til App Store og Google Play. Design", "til App Store. Design"),
  ("bygget specifikt til App Store- og Google Play-skærmbilleder.",
   "bygget specifikt til App Store-skærmbilleder."),
  ("uploads til App Store Connect, uploads til Google Play, batch-eksport",
   "uploads til App Store Connect, batch-eksport"),
  ("App Store Connect-uploads, Google Play-uploads, batch-eksporter",
   "App Store Connect-uploads, batch-eksporter"),
  ("projekt til App Store, Google Play, websteder,", "projekt til App Store, websteder,"),
  ("- Opret skærmbilleder til App Store og Google Play fra ét projekt",
   "- Opret skærmbilleder til App Store fra ét projekt"),
  ("- Lav App Store-skærmbilleder og Google Play-skærmbilleder fra ét projekt",
   "- Lav App Store-skærmbilleder fra ét projekt"),
  ("\n- Upload skærmbilleder til butikslister direkte til Google Play", ""),
  ("\n- Upload skærmbilleder til butiksvisning direkte til Google Play", ""),
  ("et værktøj til at lave Google Play-skærmbilleder, ", ""),
  ("en Google Play-skærmbilledeprogram, ", ""),
  ("App Store Connect, en uploader til Google Play-skærmbilleder eller",
   "App Store Connect eller"),
  (", en App Store Connect-uploader eller en Google Play-skærmbilledeuploader,",
   " eller en App Store Connect-uploader,"),
 ],
 "de-DE": [
  ("für App Store und Google Play. Gestalte", "für den App Store. Gestalte"),
  ("speziell für Screenshots im App Store und bei Google Play entwickelt wurde.",
   "speziell für Screenshots im App Store entwickelt wurde."),
  ("App Store Connect-Uploads, Google Play-Uploads, Stapel-Exporte",
   "App Store Connect-Uploads, Stapel-Exporte"),
  ("Uploads zu App Store Connect, Uploads zu Google Play, Stapel-Exporte",
   "Uploads zu App Store Connect, Stapel-Exporte"),
  ("für App Store, Google Play, Websites,", "für den App Store, Websites,"),
  ("- Erstellen Sie App Store Screenshots und Google Play Screenshots aus einem Projekt",
   "- Erstellen Sie App Store Screenshots aus einem Projekt"),
  ("- Erstelle App Store- und Google Play-Screenshots aus einem Projekt",
   "- Erstelle App Store-Screenshots aus einem Projekt"),
  ("\n- Laden Sie Store-Listing-Screenshots direkt in Google Play hoch", ""),
  ("\n- Lade Screenshots für den Store-Eintrag direkt zu Google Play hoch", ""),
  ("Google Play Screenshot Maker, ", ""),
  ("einen Google Play-Screenshot-Generator, ", ""),
  ("App Store Connect Uploader, Google Play Screenshot Uploader oder ein MCP-fähiges",
   "App Store Connect Uploader oder ein MCP-fähiges"),
  (", einen App Store Connect-Uploader oder einen Google Play-Screenshot-Uploader brauchst",
   " oder einen App Store Connect-Uploader brauchst"),
 ],
 "es-ES": [
  ("para la App Store y Google Play. Diseña", "para la App Store. Diseña"),
  ("diseñado específicamente para las capturas de la App Store y de Google Play.",
   "diseñado específicamente para las capturas de la App Store."),
  ("cargas en App Store Connect, cargas en Google Play, exportaciones por lotes",
   "cargas en App Store Connect, exportaciones por lotes"),
  ("subidas a App Store Connect, subidas a Google Play, exportaciones por lotes",
   "subidas a App Store Connect, exportaciones por lotes"),
  ("proyecto para App Store, Google Play, sitios web,",
   "proyecto para la App Store, sitios web,"),
  ("- Cree capturas de pantalla de App Store y Google Play desde un solo proyecto",
   "- Cree capturas de pantalla de App Store desde un solo proyecto"),
  ("- Crea capturas para la App Store y para Google Play desde un mismo proyecto",
   "- Crea capturas para la App Store desde un mismo proyecto"),
  ("\n- Cargue capturas de pantalla de la ficha de la tienda directamente a Google Play", ""),
  ("\n- Sube capturas de la ficha de la tienda directamente a Google Play", ""),
  ("un creador de capturas de pantalla de Google Play, ", ""),
  ("un creador de capturas para Google Play, ", ""),
  ("un cargador de App Store Connect, un cargador de capturas de pantalla de Google Play o una herramienta",
   "un cargador de App Store Connect o una herramienta"),
  (", un cargador para App Store Connect o un cargador de capturas para Google Play, Screenshot Bro",
   " o un cargador para App Store Connect, Screenshot Bro"),
 ],
 "fi": [
  ("generaattori App Storeen ja Google Playhin.", "generaattori App Storeen."),
  ("rakennettu erityisesti App Store- ja Google Play -kuvakaappauksia varten.",
   "rakennettu erityisesti App Store -kuvakaappauksia varten."),
  ("App Store Connect -lähetykset, Google Play -lähetykset, eräviennit",
   "App Store Connect -lähetykset, eräviennit"),
  ("App Store Connect -lataukset, Google Play -lataukset, eräviennit",
   "App Store Connect -lataukset, eräviennit"),
  ("projektissa App Storea, Google Playta, verkkosivustoja,",
   "projektissa App Storea, verkkosivustoja,"),
  ("- Luo App Store- ja Google Play -kuvakaappaukset yhdestä projektista",
   "- Luo App Store -kuvakaappaukset yhdestä projektista"),
  ("- Luo App Store -kuvakaappaukset ja Google Play -kuvakaappaukset yhdestä projektista",
   "- Luo App Store -kuvakaappaukset yhdestä projektista"),
  ("\n- Lähetä kaupan sivun kuvakaappaukset suoraan Google Playhin", ""),
  ("\n- Lataa kauppalistauksen kuvakaappaukset suoraan Google Playhin", ""),
  ("Google Play -kuvakaappausten tekijän, ", ""),
  ("App Store Connect -lähetystyökalun, Google Play -kuvakaappausten lähetystyökalun tai MCP-valmiin",
   "App Store Connect -lähetystyökalun tai MCP-valmiin"),
  (", App Store Connect -latausohjelman tai Google Play -kuvakaappausten latausohjelman, Screenshot Bro",
   " tai App Store Connect -latausohjelman, Screenshot Bro"),
 ],
 "fr-FR": [
  ("pour l'App Store et Google Play. Composez", "pour l'App Store. Composez"),
  ("conçu spécialement pour les captures de l'App Store et de Google Play.",
   "conçu spécialement pour les captures de l'App Store."),
  ("les téléchargements App Store Connect, les téléchargements Google Play, les exportations par lots",
   "les téléchargements App Store Connect, les exportations par lots"),
  ("les publications sur App Store Connect, les publications sur Google Play, les exports par lots",
   "les publications sur App Store Connect, les exports par lots"),
  ("pour l'App Store, Google Play, les sites web,",
   "pour l'App Store, les sites web,"),
  ("- Créez des captures d'écran pour l'App Store et Google Play à partir d'un seul projet",
   "- Créez des captures d'écran pour l'App Store à partir d'un seul projet"),
  ("- Créez des captures pour l'App Store et pour Google Play à partir d'un seul projet",
   "- Créez des captures pour l'App Store à partir d'un seul projet"),
  ("\n- Téléchargez les captures d'écran de la fiche de magasin directement sur Google Play", ""),
  ("\n- Publiez les captures de vos fiches directement sur Google Play", ""),
  ("d'un créateur de captures d'écran Google Play, ", ""),
  ("un outil de création de captures pour Google Play, ", ""),
  ("d'un téléchargeur App Store Connect, d'un téléchargeur de captures d'écran Google Play, ou d'un outil",
   "d'un téléchargeur App Store Connect, ou d'un outil"),
  (", un outil de publication sur App Store Connect ou un outil de publication de captures sur Google Play, Screenshot Bro",
   " ou un outil de publication sur App Store Connect, Screenshot Bro"),
 ],
 "he": [
  ("עבור App Store ו-Google Play. עצבו", "עבור App Store. עצבו"),
  ("שנבנה במיוחד עבור צילומי מסך של App Store ו-Google Play.",
   "שנבנה במיוחד עבור צילומי מסך של App Store."),
  ("העלאות ל-App Store Connect, העלאות ל-Google Play, ייצוא באצווה",
   "העלאות ל-App Store Connect, ייצוא באצווה"),
  ("אחד עבור App Store, Google Play, אתרים,", "אחד עבור App Store, אתרים,"),
  ("- יצירת צילומי מסך ל-App Store וצילומי מסך ל-Google Play מתוך פרויקט אחד",
   "- יצירת צילומי מסך ל-App Store מתוך פרויקט אחד"),
  ("- צרו צילומי מסך ל-App Store וצילומי מסך ל-Google Play מתוך פרויקט אחד",
   "- צרו צילומי מסך ל-App Store מתוך פרויקט אחד"),
  ("\n- העלאת צילומי מסך של דף החנות ישירות ל-Google Play", ""),
  ("\n- העלו צילומי מסך של דף החנות ישירות ל-Google Play", ""),
  ("כלי ליצירת צילומי מסך ל-Google Play, ", ""),
  ("יוצר צילומי מסך ל-Google Play, ", ""),
  ("כלי העלאה ל-App Store Connect, כלי להעלאת צילומי מסך ל-Google Play, או כלי אוטומציה",
   "כלי העלאה ל-App Store Connect, או כלי אוטומציה"),
  (", כלי העלאה ל-App Store Connect או כלי להעלאת צילומי מסך ל-Google Play, Screenshot Bro",
   " או כלי העלאה ל-App Store Connect, Screenshot Bro"),
 ],
 "id": [
  ("untuk App Store dan Google Play. Rancang", "untuk App Store. Rancang"),
  ("dirancang khusus untuk screenshot App Store dan Google Play.",
   "dirancang khusus untuk screenshot App Store."),
  ("unggahan ke App Store Connect, unggahan ke Google Play, ekspor massal",
   "unggahan ke App Store Connect, ekspor massal"),
  ("proyek — untuk App Store, Google Play, situs web,",
   "proyek — untuk App Store, situs web,"),
  ("- Buat screenshot App Store dan Google Play dari satu proyek",
   "- Buat screenshot App Store dari satu proyek"),
  ("\n- Unggah screenshot halaman toko langsung ke Google Play", ""),
  ("pembuat screenshot Google Play, ", ""),
  ("pengunggah ke App Store Connect, pengunggah screenshot ke Google Play, atau otomatisasi",
   "pengunggah ke App Store Connect, atau otomatisasi"),
  ("pengunggah ke App Store Connect, atau pengunggah screenshot ke Google Play, Screenshot Bro",
   "atau pengunggah ke App Store Connect, Screenshot Bro"),
 ],
 "it": [
  ("per App Store e Google Play. Progetta", "per App Store. Progetta"),
  ("pensato appositamente per gli screenshot di App Store e Google Play.",
   "pensato appositamente per gli screenshot di App Store."),
  ("i caricamenti su App Store Connect, i caricamenti su Google Play, le esportazioni in batch",
   "i caricamenti su App Store Connect, le esportazioni in batch"),
  ("i caricamenti su App Store Connect, i caricamenti su Google Play, le esportazioni in blocco",
   "i caricamenti su App Store Connect, le esportazioni in blocco"),
  ("progetto per App Store, Google Play, siti web,", "progetto per App Store, siti web,"),
  ("- Crea screenshot per App Store e Google Play da un unico progetto",
   "- Crea screenshot per App Store da un unico progetto"),
  ("\n- Carica gli screenshot della scheda dello store direttamente su Google Play", ""),
  ("un generatore di screenshot per Google Play, ", ""),
  ("un creatore di screenshot per Google Play, ", ""),
  ("un uploader per App Store Connect, un uploader di screenshot per Google Play o uno strumento",
   "un uploader per App Store Connect o uno strumento"),
  (", un uploader per App Store Connect o un uploader di screenshot per Google Play, Screenshot Bro",
   " o un uploader per App Store Connect, Screenshot Bro"),
 ],
 "ja": [
  ("App Store と Google Play のためのアプリスクリーンショット作成ツールです。",
   "App Store のためのアプリスクリーンショット作成ツールです。"),
  ("App Store と Google Play のスクリーンショットのために専用設計された",
   "App Store のスクリーンショットのために専用設計された"),
  ("App Store Connectへのアップロード、Google Playへのアップロード、バッチエクスポート",
   "App Store Connectへのアップロード、バッチエクスポート"),
  ("App Store Connect へのアップロード、Google Play へのアップロード、一括書き出し",
   "App Store Connect へのアップロード、一括書き出し"),
  ("App Store、Google Play、ウェブサイト、", "App Store、ウェブサイト、"),
  ("- 1つのプロジェクトからApp StoreスクリーンショットとGoogle Playスクリーンショットを作成",
   "- 1つのプロジェクトからApp Storeスクリーンショットを作成"),
  ("- App Store 向けと Google Play 向けのスクリーンショットを一つのプロジェクトから作成",
   "- App Store 向けのスクリーンショットを一つのプロジェクトから作成"),
  ("\n- ストアリスティングスクリーンショットをGoogle Playに直接アップロード", ""),
  ("\n- ストア掲載用スクリーンショットを Google Play に直接アップロード", ""),
  ("Google Playスクリーンショット作成ツール、", ""),
  ("Google Play のスクリーンショットメーカー、", ""),
  ("App Store Connectアップローダー、Google Playスクリーンショットアップローダー、または",
   "App Store Connectアップローダー、または"),
  ("App Store Connect アップローダー、または Google Play スクリーンショットアップローダーが必要なら",
   "または App Store Connect アップローダーが必要なら"),
 ],
 "ko": [
  ("App Store와 Google Play를 위한 앱 스크린샷 생성 도구입니다.",
   "App Store를 위한 앱 스크린샷 생성 도구입니다."),
  ("App Store와 Google Play 스크린샷을 위해 특별히 만들어진",
   "App Store 스크린샷을 위해 특별히 만들어진"),
  ("App Store Connect 업로드, Google Play 업로드, 일괄 내보내기",
   "App Store Connect 업로드, 일괄 내보내기"),
  ("App Store, Google Play, 웹사이트,", "App Store, 웹사이트,"),
  ("- 하나의 프로젝트에서 App Store 스크린샷 및 Google Play 스크린샷 생성",
   "- 하나의 프로젝트에서 App Store 스크린샷 생성"),
  ("- 하나의 프로젝트로 App Store 스크린샷과 Google Play 스크린샷 제작",
   "- 하나의 프로젝트로 App Store 스크린샷 제작"),
  ("\n- Google Play에 스토어 리스팅 스크린샷 직접 업로드", ""),
  ("\n- Google Play에 스토어 등록정보 스크린샷 바로 업로드", ""),
  ("Google Play 스크린샷 메이커, ", ""),
  ("Google Play 스크린샷 제작기, ", ""),
  ("App Store Connect 업로더, Google Play 스크린샷 업로더 또는 MCP 지원",
   "App Store Connect 업로더 또는 MCP 지원"),
  (", App Store Connect 업로더, Google Play 스크린샷 업로더가 필요하다면",
   " 또는 App Store Connect 업로더가 필요하다면"),
 ],
 "nl-NL": [
  ("voor de App Store en Google Play. Ontwerp", "voor de App Store. Ontwerp"),
  ("speciaal is gemaakt voor screenshots voor de App Store en Google Play.",
   "speciaal is gemaakt voor screenshots voor de App Store."),
  ("App Store Connect-uploads, Google Play-uploads, batchexports",
   "App Store Connect-uploads, batchexports"),
  ("uploads naar App Store Connect, uploads naar Google Play, batchexports",
   "uploads naar App Store Connect, batchexports"),
  ("project voor App Store, Google Play, websites,",
   "project voor de App Store, websites,"),
  ("project voor de App Store, Google Play, websites,",
   "project voor de App Store, websites,"),
  ("- Maak App Store-schermafbeeldingen en Google Play-schermafbeeldingen vanuit één project",
   "- Maak App Store-schermafbeeldingen vanuit één project"),
  ("- Maak screenshots voor de App Store en Google Play vanuit één project",
   "- Maak screenshots voor de App Store vanuit één project"),
  ("\n- Upload schermafbeeldingen voor storevermeldingen rechtstreeks naar Google Play", ""),
  ("\n- Upload screenshots voor je storevermelding rechtstreeks naar Google Play", ""),
  ("een maker van Google Play-schermafbeeldingen, ", ""),
  ("een maker van Google Play-screenshots, ", ""),
  ("een App Store Connect-uploader, een uploader voor Google Play-schermafbeeldingen of een MCP-klare",
   "een App Store Connect-uploader of een MCP-klare"),
  (", een uploader voor App Store Connect of een uploader voor Google Play-screenshots nodig hebt",
   " of een uploader voor App Store Connect nodig hebt"),
 ],
 "no": [
  ("for App Store og Google Play. Design", "for App Store. Design"),
  ("laget spesielt for skjermbilder til App Store og Google Play.",
   "laget spesielt for skjermbilder til App Store."),
  ("opplastinger til App Store Connect, opplastinger til Google Play, batch-eksport",
   "opplastinger til App Store Connect, batch-eksport"),
  ("opplasting til App Store Connect, opplasting til Google Play, samleeksport",
   "opplasting til App Store Connect, samleeksport"),
  ("prosjekt for App Store, Google Play, nettsteder,", "prosjekt for App Store, nettsteder,"),
  ("- Lag App Store-skjermbilder og Google Play-skjermbilder fra ett prosjekt",
   "- Lag App Store-skjermbilder fra ett prosjekt"),
  ("- Lag skjermbilder for App Store og Google Play fra ett og samme prosjekt",
   "- Lag skjermbilder for App Store fra ett og samme prosjekt"),
  ("\n- Last opp skjermbilder for butikkoppføringen direkte til Google Play", ""),
  ("et verktøy for å lage Google Play-skjermbilder, ", ""),
  ("en skjermbildeskaper for Google Play, ", ""),
  ("en opplaster til App Store Connect, en opplaster for Google Play-skjermbilder eller et MCP-klart",
   "en opplaster til App Store Connect eller et MCP-klart"),
  (", et opplastingsverktøy for App Store Connect eller et opplastingsverktøy for Google Play-skjermbilder, holder",
   " eller et opplastingsverktøy for App Store Connect, holder"),
 ],
 "pl": [
  ("dla App Store i Google Play. Zaprojektuj", "dla App Store. Zaprojektuj"),
  ("zbudowany specjalnie pod zrzuty do App Store i Google Play.",
   "zbudowany specjalnie pod zrzuty do App Store."),
  ("wysyłkę do App Store Connect, wysyłkę do Google Play, eksport wsadowy",
   "wysyłkę do App Store Connect, eksport wsadowy"),
  ("projekcie — dla App Store, Google Play, stron internetowych,",
   "projekcie — dla App Store, stron internetowych,"),
  ("- Twórz zrzuty do App Store i Google Play z jednego projektu",
   "- Twórz zrzuty do App Store z jednego projektu"),
  ("\n- Wysyłaj zrzuty ze strony sklepu bezpośrednio do Google Play", ""),
  ("generatora zrzutów do Google Play, ", ""),
  ("do App Store Connect, narzędzia do wysyłania zrzutów do Google Play albo automatyzacji",
   "do App Store Connect albo automatyzacji"),
  (", narzędzia do wysyłania obrazów do App Store Connect albo narzędzia do wysyłania zrzutów do Google Play — Screenshot Bro",
   " albo narzędzia do wysyłania obrazów do App Store Connect — Screenshot Bro"),
 ],
 "pt-BR": [
  ("para a App Store e o Google Play. Crie", "para a App Store. Crie"),
  ("feito sob medida para as capturas da App Store e do Google Play.",
   "feito sob medida para as capturas da App Store."),
  ("envios para o App Store Connect, envios para o Google Play, exportações em lote",
   "envios para o App Store Connect, exportações em lote"),
  ("projeto — para a App Store, o Google Play, sites,", "projeto — para a App Store, sites,"),
  ("- Crie capturas para a App Store e para o Google Play a partir de um único projeto",
   "- Crie capturas para a App Store a partir de um único projeto"),
  ("\n- Envie as capturas da ficha da loja direto para o Google Play", ""),
  ("um gerador de capturas para o Google Play, ", ""),
  ("ao App Store Connect, um app para enviar capturas ao Google Play ou uma automação",
   "ao App Store Connect ou uma automação"),
  (", um app para enviar imagens ao App Store Connect ou um app para enviar capturas ao Google Play, o Screenshot Bro",
   " ou um app para enviar imagens ao App Store Connect, o Screenshot Bro"),
 ],
 "pt-PT": [
  ("para a App Store e o Google Play. Crie", "para a App Store. Crie"),
  ("concebido especificamente para capturas de ecrã da App Store e da Google Play.",
   "concebido especificamente para capturas de ecrã da App Store."),
  ("uploads para a App Store Connect, uploads para o Google Play, exportações em lote",
   "uploads para a App Store Connect, exportações em lote"),
  ("carregamentos para o App Store Connect, carregamentos para a Google Play, exportações em lote",
   "carregamentos para o App Store Connect, exportações em lote"),
  ("projeto para a App Store, Google Play, sites,", "projeto para a App Store, sites,"),
  ("projeto para a App Store, a Google Play, sites,", "projeto para a App Store, sites,"),
  ("- Crie capturas de tela para a App Store e Google Play a partir de um único projeto",
   "- Crie capturas de tela para a App Store a partir de um único projeto"),
  ("- Crie capturas de ecrã da App Store e da Google Play a partir de um só projeto",
   "- Crie capturas de ecrã da App Store a partir de um só projeto"),
  ("\n- Faça upload de capturas de tela de listagens da loja diretamente para o Google Play", ""),
  ("\n- Carregue capturas de ecrã da página da loja diretamente para a Google Play", ""),
  ("criador de capturas de tela para o Google Play, ", ""),
  ("um criador de capturas de ecrã para a Google Play, ", ""),
  ("uploader para a App Store Connect, uploader de capturas de tela para o Google Play ou uma ferramenta",
   "uploader para a App Store Connect ou uma ferramenta"),
  (", um carregador para o App Store Connect ou um carregador de capturas de ecrã para a Google Play, o Screenshot Bro",
   " ou um carregador para o App Store Connect, o Screenshot Bro"),
 ],
 "ru": [
  ("для App Store и Google Play. Соберите", "для App Store. Соберите"),
  ("сделанный специально для скриншотов App Store и Google Play.",
   "сделанный специально для скриншотов App Store."),
  ("загрузку в App Store Connect, загрузку в Google Play, пакетный экспорт",
   "загрузку в App Store Connect, пакетный экспорт"),
  ("— для App Store, Google Play, сайтов,", "— для App Store, сайтов,"),
  ("- Создавайте скриншоты для App Store и Google Play в одном проекте",
   "- Создавайте скриншоты для App Store в одном проекте"),
  ("\n- Загружайте скриншоты страницы приложения напрямую в Google Play", ""),
  ("генератор скриншотов для Google Play, ", ""),
  ("загрузчик в App Store Connect, загрузчик скриншотов в Google Play или автоматизация",
   "загрузчик в App Store Connect или автоматизация"),
  (", загрузчик в App Store Connect или загрузчик скриншотов в Google Play — Screenshot Bro",
   " или загрузчик в App Store Connect — Screenshot Bro"),
 ],
 "sv": [
  ("för App Store och Google Play. Designa", "för App Store. Designa"),
  ("byggt specifikt för skärmbilder till App Store och Google Play.",
   "byggt specifikt för skärmbilder till App Store."),
  ("uppladdningar till App Store Connect, uppladdningar till Google Play, batchexporter",
   "uppladdningar till App Store Connect, batchexporter"),
  ("projekt för App Store, Google Play, webbplatser,", "projekt för App Store, webbplatser,"),
  ("- Skapa skärmbilder för App Store och Google Play från ett enda projekt",
   "- Skapa skärmbilder för App Store från ett enda projekt"),
  ("\n- Ladda upp skärmbilder för butiksinformation direkt till Google Play", ""),
  ("\n- Ladda upp skärmbilder för butikslistning direkt till Google Play", ""),
  ("ett verktyg för att skapa Google Play-skärmbilder, ", ""),
  ("för App Store Connect, ett uppladdningsverktyg för Google Play-skärmbilder eller ett MCP-redo",
   "för App Store Connect eller ett MCP-redo"),
  (", ett verktyg för uppladdning till App Store Connect eller ett verktyg för uppladdning av Google Play-skärmbilder, håller",
   " eller ett verktyg för uppladdning till App Store Connect, håller"),
 ],
 "th": [
  ("สำหรับ App Store และ Google Play ออกแบบ", "สำหรับ App Store ออกแบบ"),
  ("ที่ทำขึ้นเพื่อภาพหน้าจอของ App Store และ Google Play โดยเฉพาะ",
   "ที่ทำขึ้นเพื่อภาพหน้าจอของ App Store โดยเฉพาะ"),
  ("การอัปโหลดขึ้น App Store Connect การอัปโหลดขึ้น Google Play การส่งออกเป็นชุด",
   "การอัปโหลดขึ้น App Store Connect การส่งออกเป็นชุด"),
  ("สำหรับ App Store, Google Play, เว็บไซต์,", "สำหรับ App Store, เว็บไซต์,"),
  ("- สร้างภาพหน้าจอสำหรับ App Store และ Google Play จากโปรเจกต์เดียว",
   "- สร้างภาพหน้าจอสำหรับ App Store จากโปรเจกต์เดียว"),
  ("\n- อัปโหลดภาพหน้าจอของหน้าสโตร์ตรงไปยัง Google Play", ""),
  ("เครื่องมือสร้างภาพหน้าจอสำหรับ Google Play ", ""),
  ("เครื่องมืออัปโหลดภาพหน้าจอขึ้น Google Play หรือการสั่งงาน", "หรือการสั่งงาน"),
  ("เครื่องมืออัปโหลดขึ้น App Store Connect หรือเครื่องมืออัปโหลดภาพหน้าจอขึ้น Google Play — Screenshot Bro",
   "หรือเครื่องมืออัปโหลดขึ้น App Store Connect — Screenshot Bro"),
 ],
 "tr": [
  ("App Store ve Google Play için bir uygulama ekran görüntüsü üreticisidir.",
   "App Store için bir uygulama ekran görüntüsü üreticisidir."),
  ("özellikle App Store ve Google Play ekran görüntüleri için yapılmış",
   "özellikle App Store ekran görüntüleri için yapılmış"),
  ("App Store Connect yüklemelerini, Google Play yüklemelerini, toplu dışa aktarmayı",
   "App Store Connect yüklemelerini, toplu dışa aktarmayı"),
  ("tutun — App Store, Google Play, web siteleri,", "tutun — App Store, web siteleri,"),
  ("- App Store ve Google Play ekran görüntülerini tek projeden oluşturun",
   "- App Store ekran görüntülerini tek projeden oluşturun"),
  ("\n- Mağaza sayfası ekran görüntülerini doğrudan Google Play'e yükleyin", ""),
  ("Google Play ekran görüntüsü üreticisi, ", ""),
  ("App Store Connect yükleyici, Google Play ekran görüntüsü yükleyici ya da MCP ile",
   "App Store Connect yükleyici ya da MCP ile"),
  (", App Store Connect yükleyici ya da Google Play ekran görüntüsü yükleyici arıyorsanız",
   " ya da App Store Connect yükleyici arıyorsanız"),
 ],
 "uk": [
  ("до App Store і Google Play. Складіть", "до App Store. Складіть"),
  ("створений саме для знімків App Store і Google Play.",
   "створений саме для знімків App Store."),
  ("завантаження в App Store Connect, завантаження в Google Play, пакетний експорт",
   "завантаження в App Store Connect, пакетний експорт"),
  ("— для App Store, Google Play, сайтів,", "— для App Store, сайтів,"),
  ("- Створюйте знімки для App Store і Google Play в одному проєкті",
   "- Створюйте знімки для App Store в одному проєкті"),
  ("\n- Завантажуйте знімки сторінки застосунку напряму в Google Play", ""),
  ("генератор знімків для Google Play, ", ""),
  ("завантажувач до App Store Connect, завантажувач знімків до Google Play або автоматизація",
   "завантажувач до App Store Connect або автоматизація"),
  (", завантажувач до App Store Connect або завантажувач знімків до Google Play — Screenshot Bro",
   " або завантажувач до App Store Connect — Screenshot Bro"),
 ],
 "vi": [
  ("ứng dụng cho App Store và Google Play. Thiết kế", "ứng dụng cho App Store. Thiết kế"),
  ("làm riêng cho ảnh chụp trên App Store và Google Play.",
   "làm riêng cho ảnh chụp trên App Store."),
  ("tải lên App Store Connect, tải lên Google Play, xuất theo lô",
   "tải lên App Store Connect, xuất theo lô"),
  ("— cho App Store, Google Play, website,", "— cho App Store, website,"),
  ("- Tạo ảnh chụp cho App Store và Google Play từ một dự án",
   "- Tạo ảnh chụp cho App Store từ một dự án"),
  ("\n- Tải ảnh chụp trang cửa hàng trực tiếp lên Google Play", ""),
  ("công cụ tạo ảnh chụp cho Google Play, ", ""),
  ("lên App Store Connect, công cụ tải ảnh chụp lên Google Play hay công cụ tự động hóa",
   "lên App Store Connect hay công cụ tự động hóa"),
  (", công cụ tải ảnh lên App Store Connect hay công cụ tải ảnh chụp lên Google Play, Screenshot Bro",
   " hay công cụ tải ảnh lên App Store Connect, Screenshot Bro"),
 ],
 "zh-Hans": [
  ("是面向 App Store 与 Google Play 的应用截图生成工具。", "是面向 App Store 的应用截图生成工具。"),
  ("是一款专为 App Store 和 Google Play 截图打造的", "是一款专为 App Store 截图打造的"),
  ("App Store Connect 上传、Google Play 上传、批量导出", "App Store Connect 上传、批量导出"),
  ("App Store、Google Play、网站、", "App Store、网站、"),
  ("- 从一个项目创建 App Store 截图和 Google Play 截图", "- 从一个项目创建 App Store 截图"),
  ("- 在同一个项目中制作 App Store 截图和 Google Play 截图", "- 在同一个项目中制作 App Store 截图"),
  ("\n- 直接上传商店列表截图到 Google Play", ""),
  ("\n- 将商店页面截图直接上传到 Google Play", ""),
  ("Google Play 截图制作工具、", ""),
  ("App Store Connect 上传工具、Google Play 截图上传工具，或者支持 MCP",
   "App Store Connect 上传工具，或者支持 MCP"),
  ("、App Store Connect 上传工具或 Google Play 截图上传工具，Screenshot Bro",
   "或 App Store Connect 上传工具，Screenshot Bro"),
 ],
 "zh-Hant": [
  ("是專為 App Store 與 Google Play 打造的 App 截圖產生器。", "是專為 App Store 打造的 App 截圖產生器。"),
  ("是一款專為 App Store 與 Google Play 截圖打造的截圖製作與編輯工具。",
   "是一款專為 App Store 截圖打造的截圖製作與編輯工具。"),
  ("App Store Connect 上傳、Google Play 上傳、批次匯出", "App Store Connect 上傳、批次匯出"),
  ("供 App Store、Google Play、網站、", "供 App Store、網站、"),
  ("- 在同一個專案中製作 App Store 截圖與 Google Play 截圖", "- 在同一個專案中製作 App Store 截圖"),
  ("\n- 將商店頁面截圖直接上傳至 Google Play", ""),
  ("Google Play 截圖產生器、", ""),
  ("App Store Connect 上傳工具、Google Play 截圖上傳工具，或支援 MCP",
   "App Store Connect 上傳工具，或支援 MCP"),
  ("、App Store Connect 上傳工具或 Google Play 截圖上傳工具，Screenshot Bro",
   "或 App Store Connect 上傳工具，Screenshot Bro"),
 ],
}
RULES["en-GB"] = RULES["en-US"]


def scrub(locale, text):
    """Apply this locale's deletions. Returns (new_text, problems)."""
    for old, new in RULES[locale]:
        text = text.replace(old, new)
    problems = []
    if "google" in text.lower():
        leftover = [l for l in text.split("\n") if "google" in l.lower()]
        problems.append(f"still names Google: {leftover[0][:120]}")
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
        if "google" not in text.lower():
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
