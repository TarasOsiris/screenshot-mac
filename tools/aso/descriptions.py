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
           "sl-SI"]

# Spelling pass over the live en-US row rather than a stored translation.
SPELLING_PASS = {"en-GB", "en-AU"}

# Must survive byte-identical in every locale.
ATOMS = ["Screenshot Bro", "App Store", "App Store Connect",
         "iPhone", "iPad", "Mac", "Pixel", "Android", "PNG", "JPEG", "SVG",
         "iCloud", "ZIP",
         "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"]
ATOMS_MAC_ONLY = ["MCP", "Model Context Protocol", "Claude Code",
                  "Claude Desktop", "Cursor"]
BANNED_IOS = ["MCP", "Model Context Protocol", "Finder"]

# Price talk in the description of a paywalled app is a rejection class.
# 2.3.10 — the competing store. Apple rejected 4.9 (iOS) on 2026-09-01 for naming
# Google Play in the description, so a reintroduction has to fail the review, not
# the store. Latin and local script: a translated description is still metadata.
BANNED_PLATFORM = ["google play", "googleplay", "google", "play store",
                   "гугл", "плей", "구글", "グーグル", "谷歌", "جوجل", "גוגל"]

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

Monte conjuntos completos de capturas para iPhone, iPad, Mac, celulares Android, tablets Android e layouts do Pixel. Comece por um modelo ou crie o seu próprio sistema de layout. Solte as capturas, adicione molduras de dispositivos ou composições sem moldura, escreva títulos e legendas, estilize texto rico com fontes personalizadas e ajuste cada detalhe no canvas.

O Screenshot Bro pode hospedar um servidor MCP local no seu Mac. Conecte um assistente compatível com MCP, como Claude Code, Claude Desktop, Cursor ou outro cliente, e deixe que ele crie projetos, edite linhas, organize formas, importe capturas, traduza textos, renderize prévias do canvas e exporte as imagens finais. O MCP é opcional, fica desativado por padrão, aceita apenas conexões locais e é protegido por um token de acesso.

Mantenha variações de lançamento, substituições por idioma, planos de linhas por loja e materiais prontos para exportar em um único projeto — para a App Store, sites, redes sociais e campanhas de lançamento.

Principais recursos:

- Crie capturas para a App Store a partir de um único projeto
- Use modelos prontos ou layouts personalizados para lançamentos recorrentes
- Desenhe linhas com várias capturas, layouts comparativos e campanhas completas
- Importe capturas em lote para as linhas e troque imagens rapidamente
- Adicione molduras de iPhone, iPad, Mac, Android, Pixel e layouts abstratos
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

Monte conjuntos completos de capturas para iPhone, iPad, Mac, celulares Android, tablets Android e layouts do Pixel. Comece por um modelo ou crie o seu próprio sistema de layout. Solte as capturas, adicione molduras de dispositivos ou composições sem moldura, escreva títulos e legendas, estilize texto rico com fontes personalizadas e ajuste cada detalhe no canvas.

Mantenha variações de lançamento, substituições por idioma, planos de linhas por loja e materiais prontos para exportar em um único projeto — para a App Store, sites, redes sociais e campanhas de lançamento.

Principais recursos:

- Crie capturas para a App Store a partir de um único projeto
- Use modelos prontos ou layouts personalizados para lançamentos recorrentes
- Desenhe linhas com várias capturas, layouts comparativos e campanhas completas
- Importe capturas em lote para as linhas e troque imagens rapidamente
- Adicione molduras de iPhone, iPad, Mac, Android, Pixel e layouts abstratos
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

Собирайте полные наборы скриншотов для iPhone, iPad, Mac, Android-смартфонов, Android-планшетов и раскладок Pixel. Начните с шаблона или создайте собственную систему макетов. Добавляйте скриншоты, рамки устройств или композиции без рамок, пишите заголовки и подписи, оформляйте текст своими шрифтами и доводите каждую деталь на холсте.

Screenshot Bro умеет поднимать локальный MCP-сервер на вашем Mac. Подключите совместимого с MCP ассистента — Claude Code, Claude Desktop, Cursor или любой другой клиент — и он создаст проекты, отредактирует ряды, расставит фигуры, импортирует скриншоты, переведёт текст, отрисует превью холста и экспортирует финальные изображения. MCP включается по желанию, по умолчанию выключен, работает только на локальном интерфейсе и защищён токеном доступа.

Держите варианты релизов, переопределения для отдельных языков, планы рядов под каждый магазин и готовые к экспорту материалы в одном проекте — для App Store, сайтов, соцсетей и запусков.

Основные возможности:

- Создавайте скриншоты для App Store в одном проекте
- Используйте встроенные шаблоны или свои макеты для регулярных релизов
- Проектируйте ряды из нескольких кадров, сравнительные макеты и целые кампании
- Импортируйте скриншоты в ряды пакетом и быстро заменяйте изображения
- Добавляйте рамки устройств для iPhone, iPad, Mac, Android, Pixel и абстрактные макеты
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

Собирайте полные наборы скриншотов для iPhone, iPad, Mac, Android-смартфонов, Android-планшетов и раскладок Pixel. Начните с шаблона или создайте собственную систему макетов. Добавляйте скриншоты, рамки устройств или композиции без рамок, пишите заголовки и подписи, оформляйте текст своими шрифтами и доводите каждую деталь на холсте.

Держите варианты релизов, переопределения для отдельных языков, планы рядов под каждый магазин и готовые к экспорту материалы в одном проекте — для App Store, сайтов, соцсетей и запусков.

Основные возможности:

- Создавайте скриншоты для App Store в одном проекте
- Используйте встроенные шаблоны или свои макеты для регулярных релизов
- Проектируйте ряды из нескольких кадров, сравнительные макеты и целые кампании
- Импортируйте скриншоты в ряды пакетом и быстро заменяйте изображения
- Добавляйте рамки устройств для iPhone, iPad, Mac, Android, Pixel и абстрактные макеты
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

Складайте повні набори знімків для iPhone, iPad, Mac, смартфонів Android, планшетів Android і розкладок Pixel. Почніть із шаблона або створіть власну систему макетів. Додавайте знімки, рамки пристроїв чи композиції без рамок, пишіть заголовки та підписи, оформлюйте текст власними шрифтами й доводьте кожну деталь на полотні.

Screenshot Bro може підняти локальний сервер MCP на вашому Mac. Підключіть сумісного з MCP асистента — Claude Code, Claude Desktop, Cursor або інший клієнт — і він створить проєкти, відредагує рядки, розставить фігури, імпортує знімки, перекладе текст, покаже попередній вигляд полотна й експортує готові зображення. MCP вмикається за бажанням, типово вимкнений, працює лише на локальному інтерфейсі та захищений токеном доступу.

Тримайте варіанти релізів, окремі тексти для кожної мови, плани рядків під кожен магазин і готові до експорту матеріали в одному проєкті — для App Store, сайтів, соцмереж і запусків.

Основні можливості:

- Створюйте знімки для App Store в одному проєкті
- Використовуйте вбудовані шаблони або власні макети для регулярних релізів
- Проєктуйте рядки з кількох кадрів, порівняльні макети й цілі кампанії
- Імпортуйте знімки в рядки пакетом і швидко замінюйте зображення
- Додавайте рамки пристроїв для iPhone, iPad, Mac, Android, Pixel і абстрактні макети
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

Складайте повні набори знімків для iPhone, iPad, Mac, смартфонів Android, планшетів Android і розкладок Pixel. Почніть із шаблона або створіть власну систему макетів. Додавайте знімки, рамки пристроїв чи композиції без рамок, пишіть заголовки та підписи, оформлюйте текст власними шрифтами й доводьте кожну деталь на полотні.

Тримайте варіанти релізів, окремі тексти для кожної мови, плани рядків під кожен магазин і готові до експорту матеріали в одному проєкті — для App Store, сайтів, соцмереж і запусків.

Основні можливості:

- Створюйте знімки для App Store в одному проєкті
- Використовуйте вбудовані шаблони або власні макети для регулярних релізів
- Проєктуйте рядки з кількох кадрів, порівняльні макети й цілі кампанії
- Імпортуйте знімки в рядки пакетом і швидко замінюйте зображення
- Додавайте рамки пристроїв для iPhone, iPad, Mac, Android, Pixel і абстрактні макети
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

Twórz kompletne zestawy zrzutów dla iPhone'a, iPada, Maca, telefonów i tabletów z Androidem oraz układów Pixel. Zacznij od szablonu albo zbuduj własny system układów. Wrzuć zrzuty, dodaj ramki urządzeń lub kompozycje bez ramek, napisz nagłówki i podpisy, sformatuj tekst własnymi czcionkami i dopracuj każdy szczegół na obszarze roboczym.

Screenshot Bro może uruchomić lokalny serwer MCP na Twoim Macu. Podłącz asystenta zgodnego z MCP — Claude Code, Claude Desktop, Cursor lub innego klienta — i pozwól mu tworzyć projekty, edytować wiersze, rozmieszczać kształty, importować zrzuty, tłumaczyć teksty, renderować podglądy obszaru roboczego i eksportować gotowe obrazy. MCP jest opcjonalny, domyślnie wyłączony, działa tylko lokalnie i jest chroniony tokenem dostępu.

Trzymaj warianty wydań, teksty przypisane do poszczególnych języków, plany wierszy pod konkretne sklepy i gotowe do eksportu materiały w jednym projekcie — dla App Store, stron internetowych, mediów społecznościowych i kampanii premierowych.

Najważniejsze funkcje:

- Twórz zrzuty do App Store z jednego projektu
- Korzystaj z wbudowanych szablonów lub własnych układów przy kolejnych premierach
- Projektuj wiersze z wielu kadrów, układy porównawcze i całe kampanie
- Importuj zrzuty do wierszy wsadowo i szybko podmieniaj obrazy
- Dodawaj ramki urządzeń dla iPhone, iPad, Mac, Android, Pixel i układy abstrakcyjne
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

Twórz kompletne zestawy zrzutów dla iPhone'a, iPada, Maca, telefonów i tabletów z Androidem oraz układów Pixel. Zacznij od szablonu albo zbuduj własny system układów. Wrzuć zrzuty, dodaj ramki urządzeń lub kompozycje bez ramek, napisz nagłówki i podpisy, sformatuj tekst własnymi czcionkami i dopracuj każdy szczegół na obszarze roboczym.

Trzymaj warianty wydań, teksty przypisane do poszczególnych języków, plany wierszy pod konkretne sklepy i gotowe do eksportu materiały w jednym projekcie — dla App Store, stron internetowych, mediów społecznościowych i kampanii premierowych.

Najważniejsze funkcje:

- Twórz zrzuty do App Store z jednego projektu
- Korzystaj z wbudowanych szablonów lub własnych układów przy kolejnych premierach
- Projektuj wiersze z wielu kadrów, układy porównawcze i całe kampanie
- Importuj zrzuty do wierszy wsadowo i szybko podmieniaj obrazy
- Dodawaj ramki urządzeń dla iPhone, iPad, Mac, Android, Pixel i układy abstrakcyjne
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

iPhone, iPad, Mac, Android telefonlar, Android tabletler ve Pixel düzenleri için eksiksiz ekran görüntüsü setleri hazırlayın. Bir şablonla başlayın ya da kendi düzen sisteminizi kurun. Ekran görüntülerini bırakın, cihaz çerçeveleri veya çerçevesiz kompozisyonlar ekleyin, başlıklar ve açıklamalar yazın, zengin metni özel yazı tipleriyle biçimlendirin ve her ayrıntıyı tuval üzerinde ince ayarlayın.

Screenshot Bro, Mac'inizde yerel bir MCP sunucusu çalıştırabilir. Claude Code, Claude Desktop, Cursor gibi MCP uyumlu bir asistanı ya da başka bir istemciyi bağlayın; projeler oluştursun, satırları düzenlesin, şekilleri yerleştirsin, ekran görüntüleri içe aktarsın, metinleri çevirsin, tuval önizlemeleri üretsin ve son görselleri dışa aktarsın. MCP isteğe bağlıdır, varsayılan olarak kapalıdır, yalnızca yerel bağlantıları kabul eder ve bir erişim jetonuyla korunur.

Sürüm varyantlarını, dile özel metinleri, mağazaya özel satır planlarını ve dışa aktarmaya hazır görselleri tek bir projede tutun — App Store, web siteleri, sosyal medya ve lansman kampanyaları için.

Öne çıkan özellikler:

- App Store ekran görüntülerini tek projeden oluşturun
- Tekrarlayan lansmanlar için hazır şablonları veya kendi düzenlerinizi kullanın
- Çok kareli satırlar, karşılaştırma düzenleri ve eksiksiz kampanyalar tasarlayın
- Ekran görüntülerini satırlara toplu içe aktarın ve görselleri hızla değiştirin
- iPhone, iPad, Mac, Android, Pixel ve soyut düzenler için cihaz çerçeveleri ekleyin
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

iPhone, iPad, Mac, Android telefonlar, Android tabletler ve Pixel düzenleri için eksiksiz ekran görüntüsü setleri hazırlayın. Bir şablonla başlayın ya da kendi düzen sisteminizi kurun. Ekran görüntülerini bırakın, cihaz çerçeveleri veya çerçevesiz kompozisyonlar ekleyin, başlıklar ve açıklamalar yazın, zengin metni özel yazı tipleriyle biçimlendirin ve her ayrıntıyı tuval üzerinde ince ayarlayın.

Sürüm varyantlarını, dile özel metinleri, mağazaya özel satır planlarını ve dışa aktarmaya hazır görselleri tek bir projede tutun — App Store, web siteleri, sosyal medya ve lansman kampanyaları için.

Öne çıkan özellikler:

- App Store ekran görüntülerini tek projeden oluşturun
- Tekrarlayan lansmanlar için hazır şablonları veya kendi düzenlerinizi kullanın
- Çok kareli satırlar, karşılaştırma düzenleri ve eksiksiz kampanyalar tasarlayın
- Ekran görüntülerini satırlara toplu içe aktarın ve görselleri hızla değiştirin
- iPhone, iPad, Mac, Android, Pixel ve soyut düzenler için cihaz çerçeveleri ekleyin
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

Bangun set screenshot lengkap untuk iPhone, iPad, Mac, ponsel Android, tablet Android, dan tata letak Pixel. Mulai dari templat atau buat sistem tata letak sendiri. Masukkan screenshot, tambahkan bingkai perangkat atau komposisi tanpa bingkai, tulis headline dan keterangan, atur gaya teks dengan font kustom, dan sempurnakan setiap detail di kanvas.

Screenshot Bro bisa menjalankan server MCP lokal di Mac kamu. Hubungkan asisten yang kompatibel dengan MCP seperti Claude Code, Claude Desktop, Cursor, atau klien lain, lalu biarkan asisten itu membuat proyek, mengedit baris, menata bentuk, mengimpor screenshot, menerjemahkan teks, merender pratinjau kanvas, dan mengekspor gambar akhir. MCP bersifat opsional, mati secara bawaan, hanya menerima koneksi lokal, dan dilindungi token akses.

Simpan varian rilis, teks khusus per bahasa, rencana baris khusus per toko, dan aset siap ekspor dalam satu proyek — untuk App Store, situs web, media sosial, dan kampanye peluncuran.

Fitur utama:

- Buat screenshot App Store dari satu proyek
- Pakai templat bawaan atau tata letak sendiri untuk peluncuran berikutnya
- Rancang baris multi-gambar, tata letak perbandingan, dan kampanye lengkap
- Impor screenshot ke baris secara massal dan ganti gambar dengan cepat
- Tambahkan bingkai perangkat untuk iPhone, iPad, Mac, Android, Pixel, dan tata letak abstrak
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

Bangun set screenshot lengkap untuk iPhone, iPad, Mac, ponsel Android, tablet Android, dan tata letak Pixel. Mulai dari templat atau buat sistem tata letak sendiri. Masukkan screenshot, tambahkan bingkai perangkat atau komposisi tanpa bingkai, tulis headline dan keterangan, atur gaya teks dengan font kustom, dan sempurnakan setiap detail di kanvas.

Simpan varian rilis, teks khusus per bahasa, rencana baris khusus per toko, dan aset siap ekspor dalam satu proyek — untuk App Store, situs web, media sosial, dan kampanye peluncuran.

Fitur utama:

- Buat screenshot App Store dari satu proyek
- Pakai templat bawaan atau tata letak sendiri untuk peluncuran berikutnya
- Rancang baris multi-gambar, tata letak perbandingan, dan kampanye lengkap
- Impor screenshot ke baris secara massal dan ganti gambar dengan cepat
- Tambahkan bingkai perangkat untuk iPhone, iPad, Mac, Android, Pixel, dan tata letak abstrak
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

Tạo trọn bộ ảnh chụp cho iPhone, iPad, Mac, điện thoại Android, máy tính bảng Android và bố cục Pixel. Bắt đầu từ mẫu có sẵn hoặc tự xây hệ thống bố cục riêng. Kéo ảnh chụp vào, thêm khung thiết bị hoặc dựng ảnh không khung, viết tiêu đề và chú thích, tạo kiểu chữ với phông tùy chỉnh và chỉnh từng chi tiết ngay trên canvas.

Screenshot Bro có thể chạy một máy chủ MCP cục bộ trên máy Mac của bạn. Kết nối trợ lý tương thích MCP như Claude Code, Claude Desktop, Cursor hoặc ứng dụng khác, rồi để nó tạo dự án, sửa hàng, sắp xếp hình khối, nhập ảnh chụp, dịch văn bản, kết xuất bản xem trước canvas và xuất ảnh cuối. MCP là tùy chọn, mặc định tắt, chỉ nhận kết nối cục bộ và được bảo vệ bằng token truy cập.

Giữ các biến thể bản phát hành, phần chữ riêng theo từng ngôn ngữ, bố cục hàng riêng cho từng cửa hàng và tài nguyên sẵn sàng xuất trong cùng một dự án — cho App Store, website, mạng xã hội và các chiến dịch ra mắt.

Tính năng chính:

- Tạo ảnh chụp cho App Store từ một dự án
- Dùng mẫu có sẵn hoặc bố cục riêng cho những lần phát hành sau
- Thiết kế hàng nhiều ảnh, bố cục so sánh và trọn chiến dịch
- Nhập ảnh chụp vào hàng theo lô và thay ảnh thật nhanh
- Thêm khung thiết bị cho iPhone, iPad, Mac, Android, Pixel và bố cục trừu tượng
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

Tạo trọn bộ ảnh chụp cho iPhone, iPad, Mac, điện thoại Android, máy tính bảng Android và bố cục Pixel. Bắt đầu từ mẫu có sẵn hoặc tự xây hệ thống bố cục riêng. Kéo ảnh chụp vào, thêm khung thiết bị hoặc dựng ảnh không khung, viết tiêu đề và chú thích, tạo kiểu chữ với phông tùy chỉnh và chỉnh từng chi tiết ngay trên canvas.

Giữ các biến thể bản phát hành, phần chữ riêng theo từng ngôn ngữ, bố cục hàng riêng cho từng cửa hàng và tài nguyên sẵn sàng xuất trong cùng một dự án — cho App Store, website, mạng xã hội và các chiến dịch ra mắt.

Tính năng chính:

- Tạo ảnh chụp cho App Store từ một dự án
- Dùng mẫu có sẵn hoặc bố cục riêng cho những lần phát hành sau
- Thiết kế hàng nhiều ảnh, bố cục so sánh và trọn chiến dịch
- Nhập ảnh chụp vào hàng theo lô và thay ảnh thật nhanh
- Thêm khung thiết bị cho iPhone, iPad, Mac, Android, Pixel và bố cục trừu tượng
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

สร้างชุดภาพหน้าจอครบชุดสำหรับ iPhone, iPad, Mac, โทรศัพท์ Android, แท็บเล็ต Android และเลย์เอาต์ Pixel เริ่มจากเทมเพลตหรือสร้างระบบเลย์เอาต์ของคุณเอง วางภาพหน้าจอลงไป เพิ่มกรอบอุปกรณ์หรือจัดองค์ประกอบแบบไม่มีกรอบ เขียนหัวข้อและคำบรรยาย จัดรูปแบบข้อความด้วยฟอนต์ของคุณเอง และปรับทุกรายละเอียดบนพื้นที่ทำงาน

Screenshot Bro เปิดเซิร์ฟเวอร์ MCP ในเครื่อง Mac ของคุณได้ เชื่อมต่อผู้ช่วยที่รองรับ MCP เช่น Claude Code, Claude Desktop, Cursor หรือไคลเอนต์อื่น แล้วให้มันสร้างโปรเจกต์ แก้ไขแถว จัดวางรูปทรง นำเข้าภาพหน้าจอ แปลข้อความ เรนเดอร์ตัวอย่างพื้นที่ทำงาน และส่งออกภาพสุดท้าย MCP เป็นตัวเลือกเสริม ปิดอยู่ตามค่าเริ่มต้น รับเฉพาะการเชื่อมต่อในเครื่อง และป้องกันด้วยโทเคนการเข้าถึง

เก็บเวอร์ชันของแต่ละรอบอัปเดต ข้อความเฉพาะของแต่ละภาษา แผนแถวของแต่ละสโตร์ และไฟล์ที่พร้อมส่งออก ไว้ในโปรเจกต์เดียว สำหรับ App Store, เว็บไซต์, โซเชียลมีเดีย และแคมเปญเปิดตัว

ฟีเจอร์หลัก:

- สร้างภาพหน้าจอสำหรับ App Store จากโปรเจกต์เดียว
- ใช้เทมเพลตที่มีให้หรือเลย์เอาต์ของคุณเองสำหรับการปล่อยอัปเดตครั้งถัดไป
- ออกแบบแถวหลายภาพ เลย์เอาต์เปรียบเทียบ และแคมเปญทั้งชุด
- นำเข้าภาพหน้าจอเข้าแถวเป็นชุดและเปลี่ยนรูปได้อย่างรวดเร็ว
- เพิ่มกรอบอุปกรณ์สำหรับ iPhone, iPad, Mac, Android, Pixel และเลย์เอาต์แบบนามธรรม
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

สร้างชุดภาพหน้าจอครบชุดสำหรับ iPhone, iPad, Mac, โทรศัพท์ Android, แท็บเล็ต Android และเลย์เอาต์ Pixel เริ่มจากเทมเพลตหรือสร้างระบบเลย์เอาต์ของคุณเอง วางภาพหน้าจอลงไป เพิ่มกรอบอุปกรณ์หรือจัดองค์ประกอบแบบไม่มีกรอบ เขียนหัวข้อและคำบรรยาย จัดรูปแบบข้อความด้วยฟอนต์ของคุณเอง และปรับทุกรายละเอียดบนพื้นที่ทำงาน

เก็บเวอร์ชันของแต่ละรอบอัปเดต ข้อความเฉพาะของแต่ละภาษา แผนแถวของแต่ละสโตร์ และไฟล์ที่พร้อมส่งออก ไว้ในโปรเจกต์เดียว สำหรับ App Store, เว็บไซต์, โซเชียลมีเดีย และแคมเปญเปิดตัว

ฟีเจอร์หลัก:

- สร้างภาพหน้าจอสำหรับ App Store จากโปรเจกต์เดียว
- ใช้เทมเพลตที่มีให้หรือเลย์เอาต์ของคุณเองสำหรับการปล่อยอัปเดตครั้งถัดไป
- ออกแบบแถวหลายภาพ เลย์เอาต์เปรียบเทียบ และแคมเปญทั้งชุด
- นำเข้าภาพหน้าจอเข้าแถวเป็นชุดและเปลี่ยนรูปได้อย่างรวดเร็ว
- เพิ่มกรอบอุปกรณ์สำหรับ iPhone, iPad, Mac, Android, Pixel และเลย์เอาต์แบบนามธรรม
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

為 iPhone、iPad、Mac、Android 手機、Android 平板與 Pixel 版面打造完整的截圖組。你可以從範本開始，或建立自己的版面系統。放入截圖，加上裝置外框或無外框的構圖，撰寫標題與說明文字，用自訂字型設定豐富文字樣式，並在畫布上微調每一個細節。

Screenshot Bro 可以在你的 Mac 上執行本機 MCP 伺服器。連接支援 MCP 的助理，例如 Claude Code、Claude Desktop、Cursor 或其他用戶端，讓它建立專案、編輯行、排列圖形、匯入截圖、翻譯文字、產生畫布預覽並匯出最終圖片。MCP 是選用功能，預設關閉，僅接受本機連線，並以存取權杖保護。

把發布版本、各語言的個別文案、各商店的行規劃，以及可直接匯出的素材，全部放在同一個專案裡，供 App Store、網站、社群媒體與上線宣傳使用。

主要功能：

- 在同一個專案中製作 App Store 截圖
- 使用內建範本或自訂版面，從容應對每一次發布
- 設計多圖的行、比較式版面與完整宣傳素材
- 批次把截圖匯入各行，並快速替換圖片
- 為 iPhone、iPad、Mac、Android、Pixel 及抽象版面加上裝置外框
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

為 iPhone、iPad、Mac、Android 手機、Android 平板與 Pixel 版面打造完整的截圖組。你可以從範本開始，或建立自己的版面系統。放入截圖，加上裝置外框或無外框的構圖，撰寫標題與說明文字，用自訂字型設定豐富文字樣式，並在畫布上微調每一個細節。

把發布版本、各語言的個別文案、各商店的行規劃，以及可直接匯出的素材，全部放在同一個專案裡，供 App Store、網站、社群媒體與上線宣傳使用。

主要功能：

- 在同一個專案中製作 App Store 截圖
- 使用內建範本或自訂版面，從容應對每一次發布
- 設計多圖的行、比較式版面與完整宣傳素材
- 批次把截圖匯入各行，並快速替換圖片
- 為 iPhone、iPad、Mac、Android、Pixel 及抽象版面加上裝置外框
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

Arma sets completos de capturas para iPhone, iPad, Mac, celulares Android, tabletas Android y diseños Pixel. Empieza con una plantilla o crea tu propio sistema de composición. Suelta tus capturas, agrega marcos de dispositivo o composiciones sin marco, escribe titulares y textos de apoyo, aplica estilos de texto enriquecido con fuentes propias y ajusta cada detalle en el lienzo.

Screenshot Bro puede alojar un servidor MCP local en tu Mac. Conecta un asistente compatible con MCP, como Claude Code, Claude Desktop, Cursor u otro cliente, y déjalo crear proyectos, editar filas, acomodar figuras, importar capturas, traducir textos, generar vistas previas del lienzo y exportar las imágenes finales. MCP es opcional, viene desactivado, funciona solo en loopback y está protegido con un token de acceso.

Mantén en un solo proyecto las variantes de cada versión, los ajustes por idioma, los planes de filas por tienda y los recursos listos para exportar: para la App Store, sitios web, redes sociales y campañas de lanzamiento.

Funciones principales:

- Crea capturas para la App Store desde un solo proyecto
- Usa plantillas incluidas o diseños propios para lanzamientos recurrentes
- Diseña filas de varias capturas, comparativas y campañas completas
- Importa capturas por lotes en las filas y reemplaza imágenes al instante
- Agrega marcos de dispositivo para iPhone, iPad, Mac, Android, Pixel y diseños abstractos
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

Arma sets completos de capturas para iPhone, iPad, Mac, celulares Android, tabletas Android y diseños Pixel. Empieza con una plantilla o crea tu propio sistema de composición. Suelta tus capturas, agrega marcos de dispositivo o composiciones sin marco, escribe titulares y textos de apoyo, aplica estilos de texto enriquecido con fuentes propias y ajusta cada detalle en el lienzo.

Mantén en un solo proyecto las variantes de cada versión, los ajustes por idioma, los planes de filas por tienda y los recursos listos para exportar: para la App Store, sitios web, redes sociales y campañas de lanzamiento.

Funciones principales:

- Crea capturas para la App Store desde un solo proyecto
- Usa plantillas incluidas o diseños propios para lanzamientos recurrentes
- Diseña filas de varias capturas, comparativas y campañas completas
- Importa capturas por lotes en las filas y reemplaza imágenes al instante
- Agrega marcos de dispositivo para iPhone, iPad, Mac, Android, Pixel y diseños abstractos
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

Montez des séries complètes pour iPhone, iPad, Mac, téléphones et tablettes Android et mises en page Pixel. Partez d'un modèle ou créez votre propre système. Déposez vos captures, ajoutez des cadres d'appareils ou des compositions sans cadre, rédigez titres et légendes, mettez en forme le texte enrichi avec vos polices et peaufinez chaque détail sur le canevas.

Screenshot Bro peut héberger un serveur MCP local sur votre Mac. Branchez un assistant compatible MCP — Claude Code, Claude Desktop, Cursor ou un autre client — et laissez-le créer des projets, modifier des rangées, disposer des formes, importer des captures, traduire du texte, générer des aperçus du canevas et exporter les images finales. MCP est optionnel, désactivé par défaut, limité au bouclage local et protégé par un jeton d'accès.

Regroupez dans un même projet vos variantes de version, vos remplacements par langue, vos plans de rangées par boutique et vos fichiers prêts à exporter, pour l'App Store, vos sites web, les réseaux sociaux et vos campagnes de lancement.

Fonctions principales :

- Produisez toutes vos captures d'écran App Store à partir d'un seul projet
- Utilisez les modèles intégrés ou vos propres mises en page pour vos lancements récurrents
- Importez vos captures par lots dans les rangées et remplacez les images en un geste
- Ajoutez des cadres d'appareils pour iPhone, iPad, Mac, Android, Pixel et des mises en page abstraites
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

Montez des séries complètes pour iPhone, iPad, Mac, téléphones et tablettes Android et mises en page Pixel. Partez d'un modèle ou créez votre propre système. Déposez vos captures, ajoutez des cadres d'appareils ou des compositions sans cadre, rédigez titres et légendes, mettez en forme le texte enrichi avec vos polices et peaufinez chaque détail sur le canevas.

Regroupez dans un même projet vos variantes de version, vos remplacements par langue, vos plans de rangées par boutique et vos fichiers prêts à exporter, pour l'App Store, vos sites web, les réseaux sociaux et vos campagnes de lancement.

Fonctions principales :

- Produisez toutes vos captures d'écran App Store à partir d'un seul projet
- Utilisez les modèles intégrés ou vos propres mises en page pour vos lancements récurrents
- Concevez des rangées à plusieurs images, des mises en page comparatives et des campagnes complètes
- Importez vos captures par lots dans les rangées et remplacez les images en un geste
- Ajoutez des cadres d'appareils pour iPhone, iPad, Mac, Android, Pixel et des mises en page abstraites
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

Vytvářejte kompletní sady snímků obrazovky pro iPhone, iPad, Mac, telefony s Androidem, tablety s Androidem a rozvržení Pixel. Začněte šablonou, nebo si postavte vlastní systém rozvržení. Vložte snímky obrazovky, přidejte rámečky zařízení nebo kompozice bez rámečků, napište titulky a popisky, upravte styl formátovaného textu vlastními písmy a doladěte každý detail přímo na plátně.

Screenshot Bro umí na vašem Macu hostovat lokální MCP server. Připojte asistenta kompatibilního s MCP — třeba Claude Code, Claude Desktop, Cursor nebo jiného klienta — a nechte ho zakládat projekty, upravovat řady, uspořádávat objekty, importovat snímky obrazovky, překládat texty, vykreslovat náhledy plátna a exportovat finální obrázky. Funkce MCP je volitelná, ve výchozím stavu vypnutá, omezená na místní smyčku a chráněná přístupovým tokenem.

Držte varianty vydání, přepisy pro jednotlivé jazykové verze, plány řad pro konkrétní obchody a hotové podklady v jednom projektu — pro App Store, weby, sociální sítě i kampaně k uvedení.

Klíčové funkce:

- Vytvářejte snímky obrazovky pro App Store z jednoho projektu
- Používejte vestavěné šablony nebo vlastní rozvržení pro opakovaná vydání
- Navrhujte řady s více snímky, srovnávací rozvržení i celé kampaně
- Hromadně importujte snímky obrazovky do řad a rychle nahrazujte obrázky
- Přidávejte rámečky zařízení pro iPhone, iPad, Mac, Android, Pixel i abstraktní rozvržení
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

Vytvářejte kompletní sady snímků obrazovky pro iPhone, iPad, Mac, telefony s Androidem, tablety s Androidem a rozvržení Pixel. Začněte šablonou, nebo si postavte vlastní systém rozvržení. Vložte snímky obrazovky, přidejte rámečky zařízení nebo kompozice bez rámečků, napište titulky a popisky, upravte styl formátovaného textu vlastními písmy a doladěte každý detail přímo na plátně.

Držte varianty vydání, přepisy pro jednotlivé jazykové verze, plány řad pro konkrétní obchody a hotové podklady v jednom projektu — pro App Store, weby, sociální sítě i kampaně k uvedení.

Klíčové funkce:

- Vytvářejte snímky obrazovky pro App Store z jednoho projektu
- Používejte vestavěné šablony nebo vlastní rozvržení pro opakovaná vydání
- Navrhujte řady s více snímky, srovnávací rozvržení i celé kampaně
- Hromadně importujte snímky obrazovky do řad a rychle nahrazujte obrázky
- Přidávejte rámečky zařízení pro iPhone, iPad, Mac, Android, Pixel i abstraktní rozvržení
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

Vytvárajte kompletné sady snímok obrazovky pre iPhone, iPad, Mac, telefóny a tablety s Androidom aj rozloženia pre Pixel. Začnite so šablónou alebo si postavte vlastný systém rozložení. Vložte snímky obrazovky, pridajte rámy zariadení alebo kompozície bez rámov, napíšte titulky a popisy, naštýlujte formátovaný text vlastnými písmami a dolaďte každý detail priamo na plátne.

Screenshot Bro dokáže na vašom Macu spustiť lokálny MCP server. Pripojte asistenta kompatibilného s MCP, napríklad Claude Code, Claude Desktop, Cursor alebo iného klienta, a nechajte ho vytvárať projekty, upravovať riadky, usporadúvať tvary, importovať snímky, prekladať texty, vykresľovať náhľady plátna a exportovať finálne obrázky. MCP je voliteľné, štandardne vypnuté, funguje len cez loopback a je chránené prístupovým tokenom.

Varianty vydaní, jazykové prepisy, plány riadkov pre jednotlivé obchody aj podklady pripravené na export si držte v jednom projekte — pre App Store, weby, sociálne siete a spúšťacie kampane.

Kľúčové funkcie:

- Vytvárajte snímky obrazovky pre App Store z jedného projektu
- Používajte zabudované šablóny alebo vlastné rozloženia pre opakované vydania
- Navrhujte viacsnímkové riadky, porovnávacie rozloženia a celé kampane
- Dávkovo importujte snímky obrazovky do riadkov a rýchlo vymieňajte obrázky
- Pridávajte rámy zariadení pre iPhone, iPad, Mac, Android, Pixel a abstraktné rozloženia
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

Vytvárajte kompletné sady snímok obrazovky pre iPhone, iPad, Mac, telefóny s Androidom, tablety s Androidom aj rozloženia pre Pixel. Začnite so šablónou alebo si postavte vlastný systém rozložení. Vložte snímky obrazovky, pridajte rámy zariadení alebo kompozície bez rámov, napíšte titulky a popisy, naštýlujte formátovaný text vlastnými písmami a dolaďte každý detail priamo na plátne.

Varianty vydaní, jazykové prepisy, plány riadkov pre jednotlivé obchody aj podklady pripravené na export si držte v jednom projekte — pre App Store, weby, sociálne siete a spúšťacie kampane.

Kľúčové funkcie:

- Vytvárajte snímky obrazovky pre App Store z jedného projektu
- Používajte zabudované šablóny alebo vlastné rozloženia pre opakované vydania
- Navrhujte viacsnímkové riadky, porovnávacie rozloženia a celé kampane
- Dávkovo importujte snímky obrazovky do riadkov a rýchlo vymieňajte obrázky
- Pridávajte rámy zariadení pre iPhone, iPad, Mac, Android, Pixel a abstraktné rozloženia
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

Állíts össze teljes képernyőkép-sorozatot iPhone-ra, iPadre, Macre, Android-telefonokra, Android-tabletekre és Pixel-elrendezésekhez. Indulj egy sablonból, vagy alakítsd ki a saját elrendezési rendszeredet. Húzd be a képernyőképeket, tegyél rájuk készülékkeretet vagy hagyd őket keret nélkül, írj főcímeket és feliratokat, formázd a szöveget egyedi betűtípusokkal, és hangolj minden részletet a vásznon.

A Screenshot Bro helyi MCP-kiszolgálót futtathat a Macen. Csatlakoztass egy MCP-kompatibilis asszisztenst — például a Claude Code-ot, a Claude Desktopot, a Cursort vagy más klienst —, és bízd rá a projektek létrehozását, a sorok szerkesztését, az alakzatok rendezését, a képernyőképek importálását, a szövegek fordítását, a vászonelőnézetek renderelését és a végleges képek exportálását. Az MCP opcionális, alapértelmezés szerint kikapcsolt, csak loopback címen érhető el, és hozzáférési token védi.

Tartsd egy projektben a kiadásváltozatokat, a nyelvspecifikus felülbírálatokat, az áruházankénti sorterveket és az exportra kész elemeket az App Store, a webhelyek, a közösségi média és a bevezető kampányok számára.

Főbb funkciók:

- App Store-képernyőképek készítése egyetlen projektből
- Beépített sablonok vagy egyedi elrendezések ismétlődő kiadásokhoz
- Képernyőképek kötegelt importálása sorokba, képek gyors cseréje
- Készülékkeretek iPhone, iPad, Mac, Android, Pixel és absztrakt elrendezésekhez
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

Állíts össze teljes képernyőkép-sorozatot iPhone-ra, iPadre, Macre, Android-telefonokra, Android-tabletekre és Pixel-elrendezésekhez. Indulj egy sablonból, vagy alakítsd ki a saját elrendezési rendszeredet. Húzd be a képernyőképeket, tegyél rájuk készülékkeretet vagy hagyd őket keret nélkül, írj főcímeket és feliratokat, formázd a szöveget egyedi betűtípusokkal, és hangolj minden részletet a vásznon.

Tartsd egy projektben a kiadásváltozatokat, a nyelvspecifikus felülbírálatokat, az áruházankénti sorterveket és az exportra kész elemeket az App Store, a webhelyek, a közösségi média és a bevezető kampányok számára.

Főbb funkciók:

- App Store-képernyőképek készítése egyetlen projektből
- Beépített sablonok vagy egyedi elrendezések ismétlődő kiadásokhoz
- Többképes sorok, összehasonlító elrendezések és teljes kampányok tervezése
- Képernyőképek kötegelt importálása sorokba, képek gyors cseréje
- Készülékkeretek iPhone, iPad, Mac, Android, Pixel és absztrakt elrendezésekhez
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

Construiește seturi complete de capturi pentru iPhone, iPad, Mac, telefoane Android, tablete Android și machete Pixel. Pornește de la un șablon sau creează-ți propriul sistem de aspect. Adaugă capturile, pune rame de dispozitiv sau compoziții fără ramă, scrie titluri și descrieri, stilizează textul îmbogățit cu fonturi proprii și reglează fiecare detaliu direct pe canvas.

Screenshot Bro poate găzdui un server MCP local pe Mac. Conectează un asistent compatibil MCP — Claude Code, Claude Desktop, Cursor sau alt client — și lasă-l să creeze proiecte, să editeze rânduri, să aranjeze forme, să importe capturi de ecran, să traducă texte, să randeze previzualizări ale canvasului și să exporte imaginile finale. MCP este opțional, dezactivat implicit, limitat la loopback și protejat cu un token de acces.

Ține variantele de lansare, suprascrierile pe limbă, planurile de rânduri pentru fiecare magazin și materialele gata de export într-un singur proiect, pentru App Store, site-uri web, rețele sociale și campanii de lansare.

Funcții principale:

- Creează capturi de ecran pentru App Store dintr-un singur proiect
- Folosește șabloane incluse sau machete proprii pentru lansări repetate
- Importă capturi în lot pe rânduri și înlocuiește rapid imaginile
- Adaugă rame de dispozitiv pentru iPhone, iPad, Mac, Android, Pixel și machete abstracte
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

Construiește seturi complete de capturi pentru iPhone, iPad, Mac, telefoane Android, tablete Android și machete Pixel. Pornește de la un șablon sau creează-ți propriul sistem de aspect. Adaugă capturile, pune rame de dispozitiv sau compoziții fără ramă, scrie titluri și descrieri, stilizează textul îmbogățit cu fonturi proprii și reglează fiecare detaliu direct pe canvas.

Ține variantele de lansare, suprascrierile pe limbă, planurile de rânduri pentru fiecare magazin și materialele gata de export într-un singur proiect, pentru App Store, site-uri web, rețele sociale și campanii de lansare.

Funcții principale:

- Creează capturi de ecran pentru App Store dintr-un singur proiect
- Folosește șabloane incluse sau machete proprii pentru lansări repetate
- Proiectează rânduri cu mai multe capturi, machete comparative și campanii întregi
- Importă capturi în lot pe rânduri și înlocuiește rapid imaginile
- Adaugă rame de dispozitiv pentru iPhone, iPad, Mac, Android, Pixel și machete abstracte
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

Izradite kompletne setove snimki zaslona za iPhone, iPad, Mac, Android telefone, Android tablete i Pixel rasporede. Krenite od predloška ili izgradite vlastiti sustav rasporeda. Ubacite snimke zaslona, dodajte okvire uređaja ili kompozicije bez okvira, napišite naslove i opise, oblikujte obogaćeni tekst vlastitim fontovima i dotjerajte svaki detalj na platnu.

Screenshot Bro može pokrenuti lokalni MCP poslužitelj na vašem Macu. Povežite MCP-kompatibilnog asistenta poput alata Claude Code, Claude Desktop, Cursor ili nekog drugog klijenta i pustite ga da stvara projekte, uređuje retke, raspoređuje oblike, uvozi snimke zaslona, prevodi tekst, prikazuje pretpreglede platna i izvozi konačne slike. MCP je neobavezan, prema zadanim postavkama isključen, radi samo lokalno i zaštićen je pristupnim tokenom.

Držite varijante izdanja, prilagodbe za pojedini jezik, planove redaka za pojedinu trgovinu i materijale spremne za izvoz u jednom projektu — za App Store, web stranice, društvene mreže i lansirne kampanje.

Ključne značajke:

- Izradite App Store snimke zaslona iz jednog projekta
- Koristite ugrađene predloške ili vlastite rasporede za ponavljajuća izdanja
- Skupno uvezite snimke zaslona u retke i brzo zamijenite slike
- Dodajte okvire uređaja za iPhone, iPad, Mac, Android, Pixel i apstraktne rasporede
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

Izradite kompletne setove snimki zaslona za iPhone, iPad, Mac, Android telefone, Android tablete i Pixel rasporede. Krenite od predloška ili izgradite vlastiti sustav rasporeda. Ubacite snimke zaslona, dodajte okvire uređaja ili kompozicije bez okvira, napišite naslove i opise, oblikujte obogaćeni tekst vlastitim fontovima i dotjerajte svaki detalj na platnu.

Držite varijante izdanja, prilagodbe za pojedini jezik, planove redaka za pojedinu trgovinu i materijale spremne za izvoz u jednom projektu — za App Store, web stranice, društvene mreže i lansirne kampanje.

Ključne značajke:

- Izradite App Store snimke zaslona iz jednog projekta
- Koristite ugrađene predloške ili vlastite rasporede za ponavljajuća izdanja
- Osmislite retke s više prizora, usporedne rasporede i cijele kampanje
- Skupno uvezite snimke zaslona u retke i brzo zamijenite slike
- Dodajte okvire uređaja za iPhone, iPad, Mac, Android, Pixel i apstraktne rasporede
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

Δημιουργήστε πλήρη σετ στιγμιοτύπων για iPhone, iPad, Mac, τηλέφωνα Android, tablet Android και διατάξεις Pixel. Ξεκινήστε από ένα πρότυπο ή φτιάξτε το δικό σας σύστημα διατάξεων. Ρίξτε μέσα στιγμιότυπα, προσθέστε πλαίσια συσκευών ή συνθέσεις χωρίς πλαίσιο, γράψτε τίτλους και λεζάντες, μορφοποιήστε εμπλουτισμένο κείμενο με δικές σας γραμματοσειρές και ρυθμίστε κάθε λεπτομέρεια πάνω στον καμβά.

Το Screenshot Bro μπορεί να φιλοξενήσει έναν τοπικό διακομιστή MCP στον Mac σας. Συνδέστε έναν συμβατό με MCP βοηθό, όπως το Claude Code, το Claude Desktop, το Cursor ή οποιονδήποτε άλλο πελάτη, και αφήστε τον να δημιουργεί έργα, να επεξεργάζεται σειρές, να τακτοποιεί σχήματα, να εισάγει στιγμιότυπα, να μεταφράζει κείμενα, να αποδίδει προεπισκοπήσεις του καμβά και να εξάγει τελικές εικόνες. Το MCP είναι προαιρετικό, ανενεργό από προεπιλογή, μόνο τοπικό (loopback) και προστατεύεται με διακριτικό πρόσβασης.

Κρατήστε παραλλαγές κυκλοφορίας, παρακάμψεις ανά γλώσσα, πλάνα σειρών ανά κατάστημα και έτοιμα προς εξαγωγή στοιχεία σε ένα έργο, για το App Store, ιστότοπους, κοινωνικά δίκτυα και καμπάνιες κυκλοφορίας.

Βασικές δυνατότητες:

- Δημιουργία στιγμιοτύπων για το App Store από ένα μόνο έργο
- Ενσωματωμένα πρότυπα ή δικές σας διατάξεις για επαναλαμβανόμενες κυκλοφορίες
- Μαζική εισαγωγή στιγμιοτύπων σε σειρές και γρήγορη αντικατάσταση εικόνων
- Πλαίσια συσκευών για iPhone, iPad, Mac, Android, Pixel και αφηρημένες διατάξεις
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

Δημιουργήστε πλήρη σετ στιγμιοτύπων για iPhone, iPad, Mac, τηλέφωνα Android, tablet Android και διατάξεις Pixel. Ξεκινήστε από ένα πρότυπο ή φτιάξτε το δικό σας σύστημα διατάξεων. Ρίξτε μέσα στιγμιότυπα, προσθέστε πλαίσια συσκευών ή συνθέσεις χωρίς πλαίσιο, γράψτε τίτλους και λεζάντες, μορφοποιήστε εμπλουτισμένο κείμενο με δικές σας γραμματοσειρές και ρυθμίστε κάθε λεπτομέρεια πάνω στον καμβά.

Κρατήστε παραλλαγές κυκλοφορίας, παρακάμψεις ανά γλώσσα, πλάνα σειρών ανά κατάστημα και έτοιμα προς εξαγωγή στοιχεία σε ένα έργο, για το App Store, ιστότοπους, κοινωνικά δίκτυα και καμπάνιες κυκλοφορίας.

Βασικές δυνατότητες:

- Δημιουργία στιγμιοτύπων για το App Store από ένα μόνο έργο
- Ενσωματωμένα πρότυπα ή δικές σας διατάξεις για επαναλαμβανόμενες κυκλοφορίες
- Σχεδίαση σειρών με πολλά στιγμιότυπα, διατάξεων σύγκρισης και ολόκληρων καμπανιών
- Μαζική εισαγωγή στιγμιοτύπων σε σειρές και γρήγορη αντικατάσταση εικόνων
- Πλαίσια συσκευών για iPhone, iPad, Mac, Android, Pixel και αφηρημένες διατάξεις
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

Crea jocs complets de captures per a iPhone, iPad, Mac, telèfons Android, tauletes Android i disposicions Pixel. Comença amb una plantilla o munta el teu propi sistema de disposicions. Arrossega-hi captures, afegeix marcs de dispositiu o composicions sense marc, escriu titulars i peus de text, dona estil al text enriquit amb tipus de lletra propis i ajusta cada detall al llenç.

Screenshot Bro pot allotjar un servidor MCP local al teu Mac. Connecta-hi un assistent compatible amb MCP, com ara Claude Code, Claude Desktop, Cursor o qualsevol altre client, i deixa que creï projectes, editi files, ordeni formes, importi captures, tradueixi textos, generi previsualitzacions del llenç i exporti les imatges finals. L'MCP és opcional, està desactivat per defecte, només escolta en loopback i està protegit amb un token d'accés.

Mantén les variants de llançament, les substitucions per idioma, els plans de files per botiga i els recursos llestos per exportar dins d'un mateix projecte, per a l'App Store, webs, xarxes socials i campanyes de llançament.

Funcions principals:

- Crea captures de pantalla per a l'App Store des d'un sol projecte
- Fes servir plantilles integrades o disposicions pròpies per als llançaments recurrents
- Importa captures per lots dins de les files i substitueix imatges ràpidament
- Afegeix marcs de dispositiu per a iPhone, iPad, Mac, Android, Pixel i disposicions abstractes
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

Crea jocs complets de captures per a iPhone, iPad, Mac, telèfons Android, tauletes Android i disposicions Pixel. Comença amb una plantilla o munta el teu propi sistema de disposicions. Arrossega-hi captures, afegeix marcs de dispositiu o composicions sense marc, escriu titulars i peus de text, dona estil al text enriquit amb tipus de lletra propis i ajusta cada detall al llenç.

Mantén les variants de llançament, les substitucions per idioma, els plans de files per botiga i els recursos llestos per exportar dins d'un mateix projecte, per a l'App Store, webs, xarxes socials i campanyes de llançament.

Funcions principals:

- Crea captures de pantalla per a l'App Store des d'un sol projecte
- Fes servir plantilles integrades o disposicions pròpies per als llançaments recurrents
- Dissenya files de diverses captures, disposicions comparatives i campanyes senceres
- Importa captures per lots dins de les files i substitueix imatges ràpidament
- Afegeix marcs de dispositiu per a iPhone, iPad, Mac, Android, Pixel i disposicions abstractes
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

Sestavite celotne nabore posnetkov za iPhone, iPad, Mac, telefone Android, tablice Android in postavitve za Pixel. Začnite s predlogo ali zgradite lasten sistem postavitev. Dodajte posnetke zaslona, uporabite okvirje naprav ali kompozicije brez okvirjev, napišite naslove in podnapise, oblikujte besedilo z lastnimi pisavami in na platnu izpilite vsako podrobnost.

Screenshot Bro lahko na Macu gosti lokalni strežnik MCP. Povežite združljivega pomočnika, kot so Claude Code, Claude Desktop, Cursor ali drug odjemalec, in mu prepustite ustvarjanje projektov, urejanje vrstic, razporejanje oblik, uvoz posnetkov zaslona, prevajanje besedila, izris predogledov platna in izvoz končnih slik. MCP je izbiren, privzeto izklopljen, dostopen samo lokalno in zaščiten z žetonom.

Različice izdaj, prilagoditve za posamezne jezike, načrte vrstic za posamezne trgovine in gradivo, pripravljeno za izvoz, hranite v enem projektu za App Store, spletne strani, družbena omrežja in lansirne kampanje.

Ključne funkcije:

- Ustvarite posnetke zaslona za App Store iz enega projekta
- Uporabite vgrajene predloge ali lastne postavitve za ponavljajoče se izdaje
- Oblikujte vrstice z več posnetki, primerjalne postavitve in celotne kampanje
- Paketno uvozite posnetke zaslona v vrstice in hitro zamenjajte slike
- Dodajte okvirje naprav za iPhone, iPad, Mac, Android, Pixel in abstraktne postavitve
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

Sestavite celotne nabore posnetkov za iPhone, iPad, Mac, telefone Android, tablice Android in postavitve za Pixel. Začnite s predlogo ali zgradite lasten sistem postavitev. Dodajte posnetke zaslona, uporabite okvirje naprav ali kompozicije brez okvirjev, napišite naslove in podnapise, oblikujte besedilo z lastnimi pisavami in na platnu izpilite vsako podrobnost.

Različice izdaj, prilagoditve za posamezne jezike, načrte vrstic za posamezne trgovine in gradivo, pripravljeno za izvoz, hranite v enem projektu za App Store, spletne strani, družbena omrežja in lansirne kampanje.

Ključne funkcije:

- Ustvarite posnetke zaslona za App Store iz enega projekta
- Uporabite vgrajene predloge ali lastne postavitve za ponavljajoče se izdaje
- Oblikujte vrstice z več posnetki, primerjalne postavitve in celotne kampanje
- Paketno uvozite posnetke zaslona v vrstice in hitro zamenjajte slike
- Dodajte okvirje naprav za iPhone, iPad, Mac, Android, Pixel in abstraktne postavitve
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

SCRIPT_RANGE = {"ru": (0x0400, 0x04FF), "uk": (0x0400, 0x04FF),
                "th": (0x0E00, 0x0E7F), "zh-Hant": (0x4E00, 0x9FFF),
                "el": (0x0370, 0x03FF)}
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
