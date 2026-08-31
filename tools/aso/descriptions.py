# -*- coding: utf-8 -*-
"""App Store descriptions for the 10 locales added in Aug 2026.

Those locales were created carrying the en-US description (see finish.py), which
was no regression — Apple already showed them the en-US listing as a fallback.
This file is the real copy. macOS and iOS are separate texts: the macOS listing
advertises the MCP server and Finder, both of which are `#if os(macOS)` only, so
the iOS text must never mention either.

en-GB is not stored: it is a spelling pass over the version's own live en-US row
(`british`), so it can never drift from an English rewrite. Every other locale is
translated from en-US — never from another translation — except zh-Hant, which is
written in Taiwan vocabulary rather than converted from zh-Hans.

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

LOCALES = ["en-GB", "pt-BR", "ru", "pl", "tr", "uk", "id", "vi", "th", "zh-Hant"]

# Must survive byte-identical in every locale.
ATOMS = ["Screenshot Bro", "App Store", "Google Play", "App Store Connect",
         "iPhone", "iPad", "Mac", "Pixel", "Android", "PNG", "JPEG", "SVG",
         "iCloud", "ZIP",
         "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"]
ATOMS_MAC_ONLY = ["MCP", "Model Context Protocol", "Claude Code",
                  "Claude Desktop", "Cursor"]
BANNED_IOS = ["MCP", "Model Context Protocol", "Finder"]

# Price talk in the description of a paywalled app is a rejection class.
BANNED_ANY = ["free", "gratis", "grátis", "discount", "бесплатн", "скидк",
              "безкоштов", "знижк", "darmow", "zniżk", "ücretsiz", "indirim",
              "miễn phí", "giảm giá", "ฟรี", "ส่วนลด", "免費", "免费", "折扣"]

# Script guards — a stripped diacritic or a mojibake round trip matches nothing.
# Only characters common enough to appear in any full description: a rare letter
# (ru "ъ", uk "ґ", th "ฮ") would fail honest copy. Script integrity for those is
# covered by SCRIPT_RANGE plus the ru/uk-only letter checks in review().
SCRIPT_REQUIRED = {"vi": "ảứộ", "tr": "şğı", "zh-Hant": "專範匯"}
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
O Screenshot Bro é um gerador de capturas de tela para a App Store e o Google Play. Crie um conjunto completo de capturas de uma só vez, adicione molduras de dispositivos, localize cada título para cada mercado em que você publica e envie tudo direto para o App Store Connect — sem sair do Mac.

Ao contrário das ferramentas de design genéricas, o Screenshot Bro entende linhas específicas por dispositivo, localização, envios para o App Store Connect, envios para o Google Play, exportações em lote, projetos reutilizáveis e automação local com assistentes de IA pelo Model Context Protocol.

Monte conjuntos completos de capturas para iPhone, iPad, Mac, celulares Android, tablets Android e layouts do Pixel. Comece por um modelo ou crie o seu próprio sistema de layout. Solte as capturas, adicione molduras de dispositivos ou composições sem moldura, escreva títulos e legendas, estilize texto rico com fontes personalizadas e ajuste cada detalhe no canvas.

O Screenshot Bro pode hospedar um servidor MCP local no seu Mac. Conecte um assistente compatível com MCP, como Claude Code, Claude Desktop, Cursor ou outro cliente, e deixe que ele crie projetos, edite linhas, organize formas, importe capturas, traduza textos, renderize prévias do canvas e exporte as imagens finais. O MCP é opcional, fica desativado por padrão, aceita apenas conexões locais e é protegido por um token de acesso.

Mantenha variações de lançamento, substituições por idioma, planos de linhas por loja e materiais prontos para exportar em um único projeto — para a App Store, o Google Play, sites, redes sociais e campanhas de lançamento.

Principais recursos:

- Crie capturas para a App Store e para o Google Play a partir de um único projeto
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
- Envie as capturas da ficha da loja direto para o Google Play
- Revise e edite os metadados do App Store Connect antes do envio
- Mantenha os projetos locais por padrão, sincronize com o iCloud quando quiser e faça backups em ZIP
- Sem rastreamento

O Screenshot Bro foi feito para desenvolvedores indie, times de produto, designers e profissionais de marketing que precisam de mais controle do que um gerador básico de capturas e de um fluxo mais rápido do que refazer cada imagem de marketing à mão.

Se você precisa de um criador de capturas para a App Store, um construtor de modelos de captura, um gerador de capturas para o Google Play, uma ferramenta de localização de capturas, um app para enviar imagens ao App Store Connect, um app para enviar capturas ao Google Play ou uma automação de capturas com MCP, o Screenshot Bro reúne todo o fluxo em um único app focado para Mac.

Termos de Uso (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["pt-BR"] = """\
O Screenshot Bro é um criador e editor de capturas de tela feito sob medida para as capturas da App Store e do Google Play. Crie modelos reutilizáveis, monte conjuntos completos de capturas, localize a sua mensagem e exporte ou envie imagens de loja impecáveis.

Ao contrário das ferramentas de design genéricas, o Screenshot Bro entende linhas específicas por dispositivo, localização, envios para o App Store Connect, envios para o Google Play, exportações em lote e projetos reutilizáveis.

Monte conjuntos completos de capturas para iPhone, iPad, Mac, celulares Android, tablets Android e layouts do Pixel. Comece por um modelo ou crie o seu próprio sistema de layout. Solte as capturas, adicione molduras de dispositivos ou composições sem moldura, escreva títulos e legendas, estilize texto rico com fontes personalizadas e ajuste cada detalhe no canvas.

Mantenha variações de lançamento, substituições por idioma, planos de linhas por loja e materiais prontos para exportar em um único projeto — para a App Store, o Google Play, sites, redes sociais e campanhas de lançamento.

Principais recursos:

- Crie capturas para a App Store e para o Google Play a partir de um único projeto
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
- Envie as capturas da ficha da loja direto para o Google Play
- Revise e edite os metadados do App Store Connect antes do envio
- Receba notificações quando as exportações e os envios para as lojas terminarem
- Mantenha os projetos locais por padrão, sincronize com o iCloud quando quiser e faça backups em ZIP
- Sem rastreamento

O Screenshot Bro foi feito para desenvolvedores indie, times de produto, designers e profissionais de marketing que precisam de mais controle do que um gerador básico de capturas e de um fluxo mais rápido do que refazer cada imagem de marketing à mão.

Seja para um primeiro lançamento, uma grande atualização, uma campanha sazonal ou uma rodada de localização, o Screenshot Bro ajuda você a sair das capturas brutas e chegar a imagens de marketing prontas para a loja com mais rapidez e consistência.

Se você precisa de um criador de capturas para a App Store, um construtor de modelos de captura, um gerador de capturas para o Google Play, uma ferramenta de localização de capturas, um app para enviar imagens ao App Store Connect ou um app para enviar capturas ao Google Play, o Screenshot Bro reúne todo o fluxo em um único app focado.

Termos de Uso (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["ru"] = """\
Screenshot Bro — генератор скриншотов приложений для App Store и Google Play. Соберите полный набор скриншотов один раз, добавьте рамки устройств, локализуйте каждый заголовок под каждый рынок, куда вы выпускаете приложение, и загрузите всё прямо в App Store Connect, не покидая Mac.

В отличие от универсальных графических редакторов, Screenshot Bro понимает ряды под конкретные устройства, локализацию, загрузку в App Store Connect, загрузку в Google Play, пакетный экспорт, переиспользуемые проекты и локальную автоматизацию через ИИ-ассистента по Model Context Protocol.

Собирайте полные наборы скриншотов для iPhone, iPad, Mac, Android-смартфонов, Android-планшетов и раскладок Pixel. Начните с шаблона или создайте собственную систему макетов. Добавляйте скриншоты, рамки устройств или композиции без рамок, пишите заголовки и подписи, оформляйте текст своими шрифтами и доводите каждую деталь на холсте.

Screenshot Bro умеет поднимать локальный MCP-сервер на вашем Mac. Подключите совместимого с MCP ассистента — Claude Code, Claude Desktop, Cursor или любой другой клиент — и он создаст проекты, отредактирует ряды, расставит фигуры, импортирует скриншоты, переведёт текст, отрисует превью холста и экспортирует финальные изображения. MCP включается по желанию, по умолчанию выключен, работает только на локальном интерфейсе и защищён токеном доступа.

Держите варианты релизов, переопределения для отдельных языков, планы рядов под каждый магазин и готовые к экспорту материалы в одном проекте — для App Store, Google Play, сайтов, соцсетей и запусков.

Основные возможности:

- Создавайте скриншоты для App Store и Google Play в одном проекте
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
- Загружайте скриншоты страницы приложения напрямую в Google Play
- Просматривайте и правьте метаданные App Store Connect перед загрузкой
- Храните проекты локально, синхронизируйте с iCloud по желанию и делайте резервные копии в ZIP
- Никакой слежки

Screenshot Bro сделан для инди-разработчиков, продуктовых команд, дизайнеров и маркетологов, которым нужно больше контроля, чем даёт простой генератор скриншотов, и процесс быстрее, чем собирать каждую маркетинговую картинку вручную.

Если вам нужен конструктор скриншотов для App Store, редактор шаблонов, генератор скриншотов для Google Play, инструмент локализации скриншотов, загрузчик в App Store Connect, загрузчик скриншотов в Google Play или автоматизация скриншотов через MCP — Screenshot Bro собирает весь процесс в одном приложении для Mac.

Условия использования (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["ru"] = """\
Screenshot Bro — редактор и конструктор скриншотов, сделанный специально для скриншотов App Store и Google Play. Создавайте переиспользуемые шаблоны, собирайте полные наборы скриншотов, локализуйте текст и экспортируйте или загружайте готовые материалы для магазинов.

В отличие от универсальных графических редакторов, Screenshot Bro понимает ряды под конкретные устройства, локализацию, загрузку в App Store Connect, загрузку в Google Play, пакетный экспорт и переиспользуемые проекты.

Собирайте полные наборы скриншотов для iPhone, iPad, Mac, Android-смартфонов, Android-планшетов и раскладок Pixel. Начните с шаблона или создайте собственную систему макетов. Добавляйте скриншоты, рамки устройств или композиции без рамок, пишите заголовки и подписи, оформляйте текст своими шрифтами и доводите каждую деталь на холсте.

Держите варианты релизов, переопределения для отдельных языков, планы рядов под каждый магазин и готовые к экспорту материалы в одном проекте — для App Store, Google Play, сайтов, соцсетей и запусков.

Основные возможности:

- Создавайте скриншоты для App Store и Google Play в одном проекте
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
- Загружайте скриншоты страницы приложения напрямую в Google Play
- Просматривайте и правьте метаданные App Store Connect перед загрузкой
- Получайте уведомления о завершении экспорта и загрузки в магазины
- Храните проекты локально, синхронизируйте с iCloud по желанию и делайте резервные копии в ZIP
- Никакой слежки

Screenshot Bro сделан для инди-разработчиков, продуктовых команд, дизайнеров и маркетологов, которым нужно больше контроля, чем даёт простой генератор скриншотов, и процесс быстрее, чем собирать каждую маркетинговую картинку вручную.

Готовите первый релиз, крупное обновление, сезонную кампанию или выход на новые языки — Screenshot Bro поможет быстрее и аккуратнее превратить сырые скриншоты в готовые для магазина изображения.

Если вам нужен конструктор скриншотов для App Store, редактор шаблонов, генератор скриншотов для Google Play, инструмент локализации скриншотов, загрузчик в App Store Connect или загрузчик скриншотов в Google Play — Screenshot Bro собирает весь процесс в одном приложении.

Условия использования (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["uk"] = """\
Screenshot Bro — застосунок для створення знімків екрана до App Store і Google Play. Складіть повний набір знімків один раз, додайте рамки пристроїв, перекладіть кожен заголовок для кожного ринку, де ви публікуєте застосунок, і завантажте все просто в App Store Connect — не виходячи з Mac.

На відміну від універсальних графічних редакторів, Screenshot Bro розуміє рядки під конкретні пристрої, локалізацію, завантаження в App Store Connect, завантаження в Google Play, пакетний експорт, проєкти для повторного використання та локальну автоматизацію ШІ-асистентом через Model Context Protocol.

Складайте повні набори знімків для iPhone, iPad, Mac, смартфонів Android, планшетів Android і розкладок Pixel. Почніть із шаблона або створіть власну систему макетів. Додавайте знімки, рамки пристроїв чи композиції без рамок, пишіть заголовки та підписи, оформлюйте текст власними шрифтами й доводьте кожну деталь на полотні.

Screenshot Bro може підняти локальний сервер MCP на вашому Mac. Підключіть сумісного з MCP асистента — Claude Code, Claude Desktop, Cursor або інший клієнт — і він створить проєкти, відредагує рядки, розставить фігури, імпортує знімки, перекладе текст, покаже попередній вигляд полотна й експортує готові зображення. MCP вмикається за бажанням, типово вимкнений, працює лише на локальному інтерфейсі та захищений токеном доступу.

Тримайте варіанти релізів, окремі тексти для кожної мови, плани рядків під кожен магазин і готові до експорту матеріали в одному проєкті — для App Store, Google Play, сайтів, соцмереж і запусків.

Основні можливості:

- Створюйте знімки для App Store і Google Play в одному проєкті
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
- Завантажуйте знімки сторінки застосунку напряму в Google Play
- Переглядайте й редагуйте метадані App Store Connect перед завантаженням
- Тримайте проєкти локально, синхронізуйте з iCloud за бажанням і робіть резервні копії у ZIP
- Жодного відстеження

Screenshot Bro створений для інді-розробників, продуктових команд, дизайнерів і маркетологів, яким потрібно більше контролю, ніж дає простий генератор знімків, і робочий процес швидший, ніж збирати кожне маркетингове зображення вручну.

Якщо вам потрібен конструктор знімків для App Store, редактор шаблонів, генератор знімків для Google Play, інструмент локалізації знімків, завантажувач до App Store Connect, завантажувач знімків до Google Play або автоматизація знімків через MCP — Screenshot Bro збирає весь процес в одному застосунку для Mac.

Умови використання (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["uk"] = """\
Screenshot Bro — редактор і конструктор знімків екрана, створений саме для знімків App Store і Google Play. Робіть шаблони для повторного використання, складайте повні набори знімків, перекладайте свої тексти та експортуйте чи завантажуйте готові матеріали для магазинів.

На відміну від універсальних графічних редакторів, Screenshot Bro розуміє рядки під конкретні пристрої, локалізацію, завантаження в App Store Connect, завантаження в Google Play, пакетний експорт і проєкти для повторного використання.

Складайте повні набори знімків для iPhone, iPad, Mac, смартфонів Android, планшетів Android і розкладок Pixel. Почніть із шаблона або створіть власну систему макетів. Додавайте знімки, рамки пристроїв чи композиції без рамок, пишіть заголовки та підписи, оформлюйте текст власними шрифтами й доводьте кожну деталь на полотні.

Тримайте варіанти релізів, окремі тексти для кожної мови, плани рядків під кожен магазин і готові до експорту матеріали в одному проєкті — для App Store, Google Play, сайтів, соцмереж і запусків.

Основні можливості:

- Створюйте знімки для App Store і Google Play в одному проєкті
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
- Завантажуйте знімки сторінки застосунку напряму в Google Play
- Переглядайте й редагуйте метадані App Store Connect перед завантаженням
- Отримуйте повідомлення про завершення експорту та завантаження в магазини
- Тримайте проєкти локально, синхронізуйте з iCloud за бажанням і робіть резервні копії у ZIP
- Жодного відстеження

Screenshot Bro створений для інді-розробників, продуктових команд, дизайнерів і маркетологів, яким потрібно більше контролю, ніж дає простий генератор знімків, і робочий процес швидший, ніж збирати кожне маркетингове зображення вручну.

Готуєте перший реліз, велике оновлення, сезонну кампанію чи вихід на нові мови — Screenshot Bro допоможе швидше й узгодженіше перетворити сирі знімки на готові для магазину зображення.

Якщо вам потрібен конструктор знімків для App Store, редактор шаблонів, генератор знімків для Google Play, інструмент локалізації знімків, завантажувач до App Store Connect або завантажувач знімків до Google Play — Screenshot Bro збирає весь процес в одному застосунку.

Умови використання (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["pl"] = """\
Screenshot Bro to generator zrzutów ekranu dla App Store i Google Play. Zaprojektuj cały zestaw zrzutów raz, dodaj ramki urządzeń, przetłumacz każdy nagłówek na każdy rynek, na którym wydajesz aplikację, i wyślij wszystko prosto do App Store Connect — bez wychodzenia z Maca.

W przeciwieństwie do uniwersalnych narzędzi graficznych Screenshot Bro rozumie wiersze przypisane do konkretnych urządzeń, lokalizację, wysyłkę do App Store Connect, wysyłkę do Google Play, eksport wsadowy, projekty do wielokrotnego użytku i lokalną automatyzację asystentem AI przez Model Context Protocol.

Twórz kompletne zestawy zrzutów dla iPhone'a, iPada, Maca, telefonów i tabletów z Androidem oraz układów Pixel. Zacznij od szablonu albo zbuduj własny system układów. Wrzuć zrzuty, dodaj ramki urządzeń lub kompozycje bez ramek, napisz nagłówki i podpisy, sformatuj tekst własnymi czcionkami i dopracuj każdy szczegół na obszarze roboczym.

Screenshot Bro może uruchomić lokalny serwer MCP na Twoim Macu. Podłącz asystenta zgodnego z MCP — Claude Code, Claude Desktop, Cursor lub innego klienta — i pozwól mu tworzyć projekty, edytować wiersze, rozmieszczać kształty, importować zrzuty, tłumaczyć teksty, renderować podglądy obszaru roboczego i eksportować gotowe obrazy. MCP jest opcjonalny, domyślnie wyłączony, działa tylko lokalnie i jest chroniony tokenem dostępu.

Trzymaj warianty wydań, teksty przypisane do poszczególnych języków, plany wierszy pod konkretne sklepy i gotowe do eksportu materiały w jednym projekcie — dla App Store, Google Play, stron internetowych, mediów społecznościowych i kampanii premierowych.

Najważniejsze funkcje:

- Twórz zrzuty do App Store i Google Play z jednego projektu
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
- Wysyłaj zrzuty ze strony sklepu bezpośrednio do Google Play
- Przejrzyj i popraw metadane App Store Connect przed wysyłką
- Trzymaj projekty lokalnie, synchronizuj z iCloud, gdy chcesz, i twórz kopie ZIP
- Bez śledzenia

Screenshot Bro powstał dla niezależnych twórców, zespołów produktowych, projektantów i marketerów, którzy potrzebują większej kontroli niż w prostym generatorze zrzutów i szybszej pracy niż składanie każdego obrazu marketingowego od zera.

Jeśli szukasz kreatora zrzutów do App Store, kreatora szablonów zrzutów, generatora zrzutów do Google Play, narzędzia do lokalizacji zrzutów, narzędzia do wysyłania obrazów do App Store Connect, narzędzia do wysyłania zrzutów do Google Play albo automatyzacji zrzutów przez MCP — Screenshot Bro zbiera cały proces w jednej aplikacji na Maca.

Warunki korzystania (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["pl"] = """\
Screenshot Bro to kreator i edytor zrzutów ekranu zbudowany specjalnie pod zrzuty do App Store i Google Play. Twórz szablony do wielokrotnego użytku, projektuj kompletne zestawy zrzutów, tłumacz swój komunikat i eksportuj lub wysyłaj dopracowane materiały do sklepów.

W przeciwieństwie do uniwersalnych narzędzi graficznych Screenshot Bro rozumie wiersze przypisane do konkretnych urządzeń, lokalizację, wysyłkę do App Store Connect, wysyłkę do Google Play, eksport wsadowy i projekty do wielokrotnego użytku.

Twórz kompletne zestawy zrzutów dla iPhone'a, iPada, Maca, telefonów i tabletów z Androidem oraz układów Pixel. Zacznij od szablonu albo zbuduj własny system układów. Wrzuć zrzuty, dodaj ramki urządzeń lub kompozycje bez ramek, napisz nagłówki i podpisy, sformatuj tekst własnymi czcionkami i dopracuj każdy szczegół na obszarze roboczym.

Trzymaj warianty wydań, teksty przypisane do poszczególnych języków, plany wierszy pod konkretne sklepy i gotowe do eksportu materiały w jednym projekcie — dla App Store, Google Play, stron internetowych, mediów społecznościowych i kampanii premierowych.

Najważniejsze funkcje:

- Twórz zrzuty do App Store i Google Play z jednego projektu
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
- Wysyłaj zrzuty ze strony sklepu bezpośrednio do Google Play
- Przejrzyj i popraw metadane App Store Connect przed wysyłką
- Odbieraj powiadomienia o zakończonym eksporcie i wysyłce do sklepów
- Trzymaj projekty lokalnie, synchronizuj z iCloud, gdy chcesz, i twórz kopie ZIP
- Bez śledzenia

Screenshot Bro powstał dla niezależnych twórców, zespołów produktowych, projektantów i marketerów, którzy potrzebują większej kontroli niż w prostym generatorze zrzutów i szybszej pracy niż składanie każdego obrazu marketingowego od zera.

Niezależnie od tego, czy przygotowujesz pierwszą premierę, dużą aktualizację, kampanię sezonową czy wejście na nowe języki, Screenshot Bro pomaga szybciej i spójniej przejść od surowych zrzutów do materiałów gotowych do sklepu.

Jeśli szukasz kreatora zrzutów do App Store, kreatora szablonów zrzutów, generatora zrzutów do Google Play, narzędzia do lokalizacji zrzutów, narzędzia do wysyłania obrazów do App Store Connect albo narzędzia do wysyłania zrzutów do Google Play — Screenshot Bro zbiera cały proces w jednej skupionej aplikacji.

Warunki korzystania (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["tr"] = """\
Screenshot Bro, App Store ve Google Play için bir uygulama ekran görüntüsü üreticisidir. Ekran görüntüsü setinizin tamamını bir kez tasarlayın, cihaz çerçeveleri ekleyin, her başlığı yayın yaptığınız her pazar için yerelleştirin ve hepsini doğrudan App Store Connect'e yükleyin — Mac'inizden çıkmadan.

Genel amaçlı tasarım araçlarının aksine Screenshot Bro cihaza özel satırları, yerelleştirmeyi, App Store Connect yüklemelerini, Google Play yüklemelerini, toplu dışa aktarmayı, yeniden kullanılabilir projeleri ve Model Context Protocol üzerinden yerel yapay zekâ asistanı otomasyonunu bilir.

iPhone, iPad, Mac, Android telefonlar, Android tabletler ve Pixel düzenleri için eksiksiz ekran görüntüsü setleri hazırlayın. Bir şablonla başlayın ya da kendi düzen sisteminizi kurun. Ekran görüntülerini bırakın, cihaz çerçeveleri veya çerçevesiz kompozisyonlar ekleyin, başlıklar ve açıklamalar yazın, zengin metni özel yazı tipleriyle biçimlendirin ve her ayrıntıyı tuval üzerinde ince ayarlayın.

Screenshot Bro, Mac'inizde yerel bir MCP sunucusu çalıştırabilir. Claude Code, Claude Desktop, Cursor gibi MCP uyumlu bir asistanı ya da başka bir istemciyi bağlayın; projeler oluştursun, satırları düzenlesin, şekilleri yerleştirsin, ekran görüntüleri içe aktarsın, metinleri çevirsin, tuval önizlemeleri üretsin ve son görselleri dışa aktarsın. MCP isteğe bağlıdır, varsayılan olarak kapalıdır, yalnızca yerel bağlantıları kabul eder ve bir erişim jetonuyla korunur.

Sürüm varyantlarını, dile özel metinleri, mağazaya özel satır planlarını ve dışa aktarmaya hazır görselleri tek bir projede tutun — App Store, Google Play, web siteleri, sosyal medya ve lansman kampanyaları için.

Öne çıkan özellikler:

- App Store ve Google Play ekran görüntülerini tek projeden oluşturun
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
- Mağaza sayfası ekran görüntülerini doğrudan Google Play'e yükleyin
- Yüklemeden önce App Store Connect üst verilerini gözden geçirip düzenleyin
- Projeleri varsayılan olarak yerelde tutun, isterseniz iCloud ile eşitleyin ve ZIP yedekleri alın
- İzleme yok

Screenshot Bro; basit bir ekran görüntüsü üreticisinden daha fazla denetim ve her pazarlama görselini elle yeniden hazırlamaktan daha hızlı bir akış isteyen bağımsız geliştiriciler, ürün ekipleri, tasarımcılar ve pazarlamacılar için yapıldı.

App Store ekran görüntüsü hazırlama aracı, ekran görüntüsü şablon düzenleyici, Google Play ekran görüntüsü üreticisi, ekran görüntüsü yerelleştirme aracı, App Store Connect yükleyici, Google Play ekran görüntüsü yükleyici ya da MCP ile ekran görüntüsü otomasyonu arıyorsanız Screenshot Bro tüm akışı tek bir odaklı Mac uygulamasında toplar.

Kullanım Koşulları (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["tr"] = """\
Screenshot Bro, özellikle App Store ve Google Play ekran görüntüleri için yapılmış bir ekran görüntüsü hazırlama ve düzenleme uygulamasıdır. Yeniden kullanılabilir şablonlar oluşturun, eksiksiz ekran görüntüsü setleri tasarlayın, mesajınızı yerelleştirin ve özenli mağaza görsellerini dışa aktarın ya da yükleyin.

Genel amaçlı tasarım araçlarının aksine Screenshot Bro cihaza özel satırları, yerelleştirmeyi, App Store Connect yüklemelerini, Google Play yüklemelerini, toplu dışa aktarmayı ve yeniden kullanılabilir projeleri bilir.

iPhone, iPad, Mac, Android telefonlar, Android tabletler ve Pixel düzenleri için eksiksiz ekran görüntüsü setleri hazırlayın. Bir şablonla başlayın ya da kendi düzen sisteminizi kurun. Ekran görüntülerini bırakın, cihaz çerçeveleri veya çerçevesiz kompozisyonlar ekleyin, başlıklar ve açıklamalar yazın, zengin metni özel yazı tipleriyle biçimlendirin ve her ayrıntıyı tuval üzerinde ince ayarlayın.

Sürüm varyantlarını, dile özel metinleri, mağazaya özel satır planlarını ve dışa aktarmaya hazır görselleri tek bir projede tutun — App Store, Google Play, web siteleri, sosyal medya ve lansman kampanyaları için.

Öne çıkan özellikler:

- App Store ve Google Play ekran görüntülerini tek projeden oluşturun
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
- Mağaza sayfası ekran görüntülerini doğrudan Google Play'e yükleyin
- Yüklemeden önce App Store Connect üst verilerini gözden geçirip düzenleyin
- Dışa aktarma ve mağaza yüklemeleri bittiğinde bildirim alın
- Projeleri varsayılan olarak yerelde tutun, isterseniz iCloud ile eşitleyin ve ZIP yedekleri alın
- İzleme yok

Screenshot Bro; basit bir ekran görüntüsü üreticisinden daha fazla denetim ve her pazarlama görselini elle yeniden hazırlamaktan daha hızlı bir akış isteyen bağımsız geliştiriciler, ürün ekipleri, tasarımcılar ve pazarlamacılar için yapıldı.

İlk lansmana, büyük bir güncellemeye, sezonluk bir kampanyaya ya da yeni dillere açılmaya hazırlanıyor olun; Screenshot Bro ham ekran görüntülerinden mağazaya hazır pazarlama görsellerine daha hızlı ve daha tutarlı geçmenizi sağlar.

App Store ekran görüntüsü hazırlama aracı, ekran görüntüsü şablon düzenleyici, Google Play ekran görüntüsü üreticisi, ekran görüntüsü yerelleştirme aracı, App Store Connect yükleyici ya da Google Play ekran görüntüsü yükleyici arıyorsanız Screenshot Bro tüm akışı tek bir odaklı uygulamada toplar.

Kullanım Koşulları (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["id"] = """\
Screenshot Bro adalah pembuat screenshot aplikasi untuk App Store dan Google Play. Rancang satu set screenshot lengkap sekali saja, tambahkan bingkai perangkat, lokalkan setiap headline ke setiap pasar yang kamu tuju, dan unggah langsung ke App Store Connect — tanpa meninggalkan Mac.

Berbeda dari alat desain umum, Screenshot Bro memahami baris khusus per perangkat, pelokalan, unggahan ke App Store Connect, unggahan ke Google Play, ekspor massal, proyek yang bisa dipakai ulang, dan otomatisasi asisten AI lokal melalui Model Context Protocol.

Bangun set screenshot lengkap untuk iPhone, iPad, Mac, ponsel Android, tablet Android, dan tata letak Pixel. Mulai dari templat atau buat sistem tata letak sendiri. Masukkan screenshot, tambahkan bingkai perangkat atau komposisi tanpa bingkai, tulis headline dan keterangan, atur gaya teks dengan font kustom, dan sempurnakan setiap detail di kanvas.

Screenshot Bro bisa menjalankan server MCP lokal di Mac kamu. Hubungkan asisten yang kompatibel dengan MCP seperti Claude Code, Claude Desktop, Cursor, atau klien lain, lalu biarkan asisten itu membuat proyek, mengedit baris, menata bentuk, mengimpor screenshot, menerjemahkan teks, merender pratinjau kanvas, dan mengekspor gambar akhir. MCP bersifat opsional, mati secara bawaan, hanya menerima koneksi lokal, dan dilindungi token akses.

Simpan varian rilis, teks khusus per bahasa, rencana baris khusus per toko, dan aset siap ekspor dalam satu proyek — untuk App Store, Google Play, situs web, media sosial, dan kampanye peluncuran.

Fitur utama:

- Buat screenshot App Store dan Google Play dari satu proyek
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
- Unggah screenshot halaman toko langsung ke Google Play
- Tinjau dan sunting metadata App Store Connect sebelum mengunggah
- Simpan proyek secara lokal, sinkronkan lewat iCloud bila perlu, dan buat backup ZIP
- Tanpa pelacakan

Screenshot Bro dibuat untuk developer indie, tim produk, desainer, dan marketer yang butuh kendali lebih besar daripada pembuat screenshot biasa dan alur kerja yang lebih cepat daripada menyusun ulang setiap gambar promosi secara manual.

Kalau kamu mencari pembuat screenshot App Store, penyusun templat screenshot, pembuat screenshot Google Play, alat pelokalan screenshot, pengunggah ke App Store Connect, pengunggah screenshot ke Google Play, atau otomatisasi screenshot lewat MCP, Screenshot Bro menyatukan seluruh alur kerja dalam satu aplikasi Mac yang fokus.

Ketentuan Penggunaan (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["id"] = """\
Screenshot Bro adalah pembuat dan editor screenshot yang dirancang khusus untuk screenshot App Store dan Google Play. Buat templat yang bisa dipakai ulang, rancang set screenshot lengkap, lokalkan pesanmu, lalu ekspor atau unggah materi toko yang rapi.

Berbeda dari alat desain umum, Screenshot Bro memahami baris khusus per perangkat, pelokalan, unggahan ke App Store Connect, unggahan ke Google Play, ekspor massal, dan proyek yang bisa dipakai ulang.

Bangun set screenshot lengkap untuk iPhone, iPad, Mac, ponsel Android, tablet Android, dan tata letak Pixel. Mulai dari templat atau buat sistem tata letak sendiri. Masukkan screenshot, tambahkan bingkai perangkat atau komposisi tanpa bingkai, tulis headline dan keterangan, atur gaya teks dengan font kustom, dan sempurnakan setiap detail di kanvas.

Simpan varian rilis, teks khusus per bahasa, rencana baris khusus per toko, dan aset siap ekspor dalam satu proyek — untuk App Store, Google Play, situs web, media sosial, dan kampanye peluncuran.

Fitur utama:

- Buat screenshot App Store dan Google Play dari satu proyek
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
- Unggah screenshot halaman toko langsung ke Google Play
- Tinjau dan sunting metadata App Store Connect sebelum mengunggah
- Dapatkan notifikasi saat ekspor dan unggahan ke toko selesai
- Simpan proyek secara lokal, sinkronkan lewat iCloud bila perlu, dan buat backup ZIP
- Tanpa pelacakan

Screenshot Bro dibuat untuk developer indie, tim produk, desainer, dan marketer yang butuh kendali lebih besar daripada pembuat screenshot biasa dan alur kerja yang lebih cepat daripada menyusun ulang setiap gambar promosi secara manual.

Baik kamu sedang menyiapkan peluncuran pertama, pembaruan besar, kampanye musiman, atau perluasan ke bahasa baru, Screenshot Bro membantumu berpindah dari screenshot mentah ke materi promosi siap toko lebih cepat dan lebih konsisten.

Kalau kamu mencari pembuat screenshot App Store, penyusun templat screenshot, pembuat screenshot Google Play, alat pelokalan screenshot, pengunggah ke App Store Connect, atau pengunggah screenshot ke Google Play, Screenshot Bro menyatukan seluruh alur kerja dalam satu aplikasi yang fokus.

Ketentuan Penggunaan (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["vi"] = """\
Screenshot Bro là công cụ tạo ảnh chụp màn hình ứng dụng cho App Store và Google Play. Thiết kế trọn bộ ảnh chụp một lần, thêm khung thiết bị, bản địa hóa từng tiêu đề cho mọi thị trường bạn phát hành, rồi tải thẳng lên App Store Connect — ngay trên máy Mac.

Khác với các công cụ thiết kế đa dụng, Screenshot Bro hiểu các hàng dành riêng cho từng thiết bị, việc bản địa hóa, tải lên App Store Connect, tải lên Google Play, xuất theo lô, dự án dùng lại được và tự động hóa bằng trợ lý AI cục bộ qua Model Context Protocol.

Tạo trọn bộ ảnh chụp cho iPhone, iPad, Mac, điện thoại Android, máy tính bảng Android và bố cục Pixel. Bắt đầu từ mẫu có sẵn hoặc tự xây hệ thống bố cục riêng. Kéo ảnh chụp vào, thêm khung thiết bị hoặc dựng ảnh không khung, viết tiêu đề và chú thích, tạo kiểu chữ với phông tùy chỉnh và chỉnh từng chi tiết ngay trên canvas.

Screenshot Bro có thể chạy một máy chủ MCP cục bộ trên máy Mac của bạn. Kết nối trợ lý tương thích MCP như Claude Code, Claude Desktop, Cursor hoặc ứng dụng khác, rồi để nó tạo dự án, sửa hàng, sắp xếp hình khối, nhập ảnh chụp, dịch văn bản, kết xuất bản xem trước canvas và xuất ảnh cuối. MCP là tùy chọn, mặc định tắt, chỉ nhận kết nối cục bộ và được bảo vệ bằng token truy cập.

Giữ các biến thể bản phát hành, phần chữ riêng theo từng ngôn ngữ, bố cục hàng riêng cho từng cửa hàng và tài nguyên sẵn sàng xuất trong cùng một dự án — cho App Store, Google Play, website, mạng xã hội và các chiến dịch ra mắt.

Tính năng chính:

- Tạo ảnh chụp cho App Store và Google Play từ một dự án
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
- Tải ảnh chụp trang cửa hàng trực tiếp lên Google Play
- Xem lại và sửa thông tin App Store Connect trước khi tải lên
- Mặc định lưu dự án ngay trên máy, đồng bộ iCloud khi bạn muốn và tạo bản sao lưu ZIP
- Không theo dõi

Screenshot Bro dành cho nhà phát triển độc lập, đội ngũ sản phẩm, nhà thiết kế và người làm marketing — những người cần nhiều quyền kiểm soát hơn một công cụ tạo ảnh chụp cơ bản và một quy trình nhanh hơn việc dựng lại từng ảnh quảng bá bằng tay.

Nếu bạn cần công cụ tạo ảnh chụp cho App Store, công cụ dựng mẫu ảnh chụp, công cụ tạo ảnh chụp cho Google Play, công cụ bản địa hóa ảnh chụp, công cụ tải ảnh lên App Store Connect, công cụ tải ảnh chụp lên Google Play hay công cụ tự động hóa ảnh chụp qua MCP, Screenshot Bro gom toàn bộ quy trình vào một ứng dụng Mac duy nhất.

Điều khoản sử dụng (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["vi"] = """\
Screenshot Bro là ứng dụng tạo và chỉnh ảnh chụp màn hình, làm riêng cho ảnh chụp trên App Store và Google Play. Tạo mẫu dùng lại được, thiết kế trọn bộ ảnh chụp, bản địa hóa thông điệp của bạn, rồi xuất hoặc tải lên những ảnh quảng bá gọn gàng cho cửa hàng.

Khác với các công cụ thiết kế đa dụng, Screenshot Bro hiểu các hàng dành riêng cho từng thiết bị, việc bản địa hóa, tải lên App Store Connect, tải lên Google Play, xuất theo lô và dự án dùng lại được.

Tạo trọn bộ ảnh chụp cho iPhone, iPad, Mac, điện thoại Android, máy tính bảng Android và bố cục Pixel. Bắt đầu từ mẫu có sẵn hoặc tự xây hệ thống bố cục riêng. Kéo ảnh chụp vào, thêm khung thiết bị hoặc dựng ảnh không khung, viết tiêu đề và chú thích, tạo kiểu chữ với phông tùy chỉnh và chỉnh từng chi tiết ngay trên canvas.

Giữ các biến thể bản phát hành, phần chữ riêng theo từng ngôn ngữ, bố cục hàng riêng cho từng cửa hàng và tài nguyên sẵn sàng xuất trong cùng một dự án — cho App Store, Google Play, website, mạng xã hội và các chiến dịch ra mắt.

Tính năng chính:

- Tạo ảnh chụp cho App Store và Google Play từ một dự án
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
- Tải ảnh chụp trang cửa hàng trực tiếp lên Google Play
- Xem lại và sửa thông tin App Store Connect trước khi tải lên
- Nhận thông báo khi xuất ảnh và tải lên cửa hàng hoàn tất
- Mặc định lưu dự án ngay trên máy, đồng bộ iCloud khi bạn muốn và tạo bản sao lưu ZIP
- Không theo dõi

Screenshot Bro dành cho nhà phát triển độc lập, đội ngũ sản phẩm, nhà thiết kế và người làm marketing — những người cần nhiều quyền kiểm soát hơn một công cụ tạo ảnh chụp cơ bản và một quy trình nhanh hơn việc dựng lại từng ảnh quảng bá bằng tay.

Dù bạn đang chuẩn bị lần ra mắt đầu tiên, một bản cập nhật lớn, một chiến dịch theo mùa hay mở rộng sang ngôn ngữ mới, Screenshot Bro giúp bạn đi từ ảnh chụp thô đến ảnh quảng bá sẵn sàng lên cửa hàng nhanh hơn và nhất quán hơn.

Nếu bạn cần công cụ tạo ảnh chụp cho App Store, công cụ dựng mẫu ảnh chụp, công cụ tạo ảnh chụp cho Google Play, công cụ bản địa hóa ảnh chụp, công cụ tải ảnh lên App Store Connect hay công cụ tải ảnh chụp lên Google Play, Screenshot Bro gom toàn bộ quy trình vào một ứng dụng duy nhất.

Điều khoản sử dụng (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["th"] = """\
Screenshot Bro คือแอปสร้างภาพหน้าจอสำหรับ App Store และ Google Play ออกแบบชุดภาพหน้าจอทั้งชุดในครั้งเดียว เพิ่มกรอบอุปกรณ์ แปลทุกหัวข้อให้ทุกตลาดที่คุณวางจำหน่าย แล้วอัปโหลดตรงไปยัง App Store Connect ได้เลยจากเครื่อง Mac

ต่างจากเครื่องมือออกแบบทั่วไป Screenshot Bro เข้าใจแถวที่แยกตามอุปกรณ์ การแปลหลายภาษา การอัปโหลดขึ้น App Store Connect การอัปโหลดขึ้น Google Play การส่งออกเป็นชุด โปรเจกต์ที่นำกลับมาใช้ซ้ำได้ และการสั่งงานด้วยผู้ช่วย AI ในเครื่องผ่าน Model Context Protocol

สร้างชุดภาพหน้าจอครบชุดสำหรับ iPhone, iPad, Mac, โทรศัพท์ Android, แท็บเล็ต Android และเลย์เอาต์ Pixel เริ่มจากเทมเพลตหรือสร้างระบบเลย์เอาต์ของคุณเอง วางภาพหน้าจอลงไป เพิ่มกรอบอุปกรณ์หรือจัดองค์ประกอบแบบไม่มีกรอบ เขียนหัวข้อและคำบรรยาย จัดรูปแบบข้อความด้วยฟอนต์ของคุณเอง และปรับทุกรายละเอียดบนพื้นที่ทำงาน

Screenshot Bro เปิดเซิร์ฟเวอร์ MCP ในเครื่อง Mac ของคุณได้ เชื่อมต่อผู้ช่วยที่รองรับ MCP เช่น Claude Code, Claude Desktop, Cursor หรือไคลเอนต์อื่น แล้วให้มันสร้างโปรเจกต์ แก้ไขแถว จัดวางรูปทรง นำเข้าภาพหน้าจอ แปลข้อความ เรนเดอร์ตัวอย่างพื้นที่ทำงาน และส่งออกภาพสุดท้าย MCP เป็นตัวเลือกเสริม ปิดอยู่ตามค่าเริ่มต้น รับเฉพาะการเชื่อมต่อในเครื่อง และป้องกันด้วยโทเคนการเข้าถึง

เก็บเวอร์ชันของแต่ละรอบอัปเดต ข้อความเฉพาะของแต่ละภาษา แผนแถวของแต่ละสโตร์ และไฟล์ที่พร้อมส่งออก ไว้ในโปรเจกต์เดียว สำหรับ App Store, Google Play, เว็บไซต์, โซเชียลมีเดีย และแคมเปญเปิดตัว

ฟีเจอร์หลัก:

- สร้างภาพหน้าจอสำหรับ App Store และ Google Play จากโปรเจกต์เดียว
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
- อัปโหลดภาพหน้าจอของหน้าสโตร์ตรงไปยัง Google Play
- ตรวจและแก้เมทาดาทาของ App Store Connect ก่อนอัปโหลด
- เก็บโปรเจกต์ไว้ในเครื่องตามค่าเริ่มต้น ซิงก์ผ่าน iCloud เมื่อต้องการ และสำรองข้อมูลเป็น ZIP
- ไม่มีการติดตามผู้ใช้

Screenshot Bro ทำมาเพื่อนักพัฒนาอินดี ทีมผลิตภัณฑ์ นักออกแบบ และนักการตลาด ที่ต้องการควบคุมได้มากกว่าเครื่องมือสร้างภาพหน้าจอทั่ว ๆ ไป และต้องการขั้นตอนทำงานที่เร็วกว่าการทำภาพโปรโมตใหม่ทีละภาพด้วยมือ

หากคุณกำลังหาเครื่องมือสร้างภาพหน้าจอสำหรับ App Store เครื่องมือสร้างเทมเพลตภาพหน้าจอ เครื่องมือสร้างภาพหน้าจอสำหรับ Google Play เครื่องมือแปลภาพหน้าจอ เครื่องมืออัปโหลดขึ้น App Store Connect เครื่องมืออัปโหลดภาพหน้าจอขึ้น Google Play หรือการสั่งงานภาพหน้าจออัตโนมัติผ่าน MCP — Screenshot Bro รวมทุกขั้นตอนไว้ในแอป Mac เพียงแอปเดียว

ข้อกำหนดการใช้งาน (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["th"] = """\
Screenshot Bro คือแอปสร้างและแก้ไขภาพหน้าจอที่ทำขึ้นเพื่อภาพหน้าจอของ App Store และ Google Play โดยเฉพาะ สร้างเทมเพลตที่นำกลับมาใช้ซ้ำได้ ออกแบบชุดภาพหน้าจอครบชุด แปลข้อความของคุณ แล้วส่งออกหรืออัปโหลดภาพโปรโมตที่พร้อมขึ้นสโตร์

ต่างจากเครื่องมือออกแบบทั่วไป Screenshot Bro เข้าใจแถวที่แยกตามอุปกรณ์ การแปลหลายภาษา การอัปโหลดขึ้น App Store Connect การอัปโหลดขึ้น Google Play การส่งออกเป็นชุด และโปรเจกต์ที่นำกลับมาใช้ซ้ำได้

สร้างชุดภาพหน้าจอครบชุดสำหรับ iPhone, iPad, Mac, โทรศัพท์ Android, แท็บเล็ต Android และเลย์เอาต์ Pixel เริ่มจากเทมเพลตหรือสร้างระบบเลย์เอาต์ของคุณเอง วางภาพหน้าจอลงไป เพิ่มกรอบอุปกรณ์หรือจัดองค์ประกอบแบบไม่มีกรอบ เขียนหัวข้อและคำบรรยาย จัดรูปแบบข้อความด้วยฟอนต์ของคุณเอง และปรับทุกรายละเอียดบนพื้นที่ทำงาน

เก็บเวอร์ชันของแต่ละรอบอัปเดต ข้อความเฉพาะของแต่ละภาษา แผนแถวของแต่ละสโตร์ และไฟล์ที่พร้อมส่งออก ไว้ในโปรเจกต์เดียว สำหรับ App Store, Google Play, เว็บไซต์, โซเชียลมีเดีย และแคมเปญเปิดตัว

ฟีเจอร์หลัก:

- สร้างภาพหน้าจอสำหรับ App Store และ Google Play จากโปรเจกต์เดียว
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
- อัปโหลดภาพหน้าจอของหน้าสโตร์ตรงไปยัง Google Play
- ตรวจและแก้เมทาดาทาของ App Store Connect ก่อนอัปโหลด
- รับการแจ้งเตือนเมื่อส่งออกและอัปโหลดขึ้นสโตร์เสร็จ
- เก็บโปรเจกต์ไว้ในเครื่องตามค่าเริ่มต้น ซิงก์ผ่าน iCloud เมื่อต้องการ และสำรองข้อมูลเป็น ZIP
- ไม่มีการติดตามผู้ใช้

Screenshot Bro ทำมาเพื่อนักพัฒนาอินดี ทีมผลิตภัณฑ์ นักออกแบบ และนักการตลาด ที่ต้องการควบคุมได้มากกว่าเครื่องมือสร้างภาพหน้าจอทั่ว ๆ ไป และต้องการขั้นตอนทำงานที่เร็วกว่าการทำภาพโปรโมตใหม่ทีละภาพด้วยมือ

ไม่ว่าคุณจะเตรียมเปิดตัวครั้งแรก อัปเดตใหญ่ แคมเปญตามฤดูกาล หรือขยายไปยังภาษาใหม่ Screenshot Bro ก็ช่วยให้คุณเปลี่ยนภาพหน้าจอดิบให้เป็นภาพโปรโมตที่พร้อมขึ้นสโตร์ได้เร็วขึ้นและสม่ำเสมอขึ้น

หากคุณกำลังหาเครื่องมือสร้างภาพหน้าจอสำหรับ App Store เครื่องมือสร้างเทมเพลตภาพหน้าจอ เครื่องมือสร้างภาพหน้าจอสำหรับ Google Play เครื่องมือแปลภาพหน้าจอ เครื่องมืออัปโหลดขึ้น App Store Connect หรือเครื่องมืออัปโหลดภาพหน้าจอขึ้น Google Play — Screenshot Bro รวมทุกขั้นตอนไว้ในแอปเพียงแอปเดียว

ข้อกำหนดการใช้งาน (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_MAC["zh-Hant"] = """\
Screenshot Bro 是專為 App Store 與 Google Play 打造的 App 截圖產生器。一次設計完整的截圖組，加上裝置外框，把每一句文案在地化到你要上架的每個市場，並直接從 Mac 上傳至 App Store Connect。

與一般的通用設計工具不同，Screenshot Bro 懂得依裝置區分的行、在地化、App Store Connect 上傳、Google Play 上傳、批次匯出、可重複使用的專案，以及透過 Model Context Protocol 實現的本機 AI 助理自動化。

為 iPhone、iPad、Mac、Android 手機、Android 平板與 Pixel 版面打造完整的截圖組。你可以從範本開始，或建立自己的版面系統。放入截圖，加上裝置外框或無外框的構圖，撰寫標題與說明文字，用自訂字型設定豐富文字樣式，並在畫布上微調每一個細節。

Screenshot Bro 可以在你的 Mac 上執行本機 MCP 伺服器。連接支援 MCP 的助理，例如 Claude Code、Claude Desktop、Cursor 或其他用戶端，讓它建立專案、編輯行、排列圖形、匯入截圖、翻譯文字、產生畫布預覽並匯出最終圖片。MCP 是選用功能，預設關閉，僅接受本機連線，並以存取權杖保護。

把發布版本、各語言的個別文案、各商店的行規劃，以及可直接匯出的素材，全部放在同一個專案裡，供 App Store、Google Play、網站、社群媒體與上線宣傳使用。

主要功能：

- 在同一個專案中製作 App Store 截圖與 Google Play 截圖
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
- 將商店頁面截圖直接上傳至 Google Play
- 上傳前檢視並編輯 App Store Connect 中繼資料
- 在同一個流程中把 iOS 與 Mac 截圖上傳至 App Store Connect
- 連接支援 MCP 的助理，在本機驅動 Screenshot Bro
- 匯出與商店上傳完成時收到通知
- 專案預設留在本機，需要時可透過 iCloud 同步，並可建立 ZIP 備份
- 在 Finder 中開啟專案儲存位置與匯出資料夾
- 不追蹤使用者

Screenshot Bro 專為獨立開發者、產品團隊、設計師與行銷人員打造——他們需要比基本截圖產生器更多的掌控，也需要比手工重做每一張 App 行銷圖更快的流程。

無論你要準備首次上線、重大更新、季節性宣傳，還是在地化擴展，Screenshot Bro 都能幫你更快、更一致地把原始截圖變成可直接上架的行銷圖。

如果你需要 App Store 截圖製作工具、截圖範本編輯器、Google Play 截圖產生器、截圖在地化工具、App Store Connect 上傳工具、Google Play 截圖上傳工具，或支援 MCP 的截圖自動化工具，Screenshot Bro 會把整個流程集中在一款專注的 Mac App 裡。

使用條款（EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

DESC_IOS["zh-Hant"] = """\
Screenshot Bro 是一款專為 App Store 與 Google Play 截圖打造的截圖製作與編輯工具。建立可重複使用的範本，設計完整的截圖組，把文案在地化，並匯出或上傳精緻的商店宣傳素材。

與一般的通用設計工具不同，Screenshot Bro 懂得依裝置區分的行、在地化、App Store Connect 上傳、Google Play 上傳、批次匯出，以及可重複使用的專案。

為 iPhone、iPad、Mac、Android 手機、Android 平板與 Pixel 版面打造完整的截圖組。你可以從範本開始，或建立自己的版面系統。放入截圖，加上裝置外框或無外框的構圖，撰寫標題與說明文字，用自訂字型設定豐富文字樣式，並在畫布上微調每一個細節。

把發布版本、各語言的個別文案、各商店的行規劃，以及可直接匯出的素材，全部放在同一個專案裡，供 App Store、Google Play、網站、社群媒體與上線宣傳使用。

主要功能：

- 在同一個專案中製作 App Store 截圖與 Google Play 截圖
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
- 將商店頁面截圖直接上傳至 Google Play
- 上傳前檢視並編輯 App Store Connect 中繼資料
- 匯出與商店上傳完成時收到通知
- 專案預設留在本機，需要時可透過 iCloud 同步，並可建立 ZIP 備份
- 不追蹤使用者

Screenshot Bro 專為獨立開發者、產品團隊、設計師與行銷人員打造——他們需要比基本截圖產生器更多的掌控，也需要比手工重做每一張 App 行銷圖更快的流程。

無論你要準備首次上線、重大更新、季節性宣傳，還是在地化擴展，Screenshot Bro 都能幫你更快、更一致地把原始截圖變成可直接上架的行銷圖。

如果你需要 App Store 截圖製作工具、截圖範本編輯器、Google Play 截圖產生器、截圖在地化工具、App Store Connect 上傳工具或 Google Play 截圖上傳工具，Screenshot Bro 會把整個流程集中在一款專注的 App 裡。

使用條款（EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"""

SCRIPT_RANGE = {"ru": (0x0400, 0x04FF), "uk": (0x0400, 0x04FF),
                "th": (0x0E00, 0x0E7F), "zh-Hant": (0x4E00, 0x9FFF)}
RU_ONLY = "ыъэё"     # absent from Ukrainian
UK_ONLY = "іїєґ"     # absent from Russian


def text_for(platform, locale, en_us):
    """The description to write. `en_us` is that version's own live en-US row."""
    if locale == "en-GB":
        text = british(en_us)
        if text == en_us:
            raise SystemExit("en-GB: the spelling pass changed nothing — the en-US "
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
    least = 17 if platform == "MAC_OS" else 18
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
    from apply import asc, APP_ID
    code, d = asc("GET", f"/v1/apps/{APP_ID}/appStoreVersions?limit=40"
                         "&fields[appStoreVersions]=versionString,platform,appVersionState")
    assert code == 200, f"version list failed: {code} {d}"
    newest = {}
    for v in d["data"]:
        a = v["attributes"]
        newest.setdefault(a["platform"], (v["id"], a["versionString"], a["appVersionState"]))
    return newest


def main(offline):
    if offline:
        sources = {"MAC_OS": (None, "offline", "-", None), "IOS": (None, "offline", "-", None)}
    else:
        from apply import asc
        sources = {}
        for platform, (vid, vstr, state) in _source_versions().items():
            code, d = asc("GET", f"/v1/appStoreVersions/{vid}"
                                 f"/appStoreVersionLocalizations?limit=200")
            en = next((x["attributes"]["description"] for x in d["data"]
                       if x["attributes"]["locale"] == "en-US"), None)
            live = {x["attributes"]["locale"]: (x["attributes"].get("description") or "")
                    for x in d["data"]}
            sources[platform] = (vid, vstr, state, (en, live))

    failures = 0
    for platform in ("MAC_OS", "IOS"):
        vid, vstr, state, fetched = sources[platform]
        print(f"\n== {platform} {vstr} ({state})")
        en_us, live = fetched if fetched else (None, {})
        for locale in LOCALES:
            if locale == "en-GB" and not en_us:
                print(f"  {locale:9} SKIP  spelling pass needs the live en-US row")
                continue
            try:
                text = text_for(platform, locale, en_us or "")
            except KeyError:
                print(f"  {locale:9} MISSING from descriptions.py")
                failures += 1
                continue
            problems = review(platform, locale, text, en_us)
            still_english = live.get(locale) == en_us if en_us else None
            mark = "OK  " if not problems else "FAIL"
            note = "" if still_english is None else (
                "  live: still en-US" if still_english else "  live: translated")
            print(f"  {locale:9} {mark} {len(text):5}/{LIMIT}{note}")
            for problem in problems:
                print(f"            - {problem}")
            failures += bool(problems)
    print(f"\n  {failures} description(s) not ready to write")
    return failures


if __name__ == "__main__":
    sys.exit(1 if main("--offline" in sys.argv) else 0)
