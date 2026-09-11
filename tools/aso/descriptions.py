# -*- coding: utf-8 -*-
"""App Store descriptions for the locales added in Aug 2026 and Sept 2026.

Those locales were created carrying the en-US description (see finish.py), which
was no regression — Apple already showed them the en-US listing as a fallback.
This file is the real copy. macOS and iOS are separate texts: the macOS listing
advertises the MCP server and Finder, both of which are `#if os(macOS)` only, so
the iOS text must never mention either.

en-GB and en-AU are not stored: they are a spelling pass over the version's own
live en-US row (`british`), so they can never drift from an English rewrite.
Every other locale is translated from en-US — never from another translation —
except zh-Hant, which is written in Taiwan vocabulary rather than converted from
zh-Hans.

en-CA is deliberately absent from LOCALES. Canadian English keeps the -ize
spellings this copy uses, and the source contains no -our/-re word, so a spelling
pass would be a no-op and `review` would flag the result as "identical to the
en-US source". finish.py fills it with the version's own en-US text, which is the
correct Canadian copy; the value of the locale is its own keyword field.

macOS runs long, so the expanding-script locales carry the same trim the existing
16 got: the 4 redundant bullets, then the closing "whether you are preparing"
paragraph. zh-Hant is compact enough to keep the full text.

  python3 tools/aso/descriptions.py           # review all 20 against the live en-US
  python3 tools/aso/descriptions.py --offline  # no network; skips the en-US diff
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

LIMIT = 4000        # Apple rejects the write above this
TRIM_AT = 3900      # anything above this is treated as needing a trim

LOCALES = ["en-GB", "pt-BR", "ru", "pl", "tr", "uk", "id", "vi", "th", "zh-Hant",
           # added 2026-09-09 — see RESEARCH.md Finding 5
           "en-AU", "es-MX", "fr-CA", "cs", "sk", "hu", "ro", "hr", "el", "ca",
           "sl-SI",
           # added 2026-09-10 — South Asia and Malaysia. The subtitle and keyword
           # fields stay English for these (see keywords.py): a description is read,
           # not searched, so it is translated; the search surfaces follow demand.
           "ms", "hi", "mr-IN", "bn-BD", "gu-IN", "ta-IN", "te-IN", "kn-IN",
           "ml-IN", "ur-PK"]

# Spelling pass over the live en-US row rather than a stored translation.
SPELLING_PASS = {"en-GB", "en-AU"}

# Must survive byte-identical in every locale.
ATOMS = ["Screenshot Bro", "App Store", "App Store Connect",
         "iPhone", "iPad", "Mac", "PNG", "JPEG", "SVG",
         "iCloud", "ZIP",
         "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"]
ATOMS_MAC_ONLY = ["MCP", "Model Context Protocol", "Claude Code",
                  "Claude Desktop", "Cursor"]
BANNED_IOS = ["MCP", "Model Context Protocol", "Finder"]

# Price talk in the description of a paywalled app is a rejection class.
# 2.3.10 — the competing platform. Apple rejected 4.9 (iOS) on 2026-09-01 for naming
# Google Play in the description, so a reintroduction has to fail the review, not
# the store. Latin and local script: a translated description is still metadata.
# `android` and `pixel` joined the list after the 2026-09-11 rejection of 4.14 (iOS),
# which killed the carve-out theory they had been kept under — Apple treats the word
# as a competitor reference even when the app really draws that device frame. Both
# were `ATOMS` until then; see deandroid.py. "pixel" is safe to match bare: no locale
# writes the unit, only the phone.
BANNED_PLATFORM = ["google play", "googleplay", "google", "play store",
                   "гугл", "плей", "구글", "グーグル", "谷歌", "جوجل", "גוגל",
                   "android", "pixel", "андроид", "안드로이드", "アンドロイド",
                   "安卓", "أندرويد", "אנדרואיד", "แอนดรอยด์"]

BANNED_ANY = ["free", "gratis", "grátis", "discount", "бесплатн", "скидк",
              "безкоштов", "знижк", "darmow", "zniżk", "ücretsiz", "indirim",
              "miễn phí", "giảm giá", "ฟรี", "ส่วนลด", "免費", "免费", "折扣",
              # added 2026-09-09 with the 12 new locales
              "gratuito", "descuento", "rebaja",          # es-MX
              "gratuit", "rabais", "réduction",           # fr-CA, ro
              "zdarma", "slev",                           # cs
              "zadarmo", "zľav",                          # sk
              "ingyen", "kedvezmény", "akció",            # hu
              "reducere",                                 # ro
              "besplatn", "popust",                       # hr, sl-SI
              "brezplač",                                 # sl-SI
              "δωρεάν", "έκπτωση", "προσφορά",            # el
              "gratuït", "descompte"]                     # ca

# Script guards — a stripped diacritic or a mojibake round trip matches nothing.
# Only characters common enough to appear in any full description: a rare letter
# (ru "ъ", uk "ґ", th "ฮ") would fail honest copy. Script integrity for those is
# covered by SCRIPT_RANGE plus the ru/uk-only letter checks in review().
SCRIPT_REQUIRED = {"vi": "ảứộ", "tr": "şğı", "zh-Hant": "專範匯",
                   # added 2026-09-09. Same bar as above: only letters frequent
                   # enough that honest copy of this length cannot avoid them.
                   "cs": "ěšč", "sk": "šč", "hu": "őű", "ro": "șță",
                   "hr": "čž", "sl-SI": "čšž", "ca": "àè", "es-MX": "óñ",
                   "fr-CA": "éà"}
# Simplified-only forms: their presence means zh-Hans leaked into zh-Hant.
SIMPLIFIED_ONLY = "软图应备设计项说编辑导语简体关开张页无为与个"
TAIWAN_VOCAB = ["專案", "範本", "匯出", "匯入", "資料夾", "字型", "漸層",
                "中繼資料", "預設", "圖層"]

_BRITISH = {
    "localize": "localise", "localized": "localised", "localizing": "localising",
    "localization": "localisation", "localizations": "localisations",
    "color": "colour", "colors": "colours",
    "optimize": "optimise", "optimized": "optimised",
    "optimization": "optimisation", "center": "centre", "centered": "centred",
    "customize": "customise", "customized": "customised",
    "organize": "organise", "organized": "organised",
    "personalize": "personalise", "prioritize": "prioritise",
    "analyze": "analyse",
}


def british(text):
    """en-GB is a spelling pass, not a translation — everything else stays put."""
    pattern = "|".join(sorted(_BRITISH, key=len, reverse=True))

    def one(match):
        word = match.group(0)
        swapped = _BRITISH[word.lower()]
        return swapped.capitalize() if word[0].isupper() else swapped

    return re.sub(rf"\b({pattern})\b", one, text, flags=re.IGNORECASE)


DESC_MAC = {}
DESC_IOS = {}

DESC_MAC["pt-BR"] = """\
O Screenshot Bro é um gerador de capturas de tela para a App Store. Crie um conjunto completo de capturas de uma só vez, adicione molduras de dispositivos, localize cada título para cada mercado em que você publica e envie tudo direto para o App Store Connect — sem sair do Mac.

Ao contrário das ferramentas de design genéricas, o Screenshot Bro entende linhas específicas por dispositivo, localização, envios para o App Store Connect, exportações em lote, projetos reutilizáveis e automação local com assistentes de IA pelo Model Context Protocol.

Monte conjuntos completos de capturas para iPhone, iPad e Mac. Comece por um modelo ou crie o seu próprio sistema de layout. Solte as capturas, adicione molduras de dispositivos ou composições sem moldura, escreva títulos e legendas, estilize texto rico com fontes personalizadas e ajuste cada detalhe no canvas.

O Screenshot Bro pode hospedar um servidor MCP local no seu Mac. Conecte um assistente compatível com MCP, como Claude Code, Claude Desktop, Cursor ou outro cliente, e deixe que ele crie projetos, edite linhas, organize formas, importe capturas, traduza textos, renderize prévias do canvas e exporte as imagens finais. O MCP é opcional, fica desativado por padrão, aceita apenas conexões locais e é protegido por um token de acesso.

Mantenha variações de lançamento, substituições por idioma, planos de linhas por loja e materiais prontos para exportar em um único projeto — para a App Store, sites, redes sociais e campanhas de lançamento.

Principais recursos:

- Crie capturas para a App Store a partir de um único projeto
- Use modelos prontos ou layouts personalizados para lançamentos recorrentes
- Desenhe linhas com várias capturas, layouts comparativos e campanhas completas
- Importe capturas em lote para as linhas e troque imagens rapidamente
- Adicione molduras de iPhone, iPad, Mac e layouts abstratos
- Trabalhe com texto, formas, imagens, gradientes, fundos em mosaico e gráficos SVG
- Edite texto rico com fontes personalizadas, variantes de fonte, espaçamento, alinhamento e tamanho
- Ajuste posição, encaixe, camadas, recorte e rotação direto no canvas
- Gerencie textos e imagens específicos de cada idioma para cada mercado
- Use predefinições de idioma, traduza automaticamente o texto que falta e acompanhe o progresso
- Exporte capturas em PNG ou JPEG em pastas por idioma e por linha
- Crie exportações de vitrine para redes sociais, sites e prévias de campanha
- Envie capturas direto para o App Store Connect
- Revise e edite os metadados do App Store Connect antes do envio
- Mantenha os projetos locais por padrão, sincronize com o iCloud quando quiser e faça backups em ZIP
- Sem rastreamento

O Screenshot Bro foi feito para desenvolvedores indie, times de produto, designers e profissionais de marketing que precisam de mais controle do que um gerador básico de capturas e de um fluxo mais rápido do que refazer cada imagem de marketing à mão.

Se você precisa de um criador de capturas para a App Store, um construtor de modelos de captura, uma ferramenta de localização de capturas, um app para enviar imagens ao App Store Connect ou uma automação de capturas com MCP, o Screenshot Bro reúne todo o fluxo em um único app focado para Mac.

Termos de Uso (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["pt-BR"] = """\
O Screenshot Bro é um criador e editor de capturas de tela feito sob medida para as capturas da App Store. Crie modelos reutilizáveis, monte conjuntos completos de capturas, localize a sua mensagem e exporte ou envie imagens de loja impecáveis.

Ao contrário das ferramentas de design genéricas, o Screenshot Bro entende linhas específicas por dispositivo, localização, envios para o App Store Connect, exportações em lote e projetos reutilizáveis.

Monte conjuntos completos de capturas para iPhone, iPad e Mac. Comece por um modelo ou crie o seu próprio sistema de layout. Solte as capturas, adicione molduras de dispositivos ou composições sem moldura, escreva títulos e legendas, estilize texto rico com fontes personalizadas e ajuste cada detalhe no canvas.

Mantenha variações de lançamento, substituições por idioma, planos de linhas por loja e materiais prontos para exportar em um único projeto — para a App Store, sites, redes sociais e campanhas de lançamento.

Principais recursos:

- Crie capturas para a App Store a partir de um único projeto
- Use modelos prontos ou layouts personalizados para lançamentos recorrentes
- Desenhe linhas com várias capturas, layouts comparativos e campanhas completas
- Importe capturas em lote para as linhas e troque imagens rapidamente
- Adicione molduras de iPhone, iPad, Mac e layouts abstratos
- Trabalhe com texto, formas, imagens, gradientes, fundos em mosaico e gráficos SVG
- Edite texto rico com fontes personalizadas, variantes de fonte, espaçamento, alinhamento e tamanho
- Ajuste posição, encaixe, camadas, recorte e rotação direto no canvas
- Gerencie textos e imagens específicos de cada idioma para cada mercado
- Use predefinições de idioma, traduza automaticamente o texto que falta e acompanhe o progresso
- Exporte capturas em PNG ou JPEG em pastas por idioma e por linha
- Crie exportações de vitrine para redes sociais, sites e prévias de campanha
- Envie capturas direto para o App Store Connect
- Revise e edite os metadados do App Store Connect antes do envio
- Receba notificações quando as exportações e os envios para as lojas terminarem
- Mantenha os projetos locais por padrão, sincronize com o iCloud quando quiser e faça backups em ZIP
- Sem rastreamento

O Screenshot Bro foi feito para desenvolvedores indie, times de produto, designers e profissionais de marketing que precisam de mais controle do que um gerador básico de capturas e de um fluxo mais rápido do que refazer cada imagem de marketing à mão.

Seja para um primeiro lançamento, uma grande atualização, uma campanha sazonal ou uma rodada de localização, o Screenshot Bro ajuda você a sair das capturas brutas e chegar a imagens de marketing prontas para a loja com mais rapidez e consistência.

Se você precisa de um criador de capturas para a App Store, um construtor de modelos de captura, uma ferramenta de localização de capturas ou um app para enviar imagens ao App Store Connect, o Screenshot Bro reúne todo o fluxo em um único app focado.

Termos de Uso (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["ru"] = """\
Screenshot Bro — генератор скриншотов приложений для App Store. Соберите полный набор скриншотов один раз, добавьте рамки устройств, локализуйте каждый заголовок под каждый рынок, куда вы выпускаете приложение, и загрузите всё прямо в App Store Connect, не покидая Mac.

В отличие от универсальных графических редакторов, Screenshot Bro понимает ряды под конкретные устройства, локализацию, загрузку в App Store Connect, пакетный экспорт, переиспользуемые проекты и локальную автоматизацию через ИИ-ассистента по Model Context Protocol.

Собирайте полные наборы скриншотов для iPhone, iPad и Mac. Начните с шаблона или создайте собственную систему макетов. Добавляйте скриншоты, рамки устройств или композиции без рамок, пишите заголовки и подписи, оформляйте текст своими шрифтами и доводите каждую деталь на холсте.

Screenshot Bro умеет поднимать локальный MCP-сервер на вашем Mac. Подключите совместимого с MCP ассистента — Claude Code, Claude Desktop, Cursor или любой другой клиент — и он создаст проекты, отредактирует ряды, расставит фигуры, импортирует скриншоты, переведёт текст, отрисует превью холста и экспортирует финальные изображения. MCP включается по желанию, по умолчанию выключен, работает только на локальном интерфейсе и защищён токеном доступа.

Держите варианты релизов, переопределения для отдельных языков, планы рядов под каждый магазин и готовые к экспорту материалы в одном проекте — для App Store, сайтов, соцсетей и запусков.

Основные возможности:

- Создавайте скриншоты для App Store в одном проекте
- Используйте встроенные шаблоны или свои макеты для регулярных релизов
- Проектируйте ряды из нескольких кадров, сравнительные макеты и целые кампании
- Импортируйте скриншоты в ряды пакетом и быстро заменяйте изображения
- Добавляйте рамки устройств для iPhone, iPad, Mac и абстрактные макеты
- Работайте с текстом, фигурами, изображениями, градиентами, плиточными фонами и SVG-графикой
- Оформляйте текст своими шрифтами, начертаниями, интервалами, выравниванием и размерами
- Меняйте положение, привязку, порядок слоёв, обрезку и поворот прямо на холсте
- Управляйте текстом и изображениями отдельно для каждого языка и рынка
- Берите готовые наборы языков, автоматически переводите недостающий текст и следите за прогрессом
- Экспортируйте PNG или JPEG в папки по языкам и рядам
- Делайте витринный экспорт для соцсетей, сайтов и превью кампаний
- Загружайте скриншоты напрямую в App Store Connect
- Просматривайте и правьте метаданные App Store Connect перед загрузкой
- Храните проекты локально, синхронизируйте с iCloud по желанию и делайте резервные копии в ZIP
- Никакой слежки

Screenshot Bro сделан для инди-разработчиков, продуктовых команд, дизайнеров и маркетологов, которым нужно больше контроля, чем даёт простой генератор скриншотов, и процесс быстрее, чем собирать каждую маркетинговую картинку вручную.

Если вам нужен конструктор скриншотов для App Store, редактор шаблонов, инструмент локализации скриншотов, загрузчик в App Store Connect или автоматизация скриншотов через MCP — Screenshot Bro собирает весь процесс в одном приложении для Mac.

Условия использования (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["ru"] = """\
Screenshot Bro — редактор и конструктор скриншотов, сделанный специально для скриншотов App Store. Создавайте переиспользуемые шаблоны, собирайте полные наборы скриншотов, локализуйте текст и экспортируйте или загружайте готовые материалы для магазинов.

В отличие от универсальных графических редакторов, Screenshot Bro понимает ряды под конкретные устройства, локализацию, загрузку в App Store Connect, пакетный экспорт и переиспользуемые проекты.

Собирайте полные наборы скриншотов для iPhone, iPad и Mac. Начните с шаблона или создайте собственную систему макетов. Добавляйте скриншоты, рамки устройств или композиции без рамок, пишите заголовки и подписи, оформляйте текст своими шрифтами и доводите каждую деталь на холсте.

Держите варианты релизов, переопределения для отдельных языков, планы рядов под каждый магазин и готовые к экспорту материалы в одном проекте — для App Store, сайтов, соцсетей и запусков.

Основные возможности:

- Создавайте скриншоты для App Store в одном проекте
- Используйте встроенные шаблоны или свои макеты для регулярных релизов
- Проектируйте ряды из нескольких кадров, сравнительные макеты и целые кампании
- Импортируйте скриншоты в ряды пакетом и быстро заменяйте изображения
- Добавляйте рамки устройств для iPhone, iPad, Mac и абстрактные макеты
- Работайте с текстом, фигурами, изображениями, градиентами, плиточными фонами и SVG-графикой
- Оформляйте текст своими шрифтами, начертаниями, интервалами, выравниванием и размерами
- Меняйте положение, привязку, порядок слоёв, обрезку и поворот прямо на холсте
- Управляйте текстом и изображениями отдельно для каждого языка и рынка
- Берите готовые наборы языков, автоматически переводите недостающий текст и следите за прогрессом
- Экспортируйте PNG или JPEG в папки по языкам и рядам
- Делайте витринный экспорт для соцсетей, сайтов и превью кампаний
- Загружайте скриншоты напрямую в App Store Connect
- Просматривайте и правьте метаданные App Store Connect перед загрузкой
- Получайте уведомления о завершении экспорта и загрузки в магазины
- Храните проекты локально, синхронизируйте с iCloud по желанию и делайте резервные копии в ZIP
- Никакой слежки

Screenshot Bro сделан для инди-разработчиков, продуктовых команд, дизайнеров и маркетологов, которым нужно больше контроля, чем даёт простой генератор скриншотов, и процесс быстрее, чем собирать каждую маркетинговую картинку вручную.

Готовите первый релиз, крупное обновление, сезонную кампанию или выход на новые языки — Screenshot Bro поможет быстрее и аккуратнее превратить сырые скриншоты в готовые для магазина изображения.

Если вам нужен конструктор скриншотов для App Store, редактор шаблонов, инструмент локализации скриншотов или загрузчик в App Store Connect — Screenshot Bro собирает весь процесс в одном приложении.

Условия использования (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["uk"] = """\
Screenshot Bro — застосунок для створення знімків екрана до App Store. Складіть повний набір знімків один раз, додайте рамки пристроїв, перекладіть кожен заголовок для кожного ринку, де ви публікуєте застосунок, і завантажте все просто в App Store Connect — не виходячи з Mac.

На відміну від універсальних графічних редакторів, Screenshot Bro розуміє рядки під конкретні пристрої, локалізацію, завантаження в App Store Connect, пакетний експорт, проєкти для повторного використання та локальну автоматизацію ШІ-асистентом через Model Context Protocol.

Складайте повні набори знімків для iPhone, iPad і Mac. Почніть із шаблона або створіть власну систему макетів. Додавайте знімки, рамки пристроїв чи композиції без рамок, пишіть заголовки та підписи, оформлюйте текст власними шрифтами й доводьте кожну деталь на полотні.

Screenshot Bro може підняти локальний сервер MCP на вашому Mac. Підключіть сумісного з MCP асистента — Claude Code, Claude Desktop, Cursor або інший клієнт — і він створить проєкти, відредагує рядки, розставить фігури, імпортує знімки, перекладе текст, покаже попередній вигляд полотна й експортує готові зображення. MCP вмикається за бажанням, типово вимкнений, працює лише на локальному інтерфейсі та захищений токеном доступу.

Тримайте варіанти релізів, окремі тексти для кожної мови, плани рядків під кожен магазин і готові до експорту матеріали в одному проєкті — для App Store, сайтів, соцмереж і запусків.

Основні можливості:

- Створюйте знімки для App Store в одному проєкті
- Використовуйте вбудовані шаблони або власні макети для регулярних релізів
- Проєктуйте рядки з кількох кадрів, порівняльні макети й цілі кампанії
- Імпортуйте знімки в рядки пакетом і швидко замінюйте зображення
- Додавайте рамки пристроїв для iPhone, iPad, Mac і абстрактні макети
- Працюйте з текстом, фігурами, зображеннями, градієнтами, мозаїчними тлами та графікою SVG
- Оформлюйте текст власними шрифтами, їхніми варіантами, інтервалами, вирівнюванням і розмірами
- Змінюйте розташування, прив’язку, порядок шарів, обрізання та поворот просто на полотні
- Керуйте текстом і зображеннями окремо для кожної мови та ринку
- Беріть готові набори мов, автоматично перекладайте відсутній текст і стежте за прогресом
- Експортуйте PNG або JPEG у теки за мовами та рядками
- Робіть вітринний експорт для соцмереж, сайтів і прев’ю кампаній
- Завантажуйте знімки напряму в App Store Connect
- Переглядайте й редагуйте метадані App Store Connect перед завантаженням
- Тримайте проєкти локально, синхронізуйте з iCloud за бажанням і робіть резервні копії у ZIP
- Жодного відстеження

Screenshot Bro створений для інді-розробників, продуктових команд, дизайнерів і маркетологів, яким потрібно більше контролю, ніж дає простий генератор знімків, і робочий процес швидший, ніж збирати кожне маркетингове зображення вручну.

Якщо вам потрібен конструктор знімків для App Store, редактор шаблонів, інструмент локалізації знімків, завантажувач до App Store Connect або автоматизація знімків через MCP — Screenshot Bro збирає весь процес в одному застосунку для Mac.

Умови використання (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["uk"] = """\
Screenshot Bro — редактор і конструктор знімків екрана, створений саме для знімків App Store. Робіть шаблони для повторного використання, складайте повні набори знімків, перекладайте свої тексти та експортуйте чи завантажуйте готові матеріали для магазинів.

На відміну від універсальних графічних редакторів, Screenshot Bro розуміє рядки під конкретні пристрої, локалізацію, завантаження в App Store Connect, пакетний експорт і проєкти для повторного використання.

Складайте повні набори знімків для iPhone, iPad і Mac. Почніть із шаблона або створіть власну систему макетів. Додавайте знімки, рамки пристроїв чи композиції без рамок, пишіть заголовки та підписи, оформлюйте текст власними шрифтами й доводьте кожну деталь на полотні.

Тримайте варіанти релізів, окремі тексти для кожної мови, плани рядків під кожен магазин і готові до експорту матеріали в одному проєкті — для App Store, сайтів, соцмереж і запусків.

Основні можливості:

- Створюйте знімки для App Store в одному проєкті
- Використовуйте вбудовані шаблони або власні макети для регулярних релізів
- Проєктуйте рядки з кількох кадрів, порівняльні макети й цілі кампанії
- Імпортуйте знімки в рядки пакетом і швидко замінюйте зображення
- Додавайте рамки пристроїв для iPhone, iPad, Mac і абстрактні макети
- Працюйте з текстом, фігурами, зображеннями, градієнтами, мозаїчними тлами та графікою SVG
- Оформлюйте текст власними шрифтами, їхніми варіантами, інтервалами, вирівнюванням і розмірами
- Змінюйте розташування, прив’язку, порядок шарів, обрізання та поворот просто на полотні
- Керуйте текстом і зображеннями окремо для кожної мови та ринку
- Беріть готові набори мов, автоматично перекладайте відсутній текст і стежте за прогресом
- Експортуйте PNG або JPEG у теки за мовами та рядками
- Робіть вітринний експорт для соцмереж, сайтів і прев’ю кампаній
- Завантажуйте знімки напряму в App Store Connect
- Переглядайте й редагуйте метадані App Store Connect перед завантаженням
- Отримуйте повідомлення про завершення експорту та завантаження в магазини
- Тримайте проєкти локально, синхронізуйте з iCloud за бажанням і робіть резервні копії у ZIP
- Жодного відстеження

Screenshot Bro створений для інді-розробників, продуктових команд, дизайнерів і маркетологів, яким потрібно більше контролю, ніж дає простий генератор знімків, і робочий процес швидший, ніж збирати кожне маркетингове зображення вручну.

Готуєте перший реліз, велике оновлення, сезонну кампанію чи вихід на нові мови — Screenshot Bro допоможе швидше й узгодженіше перетворити сирі знімки на готові для магазину зображення.

Якщо вам потрібен конструктор знімків для App Store, редактор шаблонів, інструмент локалізації знімків або завантажувач до App Store Connect — Screenshot Bro збирає весь процес в одному застосунку.

Умови використання (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["pl"] = """\
Screenshot Bro to generator zrzutów ekranu dla App Store. Zaprojektuj cały zestaw zrzutów raz, dodaj ramki urządzeń, przetłumacz każdy nagłówek na każdy rynek, na którym wydajesz aplikację, i wyślij wszystko prosto do App Store Connect — bez wychodzenia z Maca.

W przeciwieństwie do uniwersalnych narzędzi graficznych Screenshot Bro rozumie wiersze przypisane do konkretnych urządzeń, lokalizację, wysyłkę do App Store Connect, eksport wsadowy, projekty do wielokrotnego użytku i lokalną automatyzację asystentem AI przez Model Context Protocol.

Twórz kompletne zestawy zrzutów dla iPhone'a, iPada i Maca. Zacznij od szablonu albo zbuduj własny system układów. Wrzuć zrzuty, dodaj ramki urządzeń lub kompozycje bez ramek, napisz nagłówki i podpisy, sformatuj tekst własnymi czcionkami i dopracuj każdy szczegół na obszarze roboczym.

Screenshot Bro może uruchomić lokalny serwer MCP na Twoim Macu. Podłącz asystenta zgodnego z MCP — Claude Code, Claude Desktop, Cursor lub innego klienta — i pozwól mu tworzyć projekty, edytować wiersze, rozmieszczać kształty, importować zrzuty, tłumaczyć teksty, renderować podglądy obszaru roboczego i eksportować gotowe obrazy. MCP jest opcjonalny, domyślnie wyłączony, działa tylko lokalnie i jest chroniony tokenem dostępu.

Trzymaj warianty wydań, teksty przypisane do poszczególnych języków, plany wierszy pod konkretne sklepy i gotowe do eksportu materiały w jednym projekcie — dla App Store, stron internetowych, mediów społecznościowych i kampanii premierowych.

Najważniejsze funkcje:

- Twórz zrzuty do App Store z jednego projektu
- Korzystaj z wbudowanych szablonów lub własnych układów przy kolejnych premierach
- Projektuj wiersze z wielu kadrów, układy porównawcze i całe kampanie
- Importuj zrzuty do wierszy wsadowo i szybko podmieniaj obrazy
- Dodawaj ramki urządzeń dla iPhone, iPad, Mac i układy abstrakcyjne
- Pracuj z tekstem, kształtami, obrazami, gradientami, kafelkowymi tłami i grafiką SVG
- Formatuj tekst własnymi czcionkami, odmianami, odstępami, wyrównaniem i rozmiarem
- Zmieniaj położenie, przyciąganie, kolejność warstw, przycinanie i obrót wprost na obszarze roboczym
- Zarządzaj tekstami i obrazami osobno dla każdego języka i rynku
- Używaj gotowych zestawów języków, tłumacz brakujący tekst automatycznie i śledź postęp
- Eksportuj PNG lub JPEG do folderów według języka i wiersza
- Twórz eksporty prezentacyjne do mediów społecznościowych, stron i podglądów kampanii
- Wysyłaj zrzuty bezpośrednio do App Store Connect
- Przejrzyj i popraw metadane App Store Connect przed wysyłką
- Trzymaj projekty lokalnie, synchronizuj z iCloud, gdy chcesz, i twórz kopie ZIP
- Bez śledzenia

Screenshot Bro powstał dla niezależnych twórców, zespołów produktowych, projektantów i marketerów, którzy potrzebują większej kontroli niż w prostym generatorze zrzutów i szybszej pracy niż składanie każdego obrazu marketingowego od zera.

Jeśli szukasz kreatora zrzutów do App Store, kreatora szablonów zrzutów, narzędzia do lokalizacji zrzutów, narzędzia do wysyłania obrazów do App Store Connect albo automatyzacji zrzutów przez MCP — Screenshot Bro zbiera cały proces w jednej aplikacji na Maca.

Warunki korzystania (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["pl"] = """\
Screenshot Bro to kreator i edytor zrzutów ekranu zbudowany specjalnie pod zrzuty do App Store. Twórz szablony do wielokrotnego użytku, projektuj kompletne zestawy zrzutów, tłumacz swój komunikat i eksportuj lub wysyłaj dopracowane materiały do sklepów.

W przeciwieństwie do uniwersalnych narzędzi graficznych Screenshot Bro rozumie wiersze przypisane do konkretnych urządzeń, lokalizację, wysyłkę do App Store Connect, eksport wsadowy i projekty do wielokrotnego użytku.

Twórz kompletne zestawy zrzutów dla iPhone'a, iPada i Maca. Zacznij od szablonu albo zbuduj własny system układów. Wrzuć zrzuty, dodaj ramki urządzeń lub kompozycje bez ramek, napisz nagłówki i podpisy, sformatuj tekst własnymi czcionkami i dopracuj każdy szczegół na obszarze roboczym.

Trzymaj warianty wydań, teksty przypisane do poszczególnych języków, plany wierszy pod konkretne sklepy i gotowe do eksportu materiały w jednym projekcie — dla App Store, stron internetowych, mediów społecznościowych i kampanii premierowych.

Najważniejsze funkcje:

- Twórz zrzuty do App Store z jednego projektu
- Korzystaj z wbudowanych szablonów lub własnych układów przy kolejnych premierach
- Projektuj wiersze z wielu kadrów, układy porównawcze i całe kampanie
- Importuj zrzuty do wierszy wsadowo i szybko podmieniaj obrazy
- Dodawaj ramki urządzeń dla iPhone, iPad, Mac i układy abstrakcyjne
- Pracuj z tekstem, kształtami, obrazami, gradientami, kafelkowymi tłami i grafiką SVG
- Formatuj tekst własnymi czcionkami, odmianami, odstępami, wyrównaniem i rozmiarem
- Zmieniaj położenie, przyciąganie, kolejność warstw, przycinanie i obrót wprost na obszarze roboczym
- Zarządzaj tekstami i obrazami osobno dla każdego języka i rynku
- Używaj gotowych zestawów języków, tłumacz brakujący tekst automatycznie i śledź postęp
- Eksportuj PNG lub JPEG do folderów według języka i wiersza
- Twórz eksporty prezentacyjne do mediów społecznościowych, stron i podglądów kampanii
- Wysyłaj zrzuty bezpośrednio do App Store Connect
- Przejrzyj i popraw metadane App Store Connect przed wysyłką
- Odbieraj powiadomienia o zakończonym eksporcie i wysyłce do sklepów
- Trzymaj projekty lokalnie, synchronizuj z iCloud, gdy chcesz, i twórz kopie ZIP
- Bez śledzenia

Screenshot Bro powstał dla niezależnych twórców, zespołów produktowych, projektantów i marketerów, którzy potrzebują większej kontroli niż w prostym generatorze zrzutów i szybszej pracy niż składanie każdego obrazu marketingowego od zera.

Niezależnie od tego, czy przygotowujesz pierwszą premierę, dużą aktualizację, kampanię sezonową czy wejście na nowe języki, Screenshot Bro pomaga szybciej i spójniej przejść od surowych zrzutów do materiałów gotowych do sklepu.

Jeśli szukasz kreatora zrzutów do App Store, kreatora szablonów zrzutów, narzędzia do lokalizacji zrzutów albo narzędzia do wysyłania obrazów do App Store Connect — Screenshot Bro zbiera cały proces w jednej skupionej aplikacji.

Warunki korzystania (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["tr"] = """\
Screenshot Bro, App Store için bir uygulama ekran görüntüsü üreticisidir. Ekran görüntüsü setinizin tamamını bir kez tasarlayın, cihaz çerçeveleri ekleyin, her başlığı yayın yaptığınız her pazar için yerelleştirin ve hepsini doğrudan App Store Connect'e yükleyin — Mac'inizden çıkmadan.

Genel amaçlı tasarım araçlarının aksine Screenshot Bro cihaza özel satırları, yerelleştirmeyi, App Store Connect yüklemelerini, toplu dışa aktarmayı, yeniden kullanılabilir projeleri ve Model Context Protocol üzerinden yerel yapay zekâ asistanı otomasyonunu bilir.

iPhone, iPad ve Mac düzenleri için eksiksiz ekran görüntüsü setleri hazırlayın. Bir şablonla başlayın ya da kendi düzen sisteminizi kurun. Ekran görüntülerini bırakın, cihaz çerçeveleri veya çerçevesiz kompozisyonlar ekleyin, başlıklar ve açıklamalar yazın, zengin metni özel yazı tipleriyle biçimlendirin ve her ayrıntıyı tuval üzerinde ince ayarlayın.

Screenshot Bro, Mac'inizde yerel bir MCP sunucusu çalıştırabilir. Claude Code, Claude Desktop, Cursor gibi MCP uyumlu bir asistanı ya da başka bir istemciyi bağlayın; projeler oluştursun, satırları düzenlesin, şekilleri yerleştirsin, ekran görüntüleri içe aktarsın, metinleri çevirsin, tuval önizlemeleri üretsin ve son görselleri dışa aktarsın. MCP isteğe bağlıdır, varsayılan olarak kapalıdır, yalnızca yerel bağlantıları kabul eder ve bir erişim jetonuyla korunur.

Sürüm varyantlarını, dile özel metinleri, mağazaya özel satır planlarını ve dışa aktarmaya hazır görselleri tek bir projede tutun — App Store, web siteleri, sosyal medya ve lansman kampanyaları için.

Öne çıkan özellikler:

- App Store ekran görüntülerini tek projeden oluşturun
- Tekrarlayan lansmanlar için hazır şablonları veya kendi düzenlerinizi kullanın
- Çok kareli satırlar, karşılaştırma düzenleri ve eksiksiz kampanyalar tasarlayın
- Ekran görüntülerini satırlara toplu içe aktarın ve görselleri hızla değiştirin
- iPhone, iPad, Mac ve soyut düzenler için cihaz çerçeveleri ekleyin
- Metin, şekil, görsel, gradyan, döşemeli arka plan ve SVG grafiklerle çalışın
- Zengin metni özel yazı tipleri, yazı tipi varyantları, boşluk, hizalama ve boyutla düzenleyin
- Konum, yapışma, katman sırası, kırpma ve döndürmeyi doğrudan tuvalde ayarlayın
- Her pazar için dile özel metin ve görsel değişikliklerini yönetin
- Hazır dil setlerini kullanın, eksik metni otomatik çevirin ve çeviri durumunu izleyin
- PNG veya JPEG ekran görüntülerini dile ve satıra göre klasörlere aktarın
- Sosyal medya, web siteleri ve kampanya önizlemeleri için vitrin görselleri üretin
- Ekran görüntülerini doğrudan App Store Connect'e yükleyin
- Yüklemeden önce App Store Connect üst verilerini gözden geçirip düzenleyin
- Projeleri varsayılan olarak yerelde tutun, isterseniz iCloud ile eşitleyin ve ZIP yedekleri alın
- İzleme yok

Screenshot Bro; basit bir ekran görüntüsü üreticisinden daha fazla denetim ve her pazarlama görselini elle yeniden hazırlamaktan daha hızlı bir akış isteyen bağımsız geliştiriciler, ürün ekipleri, tasarımcılar ve pazarlamacılar için yapıldı.

App Store ekran görüntüsü hazırlama aracı, ekran görüntüsü şablon düzenleyici, ekran görüntüsü yerelleştirme aracı, App Store Connect yükleyici ya da MCP ile ekran görüntüsü otomasyonu arıyorsanız Screenshot Bro tüm akışı tek bir odaklı Mac uygulamasında toplar.

Kullanım Koşulları (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["tr"] = """\
Screenshot Bro, özellikle App Store ekran görüntüleri için yapılmış bir ekran görüntüsü hazırlama ve düzenleme uygulamasıdır. Yeniden kullanılabilir şablonlar oluşturun, eksiksiz ekran görüntüsü setleri tasarlayın, mesajınızı yerelleştirin ve özenli mağaza görsellerini dışa aktarın ya da yükleyin.

Genel amaçlı tasarım araçlarının aksine Screenshot Bro cihaza özel satırları, yerelleştirmeyi, App Store Connect yüklemelerini, toplu dışa aktarmayı ve yeniden kullanılabilir projeleri bilir.

iPhone, iPad ve Mac düzenleri için eksiksiz ekran görüntüsü setleri hazırlayın. Bir şablonla başlayın ya da kendi düzen sisteminizi kurun. Ekran görüntülerini bırakın, cihaz çerçeveleri veya çerçevesiz kompozisyonlar ekleyin, başlıklar ve açıklamalar yazın, zengin metni özel yazı tipleriyle biçimlendirin ve her ayrıntıyı tuval üzerinde ince ayarlayın.

Sürüm varyantlarını, dile özel metinleri, mağazaya özel satır planlarını ve dışa aktarmaya hazır görselleri tek bir projede tutun — App Store, web siteleri, sosyal medya ve lansman kampanyaları için.

Öne çıkan özellikler:

- App Store ekran görüntülerini tek projeden oluşturun
- Tekrarlayan lansmanlar için hazır şablonları veya kendi düzenlerinizi kullanın
- Çok kareli satırlar, karşılaştırma düzenleri ve eksiksiz kampanyalar tasarlayın
- Ekran görüntülerini satırlara toplu içe aktarın ve görselleri hızla değiştirin
- iPhone, iPad, Mac ve soyut düzenler için cihaz çerçeveleri ekleyin
- Metin, şekil, görsel, gradyan, döşemeli arka plan ve SVG grafiklerle çalışın
- Zengin metni özel yazı tipleri, yazı tipi varyantları, boşluk, hizalama ve boyutla düzenleyin
- Konum, yapışma, katman sırası, kırpma ve döndürmeyi doğrudan tuvalde ayarlayın
- Her pazar için dile özel metin ve görsel değişikliklerini yönetin
- Hazır dil setlerini kullanın, eksik metni otomatik çevirin ve çeviri durumunu izleyin
- PNG veya JPEG ekran görüntülerini dile ve satıra göre klasörlere aktarın
- Sosyal medya, web siteleri ve kampanya önizlemeleri için vitrin görselleri üretin
- Ekran görüntülerini doğrudan App Store Connect'e yükleyin
- Yüklemeden önce App Store Connect üst verilerini gözden geçirip düzenleyin
- Dışa aktarma ve mağaza yüklemeleri bittiğinde bildirim alın
- Projeleri varsayılan olarak yerelde tutun, isterseniz iCloud ile eşitleyin ve ZIP yedekleri alın
- İzleme yok

Screenshot Bro; basit bir ekran görüntüsü üreticisinden daha fazla denetim ve her pazarlama görselini elle yeniden hazırlamaktan daha hızlı bir akış isteyen bağımsız geliştiriciler, ürün ekipleri, tasarımcılar ve pazarlamacılar için yapıldı.

İlk lansmana, büyük bir güncellemeye, sezonluk bir kampanyaya ya da yeni dillere açılmaya hazırlanıyor olun; Screenshot Bro ham ekran görüntülerinden mağazaya hazır pazarlama görsellerine daha hızlı ve daha tutarlı geçmenizi sağlar.

App Store ekran görüntüsü hazırlama aracı, ekran görüntüsü şablon düzenleyici, ekran görüntüsü yerelleştirme aracı ya da App Store Connect yükleyici arıyorsanız Screenshot Bro tüm akışı tek bir odaklı uygulamada toplar.

Kullanım Koşulları (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["id"] = """\
Screenshot Bro adalah pembuat screenshot aplikasi untuk App Store. Rancang satu set screenshot lengkap sekali saja, tambahkan bingkai perangkat, lokalkan setiap headline ke setiap pasar yang kamu tuju, dan unggah langsung ke App Store Connect — tanpa meninggalkan Mac.

Berbeda dari alat desain umum, Screenshot Bro memahami baris khusus per perangkat, pelokalan, unggahan ke App Store Connect, ekspor massal, proyek yang bisa dipakai ulang, dan otomatisasi asisten AI lokal melalui Model Context Protocol.

Bangun set screenshot lengkap untuk iPhone, iPad, dan Mac. Mulai dari templat atau buat sistem tata letak sendiri. Masukkan screenshot, tambahkan bingkai perangkat atau komposisi tanpa bingkai, tulis headline dan keterangan, atur gaya teks dengan font kustom, dan sempurnakan setiap detail di kanvas.

Screenshot Bro bisa menjalankan server MCP lokal di Mac kamu. Hubungkan asisten yang kompatibel dengan MCP seperti Claude Code, Claude Desktop, Cursor, atau klien lain, lalu biarkan asisten itu membuat proyek, mengedit baris, menata bentuk, mengimpor screenshot, menerjemahkan teks, merender pratinjau kanvas, dan mengekspor gambar akhir. MCP bersifat opsional, mati secara bawaan, hanya menerima koneksi lokal, dan dilindungi token akses.

Simpan varian rilis, teks khusus per bahasa, rencana baris khusus per toko, dan aset siap ekspor dalam satu proyek — untuk App Store, situs web, media sosial, dan kampanye peluncuran.

Fitur utama:

- Buat screenshot App Store dari satu proyek
- Pakai templat bawaan atau tata letak sendiri untuk peluncuran berikutnya
- Rancang baris multi-gambar, tata letak perbandingan, dan kampanye lengkap
- Impor screenshot ke baris secara massal dan ganti gambar dengan cepat
- Tambahkan bingkai perangkat untuk iPhone, iPad, Mac, dan tata letak abstrak
- Olah teks, bentuk, gambar, gradien, latar bermotif ubin, dan grafik SVG
- Edit teks kaya dengan font kustom, varian font, spasi, perataan, dan ukuran
- Atur posisi, snapping, urutan lapisan, pemotongan, dan rotasi langsung di kanvas
- Kelola teks dan gambar khusus per bahasa untuk setiap pasar
- Pakai preset bahasa, terjemahkan teks yang kosong secara otomatis, dan pantau progresnya
- Ekspor screenshot PNG atau JPEG ke folder per bahasa dan per baris
- Buat ekspor showcase untuk media sosial, situs web, dan pratinjau kampanye
- Unggah screenshot langsung ke App Store Connect
- Tinjau dan sunting metadata App Store Connect sebelum mengunggah
- Simpan proyek secara lokal, sinkronkan lewat iCloud bila perlu, dan buat backup ZIP
- Tanpa pelacakan

Screenshot Bro dibuat untuk developer indie, tim produk, desainer, dan marketer yang butuh kendali lebih besar daripada pembuat screenshot biasa dan alur kerja yang lebih cepat daripada menyusun ulang setiap gambar promosi secara manual.

Kalau kamu mencari pembuat screenshot App Store, penyusun templat screenshot, alat pelokalan screenshot, pengunggah ke App Store Connect, atau otomatisasi screenshot lewat MCP, Screenshot Bro menyatukan seluruh alur kerja dalam satu aplikasi Mac yang fokus.

Ketentuan Penggunaan (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["id"] = """\
Screenshot Bro adalah pembuat dan editor screenshot yang dirancang khusus untuk screenshot App Store. Buat templat yang bisa dipakai ulang, rancang set screenshot lengkap, lokalkan pesanmu, lalu ekspor atau unggah materi toko yang rapi.

Berbeda dari alat desain umum, Screenshot Bro memahami baris khusus per perangkat, pelokalan, unggahan ke App Store Connect, ekspor massal, dan proyek yang bisa dipakai ulang.

Bangun set screenshot lengkap untuk iPhone, iPad, dan Mac. Mulai dari templat atau buat sistem tata letak sendiri. Masukkan screenshot, tambahkan bingkai perangkat atau komposisi tanpa bingkai, tulis headline dan keterangan, atur gaya teks dengan font kustom, dan sempurnakan setiap detail di kanvas.

Simpan varian rilis, teks khusus per bahasa, rencana baris khusus per toko, dan aset siap ekspor dalam satu proyek — untuk App Store, situs web, media sosial, dan kampanye peluncuran.

Fitur utama:

- Buat screenshot App Store dari satu proyek
- Pakai templat bawaan atau tata letak sendiri untuk peluncuran berikutnya
- Rancang baris multi-gambar, tata letak perbandingan, dan kampanye lengkap
- Impor screenshot ke baris secara massal dan ganti gambar dengan cepat
- Tambahkan bingkai perangkat untuk iPhone, iPad, Mac, dan tata letak abstrak
- Olah teks, bentuk, gambar, gradien, latar bermotif ubin, dan grafik SVG
- Edit teks kaya dengan font kustom, varian font, spasi, perataan, dan ukuran
- Atur posisi, snapping, urutan lapisan, pemotongan, dan rotasi langsung di kanvas
- Kelola teks dan gambar khusus per bahasa untuk setiap pasar
- Pakai preset bahasa, terjemahkan teks yang kosong secara otomatis, dan pantau progresnya
- Ekspor screenshot PNG atau JPEG ke folder per bahasa dan per baris
- Buat ekspor showcase untuk media sosial, situs web, dan pratinjau kampanye
- Unggah screenshot langsung ke App Store Connect
- Tinjau dan sunting metadata App Store Connect sebelum mengunggah
- Dapatkan notifikasi saat ekspor dan unggahan ke toko selesai
- Simpan proyek secara lokal, sinkronkan lewat iCloud bila perlu, dan buat backup ZIP
- Tanpa pelacakan

Screenshot Bro dibuat untuk developer indie, tim produk, desainer, dan marketer yang butuh kendali lebih besar daripada pembuat screenshot biasa dan alur kerja yang lebih cepat daripada menyusun ulang setiap gambar promosi secara manual.

Baik kamu sedang menyiapkan peluncuran pertama, pembaruan besar, kampanye musiman, atau perluasan ke bahasa baru, Screenshot Bro membantumu berpindah dari screenshot mentah ke materi promosi siap toko lebih cepat dan lebih konsisten.

Kalau kamu mencari pembuat screenshot App Store, penyusun templat screenshot, alat pelokalan screenshot, atau pengunggah ke App Store Connect, Screenshot Bro menyatukan seluruh alur kerja dalam satu aplikasi yang fokus.

Ketentuan Penggunaan (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["vi"] = """\
Screenshot Bro là công cụ tạo ảnh chụp màn hình ứng dụng cho App Store. Thiết kế trọn bộ ảnh chụp một lần, thêm khung thiết bị, bản địa hóa từng tiêu đề cho mọi thị trường bạn phát hành, rồi tải thẳng lên App Store Connect — ngay trên máy Mac.

Khác với các công cụ thiết kế đa dụng, Screenshot Bro hiểu các hàng dành riêng cho từng thiết bị, việc bản địa hóa, tải lên App Store Connect, xuất theo lô, dự án dùng lại được và tự động hóa bằng trợ lý AI cục bộ qua Model Context Protocol.

Tạo trọn bộ ảnh chụp cho iPhone, iPad và Mac. Bắt đầu từ mẫu có sẵn hoặc tự xây hệ thống bố cục riêng. Kéo ảnh chụp vào, thêm khung thiết bị hoặc dựng ảnh không khung, viết tiêu đề và chú thích, tạo kiểu chữ với phông tùy chỉnh và chỉnh từng chi tiết ngay trên canvas.

Screenshot Bro có thể chạy một máy chủ MCP cục bộ trên máy Mac của bạn. Kết nối trợ lý tương thích MCP như Claude Code, Claude Desktop, Cursor hoặc ứng dụng khác, rồi để nó tạo dự án, sửa hàng, sắp xếp hình khối, nhập ảnh chụp, dịch văn bản, kết xuất bản xem trước canvas và xuất ảnh cuối. MCP là tùy chọn, mặc định tắt, chỉ nhận kết nối cục bộ và được bảo vệ bằng token truy cập.

Giữ các biến thể bản phát hành, phần chữ riêng theo từng ngôn ngữ, bố cục hàng riêng cho từng cửa hàng và tài nguyên sẵn sàng xuất trong cùng một dự án — cho App Store, website, mạng xã hội và các chiến dịch ra mắt.

Tính năng chính:

- Tạo ảnh chụp cho App Store từ một dự án
- Dùng mẫu có sẵn hoặc bố cục riêng cho những lần phát hành sau
- Thiết kế hàng nhiều ảnh, bố cục so sánh và trọn chiến dịch
- Nhập ảnh chụp vào hàng theo lô và thay ảnh thật nhanh
- Thêm khung thiết bị cho iPhone, iPad, Mac và bố cục trừu tượng
- Làm việc với văn bản, hình khối, ảnh, gradient, nền lát gạch và đồ họa SVG
- Chỉnh văn bản với phông tùy chỉnh, biến thể phông, khoảng cách, căn lề và cỡ chữ
- Điều chỉnh vị trí, bám dính, thứ tự lớp, cắt ảnh và xoay ngay trên canvas
- Quản lý chữ và ảnh riêng theo từng ngôn ngữ cho mỗi thị trường
- Dùng bộ ngôn ngữ sẵn có, tự động dịch phần chữ còn thiếu và theo dõi tiến độ
- Xuất ảnh PNG hoặc JPEG vào thư mục theo ngôn ngữ và theo hàng
- Tạo ảnh giới thiệu cho mạng xã hội, website và bản xem trước chiến dịch
- Tải ảnh chụp trực tiếp lên App Store Connect
- Xem lại và sửa thông tin App Store Connect trước khi tải lên
- Mặc định lưu dự án ngay trên máy, đồng bộ iCloud khi bạn muốn và tạo bản sao lưu ZIP
- Không theo dõi

Screenshot Bro dành cho nhà phát triển độc lập, đội ngũ sản phẩm, nhà thiết kế và người làm marketing — những người cần nhiều quyền kiểm soát hơn một công cụ tạo ảnh chụp cơ bản và một quy trình nhanh hơn việc dựng lại từng ảnh quảng bá bằng tay.

Nếu bạn cần công cụ tạo ảnh chụp cho App Store, công cụ dựng mẫu ảnh chụp, công cụ bản địa hóa ảnh chụp, công cụ tải ảnh lên App Store Connect hay công cụ tự động hóa ảnh chụp qua MCP, Screenshot Bro gom toàn bộ quy trình vào một ứng dụng Mac duy nhất.

Điều khoản sử dụng (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["vi"] = """\
Screenshot Bro là ứng dụng tạo và chỉnh ảnh chụp màn hình, làm riêng cho ảnh chụp trên App Store. Tạo mẫu dùng lại được, thiết kế trọn bộ ảnh chụp, bản địa hóa thông điệp của bạn, rồi xuất hoặc tải lên những ảnh quảng bá gọn gàng cho cửa hàng.

Khác với các công cụ thiết kế đa dụng, Screenshot Bro hiểu các hàng dành riêng cho từng thiết bị, việc bản địa hóa, tải lên App Store Connect, xuất theo lô và dự án dùng lại được.

Tạo trọn bộ ảnh chụp cho iPhone, iPad và Mac. Bắt đầu từ mẫu có sẵn hoặc tự xây hệ thống bố cục riêng. Kéo ảnh chụp vào, thêm khung thiết bị hoặc dựng ảnh không khung, viết tiêu đề và chú thích, tạo kiểu chữ với phông tùy chỉnh và chỉnh từng chi tiết ngay trên canvas.

Giữ các biến thể bản phát hành, phần chữ riêng theo từng ngôn ngữ, bố cục hàng riêng cho từng cửa hàng và tài nguyên sẵn sàng xuất trong cùng một dự án — cho App Store, website, mạng xã hội và các chiến dịch ra mắt.

Tính năng chính:

- Tạo ảnh chụp cho App Store từ một dự án
- Dùng mẫu có sẵn hoặc bố cục riêng cho những lần phát hành sau
- Thiết kế hàng nhiều ảnh, bố cục so sánh và trọn chiến dịch
- Nhập ảnh chụp vào hàng theo lô và thay ảnh thật nhanh
- Thêm khung thiết bị cho iPhone, iPad, Mac và bố cục trừu tượng
- Làm việc với văn bản, hình khối, ảnh, gradient, nền lát gạch và đồ họa SVG
- Chỉnh văn bản với phông tùy chỉnh, biến thể phông, khoảng cách, căn lề và cỡ chữ
- Điều chỉnh vị trí, bám dính, thứ tự lớp, cắt ảnh và xoay ngay trên canvas
- Quản lý chữ và ảnh riêng theo từng ngôn ngữ cho mỗi thị trường
- Dùng bộ ngôn ngữ sẵn có, tự động dịch phần chữ còn thiếu và theo dõi tiến độ
- Xuất ảnh PNG hoặc JPEG vào thư mục theo ngôn ngữ và theo hàng
- Tạo ảnh giới thiệu cho mạng xã hội, website và bản xem trước chiến dịch
- Tải ảnh chụp trực tiếp lên App Store Connect
- Xem lại và sửa thông tin App Store Connect trước khi tải lên
- Nhận thông báo khi xuất ảnh và tải lên cửa hàng hoàn tất
- Mặc định lưu dự án ngay trên máy, đồng bộ iCloud khi bạn muốn và tạo bản sao lưu ZIP
- Không theo dõi

Screenshot Bro dành cho nhà phát triển độc lập, đội ngũ sản phẩm, nhà thiết kế và người làm marketing — những người cần nhiều quyền kiểm soát hơn một công cụ tạo ảnh chụp cơ bản và một quy trình nhanh hơn việc dựng lại từng ảnh quảng bá bằng tay.

Dù bạn đang chuẩn bị lần ra mắt đầu tiên, một bản cập nhật lớn, một chiến dịch theo mùa hay mở rộng sang ngôn ngữ mới, Screenshot Bro giúp bạn đi từ ảnh chụp thô đến ảnh quảng bá sẵn sàng lên cửa hàng nhanh hơn và nhất quán hơn.

Nếu bạn cần công cụ tạo ảnh chụp cho App Store, công cụ dựng mẫu ảnh chụp, công cụ bản địa hóa ảnh chụp hay công cụ tải ảnh lên App Store Connect, Screenshot Bro gom toàn bộ quy trình vào một ứng dụng duy nhất.

Điều khoản sử dụng (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["th"] = """\
Screenshot Bro คือแอปสร้างภาพหน้าจอสำหรับ App Store ออกแบบชุดภาพหน้าจอทั้งชุดในครั้งเดียว เพิ่มกรอบอุปกรณ์ แปลทุกหัวข้อให้ทุกตลาดที่คุณวางจำหน่าย แล้วอัปโหลดตรงไปยัง App Store Connect ได้เลยจากเครื่อง Mac

ต่างจากเครื่องมือออกแบบทั่วไป Screenshot Bro เข้าใจแถวที่แยกตามอุปกรณ์ การแปลหลายภาษา การอัปโหลดขึ้น App Store Connect การส่งออกเป็นชุด โปรเจกต์ที่นำกลับมาใช้ซ้ำได้ และการสั่งงานด้วยผู้ช่วย AI ในเครื่องผ่าน Model Context Protocol

สร้างชุดภาพหน้าจอครบชุดสำหรับ iPhone, iPad และ Mac เริ่มจากเทมเพลตหรือสร้างระบบเลย์เอาต์ของคุณเอง วางภาพหน้าจอลงไป เพิ่มกรอบอุปกรณ์หรือจัดองค์ประกอบแบบไม่มีกรอบ เขียนหัวข้อและคำบรรยาย จัดรูปแบบข้อความด้วยฟอนต์ของคุณเอง และปรับทุกรายละเอียดบนพื้นที่ทำงาน

Screenshot Bro เปิดเซิร์ฟเวอร์ MCP ในเครื่อง Mac ของคุณได้ เชื่อมต่อผู้ช่วยที่รองรับ MCP เช่น Claude Code, Claude Desktop, Cursor หรือไคลเอนต์อื่น แล้วให้มันสร้างโปรเจกต์ แก้ไขแถว จัดวางรูปทรง นำเข้าภาพหน้าจอ แปลข้อความ เรนเดอร์ตัวอย่างพื้นที่ทำงาน และส่งออกภาพสุดท้าย MCP เป็นตัวเลือกเสริม ปิดอยู่ตามค่าเริ่มต้น รับเฉพาะการเชื่อมต่อในเครื่อง และป้องกันด้วยโทเคนการเข้าถึง

เก็บเวอร์ชันของแต่ละรอบอัปเดต ข้อความเฉพาะของแต่ละภาษา แผนแถวของแต่ละสโตร์ และไฟล์ที่พร้อมส่งออก ไว้ในโปรเจกต์เดียว สำหรับ App Store, เว็บไซต์, โซเชียลมีเดีย และแคมเปญเปิดตัว

ฟีเจอร์หลัก:

- สร้างภาพหน้าจอสำหรับ App Store จากโปรเจกต์เดียว
- ใช้เทมเพลตที่มีให้หรือเลย์เอาต์ของคุณเองสำหรับการปล่อยอัปเดตครั้งถัดไป
- ออกแบบแถวหลายภาพ เลย์เอาต์เปรียบเทียบ และแคมเปญทั้งชุด
- นำเข้าภาพหน้าจอเข้าแถวเป็นชุดและเปลี่ยนรูปได้อย่างรวดเร็ว
- เพิ่มกรอบอุปกรณ์สำหรับ iPhone, iPad, Mac และเลย์เอาต์แบบนามธรรม
- ทำงานกับข้อความ รูปทรง รูปภาพ เกรเดียนต์ พื้นหลังแบบเรียงต่อ และกราฟิก SVG
- แก้ไขข้อความด้วยฟอนต์ของคุณเอง น้ำหนักฟอนต์ ระยะห่าง การจัดแนว และขนาด
- ปรับตำแหน่ง การดูดเข้าแนว ลำดับเลเยอร์ การครอบตัด และการหมุน ได้บนพื้นที่ทำงานโดยตรง
- จัดการข้อความและรูปภาพเฉพาะของแต่ละภาษาสำหรับทุกตลาด
- ใช้ชุดภาษาสำเร็จ แปลข้อความที่ยังว่างอัตโนมัติ และติดตามความคืบหน้าของการแปล
- ส่งออกภาพ PNG หรือ JPEG ลงโฟลเดอร์แยกตามภาษาและตามแถว
- สร้างภาพโปรโมตสำหรับโพสต์โซเชียล เว็บไซต์ และตัวอย่างแคมเปญ
- อัปโหลดภาพหน้าจอตรงไปยัง App Store Connect
- ตรวจและแก้เมทาดาทาของ App Store Connect ก่อนอัปโหลด
- เก็บโปรเจกต์ไว้ในเครื่องตามค่าเริ่มต้น ซิงก์ผ่าน iCloud เมื่อต้องการ และสำรองข้อมูลเป็น ZIP
- ไม่มีการติดตามผู้ใช้

Screenshot Bro ทำมาเพื่อนักพัฒนาอินดี ทีมผลิตภัณฑ์ นักออกแบบ และนักการตลาด ที่ต้องการควบคุมได้มากกว่าเครื่องมือสร้างภาพหน้าจอทั่ว ๆ ไป และต้องการขั้นตอนทำงานที่เร็วกว่าการทำภาพโปรโมตใหม่ทีละภาพด้วยมือ

หากคุณกำลังหาเครื่องมือสร้างภาพหน้าจอสำหรับ App Store เครื่องมือสร้างเทมเพลตภาพหน้าจอ เครื่องมือแปลภาพหน้าจอ เครื่องมืออัปโหลดขึ้น App Store Connect หรือการสั่งงานภาพหน้าจออัตโนมัติผ่าน MCP — Screenshot Bro รวมทุกขั้นตอนไว้ในแอป Mac เพียงแอปเดียว

ข้อกำหนดการใช้งาน (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["th"] = """\
Screenshot Bro คือแอปสร้างและแก้ไขภาพหน้าจอที่ทำขึ้นเพื่อภาพหน้าจอของ App Store โดยเฉพาะ สร้างเทมเพลตที่นำกลับมาใช้ซ้ำได้ ออกแบบชุดภาพหน้าจอครบชุด แปลข้อความของคุณ แล้วส่งออกหรืออัปโหลดภาพโปรโมตที่พร้อมขึ้นสโตร์

ต่างจากเครื่องมือออกแบบทั่วไป Screenshot Bro เข้าใจแถวที่แยกตามอุปกรณ์ การแปลหลายภาษา การอัปโหลดขึ้น App Store Connect การส่งออกเป็นชุด และโปรเจกต์ที่นำกลับมาใช้ซ้ำได้

สร้างชุดภาพหน้าจอครบชุดสำหรับ iPhone, iPad และ Mac เริ่มจากเทมเพลตหรือสร้างระบบเลย์เอาต์ของคุณเอง วางภาพหน้าจอลงไป เพิ่มกรอบอุปกรณ์หรือจัดองค์ประกอบแบบไม่มีกรอบ เขียนหัวข้อและคำบรรยาย จัดรูปแบบข้อความด้วยฟอนต์ของคุณเอง และปรับทุกรายละเอียดบนพื้นที่ทำงาน

เก็บเวอร์ชันของแต่ละรอบอัปเดต ข้อความเฉพาะของแต่ละภาษา แผนแถวของแต่ละสโตร์ และไฟล์ที่พร้อมส่งออก ไว้ในโปรเจกต์เดียว สำหรับ App Store, เว็บไซต์, โซเชียลมีเดีย และแคมเปญเปิดตัว

ฟีเจอร์หลัก:

- สร้างภาพหน้าจอสำหรับ App Store จากโปรเจกต์เดียว
- ใช้เทมเพลตที่มีให้หรือเลย์เอาต์ของคุณเองสำหรับการปล่อยอัปเดตครั้งถัดไป
- ออกแบบแถวหลายภาพ เลย์เอาต์เปรียบเทียบ และแคมเปญทั้งชุด
- นำเข้าภาพหน้าจอเข้าแถวเป็นชุดและเปลี่ยนรูปได้อย่างรวดเร็ว
- เพิ่มกรอบอุปกรณ์สำหรับ iPhone, iPad, Mac และเลย์เอาต์แบบนามธรรม
- ทำงานกับข้อความ รูปทรง รูปภาพ เกรเดียนต์ พื้นหลังแบบเรียงต่อ และกราฟิก SVG
- แก้ไขข้อความด้วยฟอนต์ของคุณเอง น้ำหนักฟอนต์ ระยะห่าง การจัดแนว และขนาด
- ปรับตำแหน่ง การดูดเข้าแนว ลำดับเลเยอร์ การครอบตัด และการหมุน ได้บนพื้นที่ทำงานโดยตรง
- จัดการข้อความและรูปภาพเฉพาะของแต่ละภาษาสำหรับทุกตลาด
- ใช้ชุดภาษาสำเร็จ แปลข้อความที่ยังว่างอัตโนมัติ และติดตามความคืบหน้าของการแปล
- ส่งออกภาพ PNG หรือ JPEG ลงโฟลเดอร์แยกตามภาษาและตามแถว
- สร้างภาพโปรโมตสำหรับโพสต์โซเชียล เว็บไซต์ และตัวอย่างแคมเปญ
- อัปโหลดภาพหน้าจอตรงไปยัง App Store Connect
- ตรวจและแก้เมทาดาทาของ App Store Connect ก่อนอัปโหลด
- รับการแจ้งเตือนเมื่อส่งออกและอัปโหลดขึ้นสโตร์เสร็จ
- เก็บโปรเจกต์ไว้ในเครื่องตามค่าเริ่มต้น ซิงก์ผ่าน iCloud เมื่อต้องการ และสำรองข้อมูลเป็น ZIP
- ไม่มีการติดตามผู้ใช้

Screenshot Bro ทำมาเพื่อนักพัฒนาอินดี ทีมผลิตภัณฑ์ นักออกแบบ และนักการตลาด ที่ต้องการควบคุมได้มากกว่าเครื่องมือสร้างภาพหน้าจอทั่ว ๆ ไป และต้องการขั้นตอนทำงานที่เร็วกว่าการทำภาพโปรโมตใหม่ทีละภาพด้วยมือ

ไม่ว่าคุณจะเตรียมเปิดตัวครั้งแรก อัปเดตใหญ่ แคมเปญตามฤดูกาล หรือขยายไปยังภาษาใหม่ Screenshot Bro ก็ช่วยให้คุณเปลี่ยนภาพหน้าจอดิบให้เป็นภาพโปรโมตที่พร้อมขึ้นสโตร์ได้เร็วขึ้นและสม่ำเสมอขึ้น

หากคุณกำลังหาเครื่องมือสร้างภาพหน้าจอสำหรับ App Store เครื่องมือสร้างเทมเพลตภาพหน้าจอ เครื่องมือแปลภาพหน้าจอ หรือเครื่องมืออัปโหลดขึ้น App Store Connect — Screenshot Bro รวมทุกขั้นตอนไว้ในแอปเพียงแอปเดียว

ข้อกำหนดการใช้งาน (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["zh-Hant"] = """\
Screenshot Bro 是專為 App Store 打造的 App 截圖產生器。一次設計完整的截圖組，加上裝置外框，把每一句文案在地化到你要上架的每個市場，並直接從 Mac 上傳至 App Store Connect。

與一般的通用設計工具不同，Screenshot Bro 懂得依裝置區分的行、在地化、App Store Connect 上傳、批次匯出、可重複使用的專案，以及透過 Model Context Protocol 實現的本機 AI 助理自動化。

為 iPhone、iPad 與 Mac 版面打造完整的截圖組。你可以從範本開始，或建立自己的版面系統。放入截圖，加上裝置外框或無外框的構圖，撰寫標題與說明文字，用自訂字型設定豐富文字樣式，並在畫布上微調每一個細節。

Screenshot Bro 可以在你的 Mac 上執行本機 MCP 伺服器。連接支援 MCP 的助理，例如 Claude Code、Claude Desktop、Cursor 或其他用戶端，讓它建立專案、編輯行、排列圖形、匯入截圖、翻譯文字、產生畫布預覽並匯出最終圖片。MCP 是選用功能，預設關閉，僅接受本機連線，並以存取權杖保護。

把發布版本、各語言的個別文案、各商店的行規劃，以及可直接匯出的素材，全部放在同一個專案裡，供 App Store、網站、社群媒體與上線宣傳使用。

主要功能：

- 在同一個專案中製作 App Store 截圖
- 使用內建範本或自訂版面，從容應對每一次發布
- 設計多圖的行、比較式版面與完整宣傳素材
- 批次把截圖匯入各行，並快速替換圖片
- 為 iPhone、iPad、Mac 及抽象版面加上裝置外框
- 處理文字、圖形、圖片、漸層、拼貼背景與 SVG 圖形
- 編輯豐富文字，支援自訂字型、字型變體、間距、對齊與大小控制
- 直接在畫布上調整位置、吸附、圖層、裁切與旋轉
- 為每個市場管理各語言專屬的文字與圖片替換
- 使用語言預設組合、自動翻譯缺少的文字，並追蹤翻譯進度
- 依語言與行，把截圖匯出成 PNG 或 JPEG 並分資料夾整理
- 為社群貼文、網站與宣傳預覽建立展示用匯出
- 將截圖直接上傳至 App Store Connect
- 上傳前檢視並編輯 App Store Connect 中繼資料
- 在同一個流程中把 iOS 與 Mac 截圖上傳至 App Store Connect
- 連接支援 MCP 的助理，在本機驅動 Screenshot Bro
- 匯出與商店上傳完成時收到通知
- 專案預設留在本機，需要時可透過 iCloud 同步，並可建立 ZIP 備份
- 在 Finder 中開啟專案儲存位置與匯出資料夾
- 不追蹤使用者

Screenshot Bro 專為獨立開發者、產品團隊、設計師與行銷人員打造——他們需要比基本截圖產生器更多的掌控，也需要比手工重做每一張 App 行銷圖更快的流程。

無論你要準備首次上線、重大更新、季節性宣傳，還是在地化擴展，Screenshot Bro 都能幫你更快、更一致地把原始截圖變成可直接上架的行銷圖。

如果你需要 App Store 截圖製作工具、截圖範本編輯器、截圖在地化工具、App Store Connect 上傳工具，或支援 MCP 的截圖自動化工具，Screenshot Bro 會把整個流程集中在一款專注的 Mac App 裡。

使用條款（EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["zh-Hant"] = """\
Screenshot Bro 是一款專為 App Store 截圖打造的截圖製作與編輯工具。建立可重複使用的範本，設計完整的截圖組，把文案在地化，並匯出或上傳精緻的商店宣傳素材。

與一般的通用設計工具不同，Screenshot Bro 懂得依裝置區分的行、在地化、App Store Connect 上傳、批次匯出，以及可重複使用的專案。

為 iPhone、iPad 與 Mac 版面打造完整的截圖組。你可以從範本開始，或建立自己的版面系統。放入截圖，加上裝置外框或無外框的構圖，撰寫標題與說明文字，用自訂字型設定豐富文字樣式，並在畫布上微調每一個細節。

把發布版本、各語言的個別文案、各商店的行規劃，以及可直接匯出的素材，全部放在同一個專案裡，供 App Store、網站、社群媒體與上線宣傳使用。

主要功能：

- 在同一個專案中製作 App Store 截圖
- 使用內建範本或自訂版面，從容應對每一次發布
- 設計多圖的行、比較式版面與完整宣傳素材
- 批次把截圖匯入各行，並快速替換圖片
- 為 iPhone、iPad、Mac 及抽象版面加上裝置外框
- 處理文字、圖形、圖片、漸層、拼貼背景與 SVG 圖形
- 編輯豐富文字，支援自訂字型、字型變體、間距、對齊與大小控制
- 直接在畫布上調整位置、吸附、圖層、裁切與旋轉
- 為每個市場管理各語言專屬的文字與圖片替換
- 使用語言預設組合、自動翻譯缺少的文字，並追蹤翻譯進度
- 依語言與行，把截圖匯出成 PNG 或 JPEG 並分資料夾整理
- 為社群貼文、網站與宣傳預覽建立展示用匯出
- 將截圖直接上傳至 App Store Connect
- 上傳前檢視並編輯 App Store Connect 中繼資料
- 匯出與商店上傳完成時收到通知
- 專案預設留在本機，需要時可透過 iCloud 同步，並可建立 ZIP 備份
- 不追蹤使用者

Screenshot Bro 專為獨立開發者、產品團隊、設計師與行銷人員打造——他們需要比基本截圖產生器更多的掌控，也需要比手工重做每一張 App 行銷圖更快的流程。

無論你要準備首次上線、重大更新、季節性宣傳，還是在地化擴展，Screenshot Bro 都能幫你更快、更一致地把原始截圖變成可直接上架的行銷圖。

如果你需要 App Store 截圖製作工具、截圖範本編輯器、截圖在地化工具或 App Store Connect 上傳工具，Screenshot Bro 會把整個流程集中在一款專注的 App 裡。

使用條款（EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""


# ---- added 2026-09-09 (RESEARCH.md Finding 5) ----
DESC_MAC["es-MX"] = """\
Screenshot Bro es un generador de capturas de pantalla para la App Store. Diseña un set completo una sola vez, agrega marcos de dispositivo, localiza cada titular para todos los mercados donde publicas y súbelo directo a App Store Connect, sin salir de tu Mac.

A diferencia de las herramientas de diseño genéricas, Screenshot Bro entiende de filas por dispositivo, localización, cargas a App Store Connect, exportaciones por lotes, proyectos reutilizables y automatización local con asistentes de IA mediante el Model Context Protocol.

Arma sets completos de capturas para iPhone, iPad y Mac. Empieza con una plantilla o crea tu propio sistema de composición. Suelta tus capturas, agrega marcos de dispositivo o composiciones sin marco, escribe titulares y textos de apoyo, aplica estilos de texto enriquecido con fuentes propias y ajusta cada detalle en el lienzo.

Screenshot Bro puede alojar un servidor MCP local en tu Mac. Conecta un asistente compatible con MCP, como Claude Code, Claude Desktop, Cursor u otro cliente, y déjalo crear proyectos, editar filas, acomodar figuras, importar capturas, traducir textos, generar vistas previas del lienzo y exportar las imágenes finales. MCP es opcional, viene desactivado, funciona solo en loopback y está protegido con un token de acceso.

Mantén en un solo proyecto las variantes de cada versión, los ajustes por idioma, los planes de filas por tienda y los recursos listos para exportar: para la App Store, sitios web, redes sociales y campañas de lanzamiento.

Funciones principales:

- Crea capturas para la App Store desde un solo proyecto
- Usa plantillas incluidas o diseños propios para lanzamientos recurrentes
- Diseña filas de varias capturas, comparativas y campañas completas
- Importa capturas por lotes en las filas y reemplaza imágenes al instante
- Agrega marcos de dispositivo para iPhone, iPad, Mac y diseños abstractos
- Trabaja con texto, figuras, imágenes, degradados, fondos en mosaico y gráficos SVG
- Edita texto enriquecido con fuentes propias, variantes, espaciado, alineación y tamaño
- Ajusta posición, imantado, capas, recorte y rotación directo en el lienzo
- Administra textos e imágenes propios de cada idioma para cada mercado
- Usa preajustes de idioma, traduce automáticamente lo que falte y sigue el avance
- Exporta capturas en PNG o JPEG a carpetas por idioma y por fila
- Crea exportaciones de escaparate para redes sociales, sitios web y vistas previas de campaña
- Sube capturas directo a App Store Connect
- Revisa y edita los metadatos de App Store Connect antes de subirlos
- Sube capturas de iOS y de Mac a App Store Connect en un mismo flujo
- Conecta un asistente compatible con MCP para controlar Screenshot Bro en tu equipo
- Recibe notificaciones al terminar las exportaciones y las cargas a la tienda
- Guarda los proyectos en tu computadora, sincroniza con iCloud cuando lo actives y crea respaldos ZIP
- Abre en el Finder las carpetas de proyectos y de exportación
- Sin rastreo

Screenshot Bro está hecho para desarrolladores indie, equipos de producto, diseñadores y responsables de marketing que necesitan más control que un generador básico y un flujo más rápido que rehacer a mano cada imagen promocional.

Ya sea que prepares un primer lanzamiento, una actualización mayor, una campaña de temporada o la salida a nuevos idiomas, Screenshot Bro te lleva de las capturas en bruto a imágenes listas para la tienda con más rapidez y consistencia.

Si buscas un creador de capturas para la App Store, un editor de plantillas, una herramienta para localizar capturas, un cargador de App Store Connect o una automatización lista para MCP, Screenshot Bro reúne todo el flujo en una sola app de Mac.

Términos de uso (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["es-MX"] = """\
Screenshot Bro es un creador y editor de capturas de pantalla hecho específicamente para las capturas de la App Store. Crea plantillas reutilizables, diseña sets completos, localiza tu mensaje y exporta o sube material listo para la tienda.

A diferencia de las herramientas de diseño genéricas, Screenshot Bro entiende de filas por dispositivo, localización, cargas a App Store Connect, exportaciones por lotes y proyectos reutilizables.

Arma sets completos de capturas para iPhone, iPad y Mac. Empieza con una plantilla o crea tu propio sistema de composición. Suelta tus capturas, agrega marcos de dispositivo o composiciones sin marco, escribe titulares y textos de apoyo, aplica estilos de texto enriquecido con fuentes propias y ajusta cada detalle en el lienzo.

Mantén en un solo proyecto las variantes de cada versión, los ajustes por idioma, los planes de filas por tienda y los recursos listos para exportar: para la App Store, sitios web, redes sociales y campañas de lanzamiento.

Funciones principales:

- Crea capturas para la App Store desde un solo proyecto
- Usa plantillas incluidas o diseños propios para lanzamientos recurrentes
- Diseña filas de varias capturas, comparativas y campañas completas
- Importa capturas por lotes en las filas y reemplaza imágenes al instante
- Agrega marcos de dispositivo para iPhone, iPad, Mac y diseños abstractos
- Trabaja con texto, figuras, imágenes, degradados, fondos en mosaico y gráficos SVG
- Edita texto enriquecido con fuentes propias, variantes, espaciado, alineación y tamaño
- Ajusta posición, imantado, capas, recorte y rotación directo en el lienzo
- Administra textos e imágenes propios de cada idioma para cada mercado
- Usa preajustes de idioma, traduce automáticamente lo que falte y sigue el avance
- Exporta capturas en PNG o JPEG a carpetas por idioma y por fila
- Crea exportaciones de escaparate para redes sociales, sitios web y vistas previas de campaña
- Sube capturas directo a App Store Connect
- Revisa y edita los metadatos de App Store Connect antes de subirlos
- Recibe notificaciones al terminar las exportaciones y las cargas a la tienda
- Guarda los proyectos en tu equipo, sincroniza con iCloud cuando lo actives y crea respaldos ZIP
- Sin rastreo

Screenshot Bro está hecho para desarrolladores indie, equipos de producto, diseñadores y responsables de marketing que necesitan más control que un generador básico y un flujo más rápido que rehacer a mano cada imagen promocional.

Ya sea que prepares un primer lanzamiento, una actualización mayor, una campaña de temporada o la salida a nuevos idiomas, Screenshot Bro te lleva de las capturas en bruto a imágenes listas para la tienda con más rapidez y consistencia.

Si buscas un creador de capturas para la App Store, un editor de plantillas, una herramienta para localizar capturas o un cargador de App Store Connect, Screenshot Bro reúne todo el flujo en una sola app enfocada.

Términos de uso (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["fr-CA"] = """\
Screenshot Bro génère les captures d'écran de votre app pour l'App Store. Concevez la série complète une fois, ajoutez les cadres d'appareils, adaptez chaque titre à chaque marché visé, puis téléversez dans App Store Connect — sans quitter votre Mac.

Contrairement aux outils de conception génériques, Screenshot Bro connaît les rangées par appareil, la localisation, le téléversement vers App Store Connect, les exportations par lots, les projets réutilisables et l'automatisation locale par assistant IA via le Model Context Protocol.

Montez des séries complètes pour iPhone, iPad et Mac. Partez d'un modèle ou créez votre propre système. Déposez vos captures, ajoutez des cadres d'appareils ou des compositions sans cadre, rédigez titres et légendes, mettez en forme le texte enrichi avec vos polices et peaufinez chaque détail sur le canevas.

Screenshot Bro peut héberger un serveur MCP local sur votre Mac. Branchez un assistant compatible MCP — Claude Code, Claude Desktop, Cursor ou un autre client — et laissez-le créer des projets, modifier des rangées, disposer des formes, importer des captures, traduire du texte, générer des aperçus du canevas et exporter les images finales. MCP est optionnel, désactivé par défaut, limité au bouclage local et protégé par un jeton d'accès.

Regroupez dans un même projet vos variantes de version, vos remplacements par langue, vos plans de rangées par boutique et vos fichiers prêts à exporter, pour l'App Store, vos sites web, les réseaux sociaux et vos campagnes de lancement.

Fonctions principales :

- Produisez toutes vos captures d'écran App Store à partir d'un seul projet
- Utilisez les modèles intégrés ou vos propres mises en page pour vos lancements récurrents
- Importez vos captures par lots dans les rangées et remplacez les images en un geste
- Ajoutez des cadres d'appareils pour iPhone, iPad, Mac et des mises en page abstraites
- Travaillez avec du texte, des formes, des images, des dégradés, des arrière-plans en mosaïque et des graphiques SVG
- Modifiez le texte enrichi avec vos polices, leurs variantes, l'espacement, l'alignement et la taille
- Gérez les remplacements de texte et d'images propres à chaque marché
- Utilisez les préréglages de langues, traduisez automatiquement le texte manquant et suivez l'avancement
- Exportez vos captures en PNG ou en JPEG dans des dossiers classés par langue et par rangée
- Créez des exportations vitrines pour les réseaux sociaux, les sites web et les aperçus de campagne
- Téléversez vos captures d'écran directement dans App Store Connect
- Révisez et modifiez les métadonnées App Store Connect avant le téléversement
- Branchez un assistant compatible MCP pour piloter Screenshot Bro en local
- Recevez un avis à la fin de vos exportations et de vos téléversements
- Gardez vos projets en local par défaut, synchronisez-les avec iCloud au besoin et créez des sauvegardes ZIP
- Aucun suivi

Screenshot Bro s'adresse aux développeurs indépendants, aux équipes produit, aux designers et aux spécialistes du marketing qui veulent plus de contrôle qu'un générateur de base et un flux de travail plus rapide que de refaire à la main chaque image promotionnelle.

Pour un premier lancement, une mise à jour majeure, une campagne saisonnière ou un déploiement multilingue, Screenshot Bro vous fait passer des captures brutes à des images prêtes pour la boutique, plus vite et avec plus de cohérence.

Si vous cherchez un créateur de captures d'écran App Store, un générateur de modèles, un outil de localisation de captures, un utilitaire de téléversement vers App Store Connect ou un outil d'automatisation compatible MCP, Screenshot Bro réunit tout le flux de travail dans une seule app Mac.

Conditions d'utilisation (CLUF) : https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["fr-CA"] = """\
Screenshot Bro est un créateur et un éditeur de captures d'écran conçu spécialement pour l'App Store. Créez des modèles réutilisables, montez des séries complètes, adaptez votre message à chaque langue, puis exportez ou téléversez des visuels de boutique soignés.

Contrairement aux outils de conception génériques, Screenshot Bro connaît les rangées par appareil, la localisation, le téléversement vers App Store Connect, les exportations par lots et les projets réutilisables.

Montez des séries complètes pour iPhone, iPad et Mac. Partez d'un modèle ou créez votre propre système. Déposez vos captures, ajoutez des cadres d'appareils ou des compositions sans cadre, rédigez titres et légendes, mettez en forme le texte enrichi avec vos polices et peaufinez chaque détail sur le canevas.

Regroupez dans un même projet vos variantes de version, vos remplacements par langue, vos plans de rangées par boutique et vos fichiers prêts à exporter, pour l'App Store, vos sites web, les réseaux sociaux et vos campagnes de lancement.

Fonctions principales :

- Produisez toutes vos captures d'écran App Store à partir d'un seul projet
- Utilisez les modèles intégrés ou vos propres mises en page pour vos lancements récurrents
- Concevez des rangées à plusieurs images, des mises en page comparatives et des campagnes complètes
- Importez vos captures par lots dans les rangées et remplacez les images en un geste
- Ajoutez des cadres d'appareils pour iPhone, iPad, Mac et des mises en page abstraites
- Travaillez avec du texte, des formes, des images, des dégradés, des arrière-plans en mosaïque et des graphiques SVG
- Modifiez le texte enrichi avec vos polices, leurs variantes, l'espacement, l'alignement et la taille
- Ajustez le positionnement, l'aimantation, la superposition, le rognage et la rotation à même le canevas
- Gérez les remplacements de texte et d'images propres à chaque marché
- Utilisez les préréglages de langues, traduisez automatiquement le texte manquant et suivez l'avancement
- Exportez vos captures en PNG ou en JPEG dans des dossiers classés par langue et par rangée
- Créez des exportations vitrines pour les réseaux sociaux, les sites web et les aperçus de campagne
- Téléversez vos captures d'écran directement dans App Store Connect
- Révisez et modifiez les métadonnées App Store Connect avant le téléversement
- Recevez un avis à la fin de vos exportations et de vos téléversements
- Gardez vos projets en local par défaut, synchronisez-les avec iCloud au besoin et créez des sauvegardes ZIP
- Aucun suivi

Screenshot Bro s'adresse aux développeurs indépendants, aux équipes produit, aux designers et aux spécialistes du marketing qui veulent plus de contrôle qu'un générateur de base et un flux de travail plus rapide que de refaire à la main chaque image promotionnelle.

Pour un premier lancement, une mise à jour majeure, une campagne saisonnière ou un déploiement multilingue, Screenshot Bro vous fait passer des captures brutes à des images prêtes pour la boutique, plus vite et avec plus de cohérence.

Si vous cherchez un créateur de captures d'écran App Store, un générateur de modèles, un outil de localisation de captures ou un utilitaire de téléversement vers App Store Connect, Screenshot Bro réunit tout le flux de travail dans une seule app ciblée.

Conditions d'utilisation (CLUF) : https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["cs"] = """\
Screenshot Bro je generátor snímků obrazovky aplikací pro App Store. Navrhněte kompletní sadu snímků jednou, přidejte rámečky zařízení, lokalizujte každý titulek do všech trhů, kam vydáváte, a nahrajte je rovnou do App Store Connect — aniž byste opustili Mac.

Na rozdíl od univerzálních designových nástrojů Screenshot Bro rozumí řadám podle zařízení, lokalizaci, nahrávání do App Store Connect, dávkovým exportům, opakovaně použitelným projektům i lokální automatizaci pomocí AI asistenta přes Model Context Protocol.

Vytvářejte kompletní sady snímků obrazovky pro iPhone, iPad a Mac. Začněte šablonou, nebo si postavte vlastní systém rozvržení. Vložte snímky obrazovky, přidejte rámečky zařízení nebo kompozice bez rámečků, napište titulky a popisky, upravte styl formátovaného textu vlastními písmy a doladěte každý detail přímo na plátně.

Screenshot Bro umí na vašem Macu hostovat lokální MCP server. Připojte asistenta kompatibilního s MCP — třeba Claude Code, Claude Desktop, Cursor nebo jiného klienta — a nechte ho zakládat projekty, upravovat řady, uspořádávat objekty, importovat snímky obrazovky, překládat texty, vykreslovat náhledy plátna a exportovat finální obrázky. Funkce MCP je volitelná, ve výchozím stavu vypnutá, omezená na místní smyčku a chráněná přístupovým tokenem.

Držte varianty vydání, přepisy pro jednotlivé jazykové verze, plány řad pro konkrétní obchody a hotové podklady v jednom projektu — pro App Store, weby, sociální sítě i kampaně k uvedení.

Klíčové funkce:

- Vytvářejte snímky obrazovky pro App Store z jednoho projektu
- Používejte vestavěné šablony nebo vlastní rozvržení pro opakovaná vydání
- Navrhujte řady s více snímky, srovnávací rozvržení i celé kampaně
- Hromadně importujte snímky obrazovky do řad a rychle nahrazujte obrázky
- Přidávejte rámečky zařízení pro iPhone, iPad, Mac i abstraktní rozvržení
- Pracujte s textem, tvary, obrázky, přechody, dlážděnými pozadími a SVG grafikou
- Upravujte formátovaný text vlastními písmy, řezy, proložením, zarovnáním a velikostí
- Upravujte umístění, přichytávání, vrstvení, oříznutí i otočení přímo na plátně
- Spravujte jazykově specifické texty a přepisy obrázků pro každý trh
- Využijte přednastavení jazyků, automatický překlad chybějících textů a sledování postupu
- Exportujte snímky obrazovky v PNG nebo JPEG do složek podle jazyka a řady
- Vytvářejte prezentační exporty pro sociální sítě, weby a náhledy kampaní
- Nahrávejte snímky obrazovky přímo do App Store Connect
- Zkontrolujte a upravte metadata v App Store Connect ještě před nahráním
- Nahrajte snímky pro iOS i Mac do App Store Connect v jednom průchodu
- Připojte asistenta kompatibilního s MCP a řiďte Screenshot Bro lokálně
- Dostávejte upozornění na dokončení exportů a nahrávání do obchodu
- Ponechte projekty ve výchozím stavu lokálně, po zapnutí je synchronizujte přes iCloud a vytvářejte zálohy ZIP
- Otevřete úložiště projektů a exportní složky ve Finderu
- Žádné sledování

Screenshot Bro je určený nezávislým vývojářům, produktovým týmům, designérům a marketérům, kteří potřebují větší kontrolu než u základního generátoru snímků a rychlejší postup než ruční přestavování každého marketingového obrázku.

Ať už chystáte první uvedení, velkou aktualizaci, sezónní kampaň nebo rozšíření lokalizací, Screenshot Bro vás dostane od surových snímků obrazovky k marketingovým obrázkům připraveným pro obchod rychleji a konzistentněji.

Pokud hledáte nástroj na tvorbu snímků obrazovky pro App Store, editor šablon snímků, nástroj pro lokalizaci snímků, nahrávání do App Store Connect nebo automatizaci snímků přes MCP, Screenshot Bro udrží celý postup v jediné soustředěné aplikaci pro Mac.

Podmínky užívání (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["cs"] = """\
Screenshot Bro je generátor a editor snímků obrazovky vytvořený přímo pro snímky do App Store. Postavte si opakovaně použitelné šablony, navrhněte kompletní sady snímků, lokalizujte své sdělení a hotové materiály pro obchod exportujte nebo rovnou nahrajte.

Na rozdíl od univerzálních designových nástrojů Screenshot Bro rozumí řadám podle zařízení, lokalizaci, nahrávání do App Store Connect, dávkovým exportům i opakovaně použitelným projektům.

Vytvářejte kompletní sady snímků obrazovky pro iPhone, iPad a Mac. Začněte šablonou, nebo si postavte vlastní systém rozvržení. Vložte snímky obrazovky, přidejte rámečky zařízení nebo kompozice bez rámečků, napište titulky a popisky, upravte styl formátovaného textu vlastními písmy a doladěte každý detail přímo na plátně.

Držte varianty vydání, přepisy pro jednotlivé jazykové verze, plány řad pro konkrétní obchody a hotové podklady v jednom projektu — pro App Store, weby, sociální sítě i kampaně k uvedení.

Klíčové funkce:

- Vytvářejte snímky obrazovky pro App Store z jednoho projektu
- Používejte vestavěné šablony nebo vlastní rozvržení pro opakovaná vydání
- Navrhujte řady s více snímky, srovnávací rozvržení i celé kampaně
- Hromadně importujte snímky obrazovky do řad a rychle nahrazujte obrázky
- Přidávejte rámečky zařízení pro iPhone, iPad, Mac i abstraktní rozvržení
- Pracujte s textem, tvary, obrázky, přechody, dlážděnými pozadími a SVG grafikou
- Upravujte formátovaný text vlastními písmy, řezy, proložením, zarovnáním a velikostí
- Upravujte umístění, přichytávání, vrstvení, oříznutí i otočení přímo na plátně
- Spravujte jazykově specifické texty a přepisy obrázků pro každý trh
- Využijte přednastavení jazyků, automatický překlad chybějících textů a sledování postupu
- Exportujte snímky obrazovky v PNG nebo JPEG do složek podle jazyka a řady
- Vytvářejte prezentační exporty pro sociální sítě, weby a náhledy kampaní
- Nahrávejte snímky obrazovky přímo do App Store Connect
- Zkontrolujte a upravte metadata v App Store Connect ještě před nahráním
- Dostávejte upozornění na dokončení exportů a nahrávání do obchodu
- Ponechte projekty ve výchozím stavu lokálně, po zapnutí je synchronizujte přes iCloud a vytvářejte zálohy ZIP
- Žádné sledování

Screenshot Bro je určený nezávislým vývojářům, produktovým týmům, designérům a marketérům, kteří potřebují větší kontrolu než u základního generátoru snímků a rychlejší postup než ruční přestavování každého marketingového obrázku.

Ať už chystáte první uvedení, velkou aktualizaci, sezónní kampaň nebo rozšíření lokalizací, Screenshot Bro vás dostane od surových snímků obrazovky k marketingovým obrázkům připraveným pro obchod rychleji a konzistentněji.

Pokud hledáte nástroj na tvorbu snímků obrazovky pro App Store, editor šablon snímků, nástroj pro lokalizaci snímků nebo nahrávání do App Store Connect, Screenshot Bro udrží celý postup v jediné soustředěné aplikaci.

Podmínky užívání (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["sk"] = """\
Screenshot Bro je generátor snímok obrazovky aplikácií pre App Store. Navrhnite kompletnú sadu snímok raz, pridajte rámy zariadení, lokalizujte každý titulok do všetkých trhov, na ktoré vydávate, a nahrajte ich priamo do App Store Connect — bez toho, aby ste opustili Mac.

Na rozdiel od univerzálnych grafických nástrojov Screenshot Bro rozumie riadkom pre konkrétne zariadenia, lokalizácii, nahrávaniu do App Store Connect, dávkovým exportom, opakovane použiteľným projektom aj lokálnej automatizácii AI asistenta cez Model Context Protocol.

Vytvárajte kompletné sady snímok obrazovky pre iPhone, iPad a Mac. Začnite so šablónou alebo si postavte vlastný systém rozložení. Vložte snímky obrazovky, pridajte rámy zariadení alebo kompozície bez rámov, napíšte titulky a popisy, naštýlujte formátovaný text vlastnými písmami a dolaďte každý detail priamo na plátne.

Screenshot Bro dokáže na vašom Macu spustiť lokálny MCP server. Pripojte asistenta kompatibilného s MCP, napríklad Claude Code, Claude Desktop, Cursor alebo iného klienta, a nechajte ho vytvárať projekty, upravovať riadky, usporadúvať tvary, importovať snímky, prekladať texty, vykresľovať náhľady plátna a exportovať finálne obrázky. MCP je voliteľné, štandardne vypnuté, funguje len cez loopback a je chránené prístupovým tokenom.

Varianty vydaní, jazykové prepisy, plány riadkov pre jednotlivé obchody aj podklady pripravené na export si držte v jednom projekte — pre App Store, weby, sociálne siete a spúšťacie kampane.

Kľúčové funkcie:

- Vytvárajte snímky obrazovky pre App Store z jedného projektu
- Používajte zabudované šablóny alebo vlastné rozloženia pre opakované vydania
- Navrhujte viacsnímkové riadky, porovnávacie rozloženia a celé kampane
- Dávkovo importujte snímky obrazovky do riadkov a rýchlo vymieňajte obrázky
- Pridávajte rámy zariadení pre iPhone, iPad, Mac a abstraktné rozloženia
- Pracujte s textom, tvarmi, obrázkami, prechodmi, dlaždicovými pozadiami a SVG grafikou
- Upravujte formátovaný text vlastnými písmami, variantmi písma, rozostupmi, zarovnaním a veľkosťou
- Meňte umiestnenie, prichytávanie, vrstvenie, orezanie a otáčanie priamo na plátne
- Spravujte jazykovo špecifické texty a obrázkové prepisy pre každý trh
- Využívajte jazykové predvoľby, automaticky prekladajte chýbajúci text a sledujte priebeh prekladu
- Exportujte snímky obrazovky v PNG alebo JPEG do priečinkov podľa jazyka a riadka
- Vytvárajte prezentačné exporty pre sociálne siete, weby a náhľady kampaní
- Nahrajte snímky obrazovky priamo do App Store Connect
- Skontrolujte a upravte metadáta v App Store Connect pred nahratím
- Nahrajte snímky pre iOS aj Mac do App Store Connect v jednom kroku
- Pripojte asistenta kompatibilného s MCP a ovládajte Screenshot Bro lokálne
- Dostávajte upozornenia na dokončenie exportov a nahrávaní do obchodu
- Držte projekty štandardne lokálne, voliteľne ich synchronizujte cez iCloud a vytvárajte ZIP zálohy
- Otvárajte úložisko projektov a exportné priečinky vo Finderi
- Žiadne sledovanie

Screenshot Bro je určený pre nezávislých vývojárov, produktové tímy, dizajnérov a marketérov, ktorí potrebujú väčšiu kontrolu než pri základnom generátore snímok a rýchlejší postup než ručné prerábanie každého marketingového obrázka.

Či pripravujete prvé vydanie, veľkú aktualizáciu, sezónnu kampaň alebo rozšírenie do ďalších jazykov, Screenshot Bro vám pomôže dostať sa od surových snímok k marketingovým obrázkom pripraveným pre obchod rýchlejšie a konzistentnejšie.

Ak hľadáte nástroj na tvorbu snímok obrazovky pre App Store, tvorbu šablón, lokalizáciu snímok, nahrávanie do App Store Connect alebo automatizáciu snímok cez MCP, Screenshot Bro drží celý postup v jednej sústredenej aplikácii pre Mac.

Podmienky používania (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["sk"] = """\
Screenshot Bro je nástroj na tvorbu a úpravu snímok obrazovky vytvorený špeciálne pre App Store. Vytvárajte opakovane použiteľné šablóny, navrhujte kompletné sady snímok, lokalizujte svoje posolstvo a hotové podklady pre obchod exportujte alebo rovno nahrajte.

Na rozdiel od univerzálnych grafických nástrojov Screenshot Bro rozumie riadkom pre konkrétne zariadenia, lokalizácii, nahrávaniu do App Store Connect, dávkovým exportom aj opakovane použiteľným projektom.

Vytvárajte kompletné sady snímok obrazovky pre iPhone, iPad a Mac. Začnite so šablónou alebo si postavte vlastný systém rozložení. Vložte snímky obrazovky, pridajte rámy zariadení alebo kompozície bez rámov, napíšte titulky a popisy, naštýlujte formátovaný text vlastnými písmami a dolaďte každý detail priamo na plátne.

Varianty vydaní, jazykové prepisy, plány riadkov pre jednotlivé obchody aj podklady pripravené na export si držte v jednom projekte — pre App Store, weby, sociálne siete a spúšťacie kampane.

Kľúčové funkcie:

- Vytvárajte snímky obrazovky pre App Store z jedného projektu
- Používajte zabudované šablóny alebo vlastné rozloženia pre opakované vydania
- Navrhujte viacsnímkové riadky, porovnávacie rozloženia a celé kampane
- Dávkovo importujte snímky obrazovky do riadkov a rýchlo vymieňajte obrázky
- Pridávajte rámy zariadení pre iPhone, iPad, Mac a abstraktné rozloženia
- Pracujte s textom, tvarmi, obrázkami, prechodmi, dlaždicovými pozadiami a SVG grafikou
- Upravujte formátovaný text vlastnými písmami, variantmi písma, rozostupmi, zarovnaním a veľkosťou
- Meňte umiestnenie, prichytávanie, vrstvenie, orezanie a otáčanie priamo na plátne
- Spravujte jazykovo špecifické texty a obrázkové prepisy pre každý trh
- Využívajte jazykové predvoľby, automaticky prekladajte chýbajúci text a sledujte priebeh prekladu
- Exportujte snímky obrazovky v PNG alebo JPEG do priečinkov podľa jazyka a riadka
- Vytvárajte prezentačné exporty pre sociálne siete, weby a náhľady kampaní
- Nahrajte snímky obrazovky priamo do App Store Connect
- Skontrolujte a upravte metadáta v App Store Connect ešte pred nahratím
- Dostávajte upozornenia na dokončenie exportov a nahrávaní do obchodu
- Držte projekty štandardne lokálne, podľa potreby ich synchronizujte cez iCloud a vytvárajte ZIP zálohy
- Žiadne sledovanie

Screenshot Bro je určený pre nezávislých vývojárov, produktové tímy, dizajnérov a marketérov, ktorí potrebujú väčšiu kontrolu než pri základnom generátore snímok a rýchlejší postup než ručné prerábanie každého marketingového obrázka.

Či pripravujete prvé vydanie, veľkú aktualizáciu, sezónnu kampaň alebo rozšírenie do ďalších jazykov, Screenshot Bro vám pomôže dostať sa od surových snímok obrazovky k marketingovým obrázkom pripraveným pre obchod rýchlejšie a konzistentnejšie.

Ak hľadáte nástroj na tvorbu snímok obrazovky pre App Store, tvorbu šablón, lokalizáciu snímok alebo nahrávanie do App Store Connect, Screenshot Bro drží celý postup v jednej sústredenej aplikácii.

Podmienky používania (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["hu"] = """\
A Screenshot Bro képernyőkép-generátor alkalmazásokhoz, az App Store-hoz szabva. Tervezd meg egyszer a teljes képernyőkép-sorozatot, tegyél rá készülékkereteket, fordítsd le a főcímeket minden piacra, ahol megjelensz, és töltsd fel egyenesen az App Store Connectbe — anélkül, hogy elhagynád a Macet.

Az általános tervezőprogramokkal ellentétben a Screenshot Bro ismeri a készülékenkénti sorokat, a lokalizációt, az App Store Connect-feltöltéseket, a kötegelt exportot, az újrafelhasználható projekteket és a helyi AI-asszisztenssel végzett automatizálást a Model Context Protocol révén.

Állíts össze teljes képernyőkép-sorozatot iPhone-ra, iPadre és Macre. Indulj egy sablonból, vagy alakítsd ki a saját elrendezési rendszeredet. Húzd be a képernyőképeket, tegyél rájuk készülékkeretet vagy hagyd őket keret nélkül, írj főcímeket és feliratokat, formázd a szöveget egyedi betűtípusokkal, és hangolj minden részletet a vásznon.

A Screenshot Bro helyi MCP-kiszolgálót futtathat a Macen. Csatlakoztass egy MCP-kompatibilis asszisztenst — például a Claude Code-ot, a Claude Desktopot, a Cursort vagy más klienst —, és bízd rá a projektek létrehozását, a sorok szerkesztését, az alakzatok rendezését, a képernyőképek importálását, a szövegek fordítását, a vászonelőnézetek renderelését és a végleges képek exportálását. Az MCP opcionális, alapértelmezés szerint kikapcsolt, csak loopback címen érhető el, és hozzáférési token védi.

Tartsd egy projektben a kiadásváltozatokat, a nyelvspecifikus felülbírálatokat, az áruházankénti sorterveket és az exportra kész elemeket az App Store, a webhelyek, a közösségi média és a bevezető kampányok számára.

Főbb funkciók:

- App Store-képernyőképek készítése egyetlen projektből
- Beépített sablonok vagy egyedi elrendezések ismétlődő kiadásokhoz
- Képernyőképek kötegelt importálása sorokba, képek gyors cseréje
- Készülékkeretek iPhone, iPad, Mac és absztrakt elrendezésekhez
- Szöveg, alakzatok, képek, színátmenetek, csempézett hátterek és SVG-grafikák használata
- Formázott szöveg szerkesztése egyedi betűtípusokkal, betűváltozatokkal, térközzel, igazítással és méretezéssel
- Nyelvspecifikus szöveg- és képfelülbírálatok kezelése minden piachoz
- Nyelvi előbeállítások, hiányzó szövegek automatikus fordítása, fordítási állapot követése
- PNG- vagy JPEG-képernyőképek exportálása nyelv és sor szerinti mappákba
- Bemutató exportok közösségi bejegyzésekhez, webhelyekhez és kampányelőnézetekhez
- Képernyőképek feltöltése közvetlenül az App Store Connectbe
- App Store Connect-metaadatok áttekintése és szerkesztése a feltöltés előtt
- MCP-kompatibilis asszisztens csatlakoztatása a Screenshot Bro helyi vezérléséhez
- Értesítés az exportálások és az áruházi feltöltések befejezéséről
- A projektek alapból helyben maradnak, igény szerint iCloud-szinkronizálással és ZIP-mentésekkel
- Nincs nyomkövetés

A Screenshot Bro független fejlesztőknek, termékcsapatoknak, tervezőknek és marketingeseknek készült, akiknek egy egyszerű képernyőkép-generátornál több kontrollra van szükségük, és gyorsabb munkamenetre, mint minden egyes marketingkép kézi újraépítése.

Akár az első megjelenésre, nagyobb frissítésre, szezonális kampányra vagy egy újabb nyelvi bővítésre készülsz, a Screenshot Bro segít gyorsabban és következetesebben eljutni a nyers képernyőképektől az áruházra kész marketingképekig.

Ha App Store-képernyőképeket készítő eszközre, képernyőkép-sablonszerkesztőre, képernyőkép-lokalizációs eszközre, App Store Connect-feltöltőre vagy MCP-re felkészített képernyőkép-automatizálásra van szükséged, a Screenshot Bro egyetlen célirányos Mac-alkalmazásban tartja a teljes munkafolyamatot.

Felhasználási feltételek (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["hu"] = """\
A Screenshot Bro kifejezetten App Store-képernyőképekhez készült képernyőkép-szerkesztő. Hozz létre újrafelhasználható sablonokat, tervezz teljes képernyőkép-sorozatokat, lokalizáld az üzenetedet, majd exportáld vagy töltsd fel a kész áruházi képanyagot.

Az általános tervezőprogramokkal ellentétben a Screenshot Bro ismeri a készülékenkénti sorokat, a lokalizációt, az App Store Connect-feltöltéseket, a kötegelt exportot és az újrafelhasználható projekteket.

Állíts össze teljes képernyőkép-sorozatot iPhone-ra, iPadre és Macre. Indulj egy sablonból, vagy alakítsd ki a saját elrendezési rendszeredet. Húzd be a képernyőképeket, tegyél rájuk készülékkeretet vagy hagyd őket keret nélkül, írj főcímeket és feliratokat, formázd a szöveget egyedi betűtípusokkal, és hangolj minden részletet a vásznon.

Tartsd egy projektben a kiadásváltozatokat, a nyelvspecifikus felülbírálatokat, az áruházankénti sorterveket és az exportra kész elemeket az App Store, a webhelyek, a közösségi média és a bevezető kampányok számára.

Főbb funkciók:

- App Store-képernyőképek készítése egyetlen projektből
- Beépített sablonok vagy egyedi elrendezések ismétlődő kiadásokhoz
- Többképes sorok, összehasonlító elrendezések és teljes kampányok tervezése
- Képernyőképek kötegelt importálása sorokba, képek gyors cseréje
- Készülékkeretek iPhone, iPad, Mac és absztrakt elrendezésekhez
- Szöveg, alakzatok, képek, színátmenetek, csempézett hátterek és SVG-grafikák használata
- Formázott szöveg szerkesztése egyedi betűtípusokkal, betűváltozatokkal, térközzel, igazítással és méretezéssel
- Elhelyezés, illesztés, rétegsorrend, vágás és forgatás közvetlenül a vásznon
- Nyelvspecifikus szöveg- és képfelülbírálatok kezelése minden piachoz
- Nyelvi előbeállítások, hiányzó szövegek automatikus fordítása, fordítási állapot követése
- PNG- vagy JPEG-képernyőképek exportálása nyelv és sor szerinti mappákba
- Bemutató exportok közösségi bejegyzésekhez, webhelyekhez és kampányelőnézetekhez
- Képernyőképek feltöltése közvetlenül az App Store Connectbe
- App Store Connect-metaadatok áttekintése és szerkesztése a feltöltés előtt
- Értesítés az exportálások és az áruházi feltöltések befejezéséről
- A projektek alapból helyben maradnak, igény szerint iCloud-szinkronizálással és ZIP-mentésekkel
- Nincs nyomkövetés

A Screenshot Bro független fejlesztőknek, termékcsapatoknak, tervezőknek és marketingeseknek készült, akiknek egy egyszerű képernyőkép-generátornál több kontrollra van szükségük, és gyorsabb munkamenetre, mint minden egyes marketingkép kézi újraépítése.

Akár az első megjelenésre, nagyobb frissítésre, szezonális kampányra vagy egy újabb nyelvi bővítésre készülsz, a Screenshot Bro segít gyorsabban és következetesebben eljutni a nyers képernyőképektől az áruházra kész marketingképekig.

Ha App Store-képernyőképeket készítő eszközre, képernyőkép-sablonszerkesztőre, képernyőkép-lokalizációs eszközre vagy App Store Connect-feltöltőre van szükséged, a Screenshot Bro egyetlen célirányos alkalmazásban tartja a teljes munkafolyamatot.

Felhasználási feltételek (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["ro"] = """\
Screenshot Bro este un generator de capturi de ecran pentru App Store. Proiectezi o singură dată un set complet de capturi, adaugi rame de dispozitiv, localizezi fiecare titlu pentru toate piețele în care lansezi și încarci totul direct în App Store Connect — fără să ieși de pe Mac.

Spre deosebire de instrumentele generice de design, Screenshot Bro înțelege rândurile dedicate fiecărui dispozitiv, localizarea, încărcările în App Store Connect, exporturile în lot, proiectele reutilizabile și automatizarea locală cu asistenți AI prin Model Context Protocol.

Construiește seturi complete de capturi pentru iPhone, iPad și Mac. Pornește de la un șablon sau creează-ți propriul sistem de aspect. Adaugă capturile, pune rame de dispozitiv sau compoziții fără ramă, scrie titluri și descrieri, stilizează textul îmbogățit cu fonturi proprii și reglează fiecare detaliu direct pe canvas.

Screenshot Bro poate găzdui un server MCP local pe Mac. Conectează un asistent compatibil MCP — Claude Code, Claude Desktop, Cursor sau alt client — și lasă-l să creeze proiecte, să editeze rânduri, să aranjeze forme, să importe capturi de ecran, să traducă texte, să randeze previzualizări ale canvasului și să exporte imaginile finale. MCP este opțional, dezactivat implicit, limitat la loopback și protejat cu un token de acces.

Ține variantele de lansare, suprascrierile pe limbă, planurile de rânduri pentru fiecare magazin și materialele gata de export într-un singur proiect, pentru App Store, site-uri web, rețele sociale și campanii de lansare.

Funcții principale:

- Creează capturi de ecran pentru App Store dintr-un singur proiect
- Folosește șabloane incluse sau machete proprii pentru lansări repetate
- Importă capturi în lot pe rânduri și înlocuiește rapid imaginile
- Adaugă rame de dispozitiv pentru iPhone, iPad, Mac și machete abstracte
- Lucrează cu text, forme, imagini, degradeuri, fundaluri în mozaic și grafică SVG
- Editează text îmbogățit cu fonturi proprii, variante de font, spațiere, aliniere și dimensiuni
- Gestionează suprascrieri de text și de imagini pentru fiecare piață
- Folosește presetări de limbă, tradu automat textele lipsă și urmărește progresul traducerii
- Exportă capturi PNG sau JPEG în foldere, pe limbă și pe rând
- Creează exporturi de prezentare pentru postări sociale, site-uri și previzualizări de campanie
- Încarcă rapid capturile direct în App Store Connect
- Verifică și editează metadatele din App Store Connect înainte de încărcare
- Încarcă în App Store Connect capturile pentru iOS și Mac într-un singur flux
- Conectează un asistent compatibil MCP care să controleze local Screenshot Bro
- Primește notificări la finalizarea exporturilor și a încărcărilor în magazin
- Ține proiectele local implicit, sincronizează cu iCloud când vrei și fă copii ZIP
- Deschide folderele de proiecte și de export în Finder
- Fără urmărire

Screenshot Bro este făcut pentru dezvoltatori independenți, echipe de produs, designeri și marketeri care au nevoie de mai mult control decât oferă un generator obișnuit de capturi și de un flux de lucru mai rapid decât refacerea manuală a fiecărei imagini de marketing.

Fie că pregătești o primă lansare, o actualizare majoră, o campanie sezonieră sau o extindere pe limbi noi, Screenshot Bro te ajută să treci de la capturi brute la imagini gata de publicat mai repede și mai consecvent.

Dacă îți trebuie un creator de capturi de ecran pentru App Store, un constructor de șabloane, un instrument de localizare a capturilor, un uploader pentru App Store Connect sau un instrument de automatizare prin MCP, Screenshot Bro ține tot fluxul de lucru într-o singură aplicație Mac.

Condiții de utilizare (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["ro"] = """\
Screenshot Bro este un editor și un generator de capturi de ecran făcut special pentru capturile din App Store. Creezi șabloane reutilizabile, proiectezi seturi complete de capturi, îți localizezi mesajul și exporți sau încarci materiale finisate pentru magazin.

Spre deosebire de instrumentele generice de design, Screenshot Bro înțelege rândurile dedicate fiecărui dispozitiv, localizarea, încărcările în App Store Connect, exporturile în lot și proiectele reutilizabile.

Construiește seturi complete de capturi pentru iPhone, iPad și Mac. Pornește de la un șablon sau creează-ți propriul sistem de aspect. Adaugă capturile, pune rame de dispozitiv sau compoziții fără ramă, scrie titluri și descrieri, stilizează textul îmbogățit cu fonturi proprii și reglează fiecare detaliu direct pe canvas.

Ține variantele de lansare, suprascrierile pe limbă, planurile de rânduri pentru fiecare magazin și materialele gata de export într-un singur proiect, pentru App Store, site-uri web, rețele sociale și campanii de lansare.

Funcții principale:

- Creează capturi de ecran pentru App Store dintr-un singur proiect
- Folosește șabloane incluse sau machete proprii pentru lansări repetate
- Proiectează rânduri cu mai multe capturi, machete comparative și campanii întregi
- Importă capturi în lot pe rânduri și înlocuiește rapid imaginile
- Adaugă rame de dispozitiv pentru iPhone, iPad, Mac și machete abstracte
- Lucrează cu text, forme, imagini, degradeuri, fundaluri în mozaic și grafică SVG
- Editează text îmbogățit cu fonturi proprii, variante de font, spațiere, aliniere și dimensiuni
- Ajustează poziția, alinierea magnetică, straturile, decuparea și rotația direct pe canvas
- Gestionează suprascrieri de text și de imagini pentru fiecare piață
- Folosește presetări de limbă, tradu automat textele lipsă și urmărește progresul traducerii
- Exportă capturi PNG sau JPEG în foldere, pe limbă și pe rând
- Creează exporturi de prezentare pentru postări sociale, site-uri și previzualizări de campanie
- Încarcă rapid capturile direct în App Store Connect
- Verifică și editează metadatele din App Store Connect înainte de încărcare
- Primește notificări la finalizarea exporturilor și a încărcărilor în magazin
- Ține proiectele local implicit, sincronizează cu iCloud când vrei și fă copii ZIP
- Fără urmărire

Screenshot Bro este făcut pentru dezvoltatori independenți, echipe de produs, designeri și marketeri care au nevoie de mai mult control decât oferă un generator obișnuit de capturi și de un flux de lucru mai rapid decât refacerea manuală a fiecărei imagini de marketing.

Fie că pregătești o primă lansare, o actualizare majoră, o campanie sezonieră sau o extindere pe limbi noi, Screenshot Bro te ajută să treci de la capturi brute la imagini gata de publicat mai repede și mai consecvent.

Dacă îți trebuie un creator de capturi de ecran pentru App Store, un constructor de șabloane, un instrument de localizare a capturilor sau un uploader pentru App Store Connect, Screenshot Bro ține tot fluxul de lucru într-o singură aplicație.

Condiții de utilizare (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["hr"] = """\
Screenshot Bro je generator snimki zaslona za App Store. Osmislite cijeli set snimki zaslona jednom, dodajte okvire uređaja, lokalizirajte svaki naslov za svako tržište na kojem objavljujete i pošaljite sve izravno na App Store Connect — bez napuštanja Maca.

Za razliku od općenitih dizajnerskih alata, Screenshot Bro razumije retke vezane uz pojedini uređaj, lokalizaciju, prijenos na App Store Connect, skupni izvoz, projekte za višekratnu upotrebu i lokalnu automatizaciju pomoću AI asistenta preko protokola Model Context Protocol.

Izradite kompletne setove snimki zaslona za iPhone, iPad i Mac. Krenite od predloška ili izgradite vlastiti sustav rasporeda. Ubacite snimke zaslona, dodajte okvire uređaja ili kompozicije bez okvira, napišite naslove i opise, oblikujte obogaćeni tekst vlastitim fontovima i dotjerajte svaki detalj na platnu.

Screenshot Bro može pokrenuti lokalni MCP poslužitelj na vašem Macu. Povežite MCP-kompatibilnog asistenta poput alata Claude Code, Claude Desktop, Cursor ili nekog drugog klijenta i pustite ga da stvara projekte, uređuje retke, raspoređuje oblike, uvozi snimke zaslona, prevodi tekst, prikazuje pretpreglede platna i izvozi konačne slike. MCP je neobavezan, prema zadanim postavkama isključen, radi samo lokalno i zaštićen je pristupnim tokenom.

Držite varijante izdanja, prilagodbe za pojedini jezik, planove redaka za pojedinu trgovinu i materijale spremne za izvoz u jednom projektu — za App Store, web stranice, društvene mreže i lansirne kampanje.

Ključne značajke:

- Izradite App Store snimke zaslona iz jednog projekta
- Koristite ugrađene predloške ili vlastite rasporede za ponavljajuća izdanja
- Skupno uvezite snimke zaslona u retke i brzo zamijenite slike
- Dodajte okvire uređaja za iPhone, iPad, Mac i apstraktne rasporede
- Radite s tekstom, oblicima, slikama, gradijentima, popločanim pozadinama i SVG grafikama
- Uređujte obogaćeni tekst uz vlastite fontove, varijante pisma, razmake, poravnanje i veličine
- Upravljajte tekstom i slikama prilagođenima svakom tržištu
- Koristite gotove jezične postavke, automatski prevedite tekst koji nedostaje i pratite napredak prijevoda
- Izvezite PNG ili JPEG snimke zaslona u mape po jeziku i retku
- Izradite izvoze za predstavljanje na društvenim mrežama, web stranicama i u pretpregledima kampanja
- Prenesite snimke zaslona izravno na App Store Connect
- Pregledajte i uredite metapodatke za App Store Connect prije prijenosa
- Povežite MCP-kompatibilnog asistenta koji lokalno upravlja aplikacijom Screenshot Bro
- Primajte obavijesti o dovršenim izvozima i prijenosima u trgovinu
- Držite projekte lokalno, sinkronizirajte ih putem iCloud usluge kad to uključite i izradite ZIP sigurnosne kopije
- Bez praćenja

Screenshot Bro je namijenjen samostalnim razvojnim programerima, produktnim timovima, dizajnerima i marketinškim stručnjacima kojima treba više kontrole nego što je nudi običan generator snimki zaslona i brži tijek rada od ručne izrade svake marketinške slike.

Bilo da pripremate prvo izdanje, veliku nadogradnju, sezonsku kampanju ili uvođenje novih jezika, Screenshot Bro vas brže i dosljednije vodi od sirovih snimki zaslona do marketinških slika spremnih za trgovinu.

Ako trebate alat za izradu App Store snimki zaslona, graditelj predložaka, alat za lokalizaciju snimki zaslona, alat za prijenos na App Store Connect ili MCP automatizaciju snimki zaslona, Screenshot Bro drži cijeli tijek rada u jednoj usredotočenoj Mac aplikaciji.

Uvjeti korištenja (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["hr"] = """\
Screenshot Bro je alat za izradu i uređivanje snimki zaslona, napravljen upravo za App Store snimke zaslona. Izradite predloške za višekratnu upotrebu, osmislite cijele setove snimki zaslona, lokalizirajte svoju poruku te izvezite ili prenesite dotjerane materijale za trgovinu.

Za razliku od općenitih dizajnerskih alata, Screenshot Bro razumije retke vezane uz pojedini uređaj, lokalizaciju, prijenos na App Store Connect, skupni izvoz i projekte za višekratnu upotrebu.

Izradite kompletne setove snimki zaslona za iPhone, iPad i Mac. Krenite od predloška ili izgradite vlastiti sustav rasporeda. Ubacite snimke zaslona, dodajte okvire uređaja ili kompozicije bez okvira, napišite naslove i opise, oblikujte obogaćeni tekst vlastitim fontovima i dotjerajte svaki detalj na platnu.

Držite varijante izdanja, prilagodbe za pojedini jezik, planove redaka za pojedinu trgovinu i materijale spremne za izvoz u jednom projektu — za App Store, web stranice, društvene mreže i lansirne kampanje.

Ključne značajke:

- Izradite App Store snimke zaslona iz jednog projekta
- Koristite ugrađene predloške ili vlastite rasporede za ponavljajuća izdanja
- Osmislite retke s više prizora, usporedne rasporede i cijele kampanje
- Skupno uvezite snimke zaslona u retke i brzo zamijenite slike
- Dodajte okvire uređaja za iPhone, iPad, Mac i apstraktne rasporede
- Radite s tekstom, oblicima, slikama, gradijentima, popločanim pozadinama i SVG grafikama
- Uređujte obogaćeni tekst uz vlastite fontove, varijante pisma, razmake, poravnanje i veličine
- Namjestite položaj, prianjanje, slojeve, obrezivanje i rotaciju izravno na platnu
- Upravljajte tekstom i slikama prilagođenima svakom tržištu
- Koristite gotove jezične postavke, automatski prevedite tekst koji nedostaje i pratite napredak prijevoda
- Izvezite PNG ili JPEG snimke zaslona u mape po jeziku i retku
- Izradite izvoze za predstavljanje na društvenim mrežama, web stranicama i u pretpregledima kampanja
- Prenesite snimke zaslona izravno na App Store Connect
- Pregledajte i uredite metapodatke za App Store Connect prije prijenosa
- Primajte obavijesti o dovršenim izvozima i prijenosima u trgovinu
- Držite projekte lokalno, sinkronizirajte ih putem iCloud usluge kad to uključite i izradite ZIP sigurnosne kopije
- Bez praćenja

Screenshot Bro je namijenjen samostalnim razvojnim programerima, produktnim timovima, dizajnerima i marketinškim stručnjacima kojima treba više kontrole nego što je nudi običan generator snimki zaslona i brži tijek rada od ručne izrade svake marketinške slike.

Bilo da pripremate prvo izdanje, veliku nadogradnju, sezonsku kampanju ili uvođenje novih jezika, Screenshot Bro vas brže i dosljednije vodi od sirovih snimki zaslona do marketinških slika spremnih za trgovinu.

Ako trebate alat za izradu App Store snimki zaslona, graditelj predložaka, alat za lokalizaciju snimki zaslona ili alat za prijenos na App Store Connect, Screenshot Bro drži cijeli tijek rada u jednoj usredotočenoj aplikaciji.

Uvjeti korištenja (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["el"] = """\
Το Screenshot Bro είναι μια εφαρμογή δημιουργίας στιγμιοτύπων οθόνης για το App Store. Σχεδιάστε μία φορά ένα πλήρες σετ, προσθέστε πλαίσια συσκευών, μεταφράστε κάθε τίτλο για κάθε αγορά όπου κυκλοφορείτε και ανεβάστε τα απευθείας στο App Store Connect — χωρίς να φύγετε από τον Mac σας.

Σε αντίθεση με τα γενικά εργαλεία σχεδίασης, το Screenshot Bro κατανοεί σειρές ανά συσκευή, τοπική προσαρμογή, μεταφορτώσεις στο App Store Connect, μαζικές εξαγωγές, επαναχρησιμοποιήσιμα έργα και τοπική αυτοματοποίηση με βοηθό τεχνητής νοημοσύνης μέσω του Model Context Protocol.

Δημιουργήστε πλήρη σετ στιγμιοτύπων για iPhone, iPad και Mac. Ξεκινήστε από ένα πρότυπο ή φτιάξτε το δικό σας σύστημα διατάξεων. Ρίξτε μέσα στιγμιότυπα, προσθέστε πλαίσια συσκευών ή συνθέσεις χωρίς πλαίσιο, γράψτε τίτλους και λεζάντες, μορφοποιήστε εμπλουτισμένο κείμενο με δικές σας γραμματοσειρές και ρυθμίστε κάθε λεπτομέρεια πάνω στον καμβά.

Το Screenshot Bro μπορεί να φιλοξενήσει έναν τοπικό διακομιστή MCP στον Mac σας. Συνδέστε έναν συμβατό με MCP βοηθό, όπως το Claude Code, το Claude Desktop, το Cursor ή οποιονδήποτε άλλο πελάτη, και αφήστε τον να δημιουργεί έργα, να επεξεργάζεται σειρές, να τακτοποιεί σχήματα, να εισάγει στιγμιότυπα, να μεταφράζει κείμενα, να αποδίδει προεπισκοπήσεις του καμβά και να εξάγει τελικές εικόνες. Το MCP είναι προαιρετικό, ανενεργό από προεπιλογή, μόνο τοπικό (loopback) και προστατεύεται με διακριτικό πρόσβασης.

Κρατήστε παραλλαγές κυκλοφορίας, παρακάμψεις ανά γλώσσα, πλάνα σειρών ανά κατάστημα και έτοιμα προς εξαγωγή στοιχεία σε ένα έργο, για το App Store, ιστότοπους, κοινωνικά δίκτυα και καμπάνιες κυκλοφορίας.

Βασικές δυνατότητες:

- Δημιουργία στιγμιοτύπων για το App Store από ένα μόνο έργο
- Ενσωματωμένα πρότυπα ή δικές σας διατάξεις για επαναλαμβανόμενες κυκλοφορίες
- Μαζική εισαγωγή στιγμιοτύπων σε σειρές και γρήγορη αντικατάσταση εικόνων
- Πλαίσια συσκευών για iPhone, iPad, Mac και αφηρημένες διατάξεις
- Κείμενο, σχήματα, εικόνες, διαβαθμίσεις, φόντα με μοτίβο και γραφικά SVG
- Εμπλουτισμένο κείμενο με δικές σας γραμματοσειρές, παραλλαγές, διάστιχο, στοίχιση και μεγέθη
- Διαχείριση παρακάμψεων κειμένου και εικόνων ανά γλώσσα και αγορά
- Προεπιλογές γλωσσών, αυτόματη μετάφραση κειμένων που λείπουν και παρακολούθηση προόδου
- Εξαγωγή σε PNG ή JPEG με φακέλους ανά γλώσσα και σειρά
- Εξαγωγές παρουσίασης για κοινωνικά δίκτυα, ιστότοπους και προεπισκοπήσεις καμπανιών
- Απευθείας μεταφόρτωση στιγμιοτύπων στο App Store Connect
- Έλεγχος και επεξεργασία μεταδεδομένων του App Store Connect πριν από την αποστολή
- Σύνδεση συμβατού με MCP βοηθού για τοπικό έλεγχο του Screenshot Bro
- Ειδοποιήσεις ολοκλήρωσης για εξαγωγές και αποστολές στο κατάστημα
- Τοπικά έργα από προεπιλογή, συγχρονισμός με iCloud όταν ενεργοποιηθεί και αντίγραφα ασφαλείας ZIP
- Καμία παρακολούθηση

Το Screenshot Bro απευθύνεται σε ανεξάρτητους προγραμματιστές, ομάδες προϊόντος, σχεδιαστές και στελέχη μάρκετινγκ που θέλουν περισσότερο έλεγχο από μια απλή γεννήτρια στιγμιοτύπων και ταχύτερη ροή εργασίας από το να ξαναφτιάχνουν στο χέρι κάθε εικόνα προβολής της εφαρμογής.

Είτε ετοιμάζετε την πρώτη κυκλοφορία, μια μεγάλη ενημέρωση, μια εποχική καμπάνια ή την επέκταση σε νέες γλώσσες, το Screenshot Bro σας οδηγεί από τα ακατέργαστα στιγμιότυπα σε εικόνες έτοιμες για το κατάστημα, πιο γρήγορα και με μεγαλύτερη συνέπεια.

Αν χρειάζεστε εργαλείο δημιουργίας στιγμιοτύπων για το App Store, δόμηση προτύπων, τοπική προσαρμογή στιγμιοτύπων, αποστολή στο App Store Connect ή αυτοματοποίηση στιγμιοτύπων με MCP, το Screenshot Bro κρατά όλη τη ροή εργασίας σε μία εστιασμένη εφαρμογή για Mac.

Όροι χρήσης (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["el"] = """\
Το Screenshot Bro είναι ένα εργαλείο δημιουργίας και επεξεργασίας στιγμιοτύπων, φτιαγμένο ειδικά για στιγμιότυπα οθόνης του App Store. Φτιάξτε επαναχρησιμοποιήσιμα πρότυπα, σχεδιάστε πλήρη σετ στιγμιοτύπων, προσαρμόστε το μήνυμά σας ανά γλώσσα και εξάγετε ή ανεβάστε έτοιμο δημιουργικό υλικό για το κατάστημα.

Σε αντίθεση με τα γενικά εργαλεία σχεδίασης, το Screenshot Bro κατανοεί σειρές ανά συσκευή, τοπική προσαρμογή, μεταφορτώσεις στο App Store Connect, μαζικές εξαγωγές και επαναχρησιμοποιήσιμα έργα.

Δημιουργήστε πλήρη σετ στιγμιοτύπων για iPhone, iPad και Mac. Ξεκινήστε από ένα πρότυπο ή φτιάξτε το δικό σας σύστημα διατάξεων. Ρίξτε μέσα στιγμιότυπα, προσθέστε πλαίσια συσκευών ή συνθέσεις χωρίς πλαίσιο, γράψτε τίτλους και λεζάντες, μορφοποιήστε εμπλουτισμένο κείμενο με δικές σας γραμματοσειρές και ρυθμίστε κάθε λεπτομέρεια πάνω στον καμβά.

Κρατήστε παραλλαγές κυκλοφορίας, παρακάμψεις ανά γλώσσα, πλάνα σειρών ανά κατάστημα και έτοιμα προς εξαγωγή στοιχεία σε ένα έργο, για το App Store, ιστότοπους, κοινωνικά δίκτυα και καμπάνιες κυκλοφορίας.

Βασικές δυνατότητες:

- Δημιουργία στιγμιοτύπων για το App Store από ένα μόνο έργο
- Ενσωματωμένα πρότυπα ή δικές σας διατάξεις για επαναλαμβανόμενες κυκλοφορίες
- Σχεδίαση σειρών με πολλά στιγμιότυπα, διατάξεων σύγκρισης και ολόκληρων καμπανιών
- Μαζική εισαγωγή στιγμιοτύπων σε σειρές και γρήγορη αντικατάσταση εικόνων
- Πλαίσια συσκευών για iPhone, iPad, Mac και αφηρημένες διατάξεις
- Κείμενο, σχήματα, εικόνες, διαβαθμίσεις, φόντα με μοτίβο και γραφικά SVG
- Εμπλουτισμένο κείμενο με δικές σας γραμματοσειρές, παραλλαγές, διάστιχο, στοίχιση και μεγέθη
- Ρύθμιση θέσης, κουμπώματος, επιπέδων, περικοπής και περιστροφής απευθείας στον καμβά
- Διαχείριση παρακάμψεων κειμένου και εικόνων ανά γλώσσα και αγορά
- Προεπιλογές γλωσσών, αυτόματη μετάφραση κειμένων που λείπουν και παρακολούθηση προόδου
- Εξαγωγή σε PNG ή JPEG με φακέλους ανά γλώσσα και σειρά
- Εξαγωγές παρουσίασης για κοινωνικά δίκτυα, ιστότοπους και προεπισκοπήσεις καμπανιών
- Απευθείας μεταφόρτωση στιγμιοτύπων στο App Store Connect
- Έλεγχος και επεξεργασία μεταδεδομένων του App Store Connect πριν από την αποστολή
- Ειδοποιήσεις ολοκλήρωσης για εξαγωγές και αποστολές στο κατάστημα
- Τοπικά έργα από προεπιλογή, συγχρονισμός με iCloud όταν ενεργοποιηθεί και αντίγραφα ασφαλείας ZIP
- Καμία παρακολούθηση

Το Screenshot Bro απευθύνεται σε ανεξάρτητους προγραμματιστές, ομάδες προϊόντος, σχεδιαστές και στελέχη μάρκετινγκ που θέλουν περισσότερο έλεγχο από μια απλή γεννήτρια στιγμιοτύπων και ταχύτερη ροή εργασίας από το να ξαναφτιάχνουν στο χέρι κάθε εικόνα προβολής της εφαρμογής.

Είτε ετοιμάζετε την πρώτη κυκλοφορία, μια μεγάλη ενημέρωση, μια εποχική καμπάνια ή την επέκταση σε νέες γλώσσες, το Screenshot Bro σας οδηγεί από τα ακατέργαστα στιγμιότυπα σε εικόνες έτοιμες για το κατάστημα, πιο γρήγορα και με μεγαλύτερη συνέπεια.

Αν χρειάζεστε εργαλείο δημιουργίας στιγμιοτύπων για το App Store, δόμηση προτύπων στιγμιοτύπων, τοπική προσαρμογή στιγμιοτύπων ή αποστολή στο App Store Connect, το Screenshot Bro κρατά όλη τη ροή εργασίας σε μία εστιασμένη εφαρμογή.

Όροι χρήσης (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["ca"] = """\
Screenshot Bro és un generador de captures de pantalla d'aplicacions per a l'App Store. Dissenya un joc complet de captures una sola vegada, afegeix marcs de dispositiu, localitza cada titular a tots els mercats on publiques i puja-ho tot directament a App Store Connect, sense sortir del Mac.

A diferència de les eines de disseny genèriques, Screenshot Bro entén les files per dispositiu, la localització, les pujades a App Store Connect, les exportacions per lots, els projectes reutilitzables i l'automatització local amb assistents d'IA mitjançant el Model Context Protocol.

Crea jocs complets de captures per a iPhone, iPad i Mac. Comença amb una plantilla o munta el teu propi sistema de disposicions. Arrossega-hi captures, afegeix marcs de dispositiu o composicions sense marc, escriu titulars i peus de text, dona estil al text enriquit amb tipus de lletra propis i ajusta cada detall al llenç.

Screenshot Bro pot allotjar un servidor MCP local al teu Mac. Connecta-hi un assistent compatible amb MCP, com ara Claude Code, Claude Desktop, Cursor o qualsevol altre client, i deixa que creï projectes, editi files, ordeni formes, importi captures, tradueixi textos, generi previsualitzacions del llenç i exporti les imatges finals. L'MCP és opcional, està desactivat per defecte, només escolta en loopback i està protegit amb un token d'accés.

Mantén les variants de llançament, les substitucions per idioma, els plans de files per botiga i els recursos llestos per exportar dins d'un mateix projecte, per a l'App Store, webs, xarxes socials i campanyes de llançament.

Funcions principals:

- Crea captures de pantalla per a l'App Store des d'un sol projecte
- Fes servir plantilles integrades o disposicions pròpies per als llançaments recurrents
- Importa captures per lots dins de les files i substitueix imatges ràpidament
- Afegeix marcs de dispositiu per a iPhone, iPad, Mac i disposicions abstractes
- Treballa amb text, formes, imatges, degradats, fons en mosaic i gràfics SVG
- Edita text enriquit amb tipus de lletra propis, variants, espaiat, alineació i mides
- Gestiona les substitucions de text i d'imatge de cada mercat
- Fes servir idiomes predefinits, tradueix automàticament el text que falta i controla el progrés de la traducció
- Exporta captures en PNG o JPEG a carpetes per idioma i per fila
- Crea exportacions de presentació per a xarxes socials, webs i previsualitzacions de campanya
- Puja les captures directament a App Store Connect
- Revisa i edita les metadades d'App Store Connect abans de pujar-les
- Connecta un assistent compatible amb MCP per controlar Screenshot Bro en local
- Rep notificacions quan acabin les exportacions i les pujades a la botiga
- Mantén els projectes en local per defecte, sincronitza'ls amb iCloud si ho actives i crea còpies de seguretat en ZIP
- Sense seguiment

Screenshot Bro està pensat per a desenvolupadors independents, equips de producte, dissenyadors i responsables de màrqueting que necessiten més control que un generador de captures bàsic i un flux de treball més ràpid que refer a mà cada imatge de màrqueting.

Tant si prepares un primer llançament com una actualització important, una campanya de temporada o el desplegament d'un nou idioma, Screenshot Bro t'ajuda a passar de les captures en brut a les imatges llestes per a la botiga més de pressa i amb més coherència.

Si necessites un creador de captures per a l'App Store, un constructor de plantilles, una eina de localització de captures, un carregador per a App Store Connect o una eina d'automatització preparada per a MCP, Screenshot Bro concentra tot el flux de treball en una sola aplicació de Mac.

Condicions d'ús (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["ca"] = """\
Screenshot Bro és un creador i editor de captures de pantalla fet expressament per a les captures de l'App Store. Crea plantilles reutilitzables, dissenya jocs complets de captures, localitza el teu missatge i exporta o puja creativitats de botiga ben acabades.

A diferència de les eines de disseny genèriques, Screenshot Bro entén les files per dispositiu, la localització, les pujades a App Store Connect, les exportacions per lots i els projectes reutilitzables.

Crea jocs complets de captures per a iPhone, iPad i Mac. Comença amb una plantilla o munta el teu propi sistema de disposicions. Arrossega-hi captures, afegeix marcs de dispositiu o composicions sense marc, escriu titulars i peus de text, dona estil al text enriquit amb tipus de lletra propis i ajusta cada detall al llenç.

Mantén les variants de llançament, les substitucions per idioma, els plans de files per botiga i els recursos llestos per exportar dins d'un mateix projecte, per a l'App Store, webs, xarxes socials i campanyes de llançament.

Funcions principals:

- Crea captures de pantalla per a l'App Store des d'un sol projecte
- Fes servir plantilles integrades o disposicions pròpies per als llançaments recurrents
- Dissenya files de diverses captures, disposicions comparatives i campanyes senceres
- Importa captures per lots dins de les files i substitueix imatges ràpidament
- Afegeix marcs de dispositiu per a iPhone, iPad, Mac i disposicions abstractes
- Treballa amb text, formes, imatges, degradats, fons en mosaic i gràfics SVG
- Edita text enriquit amb tipus de lletra propis, variants, espaiat, alineació i mides
- Ajusta la col·locació, l'ajust automàtic, les capes, el retall i la rotació al llenç
- Gestiona les substitucions de text i d'imatge de cada mercat
- Fes servir idiomes predefinits, tradueix automàticament el text que falta i controla el progrés de la traducció
- Exporta captures en PNG o JPEG a carpetes per idioma i per fila
- Crea exportacions de presentació per a xarxes socials, webs i previsualitzacions de campanya
- Puja les captures directament a App Store Connect
- Revisa i edita les metadades d'App Store Connect abans de pujar-les
- Rep notificacions quan acabin les exportacions i les pujades a la botiga
- Mantén els projectes en local per defecte, sincronitza'ls amb iCloud si ho actives i crea còpies de seguretat en ZIP
- Sense seguiment

Screenshot Bro està pensat per a desenvolupadors independents, equips de producte, dissenyadors i responsables de màrqueting que necessiten més control que un generador de captures bàsic i un flux de treball més ràpid que refer a mà cada imatge de màrqueting.

Tant si prepares un primer llançament com una actualització important, una campanya de temporada o el desplegament d'un nou idioma, Screenshot Bro t'ajuda a passar de les captures en brut a les imatges llestes per a la botiga més de pressa i amb més coherència.

Si necessites un creador de captures per a l'App Store, un constructor de plantilles, una eina de localització de captures o un carregador per a App Store Connect, Screenshot Bro concentra tot el flux de treball en una sola aplicació.

Condicions d'ús (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["sl-SI"] = """\
Screenshot Bro je generator posnetkov zaslona za App Store. Celoten nabor posnetkov oblikujete enkrat, dodate okvirje naprav, vsak naslov lokalizirate za vse trge, na katerih objavljate, in naložite naravnost v App Store Connect – ne da bi zapustili Mac.

Za razliko od splošnih orodij za oblikovanje Screenshot Bro pozna vrstice za posamezne naprave, lokalizacijo, nalaganje v App Store Connect, paketne izvoze, projekte za večkratno uporabo in lokalno avtomatizacijo s pomočniki AI prek Model Context Protocol.

Sestavite celotne nabore posnetkov za iPhone, iPad in Mac. Začnite s predlogo ali zgradite lasten sistem postavitev. Dodajte posnetke zaslona, uporabite okvirje naprav ali kompozicije brez okvirjev, napišite naslove in podnapise, oblikujte besedilo z lastnimi pisavami in na platnu izpilite vsako podrobnost.

Screenshot Bro lahko na Macu gosti lokalni strežnik MCP. Povežite združljivega pomočnika, kot so Claude Code, Claude Desktop, Cursor ali drug odjemalec, in mu prepustite ustvarjanje projektov, urejanje vrstic, razporejanje oblik, uvoz posnetkov zaslona, prevajanje besedila, izris predogledov platna in izvoz končnih slik. MCP je izbiren, privzeto izklopljen, dostopen samo lokalno in zaščiten z žetonom.

Različice izdaj, prilagoditve za posamezne jezike, načrte vrstic za posamezne trgovine in gradivo, pripravljeno za izvoz, hranite v enem projektu za App Store, spletne strani, družbena omrežja in lansirne kampanje.

Ključne funkcije:

- Ustvarite posnetke zaslona za App Store iz enega projekta
- Uporabite vgrajene predloge ali lastne postavitve za ponavljajoče se izdaje
- Oblikujte vrstice z več posnetki, primerjalne postavitve in celotne kampanje
- Paketno uvozite posnetke zaslona v vrstice in hitro zamenjajte slike
- Dodajte okvirje naprav za iPhone, iPad, Mac in abstraktne postavitve
- Delajte z besedilom, oblikami, slikami, prelivi, ponavljajočimi se ozadji in grafiko SVG
- Urejajte oblikovano besedilo z lastnimi pisavami, različicami pisav, razmiki, poravnavo in velikostmi
- Postavitev, pripenjanje, plasti, obrezovanje in vrtenje prilagajajte neposredno na platnu
- Upravljajte prilagoditve besedila in slik za vsak trg posebej
- Uporabite prednastavitve jezikov, samodejno prevedite manjkajoče besedilo in spremljajte napredek prevodov
- Izvozite posnetke zaslona v PNG ali JPEG v mape po jeziku in vrstici
- Ustvarite predstavitvene izvoze za objave na družbenih omrežjih, spletne strani in predoglede kampanj
- Naložite posnetke zaslona neposredno v App Store Connect
- Pred nalaganjem preglejte in uredite metapodatke v App Store Connect
- V enem koraku naložite posnetke zaslona za iOS in Mac v App Store Connect
- Povežite združljivega pomočnika MCP, ki Screenshot Bro upravlja lokalno
- Prejmite obvestila o dokončanih izvozih in nalaganjih v trgovino
- Projekti so privzeto lokalni, po želji jih sinhronizirate prek iCloud in shranite v varnostne kopije ZIP
- Odprite shrambo projektov in mape z izvozi v Finderju
- Brez sledenja

Screenshot Bro je namenjen samostojnim razvijalcem, produktnim ekipam, oblikovalcem in tržnikom, ki potrebujejo več nadzora, kot ga ponuja osnovni generator posnetkov zaslona, in hitrejši potek dela od ročnega sestavljanja vsake tržne slike.

Ne glede na to, ali pripravljate prvi izid, večjo posodobitev, sezonsko kampanjo ali uvedbo novih jezikov, vam Screenshot Bro pomaga hitreje in bolj dosledno priti od surovih posnetkov zaslona do tržnih slik, pripravljenih za trgovino.

Če iščete orodje za izdelavo posnetkov zaslona za App Store, urejevalnik predlog, orodje za lokalizacijo posnetkov, nalagalnik v App Store Connect ali avtomatizacijo prek MCP, Screenshot Bro združi celoten potek dela v eni osredotočeni aplikaciji za Mac.

Pogoji uporabe (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["sl-SI"] = """\
Screenshot Bro je urejevalnik in generator posnetkov zaslona, izdelan posebej za posnetke zaslona za App Store. Ustvarite predloge za večkratno uporabo, oblikujte celotne nabore posnetkov, lokalizirajte sporočilo ter izvozite ali naložite dodelano gradivo za trgovino.

Za razliko od splošnih orodij za oblikovanje Screenshot Bro pozna vrstice za posamezne naprave, lokalizacijo, nalaganje v App Store Connect, paketne izvoze in projekte za večkratno uporabo.

Sestavite celotne nabore posnetkov za iPhone, iPad in Mac. Začnite s predlogo ali zgradite lasten sistem postavitev. Dodajte posnetke zaslona, uporabite okvirje naprav ali kompozicije brez okvirjev, napišite naslove in podnapise, oblikujte besedilo z lastnimi pisavami in na platnu izpilite vsako podrobnost.

Različice izdaj, prilagoditve za posamezne jezike, načrte vrstic za posamezne trgovine in gradivo, pripravljeno za izvoz, hranite v enem projektu za App Store, spletne strani, družbena omrežja in lansirne kampanje.

Ključne funkcije:

- Ustvarite posnetke zaslona za App Store iz enega projekta
- Uporabite vgrajene predloge ali lastne postavitve za ponavljajoče se izdaje
- Oblikujte vrstice z več posnetki, primerjalne postavitve in celotne kampanje
- Paketno uvozite posnetke zaslona v vrstice in hitro zamenjajte slike
- Dodajte okvirje naprav za iPhone, iPad, Mac in abstraktne postavitve
- Delajte z besedilom, oblikami, slikami, prelivi, ponavljajočimi se ozadji in grafiko SVG
- Urejajte oblikovano besedilo z lastnimi pisavami, različicami pisav, razmiki, poravnavo in velikostmi
- Postavitev, pripenjanje, plasti, obrezovanje in vrtenje prilagajajte neposredno na platnu
- Upravljajte prilagoditve besedila in slik za vsak trg posebej
- Uporabite prednastavitve jezikov, samodejno prevedite manjkajoče besedilo in spremljajte napredek prevodov
- Izvozite posnetke zaslona v PNG ali JPEG v mape po jeziku in vrstici
- Ustvarite predstavitvene izvoze za objave na družbenih omrežjih, spletne strani in predoglede kampanj
- Naložite posnetke zaslona neposredno v App Store Connect
- Pred nalaganjem preglejte in uredite metapodatke v App Store Connect
- Prejmite obvestila o dokončanih izvozih in nalaganjih v trgovino
- Projekti so privzeto lokalni, po želji jih sinhronizirate prek iCloud in shranite v varnostne kopije ZIP
- Brez sledenja

Screenshot Bro je namenjen samostojnim razvijalcem, produktnim ekipam, oblikovalcem in tržnikom, ki potrebujejo več nadzora, kot ga ponuja osnovni generator posnetkov zaslona, in hitrejši potek dela od ročnega sestavljanja vsake tržne slike.

Ne glede na to, ali pripravljate prvi izid, večjo posodobitev, sezonsko kampanjo ali uvedbo novih jezikov, vam Screenshot Bro pomaga hitreje in bolj dosledno priti od surovih posnetkov zaslona do tržnih slik, pripravljenih za trgovino.

Če iščete orodje za izdelavo posnetkov zaslona za App Store, urejevalnik predlog, orodje za lokalizacijo posnetkov ali nalagalnik v App Store Connect, Screenshot Bro združi celoten potek dela v eni osredotočeni aplikaciji.

Pogoji uporabe (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["ms"] = """\
Screenshot Bro ialah penjana tangkapan skrin aplikasi untuk App Store. Reka satu set tangkapan skrin yang lengkap sekali sahaja, tambah bingkai peranti, setempatkan setiap tajuk untuk setiap pasaran yang anda terbitkan, dan muat naik terus ke App Store Connect — tanpa meninggalkan Mac anda.

Tidak seperti alat reka bentuk umum, Screenshot Bro memahami baris khusus peranti, penyetempatan, muat naik ke App Store Connect, eksport pukal, projek boleh guna semula, dan automasi pembantu AI tempatan melalui Model Context Protocol.

Bina set tangkapan skrin yang lengkap untuk iPhone, iPad, dan Mac. Mulakan daripada templat atau bina sistem susun atur anda sendiri. Masukkan tangkapan skrin, tambah bingkai peranti atau komposisi tanpa bingkai, tulis tajuk dan kapsyen, gayakan teks kaya dengan fon tersuai, dan perhalusi setiap butiran pada kanvas.

Screenshot Bro boleh menjalankan pelayan MCP tempatan pada Mac anda. Sambungkan pembantu yang serasi MCP seperti Claude Code, Claude Desktop, Cursor, atau klien lain, dan biarkan ia mencipta projek, menyunting baris, menyusun bentuk, mengimport tangkapan skrin, menterjemah teks, memaparkan pratonton kanvas, dan mengeksport imej akhir. MCP ialah pilihan, dimatikan secara lalai, hanya menerima sambungan tempatan, dan dilindungi token akses.

Simpan varian keluaran, gantian mengikut bahasa, pelan baris mengikut gedung, dan aset sedia eksport dalam satu projek — untuk App Store, tapak web, media sosial, dan kempen pelancaran.

Ciri utama:

- Cipta tangkapan skrin App Store daripada satu projek
- Guna templat terbina dalam atau susun atur tersuai untuk pelancaran berulang
- Reka baris berbilang gambar, susun atur perbandingan, dan kempen penuh
- Import tangkapan skrin secara pukal ke dalam baris dan ganti imej dengan pantas
- Tambah bingkai peranti untuk iPhone, iPad, Mac, dan susun atur abstrak
- Olah teks, bentuk, imej, kecerunan, latar berjubin, dan grafik SVG
- Sunting teks kaya dengan fon tersuai, varian fon, jarak, penjajaran, dan saiz
- Laraskan kedudukan, snap, lapisan, pemangkasan, dan putaran terus pada kanvas
- Urus teks dan imej gantian mengikut bahasa untuk setiap pasaran
- Guna pratetap bahasa, terjemah teks yang tiada secara automatik, dan jejaki kemajuannya
- Eksport tangkapan skrin PNG atau JPEG ke folder mengikut bahasa dan baris
- Cipta eksport pameran untuk pos sosial, tapak web, dan pratonton kempen
- Muat naik tangkapan skrin terus ke App Store Connect
- Semak dan sunting metadata App Store Connect sebelum memuat naik
- Simpan projek secara tempatan, segerakkan dengan iCloud apabila diaktifkan, dan buat sandaran ZIP
- Tiada penjejakan

Screenshot Bro dibina untuk pembangun indie, pasukan produk, pereka, dan pemasar yang memerlukan lebih kawalan daripada penjana tangkapan skrin biasa dan aliran kerja yang lebih pantas daripada membina semula setiap imej pemasaran aplikasi secara manual.

Jika anda memerlukan pencipta tangkapan skrin App Store, pembina templat tangkapan skrin, alat penyetempatan tangkapan skrin, pemuat naik App Store Connect, atau alat automasi tangkapan skrin sedia MCP, Screenshot Bro mengekalkan keseluruhan aliran kerja dalam satu aplikasi Mac yang fokus.

Syarat Penggunaan (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["ms"] = """\
Screenshot Bro ialah pencipta dan penyunting tangkapan skrin yang dibina khas untuk tangkapan skrin App Store. Cipta templat boleh guna semula, reka set tangkapan skrin yang lengkap, setempatkan mesej anda, kemudian eksport atau muat naik aset gedung yang kemas.

Tidak seperti alat reka bentuk umum, Screenshot Bro memahami baris khusus peranti, penyetempatan, muat naik ke App Store Connect, eksport pukal, dan projek boleh guna semula.

Bina set tangkapan skrin yang lengkap untuk iPhone, iPad, dan Mac. Mulakan daripada templat atau bina sistem susun atur anda sendiri. Masukkan tangkapan skrin, tambah bingkai peranti atau komposisi tanpa bingkai, tulis tajuk dan kapsyen, gayakan teks kaya dengan fon tersuai, dan perhalusi setiap butiran pada kanvas.

Simpan varian keluaran, gantian mengikut bahasa, pelan baris mengikut gedung, dan aset sedia eksport dalam satu projek — untuk App Store, tapak web, media sosial, dan kempen pelancaran.

Ciri utama:

- Cipta tangkapan skrin App Store daripada satu projek
- Guna templat terbina dalam atau susun atur tersuai untuk pelancaran berulang
- Reka baris berbilang gambar, susun atur perbandingan, dan kempen penuh
- Import tangkapan skrin secara pukal ke dalam baris dan ganti imej dengan pantas
- Tambah bingkai peranti untuk iPhone, iPad, Mac, dan susun atur abstrak
- Olah teks, bentuk, imej, kecerunan, latar berjubin, dan grafik SVG
- Sunting teks kaya dengan fon tersuai, varian fon, jarak, penjajaran, dan saiz
- Laraskan kedudukan, snap, lapisan, pemangkasan, dan putaran terus pada kanvas
- Urus teks dan imej gantian mengikut bahasa untuk setiap pasaran
- Guna pratetap bahasa, terjemah teks yang tiada secara automatik, dan jejaki kemajuannya
- Eksport tangkapan skrin PNG atau JPEG ke folder mengikut bahasa dan baris
- Cipta eksport pameran untuk pos sosial, tapak web, dan pratonton kempen
- Muat naik tangkapan skrin terus ke App Store Connect
- Semak dan sunting metadata App Store Connect sebelum memuat naik
- Dapatkan pemberitahuan apabila eksport dan muat naik ke gedung selesai
- Simpan projek secara tempatan, segerakkan dengan iCloud apabila diaktifkan, dan buat sandaran ZIP
- Tiada penjejakan

Screenshot Bro dibina untuk pembangun indie, pasukan produk, pereka, dan pemasar yang memerlukan lebih kawalan daripada penjana tangkapan skrin biasa dan aliran kerja yang lebih pantas daripada membina semula setiap imej pemasaran aplikasi secara manual.

Sama ada anda sedang menyiapkan pelancaran pertama, kemas kini besar, kempen bermusim, atau perluasan ke bahasa baharu, Screenshot Bro membantu anda beralih daripada tangkapan skrin mentah kepada imej pemasaran sedia gedung dengan lebih pantas dan lebih konsisten.

Jika anda memerlukan pencipta tangkapan skrin App Store, pembina templat tangkapan skrin, alat penyetempatan tangkapan skrin, atau pemuat naik App Store Connect, Screenshot Bro mengekalkan keseluruhan aliran kerja dalam satu aplikasi yang fokus.

Syarat Penggunaan (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["hi"] = """\
Screenshot Bro, App Store के लिए ऐप स्क्रीनशॉट बनाने वाला ऐप है। पूरा स्क्रीनशॉट सेट एक बार डिज़ाइन करें, डिवाइस फ़्रेम जोड़ें, हर बाज़ार के लिए हर हेडलाइन का अनुवाद करें, और सीधे App Store Connect पर अपलोड करें — अपने Mac से बाहर निकले बिना।

आम डिज़ाइन टूल के उलट, Screenshot Bro डिवाइस-विशिष्ट पंक्तियों, लोकलाइज़ेशन, App Store Connect अपलोड, बैच एक्सपोर्ट, दोबारा इस्तेमाल होने वाले प्रोजेक्ट, और Model Context Protocol के ज़रिए लोकल AI असिस्टेंट ऑटोमेशन को समझता है।

iPhone, iPad और Mac लेआउट के लिए पूरे स्क्रीनशॉट सेट बनाएँ। किसी टेम्प्लेट से शुरू करें या अपना लेआउट सिस्टम बनाएँ। स्क्रीनशॉट डालें, डिवाइस फ़्रेम या बिना फ़्रेम वाली कंपोज़िशन जोड़ें, हेडलाइन और कैप्शन लिखें, कस्टम फ़ॉन्ट के साथ रिच टेक्स्ट स्टाइल करें, और कैनवस पर हर बारीकी सँवारें।

Screenshot Bro आपके Mac पर एक लोकल MCP सर्वर चला सकता है। Claude Code, Claude Desktop, Cursor या किसी दूसरे MCP-संगत असिस्टेंट को जोड़ें और उसे प्रोजेक्ट बनाने, पंक्तियाँ संपादित करने, आकृतियाँ व्यवस्थित करने, स्क्रीनशॉट इंपोर्ट करने, टेक्स्ट का अनुवाद करने, कैनवस प्रीव्यू रेंडर करने और अंतिम इमेज एक्सपोर्ट करने दें। MCP वैकल्पिक है, डिफ़ॉल्ट रूप से बंद रहता है, सिर्फ़ लोकल कनेक्शन लेता है, और एक्सेस टोकन से सुरक्षित है।

रिलीज़ वेरिएंट, भाषा-विशिष्ट ओवरराइड, स्टोर-विशिष्ट पंक्ति योजनाएँ और एक्सपोर्ट के लिए तैयार एसेट — सब कुछ एक ही प्रोजेक्ट में रखें, App Store, वेबसाइट, सोशल मीडिया और लॉन्च कैंपेन के लिए।

मुख्य विशेषताएँ:

- एक ही प्रोजेक्ट से App Store स्क्रीनशॉट बनाएँ
- बार-बार होने वाले लॉन्च के लिए बिल्ट-इन टेम्प्लेट या अपने लेआउट इस्तेमाल करें
- मल्टी-शॉट पंक्तियाँ, तुलना वाले लेआउट और पूरे कैंपेन डिज़ाइन करें
- पंक्तियों में स्क्रीनशॉट बैच-इंपोर्ट करें और इमेज तेज़ी से बदलें
- iPhone, iPad, Mac और एब्स्ट्रैक्ट लेआउट के लिए डिवाइस फ़्रेम जोड़ें
- टेक्स्ट, आकृतियाँ, इमेज, ग्रेडिएंट, टाइल वाले बैकग्राउंड और SVG ग्राफ़िक्स के साथ काम करें
- कस्टम फ़ॉन्ट, फ़ॉन्ट वेरिएंट, स्पेसिंग, अलाइनमेंट और साइज़ कंट्रोल के साथ रिच टेक्स्ट संपादित करें
- कैनवस पर ही प्लेसमेंट, स्नैपिंग, लेयरिंग, क्रॉपिंग और रोटेशन एडजस्ट करें
- हर बाज़ार के लिए भाषा-विशिष्ट टेक्स्ट और इमेज ओवरराइड मैनेज करें
- लोकेल प्रीसेट इस्तेमाल करें, छूटे हुए टेक्स्ट का अपने-आप अनुवाद कराएँ और प्रगति देखें
- PNG या JPEG स्क्रीनशॉट भाषा और पंक्ति के हिसाब से फ़ोल्डर में एक्सपोर्ट करें
- सोशल पोस्ट, वेबसाइट और कैंपेन प्रीव्यू के लिए शोकेस एक्सपोर्ट बनाएँ
- स्क्रीनशॉट सीधे App Store Connect पर अपलोड करें
- अपलोड से पहले App Store Connect मेटाडेटा देखें और संपादित करें
- प्रोजेक्ट लोकल रखें, ज़रूरत हो तो iCloud से सिंक करें, और ZIP बैकअप बनाएँ
- कोई ट्रैकिंग नहीं

Screenshot Bro उन इंडी डेवलपर, प्रोडक्ट टीम, डिज़ाइनर और मार्केटर के लिए बना है जिन्हें आम स्क्रीनशॉट जेनरेटर से ज़्यादा नियंत्रण चाहिए और हर मार्केटिंग इमेज दोबारा हाथ से बनाने के मुक़ाबले तेज़ वर्कफ़्लो चाहिए।

अगर आपको App Store स्क्रीनशॉट क्रिएटर, स्क्रीनशॉट टेम्प्लेट बिल्डर, स्क्रीनशॉट लोकलाइज़ेशन टूल, App Store Connect अपलोडर, या MCP-रेडी स्क्रीनशॉट ऑटोमेशन टूल चाहिए, तो Screenshot Bro पूरा वर्कफ़्लो एक ही फ़ोकस्ड Mac ऐप में रखता है।

उपयोग की शर्तें (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["hi"] = """\
Screenshot Bro एक स्क्रीनशॉट मेकर और एडिटर है, जो खास तौर पर App Store स्क्रीनशॉट के लिए बना है। दोबारा इस्तेमाल होने वाले टेम्प्लेट बनाएँ, पूरा स्क्रीनशॉट सेट डिज़ाइन करें, अपना संदेश हर भाषा में ढालें, फिर तैयार स्टोर एसेट एक्सपोर्ट करें या अपलोड करें।

आम डिज़ाइन टूल के उलट, Screenshot Bro डिवाइस-विशिष्ट पंक्तियों, लोकलाइज़ेशन, App Store Connect अपलोड, बैच एक्सपोर्ट और दोबारा इस्तेमाल होने वाले प्रोजेक्ट को समझता है।

iPhone, iPad और Mac लेआउट के लिए पूरे स्क्रीनशॉट सेट बनाएँ। किसी टेम्प्लेट से शुरू करें या अपना लेआउट सिस्टम बनाएँ। स्क्रीनशॉट डालें, डिवाइस फ़्रेम या बिना फ़्रेम वाली कंपोज़िशन जोड़ें, हेडलाइन और कैप्शन लिखें, कस्टम फ़ॉन्ट के साथ रिच टेक्स्ट स्टाइल करें, और कैनवस पर हर बारीकी सँवारें।

रिलीज़ वेरिएंट, भाषा-विशिष्ट ओवरराइड, स्टोर-विशिष्ट पंक्ति योजनाएँ और एक्सपोर्ट के लिए तैयार एसेट — सब कुछ एक ही प्रोजेक्ट में रखें, App Store, वेबसाइट, सोशल मीडिया और लॉन्च कैंपेन के लिए।

मुख्य विशेषताएँ:

- एक ही प्रोजेक्ट से App Store स्क्रीनशॉट बनाएँ
- बार-बार होने वाले लॉन्च के लिए बिल्ट-इन टेम्प्लेट या अपने लेआउट इस्तेमाल करें
- मल्टी-शॉट पंक्तियाँ, तुलना वाले लेआउट और पूरे कैंपेन डिज़ाइन करें
- पंक्तियों में स्क्रीनशॉट बैच-इंपोर्ट करें और इमेज तेज़ी से बदलें
- iPhone, iPad, Mac और एब्स्ट्रैक्ट लेआउट के लिए डिवाइस फ़्रेम जोड़ें
- टेक्स्ट, आकृतियाँ, इमेज, ग्रेडिएंट, टाइल वाले बैकग्राउंड और SVG ग्राफ़िक्स के साथ काम करें
- कस्टम फ़ॉन्ट, फ़ॉन्ट वेरिएंट, स्पेसिंग, अलाइनमेंट और साइज़ कंट्रोल के साथ रिच टेक्स्ट संपादित करें
- कैनवस पर ही प्लेसमेंट, स्नैपिंग, लेयरिंग, क्रॉपिंग और रोटेशन एडजस्ट करें
- हर बाज़ार के लिए भाषा-विशिष्ट टेक्स्ट और इमेज ओवरराइड मैनेज करें
- लोकेल प्रीसेट इस्तेमाल करें, छूटे हुए टेक्स्ट का अपने-आप अनुवाद कराएँ और प्रगति देखें
- PNG या JPEG स्क्रीनशॉट भाषा और पंक्ति के हिसाब से फ़ोल्डर में एक्सपोर्ट करें
- सोशल पोस्ट, वेबसाइट और कैंपेन प्रीव्यू के लिए शोकेस एक्सपोर्ट बनाएँ
- स्क्रीनशॉट सीधे App Store Connect पर अपलोड करें
- अपलोड से पहले App Store Connect मेटाडेटा देखें और संपादित करें
- एक्सपोर्ट और स्टोर अपलोड पूरा होने पर नोटिफ़िकेशन पाएँ
- प्रोजेक्ट लोकल रखें, ज़रूरत हो तो iCloud से सिंक करें, और ZIP बैकअप बनाएँ
- कोई ट्रैकिंग नहीं

Screenshot Bro उन इंडी डेवलपर, प्रोडक्ट टीम, डिज़ाइनर और मार्केटर के लिए बना है जिन्हें आम स्क्रीनशॉट जेनरेटर से ज़्यादा नियंत्रण चाहिए और हर मार्केटिंग इमेज दोबारा हाथ से बनाने के मुक़ाबले तेज़ वर्कफ़्लो चाहिए।

चाहे आप पहला लॉन्च तैयार कर रहे हों, बड़ा अपडेट, सीज़नल कैंपेन, या नई भाषाओं में विस्तार, Screenshot Bro आपको कच्चे स्क्रीनशॉट से स्टोर-रेडी मार्केटिंग इमेज तक तेज़ी से और ज़्यादा एकरूपता के साथ पहुँचाता है।

अगर आपको App Store स्क्रीनशॉट क्रिएटर, स्क्रीनशॉट टेम्प्लेट बिल्डर, स्क्रीनशॉट लोकलाइज़ेशन टूल, या App Store Connect अपलोडर चाहिए, तो Screenshot Bro पूरा वर्कफ़्लो एक ही फ़ोकस्ड ऐप में रखता है।

उपयोग की शर्तें (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["mr-IN"] = """\
Screenshot Bro हे App Store साठी अ‍ॅप स्क्रीनशॉट तयार करणारे अ‍ॅप आहे. संपूर्ण स्क्रीनशॉट संच एकदाच डिझाइन करा, डिव्हाइस फ्रेम जोडा, तुम्ही प्रकाशित करत असलेल्या प्रत्येक बाजारपेठेसाठी प्रत्येक मथळा भाषांतरित करा आणि थेट App Store Connect वर अपलोड करा — तुमचा Mac न सोडता.

सर्वसाधारण डिझाइन साधनांपेक्षा वेगळे, Screenshot Bro डिव्हाइसनुसार ओळी, स्थानिकीकरण, App Store Connect अपलोड, बॅच एक्सपोर्ट, पुन्हा वापरता येणारे प्रकल्प आणि Model Context Protocol द्वारे स्थानिक AI सहाय्यक ऑटोमेशन समजून घेते.

iPhone, iPad आणि Mac मांडणीसाठी संपूर्ण स्क्रीनशॉट संच तयार करा. एखाद्या टेम्प्लेटपासून सुरुवात करा किंवा स्वतःची मांडणी प्रणाली तयार करा. स्क्रीनशॉट टाका, डिव्हाइस फ्रेम किंवा फ्रेमशिवाय रचना जोडा, मथळे आणि मजकूर लिहा, कस्टम फॉन्टसह रिच टेक्स्टला शैली द्या आणि कॅनव्हासवर प्रत्येक तपशील नीट जुळवा.

Screenshot Bro तुमच्या Mac वर स्थानिक MCP सर्व्हर चालवू शकते. Claude Code, Claude Desktop, Cursor किंवा इतर MCP-सुसंगत सहाय्यक जोडा आणि त्याला प्रकल्प तयार करू द्या, ओळी संपादित करू द्या, आकार मांडू द्या, स्क्रीनशॉट आयात करू द्या, मजकूर भाषांतरित करू द्या, कॅनव्हास पूर्वावलोकन तयार करू द्या आणि अंतिम प्रतिमा एक्सपोर्ट करू द्या. MCP ऐच्छिक आहे, सुरुवातीला बंद असते, फक्त स्थानिक जोडणी स्वीकारते आणि अ‍ॅक्सेस टोकनने संरक्षित असते.

प्रकाशनाचे प्रकार, भाषेनुसार बदल, स्टोअरनुसार ओळींच्या योजना आणि एक्सपोर्टसाठी तयार सामग्री — सर्व काही एकाच प्रकल्पात ठेवा, App Store, संकेतस्थळे, समाजमाध्यमे आणि प्रकाशन मोहिमांसाठी.

मुख्य वैशिष्ट्ये:

- एकाच प्रकल्पातून App Store स्क्रीनशॉट तयार करा
- वारंवार होणाऱ्या प्रकाशनांसाठी अंगभूत टेम्प्लेट किंवा स्वतःची मांडणी वापरा
- अनेक प्रतिमांच्या ओळी, तुलनात्मक मांडणी आणि संपूर्ण मोहिमा रचा
- ओळींमध्ये स्क्रीनशॉट एकत्रितपणे आयात करा आणि प्रतिमा झटपट बदला
- iPhone, iPad, Mac आणि अमूर्त मांडणीसाठी डिव्हाइस फ्रेम जोडा
- मजकूर, आकार, प्रतिमा, रंगछटा, फरशीसारखी पार्श्वभूमी आणि SVG ग्राफिक्ससह काम करा
- कस्टम फॉन्ट, फॉन्ट प्रकार, अंतर, संरेखन आणि आकारासह रिच टेक्स्ट संपादित करा
- कॅनव्हासवरच स्थान, स्नॅपिंग, थर, कापणी आणि फिरवणे जुळवा
- प्रत्येक बाजारपेठेसाठी भाषेनुसार मजकूर आणि प्रतिमा बदल सांभाळा
- भाषा प्रीसेट वापरा, राहिलेला मजकूर आपोआप भाषांतरित करा आणि प्रगती पाहा
- PNG किंवा JPEG स्क्रीनशॉट भाषेनुसार आणि ओळीनुसार फोल्डरमध्ये एक्सपोर्ट करा
- समाजमाध्यम पोस्ट, संकेतस्थळे आणि मोहीम पूर्वावलोकनांसाठी शोकेस एक्सपोर्ट तयार करा
- स्क्रीनशॉट थेट App Store Connect वर अपलोड करा
- अपलोड करण्यापूर्वी App Store Connect मेटाडेटा तपासा आणि संपादित करा
- प्रकल्प स्थानिक ठेवा, गरज असल्यास iCloud शी समक्रमित करा आणि ZIP बॅकअप तयार करा
- कोणताही मागोवा नाही

Screenshot Bro अशा इंडी डेव्हलपर, उत्पादन संघ, डिझायनर आणि विपणकांसाठी बनवले आहे ज्यांना सामान्य स्क्रीनशॉट जनरेटरपेक्षा अधिक नियंत्रण हवे आहे आणि प्रत्येक विपणन प्रतिमा हाताने पुन्हा बनवण्यापेक्षा वेगवान कार्यपद्धती हवी आहे.

तुम्हाला App Store स्क्रीनशॉट निर्माता, स्क्रीनशॉट टेम्प्लेट बिल्डर, स्क्रीनशॉट स्थानिकीकरण साधन, App Store Connect अपलोडर किंवा MCP-सज्ज स्क्रीनशॉट ऑटोमेशन साधन हवे असल्यास, Screenshot Bro संपूर्ण कार्यपद्धती एकाच नेमक्या Mac अ‍ॅपमध्ये ठेवते.

वापराच्या अटी (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["mr-IN"] = """\
Screenshot Bro हे App Store स्क्रीनशॉटसाठी खास बनवलेले स्क्रीनशॉट निर्माते आणि संपादक आहे. पुन्हा वापरता येणारे टेम्प्लेट तयार करा, संपूर्ण स्क्रीनशॉट संच रचा, तुमचा संदेश प्रत्येक भाषेत मांडा आणि नंतर तयार स्टोअर सामग्री एक्सपोर्ट करा किंवा अपलोड करा.

सर्वसाधारण डिझाइन साधनांपेक्षा वेगळे, Screenshot Bro डिव्हाइसनुसार ओळी, स्थानिकीकरण, App Store Connect अपलोड, बॅच एक्सपोर्ट आणि पुन्हा वापरता येणारे प्रकल्प समजून घेते.

iPhone, iPad आणि Mac मांडणीसाठी संपूर्ण स्क्रीनशॉट संच तयार करा. एखाद्या टेम्प्लेटपासून सुरुवात करा किंवा स्वतःची मांडणी प्रणाली तयार करा. स्क्रीनशॉट टाका, डिव्हाइस फ्रेम किंवा फ्रेमशिवाय रचना जोडा, मथळे आणि मजकूर लिहा, कस्टम फॉन्टसह रिच टेक्स्टला शैली द्या आणि कॅनव्हासवर प्रत्येक तपशील नीट जुळवा.

प्रकाशनाचे प्रकार, भाषेनुसार बदल, स्टोअरनुसार ओळींच्या योजना आणि एक्सपोर्टसाठी तयार सामग्री — सर्व काही एकाच प्रकल्पात ठेवा, App Store, संकेतस्थळे, समाजमाध्यमे आणि प्रकाशन मोहिमांसाठी.

मुख्य वैशिष्ट्ये:

- एकाच प्रकल्पातून App Store स्क्रीनशॉट तयार करा
- वारंवार होणाऱ्या प्रकाशनांसाठी अंगभूत टेम्प्लेट किंवा स्वतःची मांडणी वापरा
- अनेक प्रतिमांच्या ओळी, तुलनात्मक मांडणी आणि संपूर्ण मोहिमा रचा
- ओळींमध्ये स्क्रीनशॉट एकत्रितपणे आयात करा आणि प्रतिमा झटपट बदला
- iPhone, iPad, Mac आणि अमूर्त मांडणीसाठी डिव्हाइस फ्रेम जोडा
- मजकूर, आकार, प्रतिमा, रंगछटा, फरशीसारखी पार्श्वभूमी आणि SVG ग्राफिक्ससह काम करा
- कस्टम फॉन्ट, फॉन्ट प्रकार, अंतर, संरेखन आणि आकारासह रिच टेक्स्ट संपादित करा
- कॅनव्हासवरच स्थान, स्नॅपिंग, थर, कापणी आणि फिरवणे जुळवा
- प्रत्येक बाजारपेठेसाठी भाषेनुसार मजकूर आणि प्रतिमा बदल सांभाळा
- भाषा प्रीसेट वापरा, राहिलेला मजकूर आपोआप भाषांतरित करा आणि प्रगती पाहा
- PNG किंवा JPEG स्क्रीनशॉट भाषेनुसार आणि ओळीनुसार फोल्डरमध्ये एक्सपोर्ट करा
- समाजमाध्यम पोस्ट, संकेतस्थळे आणि मोहीम पूर्वावलोकनांसाठी शोकेस एक्सपोर्ट तयार करा
- स्क्रीनशॉट थेट App Store Connect वर अपलोड करा
- अपलोड करण्यापूर्वी App Store Connect मेटाडेटा तपासा आणि संपादित करा
- एक्सपोर्ट आणि स्टोअर अपलोड पूर्ण झाल्यावर सूचना मिळवा
- प्रकल्प स्थानिक ठेवा, गरज असल्यास iCloud शी समक्रमित करा आणि ZIP बॅकअप तयार करा
- कोणताही मागोवा नाही

Screenshot Bro अशा इंडी डेव्हलपर, उत्पादन संघ, डिझायनर आणि विपणकांसाठी बनवले आहे ज्यांना सामान्य स्क्रीनशॉट जनरेटरपेक्षा अधिक नियंत्रण हवे आहे आणि प्रत्येक विपणन प्रतिमा हाताने पुन्हा बनवण्यापेक्षा वेगवान कार्यपद्धती हवी आहे.

तुम्ही पहिले प्रकाशन तयार करत असाल, मोठे अद्यतन, हंगामी मोहीम किंवा नव्या भाषांमधील विस्तार — Screenshot Bro तुम्हाला कच्च्या स्क्रीनशॉटपासून स्टोअरसाठी तयार विपणन प्रतिमांपर्यंत अधिक वेगाने आणि अधिक सुसंगतपणे नेते.

तुम्हाला App Store स्क्रीनशॉट निर्माता, स्क्रीनशॉट टेम्प्लेट बिल्डर, स्क्रीनशॉट स्थानिकीकरण साधन किंवा App Store Connect अपलोडर हवे असल्यास, Screenshot Bro संपूर्ण कार्यपद्धती एकाच नेमक्या अ‍ॅपमध्ये ठेवते.

वापराच्या अटी (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["bn-BD"] = """\
Screenshot Bro হলো App Store-এর জন্য অ্যাপ স্ক্রিনশট তৈরির অ্যাপ। পুরো স্ক্রিনশট সেট একবারই ডিজাইন করুন, ডিভাইস ফ্রেম যোগ করুন, আপনি যেসব বাজারে প্রকাশ করেন তার প্রতিটির জন্য প্রতিটি শিরোনাম অনুবাদ করুন এবং সরাসরি App Store Connect-এ আপলোড করুন — Mac ছেড়ে না গিয়েই।

সাধারণ ডিজাইন টুলের চেয়ে আলাদা, Screenshot Bro ডিভাইস-নির্দিষ্ট সারি, স্থানীয়করণ, App Store Connect আপলোড, ব্যাচ এক্সপোর্ট, পুনর্ব্যবহারযোগ্য প্রকল্প এবং Model Context Protocol-এর মাধ্যমে স্থানীয় AI সহকারী অটোমেশন বোঝে।

iPhone, iPad এবং Mac লেআউটের জন্য সম্পূর্ণ স্ক্রিনশট সেট তৈরি করুন। কোনো টেমপ্লেট থেকে শুরু করুন বা নিজের লেআউট ব্যবস্থা গড়ে তুলুন। স্ক্রিনশট বসান, ডিভাইস ফ্রেম বা ফ্রেমবিহীন কম্পোজিশন যোগ করুন, শিরোনাম ও ক্যাপশন লিখুন, কাস্টম ফন্ট দিয়ে রিচ টেক্সট সাজান এবং ক্যানভাসে প্রতিটি খুঁটিনাটি নিখুঁত করুন।

Screenshot Bro আপনার Mac-এ একটি স্থানীয় MCP সার্ভার চালাতে পারে। Claude Code, Claude Desktop, Cursor বা অন্য কোনো MCP-সমর্থিত সহকারী যুক্ত করুন এবং তাকে প্রকল্প তৈরি করতে, সারি সম্পাদনা করতে, আকার সাজাতে, স্ক্রিনশট আমদানি করতে, লেখা অনুবাদ করতে, ক্যানভাস প্রিভিউ রেন্ডার করতে এবং চূড়ান্ত ছবি এক্সপোর্ট করতে দিন। MCP ঐচ্ছিক, ডিফল্টভাবে বন্ধ থাকে, কেবল স্থানীয় সংযোগ নেয় এবং অ্যাক্সেস টোকেন দিয়ে সুরক্ষিত।

রিলিজ ভ্যারিয়েন্ট, ভাষাভিত্তিক পরিবর্তন, স্টোরভিত্তিক সারির পরিকল্পনা এবং এক্সপোর্টের জন্য প্রস্তুত উপকরণ — সবকিছু একটি প্রকল্পেই রাখুন, App Store, ওয়েবসাইট, সামাজিক মাধ্যম এবং প্রচারাভিযানের জন্য।

প্রধান বৈশিষ্ট্য:

- একটি প্রকল্প থেকেই App Store স্ক্রিনশট তৈরি করুন
- বারবার প্রকাশের জন্য বিল্ট-ইন টেমপ্লেট বা নিজের লেআউট ব্যবহার করুন
- একাধিক ছবির সারি, তুলনামূলক লেআউট এবং পূর্ণাঙ্গ প্রচারাভিযান ডিজাইন করুন
- সারিতে স্ক্রিনশট একসঙ্গে আমদানি করুন এবং ছবি দ্রুত বদলান
- iPhone, iPad, Mac এবং বিমূর্ত লেআউটের জন্য ডিভাইস ফ্রেম যোগ করুন
- লেখা, আকার, ছবি, গ্রেডিয়েন্ট, টাইল করা পটভূমি এবং SVG গ্রাফিক্স নিয়ে কাজ করুন
- কাস্টম ফন্ট, ফন্ট ভ্যারিয়েন্ট, ব্যবধান, সারিবদ্ধতা এবং আকারসহ রিচ টেক্সট সম্পাদনা করুন
- ক্যানভাসেই অবস্থান, স্ন্যাপিং, স্তর, ছাঁটাই এবং ঘূর্ণন সমন্বয় করুন
- প্রতিটি বাজারের জন্য ভাষাভিত্তিক লেখা ও ছবির পরিবর্তন সামলান
- ভাষা প্রিসেট ব্যবহার করুন, বাদ পড়া লেখা স্বয়ংক্রিয়ভাবে অনুবাদ করান এবং অগ্রগতি দেখুন
- PNG বা JPEG স্ক্রিনশট ভাষা ও সারি অনুযায়ী ফোল্ডারে এক্সপোর্ট করুন
- সামাজিক পোস্ট, ওয়েবসাইট এবং প্রচারাভিযানের প্রিভিউয়ের জন্য শোকেস এক্সপোর্ট তৈরি করুন
- স্ক্রিনশট সরাসরি App Store Connect-এ আপলোড করুন
- আপলোডের আগে App Store Connect মেটাডেটা দেখুন ও সম্পাদনা করুন
- প্রকল্প স্থানীয়ভাবে রাখুন, প্রয়োজনে iCloud-এ সিঙ্ক করুন এবং ZIP ব্যাকআপ তৈরি করুন
- কোনো ট্র্যাকিং নেই

Screenshot Bro তৈরি হয়েছে সেইসব ইন্ডি ডেভেলপার, প্রোডাক্ট টিম, ডিজাইনার এবং বিপণনকারীর জন্য, যাঁদের সাধারণ স্ক্রিনশট জেনারেটরের চেয়ে বেশি নিয়ন্ত্রণ দরকার এবং প্রতিটি বিপণন ছবি হাতে নতুন করে বানানোর চেয়ে দ্রুত কর্মপ্রবাহ দরকার।

আপনার যদি App Store স্ক্রিনশট নির্মাতা, স্ক্রিনশট টেমপ্লেট বিল্ডার, স্ক্রিনশট স্থানীয়করণ টুল, App Store Connect আপলোডার বা MCP-প্রস্তুত স্ক্রিনশট অটোমেশন টুল দরকার হয়, Screenshot Bro পুরো কর্মপ্রবাহ একটি নিবিষ্ট Mac অ্যাপেই রাখে।

ব্যবহারের শর্তাবলি (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["bn-BD"] = """\
Screenshot Bro হলো App Store স্ক্রিনশটের জন্য বিশেষভাবে তৈরি স্ক্রিনশট নির্মাতা ও সম্পাদক। পুনর্ব্যবহারযোগ্য টেমপ্লেট বানান, সম্পূর্ণ স্ক্রিনশট সেট ডিজাইন করুন, আপনার বার্তা প্রতিটি ভাষায় সাজান, তারপর প্রস্তুত স্টোর উপকরণ এক্সপোর্ট বা আপলোড করুন।

সাধারণ ডিজাইন টুলের চেয়ে আলাদা, Screenshot Bro ডিভাইস-নির্দিষ্ট সারি, স্থানীয়করণ, App Store Connect আপলোড, ব্যাচ এক্সপোর্ট এবং পুনর্ব্যবহারযোগ্য প্রকল্প বোঝে।

iPhone, iPad এবং Mac লেআউটের জন্য সম্পূর্ণ স্ক্রিনশট সেট তৈরি করুন। কোনো টেমপ্লেট থেকে শুরু করুন বা নিজের লেআউট ব্যবস্থা গড়ে তুলুন। স্ক্রিনশট বসান, ডিভাইস ফ্রেম বা ফ্রেমবিহীন কম্পোজিশন যোগ করুন, শিরোনাম ও ক্যাপশন লিখুন, কাস্টম ফন্ট দিয়ে রিচ টেক্সট সাজান এবং ক্যানভাসে প্রতিটি খুঁটিনাটি নিখুঁত করুন।

রিলিজ ভ্যারিয়েন্ট, ভাষাভিত্তিক পরিবর্তন, স্টোরভিত্তিক সারির পরিকল্পনা এবং এক্সপোর্টের জন্য প্রস্তুত উপকরণ — সবকিছু একটি প্রকল্পেই রাখুন, App Store, ওয়েবসাইট, সামাজিক মাধ্যম এবং প্রচারাভিযানের জন্য।

প্রধান বৈশিষ্ট্য:

- একটি প্রকল্প থেকেই App Store স্ক্রিনশট তৈরি করুন
- বারবার প্রকাশের জন্য বিল্ট-ইন টেমপ্লেট বা নিজের লেআউট ব্যবহার করুন
- একাধিক ছবির সারি, তুলনামূলক লেআউট এবং পূর্ণাঙ্গ প্রচারাভিযান ডিজাইন করুন
- সারিতে স্ক্রিনশট একসঙ্গে আমদানি করুন এবং ছবি দ্রুত বদলান
- iPhone, iPad, Mac এবং বিমূর্ত লেআউটের জন্য ডিভাইস ফ্রেম যোগ করুন
- লেখা, আকার, ছবি, গ্রেডিয়েন্ট, টাইল করা পটভূমি এবং SVG গ্রাফিক্স নিয়ে কাজ করুন
- কাস্টম ফন্ট, ফন্ট ভ্যারিয়েন্ট, ব্যবধান, সারিবদ্ধতা এবং আকারসহ রিচ টেক্সট সম্পাদনা করুন
- ক্যানভাসেই অবস্থান, স্ন্যাপিং, স্তর, ছাঁটাই এবং ঘূর্ণন সমন্বয় করুন
- প্রতিটি বাজারের জন্য ভাষাভিত্তিক লেখা ও ছবির পরিবর্তন সামলান
- ভাষা প্রিসেট ব্যবহার করুন, বাদ পড়া লেখা স্বয়ংক্রিয়ভাবে অনুবাদ করান এবং অগ্রগতি দেখুন
- PNG বা JPEG স্ক্রিনশট ভাষা ও সারি অনুযায়ী ফোল্ডারে এক্সপোর্ট করুন
- সামাজিক পোস্ট, ওয়েবসাইট এবং প্রচারাভিযানের প্রিভিউয়ের জন্য শোকেস এক্সপোর্ট তৈরি করুন
- স্ক্রিনশট সরাসরি App Store Connect-এ আপলোড করুন
- আপলোডের আগে App Store Connect মেটাডেটা দেখুন ও সম্পাদনা করুন
- এক্সপোর্ট ও স্টোর আপলোড শেষ হলে বিজ্ঞপ্তি পান
- প্রকল্প স্থানীয়ভাবে রাখুন, প্রয়োজনে iCloud-এ সিঙ্ক করুন এবং ZIP ব্যাকআপ তৈরি করুন
- কোনো ট্র্যাকিং নেই

Screenshot Bro তৈরি হয়েছে সেইসব ইন্ডি ডেভেলপার, প্রোডাক্ট টিম, ডিজাইনার এবং বিপণনকারীর জন্য, যাঁদের সাধারণ স্ক্রিনশট জেনারেটরের চেয়ে বেশি নিয়ন্ত্রণ দরকার এবং প্রতিটি বিপণন ছবি হাতে নতুন করে বানানোর চেয়ে দ্রুত কর্মপ্রবাহ দরকার।

আপনি প্রথম প্রকাশের প্রস্তুতি নিন, বড় হালনাগাদ, মৌসুমি প্রচারাভিযান বা নতুন ভাষায় বিস্তার — Screenshot Bro আপনাকে কাঁচা স্ক্রিনশট থেকে স্টোরের জন্য প্রস্তুত বিপণন ছবি পর্যন্ত দ্রুততর ও আরও সুসংগতভাবে পৌঁছে দেয়।

আপনার যদি App Store স্ক্রিনশট নির্মাতা, স্ক্রিনশট টেমপ্লেট বিল্ডার, স্ক্রিনশট স্থানীয়করণ টুল বা App Store Connect আপলোডার দরকার হয়, Screenshot Bro পুরো কর্মপ্রবাহ একটি নিবিষ্ট অ্যাপেই রাখে।

ব্যবহারের শর্তাবলি (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["gu-IN"] = """\
Screenshot Bro એ App Store માટે ઍપ સ્ક્રીનશોટ બનાવતી ઍપ છે. આખો સ્ક્રીનશોટ સેટ એક જ વાર ડિઝાઇન કરો, ડિવાઇસ ફ્રેમ ઉમેરો, તમે જે દરેક બજારમાં પ્રકાશિત કરો છો તેના માટે દરેક હેડલાઇનનું ભાષાંતર કરો અને સીધા App Store Connect પર અપલોડ કરો — તમારો Mac છોડ્યા વગર.

સામાન્ય ડિઝાઇન સાધનોથી અલગ, Screenshot Bro ડિવાઇસ પ્રમાણેની હરોળ, સ્થાનિકીકરણ, App Store Connect અપલોડ, બૅચ એક્સપોર્ટ, ફરી વાપરી શકાય તેવા પ્રોજેક્ટ અને Model Context Protocol દ્વારા સ્થાનિક AI સહાયક ઑટોમેશન સમજે છે.

iPhone, iPad અને Mac લેઆઉટ માટે સંપૂર્ણ સ્ક્રીનશોટ સેટ બનાવો. કોઈ ટેમ્પ્લેટથી શરૂ કરો અથવા તમારી પોતાની લેઆઉટ પદ્ધતિ ઘડો. સ્ક્રીનશોટ મૂકો, ડિવાઇસ ફ્રેમ કે ફ્રેમ વગરની રચના ઉમેરો, હેડલાઇન અને કૅપ્શન લખો, કસ્ટમ ફોન્ટ સાથે રિચ ટેક્સ્ટને શૈલી આપો અને કૅનવાસ પર દરેક વિગત સુધારો.

Screenshot Bro તમારા Mac પર સ્થાનિક MCP સર્વર ચલાવી શકે છે. Claude Code, Claude Desktop, Cursor કે બીજું કોઈ MCP-સુસંગત સહાયક જોડો અને તેને પ્રોજેક્ટ બનાવવા, હરોળ સંપાદિત કરવા, આકાર ગોઠવવા, સ્ક્રીનશોટ આયાત કરવા, લખાણનું ભાષાંતર કરવા, કૅનવાસ પૂર્વાવલોકન રેન્ડર કરવા અને અંતિમ છબીઓ એક્સપોર્ટ કરવા દો. MCP વૈકલ્પિક છે, મૂળભૂત રીતે બંધ રહે છે, ફક્ત સ્થાનિક જોડાણ સ્વીકારે છે અને ઍક્સેસ ટોકનથી સુરક્ષિત છે.

રિલીઝ પ્રકારો, ભાષા પ્રમાણેના ફેરફારો, સ્ટોર પ્રમાણેની હરોળ યોજનાઓ અને એક્સપોર્ટ માટે તૈયાર સામગ્રી — બધું એક જ પ્રોજેક્ટમાં રાખો, App Store, વેબસાઇટ, સામાજિક માધ્યમો અને લૉન્ચ ઝુંબેશ માટે.

મુખ્ય વિશેષતાઓ:

- એક જ પ્રોજેક્ટમાંથી App Store સ્ક્રીનશોટ બનાવો
- વારંવારના લૉન્ચ માટે બિલ્ટ-ઇન ટેમ્પ્લેટ કે તમારા પોતાના લેઆઉટ વાપરો
- અનેક છબીવાળી હરોળ, સરખામણી લેઆઉટ અને આખી ઝુંબેશ ડિઝાઇન કરો
- હરોળમાં સ્ક્રીનશોટ એકસાથે આયાત કરો અને છબીઓ ઝડપથી બદલો
- iPhone, iPad, Mac અને અમૂર્ત લેઆઉટ માટે ડિવાઇસ ફ્રેમ ઉમેરો
- લખાણ, આકાર, છબીઓ, ગ્રેડિયન્ટ, ટાઇલવાળી પૃષ્ઠભૂમિ અને SVG ગ્રાફિક્સ સાથે કામ કરો
- કસ્ટમ ફોન્ટ, ફોન્ટ પ્રકાર, અંતર, સંરેખણ અને કદ સાથે રિચ ટેક્સ્ટ સંપાદિત કરો
- કૅનવાસ પર જ સ્થાન, સ્નૅપિંગ, સ્તર, કાપણી અને પરિભ્રમણ ગોઠવો
- દરેક બજાર માટે ભાષા પ્રમાણેના લખાણ અને છબીના ફેરફારો સંભાળો
- ભાષા પ્રીસેટ વાપરો, બાકી રહેલું લખાણ આપમેળે ભાષાંતરિત કરાવો અને પ્રગતિ જુઓ
- PNG કે JPEG સ્ક્રીનશોટ ભાષા અને હરોળ પ્રમાણે ફોલ્ડરમાં એક્સપોર્ટ કરો
- સામાજિક પોસ્ટ, વેબસાઇટ અને ઝુંબેશ પૂર્વાવલોકન માટે શોકેસ એક્સપોર્ટ બનાવો
- સ્ક્રીનશોટ સીધા App Store Connect પર અપલોડ કરો
- અપલોડ પહેલાં App Store Connect મેટાડેટા તપાસો અને સંપાદિત કરો
- પ્રોજેક્ટ સ્થાનિક રાખો, જરૂર પડ્યે iCloud સાથે સિંક કરો અને ZIP બૅકઅપ બનાવો
- કોઈ ટ્રેકિંગ નહીં

Screenshot Bro એવા ઇન્ડી ડેવલપર, પ્રોડક્ટ ટીમ, ડિઝાઇનર અને માર્કેટર માટે બન્યું છે જેમને સામાન્ય સ્ક્રીનશોટ જનરેટર કરતાં વધુ નિયંત્રણ જોઈએ છે અને દરેક માર્કેટિંગ છબી હાથે ફરી બનાવવા કરતાં ઝડપી કાર્યપ્રવાહ જોઈએ છે.

જો તમને App Store સ્ક્રીનશોટ સર્જક, સ્ક્રીનશોટ ટેમ્પ્લેટ બિલ્ડર, સ્ક્રીનશોટ સ્થાનિકીકરણ સાધન, App Store Connect અપલોડર કે MCP-સજ્જ સ્ક્રીનશોટ ઑટોમેશન સાધન જોઈએ, તો Screenshot Bro આખો કાર્યપ્રવાહ એક જ કેન્દ્રિત Mac ઍપમાં રાખે છે.

વપરાશની શરતો (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["gu-IN"] = """\
Screenshot Bro એ App Store સ્ક્રીનશોટ માટે ખાસ બનાવેલ સ્ક્રીનશોટ સર્જક અને સંપાદક છે. ફરી વાપરી શકાય તેવા ટેમ્પ્લેટ બનાવો, સંપૂર્ણ સ્ક્રીનશોટ સેટ ડિઝાઇન કરો, તમારો સંદેશ દરેક ભાષામાં ઢાળો, પછી તૈયાર સ્ટોર સામગ્રી એક્સપોર્ટ કરો કે અપલોડ કરો.

સામાન્ય ડિઝાઇન સાધનોથી અલગ, Screenshot Bro ડિવાઇસ પ્રમાણેની હરોળ, સ્થાનિકીકરણ, App Store Connect અપલોડ, બૅચ એક્સપોર્ટ અને ફરી વાપરી શકાય તેવા પ્રોજેક્ટ સમજે છે.

iPhone, iPad અને Mac લેઆઉટ માટે સંપૂર્ણ સ્ક્રીનશોટ સેટ બનાવો. કોઈ ટેમ્પ્લેટથી શરૂ કરો અથવા તમારી પોતાની લેઆઉટ પદ્ધતિ ઘડો. સ્ક્રીનશોટ મૂકો, ડિવાઇસ ફ્રેમ કે ફ્રેમ વગરની રચના ઉમેરો, હેડલાઇન અને કૅપ્શન લખો, કસ્ટમ ફોન્ટ સાથે રિચ ટેક્સ્ટને શૈલી આપો અને કૅનવાસ પર દરેક વિગત સુધારો.

રિલીઝ પ્રકારો, ભાષા પ્રમાણેના ફેરફારો, સ્ટોર પ્રમાણેની હરોળ યોજનાઓ અને એક્સપોર્ટ માટે તૈયાર સામગ્રી — બધું એક જ પ્રોજેક્ટમાં રાખો, App Store, વેબસાઇટ, સામાજિક માધ્યમો અને લૉન્ચ ઝુંબેશ માટે.

મુખ્ય વિશેષતાઓ:

- એક જ પ્રોજેક્ટમાંથી App Store સ્ક્રીનશોટ બનાવો
- વારંવારના લૉન્ચ માટે બિલ્ટ-ઇન ટેમ્પ્લેટ કે તમારા પોતાના લેઆઉટ વાપરો
- અનેક છબીવાળી હરોળ, સરખામણી લેઆઉટ અને આખી ઝુંબેશ ડિઝાઇન કરો
- હરોળમાં સ્ક્રીનશોટ એકસાથે આયાત કરો અને છબીઓ ઝડપથી બદલો
- iPhone, iPad, Mac અને અમૂર્ત લેઆઉટ માટે ડિવાઇસ ફ્રેમ ઉમેરો
- લખાણ, આકાર, છબીઓ, ગ્રેડિયન્ટ, ટાઇલવાળી પૃષ્ઠભૂમિ અને SVG ગ્રાફિક્સ સાથે કામ કરો
- કસ્ટમ ફોન્ટ, ફોન્ટ પ્રકાર, અંતર, સંરેખણ અને કદ સાથે રિચ ટેક્સ્ટ સંપાદિત કરો
- કૅનવાસ પર જ સ્થાન, સ્નૅપિંગ, સ્તર, કાપણી અને પરિભ્રમણ ગોઠવો
- દરેક બજાર માટે ભાષા પ્રમાણેના લખાણ અને છબીના ફેરફારો સંભાળો
- ભાષા પ્રીસેટ વાપરો, બાકી રહેલું લખાણ આપમેળે ભાષાંતરિત કરાવો અને પ્રગતિ જુઓ
- PNG કે JPEG સ્ક્રીનશોટ ભાષા અને હરોળ પ્રમાણે ફોલ્ડરમાં એક્સપોર્ટ કરો
- સામાજિક પોસ્ટ, વેબસાઇટ અને ઝુંબેશ પૂર્વાવલોકન માટે શોકેસ એક્સપોર્ટ બનાવો
- સ્ક્રીનશોટ સીધા App Store Connect પર અપલોડ કરો
- અપલોડ પહેલાં App Store Connect મેટાડેટા તપાસો અને સંપાદિત કરો
- એક્સપોર્ટ અને સ્ટોર અપલોડ પૂરાં થાય ત્યારે સૂચના મેળવો
- પ્રોજેક્ટ સ્થાનિક રાખો, જરૂર પડ્યે iCloud સાથે સિંક કરો અને ZIP બૅકઅપ બનાવો
- કોઈ ટ્રેકિંગ નહીં

Screenshot Bro એવા ઇન્ડી ડેવલપર, પ્રોડક્ટ ટીમ, ડિઝાઇનર અને માર્કેટર માટે બન્યું છે જેમને સામાન્ય સ્ક્રીનશોટ જનરેટર કરતાં વધુ નિયંત્રણ જોઈએ છે અને દરેક માર્કેટિંગ છબી હાથે ફરી બનાવવા કરતાં ઝડપી કાર્યપ્રવાહ જોઈએ છે.

તમે પહેલું લૉન્ચ તૈયાર કરતા હો, મોટું અપડેટ, મોસમી ઝુંબેશ કે નવી ભાષાઓમાં વિસ્તાર — Screenshot Bro તમને કાચા સ્ક્રીનશોટથી સ્ટોર માટે તૈયાર માર્કેટિંગ છબીઓ સુધી વધુ ઝડપથી અને વધુ સુસંગતતા સાથે લઈ જાય છે.

જો તમને App Store સ્ક્રીનશોટ સર્જક, સ્ક્રીનશોટ ટેમ્પ્લેટ બિલ્ડર, સ્ક્રીનશોટ સ્થાનિકીકરણ સાધન કે App Store Connect અપલોડર જોઈએ, તો Screenshot Bro આખો કાર્યપ્રવાહ એક જ કેન્દ્રિત ઍપમાં રાખે છે.

વપરાશની શરતો (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["ta-IN"] = """\
Screenshot Bro என்பது App Store-க்கான ஆப் ஸ்கிரீன்ஷாட் உருவாக்கும் செயலி. முழு ஸ்கிரீன்ஷாட் தொகுப்பையும் ஒரே முறை வடிவமைத்து, சாதன சட்டங்களைச் சேர்த்து, நீங்கள் வெளியிடும் ஒவ்வொரு சந்தைக்கும் ஒவ்வொரு தலைப்பையும் மொழிபெயர்த்து, நேரடியாக App Store Connect-க்கு பதிவேற்றுங்கள் — உங்கள் Mac-ஐ விட்டு வெளியேறாமல்.

பொதுவான வடிவமைப்புக் கருவிகளைப் போலல்லாமல், Screenshot Bro சாதனவாரியான வரிசைகள், உள்ளூர்மயமாக்கல், App Store Connect பதிவேற்றங்கள், தொகுப்பு ஏற்றுமதிகள், மீண்டும் பயன்படுத்தக்கூடிய திட்டங்கள், Model Context Protocol வழியாக உள்ளூர் AI உதவியாளர் தன்னியக்கம் ஆகியவற்றைப் புரிந்துகொள்கிறது.

iPhone, iPad மற்றும் Mac தளவமைப்புகளுக்கு முழுமையான ஸ்கிரீன்ஷாட் தொகுப்புகளை உருவாக்குங்கள். ஒரு வார்ப்புருவிலிருந்து தொடங்குங்கள் அல்லது உங்கள் சொந்த தளவமைப்பு முறையை உருவாக்குங்கள். ஸ்கிரீன்ஷாட்களைச் சேர்த்து, சாதன சட்டங்கள் அல்லது சட்டமில்லாத அமைப்புகளைச் சேர்த்து, தலைப்புகளையும் விளக்கங்களையும் எழுதி, தனிப்பயன் எழுத்துருக்களுடன் வளமான உரையை வடிவமைத்து, கேன்வாஸில் ஒவ்வொரு நுணுக்கத்தையும் செம்மைப்படுத்துங்கள்.

Screenshot Bro உங்கள் Mac-இல் உள்ளூர் MCP சேவையகத்தை இயக்க முடியும். Claude Code, Claude Desktop, Cursor அல்லது பிற MCP-இணக்க உதவியாளரை இணைத்து, திட்டங்களை உருவாக்கவும், வரிசைகளைத் திருத்தவும், வடிவங்களை ஒழுங்கமைக்கவும், ஸ்கிரீன்ஷாட்களை இறக்குமதி செய்யவும், உரையை மொழிபெயர்க்கவும், கேன்வாஸ் முன்னோட்டங்களை உருவாக்கவும், இறுதிப் படங்களை ஏற்றுமதி செய்யவும் அனுமதியுங்கள். MCP விருப்பத்தேர்வானது, இயல்பாக அணைந்திருக்கும், உள்ளூர் இணைப்புகளை மட்டுமே ஏற்கும், அணுகல் டோக்கனால் பாதுகாக்கப்படுகிறது.

வெளியீட்டு வகைகள், மொழிவாரியான மாற்றங்கள், கடைவாரியான வரிசைத் திட்டங்கள், ஏற்றுமதிக்குத் தயாரான சொத்துகள் — அனைத்தையும் ஒரே திட்டத்தில் வையுங்கள்: App Store, இணையதளங்கள், சமூக ஊடகங்கள், அறிமுகப் பிரச்சாரங்களுக்காக.

முக்கிய அம்சங்கள்:

- ஒரே திட்டத்திலிருந்து App Store ஸ்கிரீன்ஷாட்களை உருவாக்குங்கள்
- மீண்டும் வரும் வெளியீடுகளுக்கு உள்ளமைந்த வார்ப்புருக்கள் அல்லது சொந்த தளவமைப்புகளைப் பயன்படுத்துங்கள்
- பல படங்கள் கொண்ட வரிசைகள், ஒப்பீட்டுத் தளவமைப்புகள் மற்றும் முழுப் பிரச்சாரங்களை வடிவமைக்குங்கள்
- வரிசைகளுக்குள் ஸ்கிரீன்ஷாட்களைத் தொகுப்பாக இறக்குமதி செய்து படங்களை விரைவாக மாற்றுங்கள்
- iPhone, iPad, Mac மற்றும் சுருக்கத் தளவமைப்புகளுக்கு சாதன சட்டங்களைச் சேர்க்குங்கள்
- உரை, வடிவங்கள், படங்கள், சாய்வுகள், ஓடு போன்ற பின்னணிகள் மற்றும் SVG வரைகலையுடன் வேலை செய்யுங்கள்
- தனிப்பயன் எழுத்துருக்கள், எழுத்துரு வகைகள், இடைவெளி, சீரமைப்பு மற்றும் அளவுடன் வளமான உரையைத் திருத்துங்கள்
- கேன்வாஸிலேயே இடம், ஸ்னாப்பிங், அடுக்குகள், வெட்டுதல் மற்றும் சுழற்சியைச் சரிசெய்யுங்கள்
- ஒவ்வொரு சந்தைக்கும் மொழிவாரியான உரை மற்றும் பட மாற்றங்களை நிர்வகியுங்கள்
- மொழி முன்னமைவுகளைப் பயன்படுத்தி, விடுபட்ட உரையைத் தானாக மொழிபெயர்த்து, முன்னேற்றத்தைக் காணுங்கள்
- PNG அல்லது JPEG ஸ்கிரீன்ஷாட்களை மொழி மற்றும் வரிசை வாரியாக கோப்புறைகளில் ஏற்றுமதி செய்யுங்கள்
- சமூக இடுகைகள், இணையதளங்கள் மற்றும் பிரச்சார முன்னோட்டங்களுக்கு காட்சி ஏற்றுமதிகளை உருவாக்குங்கள்
- ஸ்கிரீன்ஷாட்களை நேரடியாக App Store Connect-க்கு பதிவேற்றுங்கள்
- பதிவேற்றுவதற்கு முன் App Store Connect மேனிலைத் தரவைப் பார்த்துத் திருத்துங்கள்
- திட்டங்களை உள்ளூரில் வைத்து, தேவைப்படும்போது iCloud-உடன் ஒத்திசைத்து, ZIP காப்புப்பிரதிகளை உருவாக்குங்கள்
- எந்தக் கண்காணிப்பும் இல்லை

சாதாரண ஸ்கிரீன்ஷாட் உருவாக்கியை விட அதிகக் கட்டுப்பாடு, ஒவ்வொரு படத்தையும் கையால் மீண்டும் உருவாக்குவதை விட வேகமான பணிமுறை தேவைப்படும் இண்டி டெவலப்பர்கள், தயாரிப்புக் குழுக்கள், வடிவமைப்பாளர்கள், சந்தைப்படுத்துபவர்களுக்காக Screenshot Bro உருவாக்கப்பட்டது.

உங்களுக்கு App Store ஸ்கிரீன்ஷாட் உருவாக்கி, ஸ்கிரீன்ஷாட் வார்ப்புரு கட்டமைப்பான், ஸ்கிரீன்ஷாட் உள்ளூர்மயமாக்கல் கருவி, App Store Connect பதிவேற்றி, அல்லது MCP-தயார் ஸ்கிரீன்ஷாட் தன்னியக்கக் கருவி தேவைப்பட்டால், Screenshot Bro முழுப் பணிமுறையையும் ஒரே கவனம் செலுத்திய Mac செயலியில் வைத்திருக்கிறது.

பயன்பாட்டு விதிமுறைகள் (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["ta-IN"] = """\
Screenshot Bro என்பது App Store ஸ்கிரீன்ஷாட்களுக்காகவே உருவாக்கப்பட்ட ஸ்கிரீன்ஷாட் உருவாக்கி மற்றும் திருத்தி. மீண்டும் பயன்படுத்தக்கூடிய வார்ப்புருக்களை உருவாக்குங்கள், முழுமையான ஸ்கிரீன்ஷாட் தொகுப்புகளை வடிவமைக்குங்கள், உங்கள் செய்தியை ஒவ்வொரு மொழியிலும் அமைத்து, பின்னர் தயாரான கடைச் சொத்துகளை ஏற்றுமதி செய்யுங்கள் அல்லது பதிவேற்றுங்கள்.

பொதுவான வடிவமைப்புக் கருவிகளைப் போலல்லாமல், Screenshot Bro சாதனவாரியான வரிசைகள், உள்ளூர்மயமாக்கல், App Store Connect பதிவேற்றங்கள், தொகுப்பு ஏற்றுமதிகள் மற்றும் மீண்டும் பயன்படுத்தக்கூடிய திட்டங்களைப் புரிந்துகொள்கிறது.

iPhone, iPad மற்றும் Mac தளவமைப்புகளுக்கு முழுமையான ஸ்கிரீன்ஷாட் தொகுப்புகளை உருவாக்குங்கள். ஒரு வார்ப்புருவிலிருந்து தொடங்குங்கள் அல்லது உங்கள் சொந்த தளவமைப்பு முறையை உருவாக்குங்கள். ஸ்கிரீன்ஷாட்களைச் சேர்த்து, சாதன சட்டங்கள் அல்லது சட்டமில்லாத அமைப்புகளைச் சேர்த்து, தலைப்புகளையும் விளக்கங்களையும் எழுதி, தனிப்பயன் எழுத்துருக்களுடன் வளமான உரையை வடிவமைத்து, கேன்வாஸில் ஒவ்வொரு நுணுக்கத்தையும் செம்மைப்படுத்துங்கள்.

வெளியீட்டு வகைகள், மொழிவாரியான மாற்றங்கள், கடைவாரியான வரிசைத் திட்டங்கள், ஏற்றுமதிக்குத் தயாரான சொத்துகள் — அனைத்தையும் ஒரே திட்டத்தில் வையுங்கள்: App Store, இணையதளங்கள், சமூக ஊடகங்கள், அறிமுகப் பிரச்சாரங்களுக்காக.

முக்கிய அம்சங்கள்:

- ஒரே திட்டத்திலிருந்து App Store ஸ்கிரீன்ஷாட்களை உருவாக்குங்கள்
- மீண்டும் வரும் வெளியீடுகளுக்கு உள்ளமைந்த வார்ப்புருக்கள் அல்லது சொந்த தளவமைப்புகளைப் பயன்படுத்துங்கள்
- பல படங்கள் கொண்ட வரிசைகள், ஒப்பீட்டுத் தளவமைப்புகள் மற்றும் முழுப் பிரச்சாரங்களை வடிவமைக்குங்கள்
- வரிசைகளுக்குள் ஸ்கிரீன்ஷாட்களைத் தொகுப்பாக இறக்குமதி செய்து படங்களை விரைவாக மாற்றுங்கள்
- iPhone, iPad, Mac மற்றும் சுருக்கத் தளவமைப்புகளுக்கு சாதன சட்டங்களைச் சேர்க்குங்கள்
- உரை, வடிவங்கள், படங்கள், சாய்வுகள், ஓடு போன்ற பின்னணிகள் மற்றும் SVG வரைகலையுடன் வேலை செய்யுங்கள்
- தனிப்பயன் எழுத்துருக்கள், எழுத்துரு வகைகள், இடைவெளி, சீரமைப்பு மற்றும் அளவுடன் வளமான உரையைத் திருத்துங்கள்
- கேன்வாஸிலேயே இடம், ஸ்னாப்பிங், அடுக்குகள், வெட்டுதல் மற்றும் சுழற்சியைச் சரிசெய்யுங்கள்
- ஒவ்வொரு சந்தைக்கும் மொழிவாரியான உரை மற்றும் பட மாற்றங்களை நிர்வகியுங்கள்
- மொழி முன்னமைவுகளைப் பயன்படுத்தி, விடுபட்ட உரையைத் தானாக மொழிபெயர்த்து, முன்னேற்றத்தைக் காணுங்கள்
- PNG அல்லது JPEG ஸ்கிரீன்ஷாட்களை மொழி மற்றும் வரிசை வாரியாக கோப்புறைகளில் ஏற்றுமதி செய்யுங்கள்
- சமூக இடுகைகள், இணையதளங்கள் மற்றும் பிரச்சார முன்னோட்டங்களுக்கு காட்சி ஏற்றுமதிகளை உருவாக்குங்கள்
- ஸ்கிரீன்ஷாட்களை நேரடியாக App Store Connect-க்கு பதிவேற்றுங்கள்
- பதிவேற்றுவதற்கு முன் App Store Connect மேனிலைத் தரவைப் பார்த்துத் திருத்துங்கள்
- ஏற்றுமதிகள் மற்றும் கடைப் பதிவேற்றங்கள் முடிந்ததும் அறிவிப்புகளைப் பெறுங்கள்
- திட்டங்களை உள்ளூரில் வைத்து, தேவைப்படும்போது iCloud-உடன் ஒத்திசைத்து, ZIP காப்புப்பிரதிகளை உருவாக்குங்கள்
- எந்தக் கண்காணிப்பும் இல்லை

சாதாரண ஸ்கிரீன்ஷாட் உருவாக்கியை விட அதிகக் கட்டுப்பாடு, ஒவ்வொரு படத்தையும் கையால் மீண்டும் உருவாக்குவதை விட வேகமான பணிமுறை தேவைப்படும் இண்டி டெவலப்பர்கள், தயாரிப்புக் குழுக்கள், வடிவமைப்பாளர்கள், சந்தைப்படுத்துபவர்களுக்காக Screenshot Bro உருவாக்கப்பட்டது.

நீங்கள் முதல் அறிமுகத்தைத் தயாரித்தாலும், பெரிய புதுப்பிப்பாக இருந்தாலும், பருவகாலப் பிரச்சாரமாக இருந்தாலும், புதிய மொழிகளுக்கு விரிவாக்கமாக இருந்தாலும் — Screenshot Bro உங்களை மூலப் ஸ்கிரீன்ஷாட்களிலிருந்து கடைக்குத் தயாரான சந்தைப்படுத்தல் படங்களுக்கு வேகமாகவும் நிலைத்தன்மையுடனும் அழைத்துச் செல்கிறது.

உங்களுக்கு App Store ஸ்கிரீன்ஷாட் உருவாக்கி, ஸ்கிரீன்ஷாட் வார்ப்புரு கட்டமைப்பான், ஸ்கிரீன்ஷாட் உள்ளூர்மயமாக்கல் கருவி, அல்லது App Store Connect பதிவேற்றி தேவைப்பட்டால், Screenshot Bro முழுப் பணிமுறையையும் ஒரே கவனம் செலுத்திய செயலியில் வைத்திருக்கிறது.

பயன்பாட்டு விதிமுறைகள் (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["te-IN"] = """\
Screenshot Bro అనేది App Store కోసం యాప్ స్క్రీన్‌షాట్‌లను తయారుచేసే యాప్. పూర్తి స్క్రీన్‌షాట్ సెట్‌ను ఒకేసారి డిజైన్ చేయండి, పరికర ఫ్రేమ్‌లు జోడించండి, మీరు విడుదల చేసే ప్రతి మార్కెట్ కోసం ప్రతి శీర్షికను అనువదించండి, నేరుగా App Store Connect కు అప్‌లోడ్ చేయండి — మీ Mac ను వదిలి వెళ్లకుండానే.

సాధారణ డిజైన్ సాధనాల కంటే భిన్నంగా, Screenshot Bro పరికరాల వారీ వరుసలు, స్థానికీకరణ, App Store Connect అప్‌లోడ్‌లు, బ్యాచ్ ఎగుమతులు, పునర్వినియోగ ప్రాజెక్టులు, Model Context Protocol ద్వారా స్థానిక AI సహాయక ఆటోమేషన్‌ను అర్థం చేసుకుంటుంది.

iPhone, iPad, Mac లేఅవుట్‌ల కోసం పూర్తి స్క్రీన్‌షాట్ సెట్‌లను రూపొందించండి. ఒక టెంప్లేట్‌తో మొదలుపెట్టండి లేదా మీ సొంత లేఅవుట్ వ్యవస్థను నిర్మించండి. స్క్రీన్‌షాట్‌లు చేర్చండి, పరికర ఫ్రేమ్‌లు లేదా ఫ్రేమ్ లేని కూర్పులు జోడించండి, శీర్షికలు, వివరణలు రాయండి, కస్టమ్ ఫాంట్‌లతో రిచ్ టెక్స్ట్‌కు శైలి ఇవ్వండి, కాన్వాస్‌పై ప్రతి వివరాన్ని సరిచేయండి.

Screenshot Bro మీ Mac లో స్థానిక MCP సర్వర్‌ను నడపగలదు. Claude Code, Claude Desktop, Cursor లేదా ఇతర MCP-అనుకూల సహాయకాన్ని కలిపి, ప్రాజెక్టులు సృష్టించడం, వరుసలు సవరించడం, ఆకారాలు అమర్చడం, స్క్రీన్‌షాట్‌లు దిగుమతి చేయడం, వచనాన్ని అనువదించడం, కాన్వాస్ ప్రివ్యూలు రెండర్ చేయడం, తుది చిత్రాలను ఎగుమతి చేయడం చేయనివ్వండి. MCP ఐచ్ఛికం, డిఫాల్ట్‌గా ఆఫ్‌లో ఉంటుంది, స్థానిక కనెక్షన్‌లనే స్వీకరిస్తుంది, యాక్సెస్ టోకెన్‌తో రక్షితం.

విడుదల రకాలు, భాషల వారీ మార్పులు, స్టోర్ వారీ వరుస ప్రణాళికలు, ఎగుమతికి సిద్ధమైన సామగ్రి — అన్నీ ఒకే ప్రాజెక్టులో ఉంచండి: App Store, వెబ్‌సైట్లు, సామాజిక మాధ్యమాలు, విడుదల ప్రచారాల కోసం.

ముఖ్య లక్షణాలు:

- ఒకే ప్రాజెక్టు నుంచి App Store స్క్రీన్‌షాట్‌లు తయారు చేయండి
- పునరావృత విడుదలలకు అంతర్నిర్మిత టెంప్లేట్‌లు లేదా సొంత లేఅవుట్‌లు వాడండి
- బహుళ చిత్రాల వరుసలు, పోలిక లేఅవుట్‌లు, పూర్తి ప్రచారాలు డిజైన్ చేయండి
- వరుసల్లోకి స్క్రీన్‌షాట్‌లను గుంపుగా దిగుమతి చేసి చిత్రాలను వేగంగా మార్చండి
- iPhone, iPad, Mac, నైరూప్య లేఅవుట్‌లకు పరికర ఫ్రేమ్‌లు జోడించండి
- వచనం, ఆకారాలు, చిత్రాలు, గ్రేడియంట్‌లు, పలకల నేపథ్యాలు, SVG గ్రాఫిక్స్‌తో పని చేయండి
- కస్టమ్ ఫాంట్‌లు, ఫాంట్ రకాలు, అంతరం, సర్దుబాటు, పరిమాణంతో రిచ్ టెక్స్ట్ సవరించండి
- కాన్వాస్‌పైనే స్థానం, స్నాపింగ్, పొరలు, కత్తిరింపు, భ్రమణం సర్దండి
- ప్రతి మార్కెట్ కోసం భాషల వారీ వచనం, చిత్ర మార్పులు నిర్వహించండి
- భాషా ప్రీసెట్‌లు వాడండి, మిగిలిన వచనాన్ని ఆటోమేటిక్‌గా అనువదించండి, పురోగతి చూడండి
- PNG లేదా JPEG స్క్రీన్‌షాట్‌లను భాష, వరుస వారీగా ఫోల్డర్లలో ఎగుమతి చేయండి
- సామాజిక పోస్టులు, వెబ్‌సైట్లు, ప్రచార ప్రివ్యూల కోసం షోకేస్ ఎగుమతులు చేయండి
- స్క్రీన్‌షాట్‌లను నేరుగా App Store Connect కు అప్‌లోడ్ చేయండి
- అప్‌లోడ్ ముందు App Store Connect మెటాడేటాను చూసి సవరించండి
- ప్రాజెక్టులు స్థానికంగా ఉంచండి, అవసరమైతే iCloud తో సమకాలీకరించండి, ZIP బ్యాకప్‌లు చేయండి
- ఎలాంటి ట్రాకింగ్ లేదు

సాధారణ స్క్రీన్‌షాట్ జెనరేటర్ కంటే ఎక్కువ నియంత్రణ, ప్రతి చిత్రాన్ని చేతితో మళ్లీ తయారు చేయడం కంటే వేగవంతమైన పని విధానం కావాలనుకునే ఇండీ డెవలపర్లు, ఉత్పత్తి బృందాలు, డిజైనర్లు, మార్కెటర్ల కోసం Screenshot Bro రూపొందించబడింది.

మీకు App Store స్క్రీన్‌షాట్ సృష్టికర్త, స్క్రీన్‌షాట్ టెంప్లేట్ బిల్డర్, స్క్రీన్‌షాట్ స్థానికీకరణ సాధనం, App Store Connect అప్‌లోడర్, లేదా MCP-సిద్ధ స్క్రీన్‌షాట్ ఆటోమేషన్ సాధనం కావాలంటే, Screenshot Bro మొత్తం పని విధానాన్ని ఒకే కేంద్రీకృత Mac యాప్‌లో ఉంచుతుంది.

వినియోగ నిబంధనలు (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["te-IN"] = """\
Screenshot Bro అనేది App Store స్క్రీన్‌షాట్‌ల కోసమే రూపొందించిన స్క్రీన్‌షాట్ సృష్టికర్త, ఎడిటర్. పునర్వినియోగ టెంప్లేట్‌లు తయారు చేయండి, పూర్తి స్క్రీన్‌షాట్ సెట్‌లు డిజైన్ చేయండి, మీ సందేశాన్ని ప్రతి భాషలో అమర్చండి, ఆపై సిద్ధమైన స్టోర్ సామగ్రిని ఎగుమతి చేయండి లేదా అప్‌లోడ్ చేయండి.

సాధారణ డిజైన్ సాధనాల కంటే భిన్నంగా, Screenshot Bro పరికరాల వారీ వరుసలు, స్థానికీకరణ, App Store Connect అప్‌లోడ్‌లు, బ్యాచ్ ఎగుమతులు, పునర్వినియోగ ప్రాజెక్టులను అర్థం చేసుకుంటుంది.

iPhone, iPad, Mac లేఅవుట్‌ల కోసం పూర్తి స్క్రీన్‌షాట్ సెట్‌లను రూపొందించండి. ఒక టెంప్లేట్‌తో మొదలుపెట్టండి లేదా మీ సొంత లేఅవుట్ వ్యవస్థను నిర్మించండి. స్క్రీన్‌షాట్‌లు చేర్చండి, పరికర ఫ్రేమ్‌లు లేదా ఫ్రేమ్ లేని కూర్పులు జోడించండి, శీర్షికలు, వివరణలు రాయండి, కస్టమ్ ఫాంట్‌లతో రిచ్ టెక్స్ట్‌కు శైలి ఇవ్వండి, కాన్వాస్‌పై ప్రతి వివరాన్ని సరిచేయండి.

విడుదల రకాలు, భాషల వారీ మార్పులు, స్టోర్ వారీ వరుస ప్రణాళికలు, ఎగుమతికి సిద్ధమైన సామగ్రి — అన్నీ ఒకే ప్రాజెక్టులో ఉంచండి: App Store, వెబ్‌సైట్లు, సామాజిక మాధ్యమాలు, విడుదల ప్రచారాల కోసం.

ముఖ్య లక్షణాలు:

- ఒకే ప్రాజెక్టు నుంచి App Store స్క్రీన్‌షాట్‌లు తయారు చేయండి
- పునరావృత విడుదలలకు అంతర్నిర్మిత టెంప్లేట్‌లు లేదా సొంత లేఅవుట్‌లు వాడండి
- బహుళ చిత్రాల వరుసలు, పోలిక లేఅవుట్‌లు, పూర్తి ప్రచారాలు డిజైన్ చేయండి
- వరుసల్లోకి స్క్రీన్‌షాట్‌లను గుంపుగా దిగుమతి చేసి చిత్రాలను వేగంగా మార్చండి
- iPhone, iPad, Mac, నైరూప్య లేఅవుట్‌లకు పరికర ఫ్రేమ్‌లు జోడించండి
- వచనం, ఆకారాలు, చిత్రాలు, గ్రేడియంట్‌లు, పలకల నేపథ్యాలు, SVG గ్రాఫిక్స్‌తో పని చేయండి
- కస్టమ్ ఫాంట్‌లు, ఫాంట్ రకాలు, అంతరం, సర్దుబాటు, పరిమాణంతో రిచ్ టెక్స్ట్ సవరించండి
- కాన్వాస్‌పైనే స్థానం, స్నాపింగ్, పొరలు, కత్తిరింపు, భ్రమణం సర్దండి
- ప్రతి మార్కెట్ కోసం భాషల వారీ వచనం, చిత్ర మార్పులు నిర్వహించండి
- భాషా ప్రీసెట్‌లు వాడండి, మిగిలిన వచనాన్ని ఆటోమేటిక్‌గా అనువదించండి, పురోగతి చూడండి
- PNG లేదా JPEG స్క్రీన్‌షాట్‌లను భాష, వరుస వారీగా ఫోల్డర్లలో ఎగుమతి చేయండి
- సామాజిక పోస్టులు, వెబ్‌సైట్లు, ప్రచార ప్రివ్యూల కోసం షోకేస్ ఎగుమతులు చేయండి
- స్క్రీన్‌షాట్‌లను నేరుగా App Store Connect కు అప్‌లోడ్ చేయండి
- అప్‌లోడ్ ముందు App Store Connect మెటాడేటాను చూసి సవరించండి
- ఎగుమతులు, స్టోర్ అప్‌లోడ్‌లు పూర్తయినప్పుడు నోటిఫికేషన్‌లు పొందండి
- ప్రాజెక్టులు స్థానికంగా ఉంచండి, అవసరమైతే iCloud తో సమకాలీకరించండి, ZIP బ్యాకప్‌లు చేయండి
- ఎలాంటి ట్రాకింగ్ లేదు

సాధారణ స్క్రీన్‌షాట్ జెనరేటర్ కంటే ఎక్కువ నియంత్రణ, ప్రతి చిత్రాన్ని చేతితో మళ్లీ తయారు చేయడం కంటే వేగవంతమైన పని విధానం కావాలనుకునే ఇండీ డెవలపర్లు, ఉత్పత్తి బృందాలు, డిజైనర్లు, మార్కెటర్ల కోసం Screenshot Bro రూపొందించబడింది.

మీరు మొదటి విడుదలను సిద్ధం చేస్తున్నా, పెద్ద అప్‌డేట్, కాలానుగుణ ప్రచారం లేదా కొత్త భాషలకు విస్తరణ అయినా — Screenshot Bro మిమ్మల్ని ముడి స్క్రీన్‌షాట్‌ల నుంచి స్టోర్‌కు సిద్ధమైన మార్కెటింగ్ చిత్రాల వరకు వేగంగా, మరింత స్థిరత్వంతో తీసుకెళ్తుంది.

మీకు App Store స్క్రీన్‌షాట్ సృష్టికర్త, స్క్రీన్‌షాట్ టెంప్లేట్ బిల్డర్, స్క్రీన్‌షాట్ స్థానికీకరణ సాధనం, లేదా App Store Connect అప్‌లోడర్ కావాలంటే, Screenshot Bro మొత్తం పని విధానాన్ని ఒకే కేంద్రీకృత యాప్‌లో ఉంచుతుంది.

వినియోగ నిబంధనలు (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["kn-IN"] = """\
Screenshot Bro ಎಂಬುದು App Store ಗಾಗಿ ಆ್ಯಪ್ ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ರಚಿಸುವ ಆ್ಯಪ್. ಪೂರ್ಣ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸೆಟ್ ಅನ್ನು ಒಮ್ಮೆಯೇ ವಿನ್ಯಾಸಗೊಳಿಸಿ, ಸಾಧನ ಚೌಕಟ್ಟುಗಳನ್ನು ಸೇರಿಸಿ, ನೀವು ಬಿಡುಗಡೆ ಮಾಡುವ ಪ್ರತಿ ಮಾರುಕಟ್ಟೆಗೂ ಪ್ರತಿ ಶೀರ್ಷಿಕೆಯನ್ನು ಅನುವಾದಿಸಿ, ನೇರವಾಗಿ App Store Connect ಗೆ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ — ನಿಮ್ಮ Mac ಬಿಟ್ಟು ಹೋಗದೆ.

ಸಾಮಾನ್ಯ ವಿನ್ಯಾಸ ಸಾಧನಗಳಿಗಿಂತ ಭಿನ್ನವಾಗಿ, Screenshot Bro ಸಾಧನವಾರು ಸಾಲುಗಳು, ಸ್ಥಳೀಕರಣ, App Store Connect ಅಪ್‌ಲೋಡ್‌ಗಳು, ಬ್ಯಾಚ್ ರಫ್ತುಗಳು, ಮರುಬಳಕೆಯ ಯೋಜನೆಗಳು, Model Context Protocol ಮೂಲಕ ಸ್ಥಳೀಯ AI ಸಹಾಯಕ ಸ್ವಯಂಚಾಲನೆಯನ್ನು ಅರ್ಥಮಾಡಿಕೊಳ್ಳುತ್ತದೆ.

iPhone, iPad, Mac ವಿನ್ಯಾಸಗಳಿಗಾಗಿ ಪೂರ್ಣ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸೆಟ್‌ಗಳನ್ನು ರಚಿಸಿ. ಒಂದು ಟೆಂಪ್ಲೇಟ್‌ನಿಂದ ಆರಂಭಿಸಿ ಅಥವಾ ನಿಮ್ಮದೇ ವಿನ್ಯಾಸ ವ್ಯವಸ್ಥೆಯನ್ನು ಕಟ್ಟಿ. ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ಸೇರಿಸಿ, ಸಾಧನ ಚೌಕಟ್ಟುಗಳು ಅಥವಾ ಚೌಕಟ್ಟಿಲ್ಲದ ರಚನೆಗಳನ್ನು ಸೇರಿಸಿ, ಶೀರ್ಷಿಕೆ ಮತ್ತು ವಿವರಣೆ ಬರೆಯಿರಿ, ಕಸ್ಟಮ್ ಫಾಂಟ್‌ಗಳಿಂದ ರಿಚ್ ಟೆಕ್ಸ್ಟ್‌ಗೆ ಶೈಲಿ ನೀಡಿ, ಕ್ಯಾನ್ವಾಸ್‌ನಲ್ಲಿ ಪ್ರತಿ ವಿವರವನ್ನು ಸರಿಪಡಿಸಿ.

Screenshot Bro ನಿಮ್ಮ Mac ನಲ್ಲಿ ಸ್ಥಳೀಯ MCP ಸರ್ವರ್ ಚಲಾಯಿಸಬಲ್ಲದು. Claude Code, Claude Desktop, Cursor ಅಥವಾ ಇತರ MCP-ಹೊಂದಾಣಿಕೆಯ ಸಹಾಯಕವನ್ನು ಜೋಡಿಸಿ, ಯೋಜನೆಗಳನ್ನು ರಚಿಸಲು, ಸಾಲುಗಳನ್ನು ಸಂಪಾದಿಸಲು, ಆಕಾರಗಳನ್ನು ಜೋಡಿಸಲು, ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ಆಮದು ಮಾಡಲು, ಪಠ್ಯ ಅನುವಾದಿಸಲು, ಕ್ಯಾನ್ವಾಸ್ ಮುನ್ನೋಟ ರೆಂಡರ್ ಮಾಡಲು, ಅಂತಿಮ ಚಿತ್ರಗಳನ್ನು ರಫ್ತು ಮಾಡಲು ಬಿಡಿ. MCP ಐಚ್ಛಿಕ, ಪೂರ್ವನಿಯೋಜಿತವಾಗಿ ಆಫ್ ಆಗಿರುತ್ತದೆ, ಸ್ಥಳೀಯ ಸಂಪರ್ಕಗಳನ್ನಷ್ಟೇ ಸ್ವೀಕರಿಸುತ್ತದೆ, ಪ್ರವೇಶ ಟೋಕನ್‌ನಿಂದ ಸಂರಕ್ಷಿತ.

ಬಿಡುಗಡೆ ಪ್ರಕಾರಗಳು, ಭಾಷಾವಾರು ಬದಲಾವಣೆಗಳು, ಅಂಗಡಿವಾರು ಸಾಲಿನ ಯೋಜನೆಗಳು, ರಫ್ತಿಗೆ ಸಿದ್ಧ ಸಾಮಗ್ರಿ — ಎಲ್ಲವನ್ನೂ ಒಂದೇ ಯೋಜನೆಯಲ್ಲಿ ಇರಿಸಿ: App Store, ಜಾಲತಾಣಗಳು, ಸಾಮಾಜಿಕ ಮಾಧ್ಯಮ, ಬಿಡುಗಡೆ ಅಭಿಯಾನಗಳಿಗಾಗಿ.

ಮುಖ್ಯ ವೈಶಿಷ್ಟ್ಯಗಳು:

- ಒಂದೇ ಯೋಜನೆಯಿಂದ App Store ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ರಚಿಸಿ
- ಪುನರಾವರ್ತಿತ ಬಿಡುಗಡೆಗಳಿಗೆ ಅಂತರ್ನಿರ್ಮಿತ ಟೆಂಪ್ಲೇಟ್ ಅಥವಾ ಸ್ವಂತ ವಿನ್ಯಾಸ ಬಳಸಿ
- ಬಹು ಚಿತ್ರಗಳ ಸಾಲುಗಳು, ಹೋಲಿಕೆ ವಿನ್ಯಾಸಗಳು, ಪೂರ್ಣ ಅಭಿಯಾನಗಳನ್ನು ರೂಪಿಸಿ
- ಸಾಲುಗಳಿಗೆ ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ಗುಂಪಾಗಿ ಆಮದು ಮಾಡಿ, ಚಿತ್ರಗಳನ್ನು ಬೇಗ ಬದಲಿಸಿ
- iPhone, iPad, Mac ಮತ್ತು ಅಮೂರ್ತ ವಿನ್ಯಾಸಗಳಿಗೆ ಸಾಧನ ಚೌಕಟ್ಟು ಸೇರಿಸಿ
- ಪಠ್ಯ, ಆಕಾರ, ಚಿತ್ರ, ಗ್ರೇಡಿಯಂಟ್, ಹಂಚಿನಂತಹ ಹಿನ್ನೆಲೆ, SVG ಗ್ರಾಫಿಕ್ಸ್‌ನೊಂದಿಗೆ ಕೆಲಸ ಮಾಡಿ
- ಕಸ್ಟಮ್ ಫಾಂಟ್, ಫಾಂಟ್ ಪ್ರಕಾರ, ಅಂತರ, ಜೋಡಣೆ, ಗಾತ್ರದೊಂದಿಗೆ ರಿಚ್ ಟೆಕ್ಸ್ಟ್ ಸಂಪಾದಿಸಿ
- ಕ್ಯಾನ್ವಾಸ್‌ನಲ್ಲಿಯೇ ಸ್ಥಾನ, ಸ್ನ್ಯಾಪಿಂಗ್, ಪದರ, ಕತ್ತರಿಸುವಿಕೆ, ತಿರುಗುವಿಕೆ ಹೊಂದಿಸಿ
- ಪ್ರತಿ ಮಾರುಕಟ್ಟೆಗೆ ಭಾಷಾವಾರು ಪಠ್ಯ ಮತ್ತು ಚಿತ್ರ ಬದಲಾವಣೆಗಳನ್ನು ನಿರ್ವಹಿಸಿ
- ಭಾಷಾ ಪ್ರೀಸೆಟ್ ಬಳಸಿ, ಬಿಟ್ಟುಹೋದ ಪಠ್ಯವನ್ನು ತಾನಾಗಿ ಅನುವಾದಿಸಿ, ಪ್ರಗತಿ ನೋಡಿ
- PNG ಅಥವಾ JPEG ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ಭಾಷೆ ಮತ್ತು ಸಾಲಿನ ಪ್ರಕಾರ ಫೋಲ್ಡರ್‌ಗಳಿಗೆ ರಫ್ತು ಮಾಡಿ
- ಸಾಮಾಜಿಕ ಪೋಸ್ಟ್, ಜಾಲತಾಣ, ಅಭಿಯಾನ ಮುನ್ನೋಟಗಳಿಗೆ ಶೋಕೇಸ್ ರಫ್ತು ರಚಿಸಿ
- ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ನೇರವಾಗಿ App Store Connect ಗೆ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ
- ಅಪ್‌ಲೋಡ್ ಮೊದಲು App Store Connect ಮೆಟಾಡೇಟಾ ಪರಿಶೀಲಿಸಿ ಮತ್ತು ಸಂಪಾದಿಸಿ
- ಯೋಜನೆಗಳನ್ನು ಸ್ಥಳೀಯವಾಗಿ ಇರಿಸಿ, ಬೇಕಿದ್ದರೆ iCloud ಜೊತೆ ಹೊಂದಿಸಿ, ZIP ಬ್ಯಾಕಪ್ ಮಾಡಿ
- ಯಾವುದೇ ಟ್ರ್ಯಾಕಿಂಗ್ ಇಲ್ಲ

ಸಾಮಾನ್ಯ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಜನರೇಟರ್‌ಗಿಂತ ಹೆಚ್ಚು ನಿಯಂತ್ರಣ, ಪ್ರತಿ ಚಿತ್ರವನ್ನೂ ಕೈಯಿಂದ ಮತ್ತೆ ಮಾಡುವುದಕ್ಕಿಂತ ವೇಗದ ಕಾರ್ಯವಿಧಾನ ಬೇಕಾದ ಇಂಡೀ ಡೆವಲಪರ್‌ಗಳು, ಉತ್ಪನ್ನ ತಂಡಗಳು, ವಿನ್ಯಾಸಕರು, ಮಾರುಕಟ್ಟೆದಾರರಿಗಾಗಿ Screenshot Bro ರೂಪಿಸಲಾಗಿದೆ.

ನಿಮಗೆ App Store ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ರಚನಕಾರ, ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಟೆಂಪ್ಲೇಟ್ ಬಿಲ್ಡರ್, ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸ್ಥಳೀಕರಣ ಸಾಧನ, App Store Connect ಅಪ್‌ಲೋಡರ್, ಅಥವಾ MCP-ಸಿದ್ಧ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸ್ವಯಂಚಾಲನೆ ಸಾಧನ ಬೇಕಿದ್ದರೆ, Screenshot Bro ಇಡೀ ಕಾರ್ಯವಿಧಾನವನ್ನು ಒಂದೇ ಕೇಂದ್ರೀಕೃತ Mac ಆ್ಯಪ್‌ನಲ್ಲಿ ಇರಿಸುತ್ತದೆ.

ಬಳಕೆಯ ನಿಯಮಗಳು (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["kn-IN"] = """\
Screenshot Bro ಎಂಬುದು App Store ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳಿಗಾಗಿಯೇ ರೂಪಿಸಿದ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ರಚನಕಾರ ಮತ್ತು ಸಂಪಾದಕ. ಮರುಬಳಕೆಯ ಟೆಂಪ್ಲೇಟ್‌ಗಳನ್ನು ರಚಿಸಿ, ಪೂರ್ಣ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸೆಟ್‌ಗಳನ್ನು ವಿನ್ಯಾಸಗೊಳಿಸಿ, ನಿಮ್ಮ ಸಂದೇಶವನ್ನು ಪ್ರತಿ ಭಾಷೆಯಲ್ಲಿ ಹೊಂದಿಸಿ, ನಂತರ ಸಿದ್ಧ ಅಂಗಡಿ ಸಾಮಗ್ರಿಯನ್ನು ರಫ್ತು ಮಾಡಿ ಅಥವಾ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ.

ಸಾಮಾನ್ಯ ವಿನ್ಯಾಸ ಸಾಧನಗಳಿಗಿಂತ ಭಿನ್ನವಾಗಿ, Screenshot Bro ಸಾಧನವಾರು ಸಾಲುಗಳು, ಸ್ಥಳೀಕರಣ, App Store Connect ಅಪ್‌ಲೋಡ್‌ಗಳು, ಬ್ಯಾಚ್ ರಫ್ತುಗಳು, ಮರುಬಳಕೆಯ ಯೋಜನೆಗಳನ್ನು ಅರ್ಥಮಾಡಿಕೊಳ್ಳುತ್ತದೆ.

iPhone, iPad, Mac ವಿನ್ಯಾಸಗಳಿಗಾಗಿ ಪೂರ್ಣ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸೆಟ್‌ಗಳನ್ನು ರಚಿಸಿ. ಒಂದು ಟೆಂಪ್ಲೇಟ್‌ನಿಂದ ಆರಂಭಿಸಿ ಅಥವಾ ನಿಮ್ಮದೇ ವಿನ್ಯಾಸ ವ್ಯವಸ್ಥೆಯನ್ನು ಕಟ್ಟಿ. ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ಸೇರಿಸಿ, ಸಾಧನ ಚೌಕಟ್ಟುಗಳು ಅಥವಾ ಚೌಕಟ್ಟಿಲ್ಲದ ರಚನೆಗಳನ್ನು ಸೇರಿಸಿ, ಶೀರ್ಷಿಕೆ ಮತ್ತು ವಿವರಣೆ ಬರೆಯಿರಿ, ಕಸ್ಟಮ್ ಫಾಂಟ್‌ಗಳಿಂದ ರಿಚ್ ಟೆಕ್ಸ್ಟ್‌ಗೆ ಶೈಲಿ ನೀಡಿ, ಕ್ಯಾನ್ವಾಸ್‌ನಲ್ಲಿ ಪ್ರತಿ ವಿವರವನ್ನು ಸರಿಪಡಿಸಿ.

ಬಿಡುಗಡೆ ಪ್ರಕಾರಗಳು, ಭಾಷಾವಾರು ಬದಲಾವಣೆಗಳು, ಅಂಗಡಿವಾರು ಸಾಲಿನ ಯೋಜನೆಗಳು, ರಫ್ತಿಗೆ ಸಿದ್ಧ ಸಾಮಗ್ರಿ — ಎಲ್ಲವನ್ನೂ ಒಂದೇ ಯೋಜನೆಯಲ್ಲಿ ಇರಿಸಿ: App Store, ಜಾಲತಾಣಗಳು, ಸಾಮಾಜಿಕ ಮಾಧ್ಯಮ, ಬಿಡುಗಡೆ ಅಭಿಯಾನಗಳಿಗಾಗಿ.

ಮುಖ್ಯ ವೈಶಿಷ್ಟ್ಯಗಳು:

- ಒಂದೇ ಯೋಜನೆಯಿಂದ App Store ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ರಚಿಸಿ
- ಪುನರಾವರ್ತಿತ ಬಿಡುಗಡೆಗಳಿಗೆ ಅಂತರ್ನಿರ್ಮಿತ ಟೆಂಪ್ಲೇಟ್ ಅಥವಾ ಸ್ವಂತ ವಿನ್ಯಾಸ ಬಳಸಿ
- ಬಹು ಚಿತ್ರಗಳ ಸಾಲುಗಳು, ಹೋಲಿಕೆ ವಿನ್ಯಾಸಗಳು, ಪೂರ್ಣ ಅಭಿಯಾನಗಳನ್ನು ರೂಪಿಸಿ
- ಸಾಲುಗಳಿಗೆ ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ಗುಂಪಾಗಿ ಆಮದು ಮಾಡಿ, ಚಿತ್ರಗಳನ್ನು ಬೇಗ ಬದಲಿಸಿ
- iPhone, iPad, Mac ಮತ್ತು ಅಮೂರ್ತ ವಿನ್ಯಾಸಗಳಿಗೆ ಸಾಧನ ಚೌಕಟ್ಟು ಸೇರಿಸಿ
- ಪಠ್ಯ, ಆಕಾರ, ಚಿತ್ರ, ಗ್ರೇಡಿಯಂಟ್, ಹಂಚಿನಂತಹ ಹಿನ್ನೆಲೆ, SVG ಗ್ರಾಫಿಕ್ಸ್‌ನೊಂದಿಗೆ ಕೆಲಸ ಮಾಡಿ
- ಕಸ್ಟಮ್ ಫಾಂಟ್, ಫಾಂಟ್ ಪ್ರಕಾರ, ಅಂತರ, ಜೋಡಣೆ, ಗಾತ್ರದೊಂದಿಗೆ ರಿಚ್ ಟೆಕ್ಸ್ಟ್ ಸಂಪಾದಿಸಿ
- ಕ್ಯಾನ್ವಾಸ್‌ನಲ್ಲಿಯೇ ಸ್ಥಾನ, ಸ್ನ್ಯಾಪಿಂಗ್, ಪದರ, ಕತ್ತರಿಸುವಿಕೆ, ತಿರುಗುವಿಕೆ ಹೊಂದಿಸಿ
- ಪ್ರತಿ ಮಾರುಕಟ್ಟೆಗೆ ಭಾಷಾವಾರು ಪಠ್ಯ ಮತ್ತು ಚಿತ್ರ ಬದಲಾವಣೆಗಳನ್ನು ನಿರ್ವಹಿಸಿ
- ಭಾಷಾ ಪ್ರೀಸೆಟ್ ಬಳಸಿ, ಬಿಟ್ಟುಹೋದ ಪಠ್ಯವನ್ನು ತಾನಾಗಿ ಅನುವಾದಿಸಿ, ಪ್ರಗತಿ ನೋಡಿ
- PNG ಅಥವಾ JPEG ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ಭಾಷೆ ಮತ್ತು ಸಾಲಿನ ಪ್ರಕಾರ ಫೋಲ್ಡರ್‌ಗಳಿಗೆ ರಫ್ತು ಮಾಡಿ
- ಸಾಮಾಜಿಕ ಪೋಸ್ಟ್, ಜಾಲತಾಣ, ಅಭಿಯಾನ ಮುನ್ನೋಟಗಳಿಗೆ ಶೋಕೇಸ್ ರಫ್ತು ರಚಿಸಿ
- ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳನ್ನು ನೇರವಾಗಿ App Store Connect ಗೆ ಅಪ್‌ಲೋಡ್ ಮಾಡಿ
- ಅಪ್‌ಲೋಡ್ ಮೊದಲು App Store Connect ಮೆಟಾಡೇಟಾ ಪರಿಶೀಲಿಸಿ ಮತ್ತು ಸಂಪಾದಿಸಿ
- ರಫ್ತು ಮತ್ತು ಅಂಗಡಿ ಅಪ್‌ಲೋಡ್ ಮುಗಿದಾಗ ಅಧಿಸೂಚನೆ ಪಡೆಯಿರಿ
- ಯೋಜನೆಗಳನ್ನು ಸ್ಥಳೀಯವಾಗಿ ಇರಿಸಿ, ಬೇಕಿದ್ದರೆ iCloud ಜೊತೆ ಹೊಂದಿಸಿ, ZIP ಬ್ಯಾಕಪ್ ಮಾಡಿ
- ಯಾವುದೇ ಟ್ರ್ಯಾಕಿಂಗ್ ಇಲ್ಲ

ಸಾಮಾನ್ಯ ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಜನರೇಟರ್‌ಗಿಂತ ಹೆಚ್ಚು ನಿಯಂತ್ರಣ, ಪ್ರತಿ ಚಿತ್ರವನ್ನೂ ಕೈಯಿಂದ ಮತ್ತೆ ಮಾಡುವುದಕ್ಕಿಂತ ವೇಗದ ಕಾರ್ಯವಿಧಾನ ಬೇಕಾದ ಇಂಡೀ ಡೆವಲಪರ್‌ಗಳು, ಉತ್ಪನ್ನ ತಂಡಗಳು, ವಿನ್ಯಾಸಕರು, ಮಾರುಕಟ್ಟೆದಾರರಿಗಾಗಿ Screenshot Bro ರೂಪಿಸಲಾಗಿದೆ.

ನೀವು ಮೊದಲ ಬಿಡುಗಡೆ ಸಿದ್ಧಪಡಿಸುತ್ತಿರಲಿ, ದೊಡ್ಡ ಅಪ್‌ಡೇಟ್, ಋತುಮಾನದ ಅಭಿಯಾನ ಅಥವಾ ಹೊಸ ಭಾಷೆಗಳಿಗೆ ವಿಸ್ತರಣೆಯಾಗಿರಲಿ — Screenshot Bro ನಿಮ್ಮನ್ನು ಕಚ್ಚಾ ಸ್ಕ್ರೀನ್‌ಶಾಟ್‌ಗಳಿಂದ ಅಂಗಡಿಗೆ ಸಿದ್ಧ ಮಾರುಕಟ್ಟೆ ಚಿತ್ರಗಳವರೆಗೆ ವೇಗವಾಗಿ, ಹೆಚ್ಚು ಸ್ಥಿರವಾಗಿ ಕರೆದೊಯ್ಯುತ್ತದೆ.

ನಿಮಗೆ App Store ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ರಚನಕಾರ, ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಟೆಂಪ್ಲೇಟ್ ಬಿಲ್ಡರ್, ಸ್ಕ್ರೀನ್‌ಶಾಟ್ ಸ್ಥಳೀಕರಣ ಸಾಧನ, ಅಥವಾ App Store Connect ಅಪ್‌ಲೋಡರ್ ಬೇಕಿದ್ದರೆ, Screenshot Bro ಇಡೀ ಕಾರ್ಯವಿಧಾನವನ್ನು ಒಂದೇ ಕೇಂದ್ರೀಕೃತ ಆ್ಯಪ್‌ನಲ್ಲಿ ಇರಿಸುತ್ತದೆ.

ಬಳಕೆಯ ನಿಯಮಗಳು (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["ml-IN"] = """\
Screenshot Bro എന്നത് App Store-നായി ആപ്പ് സ്ക്രീൻഷോട്ടുകൾ ഉണ്ടാക്കുന്ന ആപ്പാണ്. പൂർണ്ണ സ്ക്രീൻഷോട്ട് സെറ്റ് ഒറ്റത്തവണ രൂപകൽപ്പന ചെയ്യുക, ഉപകരണ ഫ്രെയിമുകൾ ചേർക്കുക, നിങ്ങൾ പ്രസിദ്ധീകരിക്കുന്ന ഓരോ വിപണിക്കും ഓരോ തലക്കെട്ടും വിവർത്തനം ചെയ്യുക, നേരിട്ട് App Store Connect-ലേക്ക് അപ്‌ലോഡ് ചെയ്യുക — നിങ്ങളുടെ Mac വിട്ടുപോകാതെ.

സാധാരണ ഡിസൈൻ ഉപകരണങ്ങളിൽ നിന്ന് വ്യത്യസ്തമായി, Screenshot Bro ഉപകരണാധിഷ്ഠിത നിരകൾ, പ്രാദേശികവൽക്കരണം, App Store Connect അപ്‌ലോഡുകൾ, ബാച്ച് കയറ്റുമതികൾ, പുനരുപയോഗിക്കാവുന്ന പ്രോജക്ടുകൾ, Model Context Protocol വഴിയുള്ള പ്രാദേശിക AI സഹായി ഓട്ടോമേഷൻ എന്നിവ മനസ്സിലാക്കുന്നു.

iPhone, iPad, Mac ലേഔട്ടുകൾ എന്നിവയ്ക്കായി പൂർണ്ണ സ്ക്രീൻഷോട്ട് സെറ്റുകൾ ഉണ്ടാക്കുക. ഒരു ടെംപ്ലേറ്റിൽ നിന്ന് തുടങ്ങുക അല്ലെങ്കിൽ സ്വന്തം ലേഔട്ട് സംവിധാനം ഉണ്ടാക്കുക. സ്ക്രീൻഷോട്ടുകൾ ചേർക്കുക, ഉപകരണ ഫ്രെയിമുകളോ ഫ്രെയിമില്ലാത്ത ക്രമീകരണങ്ങളോ ചേർക്കുക, തലക്കെട്ടുകളും വിവരണങ്ങളും എഴുതുക, കസ്റ്റം ഫോണ്ടുകളോടെ റിച്ച് ടെക്സ്റ്റിന് ശൈലി നൽകുക, കാൻവാസിൽ ഓരോ വിശദാംശവും മെച്ചപ്പെടുത്തുക.

Screenshot Bro-യ്ക്ക് നിങ്ങളുടെ Mac-ൽ ഒരു പ്രാദേശിക MCP സെർവർ പ്രവർത്തിപ്പിക്കാനാകും. Claude Code, Claude Desktop, Cursor അല്ലെങ്കിൽ മറ്റ് MCP-അനുയോജ്യ സഹായിയെ ബന്ധിപ്പിച്ച്, പ്രോജക്ടുകൾ ഉണ്ടാക്കാനും നിരകൾ തിരുത്താനും രൂപങ്ങൾ ക്രമീകരിക്കാനും സ്ക്രീൻഷോട്ടുകൾ ഇറക്കുമതി ചെയ്യാനും വാചകം വിവർത്തനം ചെയ്യാനും കാൻവാസ് പ്രിവ്യൂകൾ റെൻഡർ ചെയ്യാനും അന്തിമ ചിത്രങ്ങൾ കയറ്റുമതി ചെയ്യാനും അനുവദിക്കുക. MCP ഐച്ഛികമാണ്, സ്ഥിരസ്ഥിതിയായി ഓഫാണ്, പ്രാദേശിക കണക്ഷനുകൾ മാത്രം സ്വീകരിക്കുന്നു, ആക്‌സസ് ടോക്കൺ കൊണ്ട് സംരക്ഷിതമാണ്.

റിലീസ് വകഭേദങ്ങൾ, ഭാഷാടിസ്ഥാന മാറ്റങ്ങൾ, സ്റ്റോർ അടിസ്ഥാന നിര പദ്ധതികൾ, കയറ്റുമതിക്ക് തയ്യാറായ സാമഗ്രികൾ — എല്ലാം ഒരൊറ്റ പ്രോജക്ടിൽ സൂക്ഷിക്കുക: App Store, വെബ്‌സൈറ്റുകൾ, സാമൂഹ്യ മാധ്യമങ്ങൾ, പ്രചാരണങ്ങൾ എന്നിവയ്ക്കായി.

പ്രധാന സവിശേഷതകൾ:

- ഒരൊറ്റ പ്രോജക്ടിൽ നിന്ന് App Store സ്ക്രീൻഷോട്ടുകൾ ഉണ്ടാക്കുക
- ആവർത്തിക്കുന്ന റിലീസുകൾക്ക് അന്തർനിർമ്മിത ടെംപ്ലേറ്റുകളോ സ്വന്തം ലേഔട്ടുകളോ ഉപയോഗിക്കുക
- ഒന്നിലധികം ചിത്രങ്ങളുള്ള നിരകൾ, താരതമ്യ ലേഔട്ടുകൾ, പൂർണ്ണ പ്രചാരണങ്ങൾ രൂപകൽപ്പന ചെയ്യുക
- നിരകളിലേക്ക് സ്ക്രീൻഷോട്ടുകൾ കൂട്ടത്തോടെ ഇറക്കുമതി ചെയ്ത് ചിത്രങ്ങൾ വേഗത്തിൽ മാറ്റുക
- iPhone, iPad, Mac, അമൂർത്ത ലേഔട്ടുകൾക്കായി ഉപകരണ ഫ്രെയിമുകൾ ചേർക്കുക
- വാചകം, രൂപങ്ങൾ, ചിത്രങ്ങൾ, ഗ്രേഡിയന്റുകൾ, ടൈൽ പശ്ചാത്തലങ്ങൾ, SVG ഗ്രാഫിക്‌സ് എന്നിവയിൽ പ്രവർത്തിക്കുക
- കസ്റ്റം ഫോണ്ടുകൾ, ഫോണ്ട് വകഭേദങ്ങൾ, അകലം, വിന്യാസം, വലുപ്പം എന്നിവയോടെ റിച്ച് ടെക്സ്റ്റ് തിരുത്തുക
- കാൻവാസിൽ തന്നെ സ്ഥാനം, സ്നാപ്പിംഗ്, പാളികൾ, ക്രോപ്പിംഗ്, തിരിക്കൽ ക്രമീകരിക്കുക
- ഓരോ വിപണിക്കും ഭാഷാടിസ്ഥാന വാചകവും ചിത്ര മാറ്റങ്ങളും കൈകാര്യം ചെയ്യുക
- ഭാഷാ പ്രീസെറ്റുകൾ ഉപയോഗിക്കുക, വിട്ടുപോയ വാചകം സ്വയമേവ വിവർത്തനം ചെയ്യുക, പുരോഗതി കാണുക
- PNG അല്ലെങ്കിൽ JPEG സ്ക്രീൻഷോട്ടുകൾ ഭാഷയും നിരയും അനുസരിച്ച് ഫോൾഡറുകളിലേക്ക് കയറ്റുമതി ചെയ്യുക
- സാമൂഹ്യ പോസ്റ്റുകൾ, വെബ്‌സൈറ്റുകൾ, പ്രചാരണ പ്രിവ്യൂകൾ എന്നിവയ്ക്കായി ഷോകേസ് കയറ്റുമതി ഉണ്ടാക്കുക
- സ്ക്രീൻഷോട്ടുകൾ നേരിട്ട് App Store Connect-ലേക്ക് അപ്‌ലോഡ് ചെയ്യുക
- അപ്‌ലോഡിന് മുമ്പ് App Store Connect മെറ്റാഡേറ്റ പരിശോധിച്ച് തിരുത്തുക
- പ്രോജക്ടുകൾ പ്രാദേശികമായി സൂക്ഷിക്കുക, വേണ്ടിവന്നാൽ iCloud-മായി സമന്വയിപ്പിക്കുക, ZIP ബാക്കപ്പുകൾ ഉണ്ടാക്കുക
- ട്രാക്കിംഗ് ഇല്ല

സാധാരണ സ്ക്രീൻഷോട്ട് ജനറേറ്ററിനെക്കാൾ കൂടുതൽ നിയന്ത്രണവും, ഓരോ ചിത്രവും കൈകൊണ്ട് വീണ്ടും ഉണ്ടാക്കുന്നതിനെക്കാൾ വേഗമേറിയ പ്രവർത്തനരീതിയും വേണ്ട ഇൻഡി ഡെവലപ്പർമാർ, ഉൽപ്പന്ന ടീമുകൾ, ഡിസൈനർമാർ, മാർക്കറ്റർമാർ എന്നിവർക്കായാണ് Screenshot Bro ഒരുക്കിയിരിക്കുന്നത്.

നിങ്ങൾക്ക് App Store സ്ക്രീൻഷോട്ട് സ്രഷ്ടാവ്, സ്ക്രീൻഷോട്ട് ടെംപ്ലേറ്റ് ബിൽഡർ, സ്ക്രീൻഷോട്ട് പ്രാദേശികവൽക്കരണ ഉപകരണം, App Store Connect അപ്‌ലോഡർ, അല്ലെങ്കിൽ MCP-സജ്ജ സ്ക്രീൻഷോട്ട് ഓട്ടോമേഷൻ ഉപകരണം വേണമെങ്കിൽ, Screenshot Bro മുഴുവൻ പ്രവർത്തനരീതിയും ഒരൊറ്റ കേന്ദ്രീകൃത Mac ആപ്പിൽ സൂക്ഷിക്കുന്നു.

ഉപയോഗ നിബന്ധനകൾ (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["ml-IN"] = """\
Screenshot Bro എന്നത് App Store സ്ക്രീൻഷോട്ടുകൾക്കായി തന്നെ ഒരുക്കിയ സ്ക്രീൻഷോട്ട് സ്രഷ്ടാവും എഡിറ്ററുമാണ്. പുനരുപയോഗിക്കാവുന്ന ടെംപ്ലേറ്റുകൾ ഉണ്ടാക്കുക, പൂർണ്ണ സ്ക്രീൻഷോട്ട് സെറ്റുകൾ രൂപകൽപ്പന ചെയ്യുക, നിങ്ങളുടെ സന്ദേശം ഓരോ ഭാഷയിലും ഒരുക്കുക, പിന്നെ തയ്യാറായ സ്റ്റോർ സാമഗ്രികൾ കയറ്റുമതി ചെയ്യുകയോ അപ്‌ലോഡ് ചെയ്യുകയോ ചെയ്യുക.

സാധാരണ ഡിസൈൻ ഉപകരണങ്ങളിൽ നിന്ന് വ്യത്യസ്തമായി, Screenshot Bro ഉപകരണാധിഷ്ഠിത നിരകൾ, പ്രാദേശികവൽക്കരണം, App Store Connect അപ്‌ലോഡുകൾ, ബാച്ച് കയറ്റുമതികൾ, പുനരുപയോഗിക്കാവുന്ന പ്രോജക്ടുകൾ എന്നിവ മനസ്സിലാക്കുന്നു.

iPhone, iPad, Mac ലേഔട്ടുകൾ എന്നിവയ്ക്കായി പൂർണ്ണ സ്ക്രീൻഷോട്ട് സെറ്റുകൾ ഉണ്ടാക്കുക. ഒരു ടെംപ്ലേറ്റിൽ നിന്ന് തുടങ്ങുക അല്ലെങ്കിൽ സ്വന്തം ലേഔട്ട് സംവിധാനം ഉണ്ടാക്കുക. സ്ക്രീൻഷോട്ടുകൾ ചേർക്കുക, ഉപകരണ ഫ്രെയിമുകളോ ഫ്രെയിമില്ലാത്ത ക്രമീകരണങ്ങളോ ചേർക്കുക, തലക്കെട്ടുകളും വിവരണങ്ങളും എഴുതുക, കസ്റ്റം ഫോണ്ടുകളോടെ റിച്ച് ടെക്സ്റ്റിന് ശൈലി നൽകുക, കാൻവാസിൽ ഓരോ വിശദാംശവും മെച്ചപ്പെടുത്തുക.

റിലീസ് വകഭേദങ്ങൾ, ഭാഷാടിസ്ഥാന മാറ്റങ്ങൾ, സ്റ്റോർ അടിസ്ഥാന നിര പദ്ധതികൾ, കയറ്റുമതിക്ക് തയ്യാറായ സാമഗ്രികൾ — എല്ലാം ഒരൊറ്റ പ്രോജക്ടിൽ സൂക്ഷിക്കുക: App Store, വെബ്‌സൈറ്റുകൾ, സാമൂഹ്യ മാധ്യമങ്ങൾ, പ്രചാരണങ്ങൾ എന്നിവയ്ക്കായി.

പ്രധാന സവിശേഷതകൾ:

- ഒരൊറ്റ പ്രോജക്ടിൽ നിന്ന് App Store സ്ക്രീൻഷോട്ടുകൾ ഉണ്ടാക്കുക
- ആവർത്തിക്കുന്ന റിലീസുകൾക്ക് അന്തർനിർമ്മിത ടെംപ്ലേറ്റുകളോ സ്വന്തം ലേഔട്ടുകളോ ഉപയോഗിക്കുക
- ഒന്നിലധികം ചിത്രങ്ങളുള്ള നിരകൾ, താരതമ്യ ലേഔട്ടുകൾ, പൂർണ്ണ പ്രചാരണങ്ങൾ രൂപകൽപ്പന ചെയ്യുക
- നിരകളിലേക്ക് സ്ക്രീൻഷോട്ടുകൾ കൂട്ടത്തോടെ ഇറക്കുമതി ചെയ്ത് ചിത്രങ്ങൾ വേഗത്തിൽ മാറ്റുക
- iPhone, iPad, Mac, അമൂർത്ത ലേഔട്ടുകൾക്കായി ഉപകരണ ഫ്രെയിമുകൾ ചേർക്കുക
- വാചകം, രൂപങ്ങൾ, ചിത്രങ്ങൾ, ഗ്രേഡിയന്റുകൾ, ടൈൽ പശ്ചാത്തലങ്ങൾ, SVG ഗ്രാഫിക്‌സ് എന്നിവയിൽ പ്രവർത്തിക്കുക
- കസ്റ്റം ഫോണ്ടുകൾ, ഫോണ്ട് വകഭേദങ്ങൾ, അകലം, വിന്യാസം, വലുപ്പം എന്നിവയോടെ റിച്ച് ടെക്സ്റ്റ് തിരുത്തുക
- കാൻവാസിൽ തന്നെ സ്ഥാനം, സ്നാപ്പിംഗ്, പാളികൾ, ക്രോപ്പിംഗ്, തിരിക്കൽ ക്രമീകരിക്കുക
- ഓരോ വിപണിക്കും ഭാഷാടിസ്ഥാന വാചകവും ചിത്ര മാറ്റങ്ങളും കൈകാര്യം ചെയ്യുക
- ഭാഷാ പ്രീസെറ്റുകൾ ഉപയോഗിക്കുക, വിട്ടുപോയ വാചകം സ്വയമേവ വിവർത്തനം ചെയ്യുക, പുരോഗതി കാണുക
- PNG അല്ലെങ്കിൽ JPEG സ്ക്രീൻഷോട്ടുകൾ ഭാഷയും നിരയും അനുസരിച്ച് ഫോൾഡറുകളിലേക്ക് കയറ്റുമതി ചെയ്യുക
- സാമൂഹ്യ പോസ്റ്റുകൾ, വെബ്‌സൈറ്റുകൾ, പ്രചാരണ പ്രിവ്യൂകൾ എന്നിവയ്ക്കായി ഷോകേസ് കയറ്റുമതി ഉണ്ടാക്കുക
- സ്ക്രീൻഷോട്ടുകൾ നേരിട്ട് App Store Connect-ലേക്ക് അപ്‌ലോഡ് ചെയ്യുക
- അപ്‌ലോഡിന് മുമ്പ് App Store Connect മെറ്റാഡേറ്റ പരിശോധിച്ച് തിരുത്തുക
- കയറ്റുമതികളും സ്റ്റോർ അപ്‌ലോഡുകളും പൂർത്തിയാകുമ്പോൾ അറിയിപ്പുകൾ ലഭിക്കുക
- പ്രോജക്ടുകൾ പ്രാദേശികമായി സൂക്ഷിക്കുക, വേണ്ടിവന്നാൽ iCloud-മായി സമന്വയിപ്പിക്കുക, ZIP ബാക്കപ്പുകൾ ഉണ്ടാക്കുക
- ട്രാക്കിംഗ് ഇല്ല

സാധാരണ സ്ക്രീൻഷോട്ട് ജനറേറ്ററിനെക്കാൾ കൂടുതൽ നിയന്ത്രണവും, ഓരോ ചിത്രവും കൈകൊണ്ട് വീണ്ടും ഉണ്ടാക്കുന്നതിനെക്കാൾ വേഗമേറിയ പ്രവർത്തനരീതിയും വേണ്ട ഇൻഡി ഡെവലപ്പർമാർ, ഉൽപ്പന്ന ടീമുകൾ, ഡിസൈനർമാർ, മാർക്കറ്റർമാർ എന്നിവർക്കായാണ് Screenshot Bro ഒരുക്കിയിരിക്കുന്നത്.

ആദ്യ റിലീസ് ഒരുക്കുകയാണെങ്കിലും, വലിയ അപ്‌ഡേറ്റ്, സീസണൽ പ്രചാരണം അല്ലെങ്കിൽ പുതിയ ഭാഷകളിലേക്കുള്ള വ്യാപനമാണെങ്കിലും — Screenshot Bro നിങ്ങളെ അസംസ്കൃത സ്ക്രീൻഷോട്ടുകളിൽ നിന്ന് സ്റ്റോറിന് തയ്യാറായ മാർക്കറ്റിംഗ് ചിത്രങ്ങളിലേക്ക് വേഗത്തിലും കൂടുതൽ ഏകീകൃതമായും എത്തിക്കുന്നു.

നിങ്ങൾക്ക് App Store സ്ക്രീൻഷോട്ട് സ്രഷ്ടാവ്, സ്ക്രീൻഷോട്ട് ടെംപ്ലേറ്റ് ബിൽഡർ, സ്ക്രീൻഷോട്ട് പ്രാദേശികവൽക്കരണ ഉപകരണം, അല്ലെങ്കിൽ App Store Connect അപ്‌ലോഡർ വേണമെങ്കിൽ, Screenshot Bro മുഴുവൻ പ്രവർത്തനരീതിയും ഒരൊറ്റ കേന്ദ്രീകൃത ആപ്പിൽ സൂക്ഷിക്കുന്നു.

ഉപയോഗ നിബന്ധനകൾ (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["ur-PK"] = """\
Screenshot Bro ایک ایسی ایپ ہے جو App Store کے لیے ایپ اسکرین شاٹس بناتی ہے۔ پورا اسکرین شاٹ سیٹ ایک ہی بار ڈیزائن کریں، ڈیوائس فریم شامل کریں، جس بھی مارکیٹ میں آپ ریلیز کرتے ہیں اس کے لیے ہر سرخی کا ترجمہ کریں، اور براہِ راست App Store Connect پر اپ لوڈ کریں — اپنے Mac سے باہر نکلے بغیر۔

عام ڈیزائن ٹولز کے برعکس، Screenshot Bro ڈیوائس کے مطابق قطاریں، مقامی کاری، App Store Connect اپ لوڈز، بیچ ایکسپورٹ، دوبارہ استعمال ہونے والے پروجیکٹس، اور Model Context Protocol کے ذریعے مقامی AI معاون آٹومیشن کو سمجھتا ہے۔

iPhone، iPad اور Mac لے آؤٹس کے لیے مکمل اسکرین شاٹ سیٹ بنائیں۔ کسی ٹیمپلیٹ سے شروع کریں یا اپنا لے آؤٹ نظام بنائیں۔ اسکرین شاٹس رکھیں، ڈیوائس فریم یا بغیر فریم کی ترتیب شامل کریں، سرخیاں اور تفصیل لکھیں، کسٹم فونٹس کے ساتھ رچ ٹیکسٹ کو انداز دیں، اور کینوس پر ہر تفصیل کو بہتر بنائیں۔

Screenshot Bro آپ کے Mac پر مقامی MCP سرور چلا سکتا ہے۔ Claude Code، Claude Desktop، Cursor یا کوئی اور MCP-موافق معاون جوڑیں اور اسے پروجیکٹ بنانے، قطاریں ترمیم کرنے، شکلیں ترتیب دینے، اسکرین شاٹس درآمد کرنے، متن کا ترجمہ کرنے، کینوس پیش منظر بنانے اور حتمی تصاویر ایکسپورٹ کرنے دیں۔ MCP اختیاری ہے، بطورِ طے شدہ بند رہتا ہے، صرف مقامی کنکشن قبول کرتا ہے، اور رسائی ٹوکن سے محفوظ ہے۔

ریلیز کی اقسام، زبان کے مطابق تبدیلیاں، اسٹور کے مطابق قطار کے منصوبے، اور ایکسپورٹ کے لیے تیار مواد — سب کچھ ایک ہی پروجیکٹ میں رکھیں: App Store، ویب سائٹس، سوشل میڈیا اور لانچ مہمات کے لیے۔

نمایاں خصوصیات:

- ایک ہی پروجیکٹ سے App Store اسکرین شاٹس بنائیں
- بار بار ہونے والی ریلیزز کے لیے بلٹ اِن ٹیمپلیٹس یا اپنے لے آؤٹ استعمال کریں
- کئی تصاویر والی قطاریں، تقابلی لے آؤٹ اور مکمل مہمات ڈیزائن کریں
- قطاروں میں اسکرین شاٹس اجتماعی طور پر درآمد کریں اور تصاویر تیزی سے بدلیں
- iPhone، iPad، Mac اور تجریدی لے آؤٹ کے لیے ڈیوائس فریم شامل کریں
- متن، شکلیں، تصاویر، گریڈیئنٹ، ٹائل والے پس منظر اور SVG گرافکس کے ساتھ کام کریں
- کسٹم فونٹس، فونٹ اقسام، وقفہ، ترتیب اور سائز کے ساتھ رچ ٹیکسٹ میں ترمیم کریں
- کینوس پر ہی جگہ، اسنیپنگ، تہیں، کٹائی اور گھماؤ ایڈجسٹ کریں
- ہر مارکیٹ کے لیے زبان کے مطابق متن اور تصویری تبدیلیاں سنبھالیں
- زبان پری سیٹ استعمال کریں، رہ جانے والا متن خودکار ترجمہ کریں، اور پیش رفت دیکھیں
- PNG یا JPEG اسکرین شاٹس زبان اور قطار کے مطابق فولڈرز میں ایکسپورٹ کریں
- سوشل پوسٹس، ویب سائٹس اور مہم کے پیش منظر کے لیے شوکیس ایکسپورٹ بنائیں
- اسکرین شاٹس براہِ راست App Store Connect پر اپ لوڈ کریں
- اپ لوڈ سے پہلے App Store Connect میٹا ڈیٹا دیکھیں اور ترمیم کریں
- پروجیکٹ مقامی رکھیں، ضرورت ہو تو iCloud سے ہم آہنگ کریں، اور ZIP بیک اپ بنائیں
- کوئی ٹریکنگ نہیں

Screenshot Bro اُن انڈی ڈویلپرز، پروڈکٹ ٹیموں، ڈیزائنرز اور مارکیٹرز کے لیے بنایا گیا ہے جنہیں عام اسکرین شاٹ جنریٹر سے زیادہ کنٹرول چاہیے اور ہر مارکیٹنگ تصویر ہاتھ سے دوبارہ بنانے کے مقابلے میں تیز طریقۂ کار چاہیے۔

اگر آپ کو App Store اسکرین شاٹ بنانے والا، اسکرین شاٹ ٹیمپلیٹ بلڈر، اسکرین شاٹ مقامی کاری کا ٹول، App Store Connect اپ لوڈر، یا MCP کے لیے تیار اسکرین شاٹ آٹومیشن ٹول چاہیے، تو Screenshot Bro پورا طریقۂ کار ایک ہی مرکوز Mac ایپ میں رکھتا ہے۔

استعمال کی شرائط (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["ur-PK"] = """\
Screenshot Bro ایک اسکرین شاٹ بنانے اور ترمیم کرنے والی ایپ ہے جو خاص طور پر App Store اسکرین شاٹس کے لیے بنائی گئی ہے۔ دوبارہ استعمال ہونے والے ٹیمپلیٹس بنائیں، مکمل اسکرین شاٹ سیٹ ڈیزائن کریں، اپنا پیغام ہر زبان میں ڈھالیں، پھر تیار اسٹور مواد ایکسپورٹ یا اپ لوڈ کریں۔

عام ڈیزائن ٹولز کے برعکس، Screenshot Bro ڈیوائس کے مطابق قطاریں، مقامی کاری، App Store Connect اپ لوڈز، بیچ ایکسپورٹ، اور دوبارہ استعمال ہونے والے پروجیکٹس کو سمجھتا ہے۔

iPhone، iPad اور Mac لے آؤٹس کے لیے مکمل اسکرین شاٹ سیٹ بنائیں۔ کسی ٹیمپلیٹ سے شروع کریں یا اپنا لے آؤٹ نظام بنائیں۔ اسکرین شاٹس رکھیں، ڈیوائس فریم یا بغیر فریم کی ترتیب شامل کریں، سرخیاں اور تفصیل لکھیں، کسٹم فونٹس کے ساتھ رچ ٹیکسٹ کو انداز دیں، اور کینوس پر ہر تفصیل کو بہتر بنائیں۔

ریلیز کی اقسام، زبان کے مطابق تبدیلیاں، اسٹور کے مطابق قطار کے منصوبے، اور ایکسپورٹ کے لیے تیار مواد — سب کچھ ایک ہی پروجیکٹ میں رکھیں: App Store، ویب سائٹس، سوشل میڈیا اور لانچ مہمات کے لیے۔

نمایاں خصوصیات:

- ایک ہی پروجیکٹ سے App Store اسکرین شاٹس بنائیں
- بار بار ہونے والی ریلیزز کے لیے بلٹ اِن ٹیمپلیٹس یا اپنے لے آؤٹ استعمال کریں
- کئی تصاویر والی قطاریں، تقابلی لے آؤٹ اور مکمل مہمات ڈیزائن کریں
- قطاروں میں اسکرین شاٹس اجتماعی طور پر درآمد کریں اور تصاویر تیزی سے بدلیں
- iPhone، iPad، Mac اور تجریدی لے آؤٹ کے لیے ڈیوائس فریم شامل کریں
- متن، شکلیں، تصاویر، گریڈیئنٹ، ٹائل والے پس منظر اور SVG گرافکس کے ساتھ کام کریں
- کسٹم فونٹس، فونٹ اقسام، وقفہ، ترتیب اور سائز کے ساتھ رچ ٹیکسٹ میں ترمیم کریں
- کینوس پر ہی جگہ، اسنیپنگ، تہیں، کٹائی اور گھماؤ ایڈجسٹ کریں
- ہر مارکیٹ کے لیے زبان کے مطابق متن اور تصویری تبدیلیاں سنبھالیں
- زبان پری سیٹ استعمال کریں، رہ جانے والا متن خودکار ترجمہ کریں، اور پیش رفت دیکھیں
- PNG یا JPEG اسکرین شاٹس زبان اور قطار کے مطابق فولڈرز میں ایکسپورٹ کریں
- سوشل پوسٹس، ویب سائٹس اور مہم کے پیش منظر کے لیے شوکیس ایکسپورٹ بنائیں
- اسکرین شاٹس براہِ راست App Store Connect پر اپ لوڈ کریں
- اپ لوڈ سے پہلے App Store Connect میٹا ڈیٹا دیکھیں اور ترمیم کریں
- ایکسپورٹ اور اسٹور اپ لوڈ مکمل ہونے پر اطلاعات حاصل کریں
- پروجیکٹ مقامی رکھیں، ضرورت ہو تو iCloud سے ہم آہنگ کریں، اور ZIP بیک اپ بنائیں
- کوئی ٹریکنگ نہیں

Screenshot Bro اُن انڈی ڈویلپرز، پروڈکٹ ٹیموں، ڈیزائنرز اور مارکیٹرز کے لیے بنایا گیا ہے جنہیں عام اسکرین شاٹ جنریٹر سے زیادہ کنٹرول چاہیے اور ہر مارکیٹنگ تصویر ہاتھ سے دوبارہ بنانے کے مقابلے میں تیز طریقۂ کار چاہیے۔

چاہے آپ پہلی ریلیز تیار کر رہے ہوں، بڑا اپ ڈیٹ، موسمی مہم، یا نئی زبانوں میں توسیع — Screenshot Bro آپ کو خام اسکرین شاٹس سے اسٹور کے لیے تیار مارکیٹنگ تصاویر تک زیادہ تیزی اور زیادہ یکسانیت کے ساتھ پہنچاتا ہے۔

اگر آپ کو App Store اسکرین شاٹ بنانے والا، اسکرین شاٹ ٹیمپلیٹ بلڈر، اسکرین شاٹ مقامی کاری کا ٹول، یا App Store Connect اپ لوڈر چاہیے، تو Screenshot Bro پورا طریقۂ کار ایک ہی مرکوز ایپ میں رکھتا ہے۔

استعمال کی شرائط (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

SCRIPT_RANGE = {"ru": (0x0400, 0x04FF), "uk": (0x0400, 0x04FF),
                "th": (0x0E00, 0x0E7F), "zh-Hant": (0x4E00, 0x9FFF),
                "el": (0x0370, 0x03FF),
                # 2026-09-10. Every one of these carries Latin brand atoms
                # (Screenshot Bro, iPhone, PNG…), so the 0.3 floor is what makes
                # the check survive them while still catching a transliteration.
                "hi": (0x0900, 0x097F), "mr-IN": (0x0900, 0x097F),
                "bn-BD": (0x0980, 0x09FF), "gu-IN": (0x0A80, 0x0AFF),
                "ta-IN": (0x0B80, 0x0BFF), "te-IN": (0x0C00, 0x0C7F),
                "kn-IN": (0x0C80, 0x0CFF), "ml-IN": (0x0D00, 0x0D7F),
                "ur-PK": (0x0600, 0x06FF)}
RU_ONLY = "ыъэё"     # absent from Ukrainian
UK_ONLY = "іїєґ"     # absent from Russian

# Letters that belong to a close neighbour and never to this locale. Each of
# these pairs is a language a translator can slide into without noticing, and
# every pair was produced in the same 2026-09-09 batch, so the guard is cheap.
FOREIGN_CHARS = {
    "cs": "ľĺŕäô",      # Slovak
    "sk": "řě",         # Czech
    "sl-SI": "ćđ",      # Croatian
    "ca": "ñ",          # Castilian — Catalan writes "ny"
}

# Same idea one level up: vocabulary, where the scripts are identical.
FOREIGN_WORDS = {
    "es-MX": ["ordenador", "móvil", "vosotros", "vuestr", "fichero"],
    "fr-CA": ["maquette"],   # RESEARCH.md Finding 5 — returns Marquette in CA
    "hr": ["snimak", "fascikl"],
    # Hindi and Marathi share Devanagari, so SCRIPT_RANGE cannot tell them apart
    # and a translator sliding between them leaves no trace the script check sees.
    # These are function words, not vocabulary: each is ordinary in one and wrong
    # in the other.
    "hi": ["आहे", "साठी", "तुमच्या", "आणि"],
    "mr-IN": ["के लिए", "चाहिए", "हैं", "और"],
}


def text_for(platform, locale, en_us):
    """The description to write. `en_us` is that version's own live en-US row."""
    if locale in SPELLING_PASS:
        text = british(en_us)
        if text == en_us:
            raise SystemExit(f"{locale}: the spelling pass changed nothing — the en-US "
                             "copy no longer contains a mapped spelling. Update _BRITISH.")
        return text
    return (DESC_MAC if platform == "MAC_OS" else DESC_IOS)[locale]


def _script_ratio(text, lo, hi):
    letters = [c for c in text if c.isalpha()]
    if not letters:
        return 0.0
    return sum(lo <= ord(c) <= hi for c in letters) / len(letters)


def review(platform, locale, text, en_us=None):
    """Every problem with one description. An empty list means it is safe to write."""
    bad = []
    if len(text) > LIMIT:
        bad.append(f"{len(text)} chars — over the {LIMIT} ceiling")
    elif len(text) > TRIM_AT:
        bad.append(f"{len(text)} chars — over {TRIM_AT}, apply the trim recipe")

    missing = [a for a in ATOMS if a not in text]
    if platform == "MAC_OS":
        missing += [a for a in ATOMS_MAC_ONLY if a not in text]
    if missing:
        bad.append("missing verbatim atoms: " + ", ".join(missing))
    if platform == "IOS":
        leaked = [w for w in BANNED_IOS if w in text]
        if leaked:
            bad.append("macOS-only feature in the iOS listing: " + ", ".join(leaked))

    low = text.lower()
    priced = [w for w in BANNED_ANY if w in low]
    if priced:
        bad.append("price/discount wording: " + ", ".join(priced))
    platforms = [w for w in BANNED_PLATFORM if w in low]
    if platforms:
        bad.append("competing platform named (2.3.10): " + ", ".join(platforms))

    if en_us is not None and text == en_us:
        bad.append("identical to the en-US source — this locale was left behind")
    if "�" in text:
        bad.append("U+FFFD replacement character — encoding damage")

    for ch in SCRIPT_REQUIRED.get(locale, ""):
        if ch not in low:
            bad.append(f"expected character {ch!r} absent — diacritics stripped?")
    lo_hi = SCRIPT_RANGE.get(locale)
    if lo_hi and _script_ratio(text, *lo_hi) < 0.3:
        bad.append("mostly not in the expected script — untranslated or transliterated")
    intruders = sorted({c for c in low if c in FOREIGN_CHARS.get(locale, "")})
    if intruders:
        bad.append("letters from a neighbouring language: " + "".join(intruders))
    borrowed = [w for w in FOREIGN_WORDS.get(locale, []) if w in low]
    if borrowed:
        bad.append("vocabulary from a neighbouring language: " + ", ".join(borrowed))

    if locale == "uk" and any(c in text for c in RU_ONLY):
        bad.append("Russian-only letters in Ukrainian — derived from ru, not en-US")
    if locale == "ru" and not any(c in text for c in RU_ONLY):
        bad.append("no Russian-only letter — is this actually Ukrainian?")
    if locale == "uk" and not any(c in text for c in UK_ONLY):
        bad.append("no Ukrainian-only letter — is this actually Russian?")
    if locale == "zh-Hant":
        leaked = sorted({c for c in text if c in SIMPLIFIED_ONLY})
        if leaked:
            bad.append("simplified-only characters: " + "".join(leaked))
        if sum(v in text for v in TAIWAN_VOCAB) < 4:
            bad.append("too little Taiwan vocabulary — converted rather than rewritten")

    bullets = [ln for ln in text.split("\n") if ln.startswith("- ")]
    least = 16 if platform == "MAC_OS" else 17
    if len(bullets) < least:
        bad.append(f"{len(bullets)} bullets — trimmed past the {least} the recipe allows")
    paragraphs = [p for p in text.split("\n\n") if p.strip()]
    if len(paragraphs) < 10:
        bad.append(f"{len(paragraphs)} paragraphs — a never-trim section is missing")
    if not text.rstrip().endswith(ATOMS[-1]):
        bad.append("does not end with the EULA line")
    heading = text.split("\n- ")[0].rstrip().split("\n")[-1]
    if not heading.endswith((":", "：")):
        bad.append("no key-features heading before the bullets")
    return bad


def _source_versions():
    """Newest version per platform, whatever state it is in — reads are never blocked."""
    from apply import versions
    newest = {}
    for vid, platform, vstr, state in versions():
        newest.setdefault(platform, (vid, vstr, state))
    return newest


def main(offline):
    if offline:
        sources = {"MAC_OS": (None, "offline", "-", None), "IOS": (None, "offline", "-", None)}
    else:
        from apply import version_localizations
        sources = {}
        for platform, (vid, vstr, state) in _source_versions().items():
            rows = version_localizations(vid)
            en = next((x["attributes"]["description"] for x in rows
                       if x["attributes"]["locale"] == "en-US"), None)
            live = {x["attributes"]["locale"]: (x["attributes"].get("description") or "")
                    for x in rows}
            sources[platform] = (vid, vstr, state, (en, live))

    failures = 0
    for platform in ("MAC_OS", "IOS"):
        vid, vstr, state, fetched = sources[platform]
        print(f"\n== {platform} {vstr} ({state})")
        en_us, live = fetched if fetched else (None, {})
        for locale in LOCALES:
            if locale in SPELLING_PASS and not en_us:
                print(f"  {locale:9} SKIP  spelling pass needs the live en-US row")
                continue
            try:
                text = text_for(platform, locale, en_us or "")
            except KeyError:
                print(f"  {locale:9} MISSING from descriptions.py")
                failures += 1
                continue
            problems = review(platform, locale, text, en_us)
            mark = "OK  " if not problems else "FAIL"
            if not en_us:
                note = ""
            elif locale not in live:
                note = "  live: locale not created yet"
            else:
                note = ("  live: still en-US" if live[locale] == en_us
                        else "  live: translated")
            print(f"  {locale:9} {mark} {len(text):5}/{LIMIT}{note}")
            for problem in problems:
                print(f"            - {problem}")
            failures += bool(problems)
    print(f"\n  {failures} description(s) not ready to write")
    return failures


if __name__ == "__main__":
    sys.exit(1 if main("--offline" in sys.argv) else 0)
