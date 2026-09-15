#!/usr/bin/env python3
"""Apply curated interface-localization fixes to Localizable.xcstrings."""

from __future__ import annotations

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

import xcstrings_format


CATALOG = Path(__file__).parent.parent / "screenshot" / "Localizable.xcstrings"
LANGUAGES = ("de", "es", "fa", "fr", "ja", "ko", "pt-BR", "zh-Hans")


PHRASES = {
    "de": {
        "screenshot": "1 Screenshot", "screenshots": "%lld Screenshots",
        "set": "1 Set", "sets": "%lld Sets", "locale": "1 Locale", "locales": "%lld Locales",
        "version": "1 Version", "versions": "%lld Versionen", "language": "1 Sprache", "languages": "%lld Sprachen",
        "upload": "1 Upload", "uploads": "%lld Uploads", "removal": "1 Entfernung", "removals": "%lld Entfernungen",
        "move": "1 Verschiebung", "moves": "%lld Verschiebungen", "field": "1 Feld", "fields": "%lld Felder",
        "included": "1 enthalten", "included_many": "%lld enthalten", "changed": "1 geändert", "changed_many": "%lld geändert",
        "blocked": "1 blockiert", "blocked_many": "%lld blockiert",
    },
    "es": {
        "screenshot": "1 captura", "screenshots": "%lld capturas",
        "set": "1 conjunto", "sets": "%lld conjuntos", "locale": "1 idioma", "locales": "%lld idiomas",
        "version": "1 versión", "versions": "%lld versiones", "language": "1 idioma", "languages": "%lld idiomas",
        "upload": "1 subida", "uploads": "%lld subidas", "removal": "1 eliminación", "removals": "%lld eliminaciones",
        "move": "1 movimiento", "moves": "%lld movimientos", "field": "1 campo", "fields": "%lld campos",
        "included": "1 incluido", "included_many": "%lld incluidos", "changed": "1 cambiado", "changed_many": "%lld cambiados",
        "blocked": "1 bloqueado", "blocked_many": "%lld bloqueados",
    },
    "fa": {
        "screenshot": "۱ اسکرین‌شات", "screenshots": "%lld اسکرین‌شات",
        "set": "۱ مجموعه", "sets": "%lld مجموعه", "locale": "۱ زبان", "locales": "%lld زبان",
        "version": "۱ نسخه", "versions": "%lld نسخه", "language": "۱ زبان", "languages": "%lld زبان",
        "upload": "۱ آپلود", "uploads": "%lld آپلود", "removal": "۱ حذف", "removals": "%lld حذف",
        "move": "۱ جابه‌جایی", "moves": "%lld جابه‌جایی", "field": "۱ فیلد", "fields": "%lld فیلد",
        "included": "۱ مورد انتخاب‌شده", "included_many": "%lld مورد انتخاب‌شده", "changed": "۱ تغییر", "changed_many": "%lld تغییر",
        "blocked": "۱ مورد مسدود", "blocked_many": "%lld مورد مسدود",
    },
    "fr": {
        "screenshot": "1 capture d’écran", "screenshots": "%lld captures d’écran",
        "set": "1 ensemble", "sets": "%lld ensembles", "locale": "1 langue", "locales": "%lld langues",
        "version": "1 version", "versions": "%lld versions", "language": "1 langue", "languages": "%lld langues",
        "upload": "1 ajout", "uploads": "%lld ajouts", "removal": "1 suppression", "removals": "%lld suppressions",
        "move": "1 déplacement", "moves": "%lld déplacements", "field": "1 champ", "fields": "%lld champs",
        "included": "1 inclus", "included_many": "%lld inclus", "changed": "1 modifié", "changed_many": "%lld modifiés",
        "blocked": "1 bloqué", "blocked_many": "%lld bloqués",
    },
    "ja": {
        "screenshot": "1枚のスクリーンショット", "screenshots": "%lld枚のスクリーンショット",
        "set": "1セット", "sets": "%lldセット", "locale": "1ロケール", "locales": "%lldロケール",
        "version": "1バージョン", "versions": "%lldバージョン", "language": "1言語", "languages": "%lld言語",
        "upload": "1件のアップロード", "uploads": "%lld件のアップロード", "removal": "1件の削除", "removals": "%lld件の削除",
        "move": "1件の移動", "moves": "%lld件の移動", "field": "1項目", "fields": "%lld項目",
        "included": "1件を含む", "included_many": "%lld件を含む", "changed": "1件変更", "changed_many": "%lld件変更",
        "blocked": "1件ブロック", "blocked_many": "%lld件ブロック",
    },
    "ko": {
        "screenshot": "스크린샷 1개", "screenshots": "스크린샷 %lld개",
        "set": "세트 1개", "sets": "세트 %lld개", "locale": "로케일 1개", "locales": "로케일 %lld개",
        "version": "버전 1개", "versions": "버전 %lld개", "language": "언어 1개", "languages": "언어 %lld개",
        "upload": "업로드 1개", "uploads": "업로드 %lld개", "removal": "삭제 1개", "removals": "삭제 %lld개",
        "move": "이동 1개", "moves": "이동 %lld개", "field": "필드 1개", "fields": "필드 %lld개",
        "included": "포함 1개", "included_many": "포함 %lld개", "changed": "변경 1개", "changed_many": "변경 %lld개",
        "blocked": "차단 1개", "blocked_many": "차단 %lld개",
    },
    "pt-BR": {
        "screenshot": "1 captura de tela", "screenshots": "%lld capturas de tela",
        "set": "1 conjunto", "sets": "%lld conjuntos", "locale": "1 localidade", "locales": "%lld localidades",
        "version": "1 versão", "versions": "%lld versões", "language": "1 idioma", "languages": "%lld idiomas",
        "upload": "1 envio", "uploads": "%lld envios", "removal": "1 remoção", "removals": "%lld remoções",
        "move": "1 movimentação", "moves": "%lld movimentações", "field": "1 campo", "fields": "%lld campos",
        "included": "1 incluído", "included_many": "%lld incluídos", "changed": "1 alterado", "changed_many": "%lld alterados",
        "blocked": "1 bloqueado", "blocked_many": "%lld bloqueados",
    },
    "zh-Hans": {
        "screenshot": "1 张截图", "screenshots": "%lld 张截图",
        "set": "1 个集合", "sets": "%lld 个集合", "locale": "1 个语言区域", "locales": "%lld 个语言区域",
        "version": "1 个版本", "versions": "%lld 个版本", "language": "1 种语言", "languages": "%lld 种语言",
        "upload": "1 次上传", "uploads": "%lld 次上传", "removal": "1 次移除", "removals": "%lld 次移除",
        "move": "1 次移动", "moves": "%lld 次移动", "field": "1 个字段", "fields": "%lld 个字段",
        "included": "已包含 1 个", "included_many": "已包含 %lld 个", "changed": "已更改 1 个", "changed_many": "已更改 %lld 个",
        "blocked": "已阻止 1 个", "blocked_many": "已阻止 %lld 个",
    },
}


EXACT = {
    "Insert": {
        "de": "Einfügen", "es": "Insertar", "fa": "درج", "fr": "Insérer",
        "ja": "挿入", "ko": "삽입", "pt-BR": "Inserir", "zh-Hans": "插入",
    },
    "No Selection": {
        "de": "Keine Auswahl", "es": "Sin selección", "fa": "بدون انتخاب", "fr": "Aucune sélection",
        "ja": "選択なし", "ko": "선택 없음", "pt-BR": "Nenhuma seleção", "zh-Hans": "未选择",
    },
    "Text Background": {
        "de": "Texthintergrund", "es": "Fondo del texto", "fa": "پس‌زمینه متن", "fr": "Arrière-plan du texte",
        "ja": "テキストの背景", "ko": "텍스트 배경", "pt-BR": "Fundo do texto", "zh-Hans": "文本背景",
    },
    "Edit selected shapes in the inspector": {
        "de": "Ausgewählte Formen im Inspektor bearbeiten", "es": "Editar las formas seleccionadas en el inspector",
        "fa": "ویرایش شکل‌های انتخاب‌شده در بازرس", "fr": "Modifier les formes sélectionnées dans l’inspecteur",
        "ja": "選択した図形をインスペクタで編集", "ko": "선택한 도형을 검사기에서 편집",
        "pt-BR": "Editar formas selecionadas no inspetor", "zh-Hans": "在检查器中编辑所选形状",
    },
    "Insert a shape into the selected row": {
        "de": "Eine Form in die ausgewählte Zeile einfügen", "es": "Inserta una forma en la fila seleccionada",
        "fa": "یک شکل را در ردیف انتخاب‌شده درج کنید", "fr": "Insérez une forme dans la ligne sélectionnée",
        "ja": "選択した行に図形を挿入します", "ko": "선택한 행에 도형을 삽입합니다",
        "pt-BR": "Insere uma forma na linha selecionada", "zh-Hans": "将形状插入所选行",
    },
    "Select a row or a shape to edit it here.": {
        "de": "Wähle eine Zeile oder Form aus, um sie hier zu bearbeiten.", "es": "Selecciona una fila o una forma para editarla aquí.",
        "fa": "یک ردیف یا شکل را انتخاب کنید تا آن را اینجا ویرایش کنید.", "fr": "Sélectionnez une ligne ou une forme pour la modifier ici.",
        "ja": "ここで編集する行または図形を選択してください。", "ko": "여기에서 편집할 행이나 도형을 선택하세요.",
        "pt-BR": "Selecione uma linha ou forma para editá-la aqui.", "zh-Hans": "选择一行或形状以在此编辑。",
    },
    "Show row settings (Esc)": {
        "de": "Zeileneinstellungen anzeigen (Esc)", "es": "Mostrar ajustes de fila (Esc)",
        "fa": "نمایش تنظیمات ردیف (Esc)", "fr": "Afficher les réglages de la ligne (Échap)",
        "ja": "行設定を表示（Esc）", "ko": "행 설정 표시(Esc)",
        "pt-BR": "Mostrar ajustes da linha (Esc)", "zh-Hans": "显示行设置 (Esc)",
    },
    "Shape properties move from the bar below the canvas into the sidebar. Click the row name or press Esc to return to row settings.": {
        "de": "Formeigenschaften werden aus der Leiste unter der Zeichenfläche in die Seitenleiste verschoben. Klicke auf den Zeilennamen oder drücke Esc, um zu den Zeileneinstellungen zurückzukehren.",
        "es": "Las propiedades de forma pasan de la barra bajo el lienzo a la barra lateral. Haz clic en el nombre de la fila o pulsa Esc para volver a los ajustes de la fila.",
        "fa": "ویژگی‌های شکل از نوار زیر بوم به نوار کناری منتقل می‌شوند. برای بازگشت به تنظیمات ردیف، روی نام ردیف کلیک کنید یا Esc را فشار دهید.",
        "fr": "Les propriétés des formes passent de la barre sous le canevas à la barre latérale. Cliquez sur le nom de la ligne ou appuyez sur Échap pour revenir aux réglages de la ligne.",
        "ja": "図形のプロパティはキャンバス下のバーからサイドバーに移動します。行名をクリックするかEscキーを押すと、行設定に戻ります。",
        "ko": "도형 속성이 캔버스 아래 막대에서 사이드바로 이동합니다. 행 설정으로 돌아가려면 행 이름을 클릭하거나 Esc를 누르세요.",
        "pt-BR": "As propriedades da forma saem da barra abaixo da tela e vão para a barra lateral. Clique no nome da linha ou pressione Esc para voltar aos ajustes da linha.",
        "zh-Hans": "形状属性会从画布下方的栏移到侧边栏。点按行名称或按 Esc 返回行设置。",
    },
    "**Edit selected shapes in the inspector** — shows a selected shape's properties in the sidebar instead of the bar below the canvas.": {
        "de": "**Ausgewählte Formen im Inspektor bearbeiten** – zeigt die Eigenschaften der ausgewählten Form in der Seitenleiste statt in der Leiste unter der Zeichenfläche.",
        "es": "**Editar las formas seleccionadas en el inspector**: muestra las propiedades de la forma seleccionada en la barra lateral en vez de la barra bajo el lienzo.",
        "fa": "**ویرایش شکل‌های انتخاب‌شده در بازرس** — ویژگی‌های شکل انتخاب‌شده را به‌جای نوار زیر بوم، در نوار کناری نشان می‌دهد.",
        "fr": "**Modifier les formes sélectionnées dans l’inspecteur** — affiche les propriétés de la forme sélectionnée dans la barre latérale plutôt que dans la barre sous le canevas.",
        "ja": "**選択した図形をインスペクタで編集** — 選択した図形のプロパティを、キャンバス下のバーではなくサイドバーに表示します。",
        "ko": "**선택한 도형을 검사기에서 편집** — 선택한 도형의 속성을 캔버스 아래 막대 대신 사이드바에 표시합니다.",
        "pt-BR": "**Editar formas selecionadas no inspetor** — mostra as propriedades da forma selecionada na barra lateral em vez da barra abaixo da tela.",
        "zh-Hans": "**在检查器中编辑所选形状** — 在侧边栏中显示所选形状的属性，而不是显示在画布下方的栏中。",
    },
    "Prefer a sidebar? Turn on **Edit selected shapes in the inspector** in Settings ▸ General. The same controls then move into the inspector as collapsible sections, a multi-selection gets align and distribute buttons, and the **Insert** menu in the toolbar adds shapes.": {
        "de": "Lieber eine Seitenleiste? Aktiviere **Ausgewählte Formen im Inspektor bearbeiten** unter Einstellungen ▸ Allgemein. Dieselben Steuerelemente werden dann als aufklappbare Bereiche in den Inspektor verschoben, Mehrfachauswahl erhält Ausrichten- und Verteilen-Tasten, und das Menü **Einfügen** in der Symbolleiste fügt Formen hinzu.",
        "es": "¿Prefieres una barra lateral? Activa **Editar las formas seleccionadas en el inspector** en Ajustes ▸ General. Los mismos controles pasarán al inspector como secciones plegables, la selección múltiple tendrá botones de alinear y distribuir, y el menú **Insertar** de la barra de herramientas añadirá formas.",
        "fa": "نوار کناری را ترجیح می‌دهید؟ در تنظیمات ▸ عمومی، **ویرایش شکل‌های انتخاب‌شده در بازرس** را روشن کنید. همان کنترل‌ها به‌صورت بخش‌های جمع‌شونده به بازرس منتقل می‌شوند، انتخاب چندتایی دکمه‌های هم‌ترازی و توزیع می‌گیرد، و منوی **درج** در نوار ابزار شکل اضافه می‌کند.",
        "fr": "Vous préférez une barre latérale ? Activez **Modifier les formes sélectionnées dans l’inspecteur** dans Réglages ▸ Général. Les mêmes commandes passent alors dans l’inspecteur sous forme de sections repliables, une sélection multiple obtient des boutons d’alignement et de répartition, et le menu **Insérer** de la barre d’outils ajoute des formes.",
        "ja": "サイドバーがよい場合は、設定 ▸ 一般で**選択した図形をインスペクタで編集**をオンにします。同じコントロールが折りたたみ可能なセクションとしてインスペクタに移動し、複数選択では整列と分布のボタンが使え、ツールバーの**挿入**メニューから図形を追加できます。",
        "ko": "사이드바가 더 편하다면 설정 ▸ 일반에서 **선택한 도형을 검사기에서 편집**을 켜세요. 같은 컨트롤이 접을 수 있는 섹션으로 검사기에 이동하고, 다중 선택에는 정렬 및 분배 버튼이 생기며, 도구 막대의 **삽입** 메뉴로 도형을 추가합니다.",
        "pt-BR": "Prefere uma barra lateral? Ative **Editar formas selecionadas no inspetor** em Ajustes ▸ Geral. Os mesmos controles passam para o inspetor como seções recolhíveis, uma seleção múltipla ganha botões de alinhar e distribuir, e o menu **Inserir** na barra de ferramentas adiciona formas.",
        "zh-Hans": "更喜欢侧边栏？在设置 ▸ 通用中打开**在检查器中编辑所选形状**。相同控件会以可折叠分区移动到检查器中，多选时会显示对齐和分布按钮，工具栏中的**插入**菜单可添加形状。",
    },
    "With **Edit selected shapes in the inspector** turned on in Settings, selecting a shape swaps these controls for the shape's own. Click the row name at the top of the inspector, or press **Esc**, to come back.": {
        "de": "Wenn **Ausgewählte Formen im Inspektor bearbeiten** in den Einstellungen aktiviert ist, ersetzt die Auswahl einer Form diese Steuerelemente durch die eigenen Form-Steuerelemente. Klicke oben im Inspektor auf den Zeilennamen oder drücke **Esc**, um zurückzukehren.",
        "es": "Con **Editar las formas seleccionadas en el inspector** activado en Ajustes, al seleccionar una forma estos controles se cambian por los de la forma. Haz clic en el nombre de la fila arriba del inspector, o pulsa **Esc**, para volver.",
        "fa": "وقتی **ویرایش شکل‌های انتخاب‌شده در بازرس** در تنظیمات روشن باشد، انتخاب یک شکل این کنترل‌ها را با کنترل‌های همان شکل جایگزین می‌کند. برای بازگشت، روی نام ردیف در بالای بازرس کلیک کنید یا **Esc** را فشار دهید.",
        "fr": "Lorsque **Modifier les formes sélectionnées dans l’inspecteur** est activé dans les réglages, sélectionner une forme remplace ces commandes par celles de la forme. Cliquez sur le nom de la ligne en haut de l’inspecteur, ou appuyez sur **Échap**, pour revenir.",
        "ja": "設定で**選択した図形をインスペクタで編集**をオンにすると、図形を選択したときにこれらのコントロールがその図形用のものに切り替わります。戻るには、インスペクタ上部の行名をクリックするか、**Esc**を押します。",
        "ko": "설정에서 **선택한 도형을 검사기에서 편집**을 켜면 도형을 선택할 때 이 컨트롤이 해당 도형의 컨트롤로 바뀝니다. 돌아가려면 검사기 상단의 행 이름을 클릭하거나 **Esc**를 누르세요.",
        "pt-BR": "Com **Editar formas selecionadas no inspetor** ativado em Ajustes, selecionar uma forma troca esses controles pelos controles da própria forma. Clique no nome da linha no topo do inspetor, ou pressione **Esc**, para voltar.",
        "zh-Hans": "在设置中打开**在检查器中编辑所选形状**后，选择形状会将这些控件替换为该形状自己的控件。点按检查器顶部的行名称，或按 **Esc** 返回。",
    },
}


QUALITY_OVERRIDES = {
    "Export": {"de": "Exportieren", "fa": "صدور", "ja": "書き出す", "ko": "내보내기", "zh-Hans": "导出"},
    "Export…": {"de": "Exportieren …", "fa": "صدور…", "ja": "書き出す…", "ko": "내보내기…", "zh-Hans": "导出…"},
    "Details": {"de": "Details", "fa": "جزئیات", "ja": "詳細", "ko": "세부 정보", "zh-Hans": "详细信息"},
    "Source": {"fr": "Source"},
    "version": {"fr": "version"},
    "Angular": {"pt-BR": "Angular"},
    "App": {"de": "App"},
    "Auto": {"de": "Automatisch", "fr": "Auto", "pt-BR": "Automático"},
    "Base": {"de": "Basis", "es": "Base", "fr": "Base", "pt-BR": "Base"},
    "Center": {"de": "Zentrieren"},
    "Copyright": {"de": "Copyright"},
    "Description": {"fr": "Description"},
    "Download": {"pt-BR": "Baixar"},
    "Fit": {"de": "Anpassen"},
    "Format": {"de": "Format", "fr": "Format"},
    "General": {"es": "General"},
    "Gradient": {"de": "Verlauf"},
    "Image": {"fr": "Image"},
    "Images": {"fr": "Images"},
    "Inspector": {"es": "Inspector"},
    "Invisible": {"es": "Invisible", "fr": "Invisible"},
    "Regenerate Access Token": {"fa": "بازسازی توکن دسترسی"},
    "Spanning is great for storytelling: a sunset gradient or a single panoramic image can stretch across three templates and tell a continuous visual story in the App Store carousel.": {
        "ja": "スパン表示はストーリー作りに最適です。夕焼けのグラデーションや1枚のパノラマ画像を3つのテンプレートにまたがって伸ばし、App Storeのカルーセルで連続したビジュアルストーリーを伝えられます。"
    },
}

STALE_KEYS = {
    "Translate %@ into all %lld other language%@",
}

VALIDATION = {
    "App Store Connect returned %lld while trying to %@.": {
        "de": "App Store Connect gab %1$lld zurück beim Versuch: %2$@.",
        "es": "App Store Connect devolvió %1$lld al intentar %2$@.",
        "fa": "App Store Connect هنگام تلاش برای %2$@ مقدار %1$lld را برگرداند.",
        "fr": "App Store Connect a renvoyé %1$lld en essayant de %2$@.",
        "ja": "%2$@の試行中にApp Store Connectが%1$lldを返しました。",
        "ko": "%2$@을(를) 시도하는 동안 App Store Connect가 %1$lld을(를) 반환했습니다.",
        "pt-BR": "O App Store Connect retornou %1$lld ao tentar %2$@.",
        "zh-Hans": "App Store Connect 在尝试 %2$@ 时返回了 %1$lld。",
    },
    "Google Play returned %lld while trying to %@.": {
        "de": "Google Play gab %1$lld zurück beim Versuch: %2$@.",
        "es": "Google Play devolvió %1$lld al intentar %2$@.",
        "fa": "Google Play هنگام تلاش برای %2$@ مقدار %1$lld را برگرداند.",
        "fr": "Google Play a renvoyé %1$lld en essayant de %2$@.",
        "ja": "%2$@の試行中にGoogle Playが%1$lldを返しました。",
        "ko": "%2$@을(를) 시도하는 동안 Google Play가 %1$lld을(를) 반환했습니다.",
        "pt-BR": "O Google Play retornou %1$lld ao tentar %2$@.",
        "zh-Hans": "Google Play 在尝试 %2$@ 时返回了 %1$lld。",
    },
    "Could not read the private key from the service account JSON. Re-download the key from the Google Cloud console.": {
        "de": "Der private Schlüssel konnte nicht aus dem JSON des Dienstkontos gelesen werden. Lade den Schlüssel erneut aus der Google Cloud Console herunter.",
        "es": "No se pudo leer la clave privada del JSON de la cuenta de servicio. Vuelve a descargar la clave desde Google Cloud Console.",
        "fa": "کلید خصوصی از JSON حساب سرویس خوانده نشد. کلید را دوباره از کنسول Google Cloud دانلود کنید.",
        "fr": "Impossible de lire la clé privée depuis le JSON du compte de service. Téléchargez de nouveau la clé depuis la console Google Cloud.",
        "ja": "サービスアカウントJSONから秘密鍵を読み込めませんでした。Google Cloud Consoleからキーを再ダウンロードしてください。",
        "ko": "서비스 계정 JSON에서 비공개 키를 읽을 수 없습니다. Google Cloud 콘솔에서 키를 다시 다운로드하세요.",
        "pt-BR": "Não foi possível ler a chave privada do JSON da conta de serviço. Baixe a chave novamente no console do Google Cloud.",
        "zh-Hans": "无法从服务账号 JSON 中读取私钥。请从 Google Cloud 控制台重新下载密钥。",
    },
    "Could not render screenshot %lld for %@ (%@) in %@. Check that this row previews correctly in the editor, then try the upload again.": {
        "de": "Screenshot %1$lld für %2$@ (%3$@) in %4$@ konnte nicht gerendert werden. Prüfe, ob diese Zeile im Editor korrekt angezeigt wird, und versuche den Upload erneut.",
        "es": "No se pudo renderizar la captura %1$lld para %2$@ (%3$@) en %4$@. Comprueba que esta fila se previsualice correctamente en el editor y vuelve a intentar la subida.",
        "fa": "اسکرین‌شات %1$lld برای %2$@ (%3$@) در %4$@ رندر نشد. بررسی کنید این ردیف در ویرایشگر درست پیش‌نمایش می‌شود، سپس دوباره آپلود کنید.",
        "fr": "Impossible de rendre la capture %1$lld pour %2$@ (%3$@) dans %4$@. Vérifiez que cette ligne s’affiche correctement dans l’éditeur, puis réessayez l’envoi.",
        "ja": "%4$@の%2$@（%3$@）向けスクリーンショット%1$lldをレンダリングできませんでした。この行がエディタで正しくプレビューされることを確認してから、アップロードを再試行してください。",
        "ko": "%4$@의 %2$@(%3$@)용 스크린샷 %1$lld을(를) 렌더링할 수 없습니다. 편집기에서 이 행이 올바르게 미리보기되는지 확인한 뒤 다시 업로드하세요.",
        "pt-BR": "Não foi possível renderizar a captura %1$lld para %2$@ (%3$@) em %4$@. Verifique se esta linha aparece corretamente no editor e tente enviar novamente.",
        "zh-Hans": "无法渲染 %4$@ 中 %2$@（%3$@）的截图 %1$lld。请检查此行能否在编辑器中正确预览，然后再次尝试上传。",
    },
    "Could not render screenshot %lld for %@ (%@) in %@. Check that this row previews correctly, then try again.": {
        "de": "Screenshot %1$lld für %2$@ (%3$@) in %4$@ konnte nicht gerendert werden. Prüfe, ob diese Zeile korrekt angezeigt wird, und versuche es erneut.",
        "es": "No se pudo renderizar la captura %1$lld para %2$@ (%3$@) en %4$@. Comprueba que esta fila se previsualice correctamente y vuelve a intentarlo.",
        "fa": "اسکرین‌شات %1$lld برای %2$@ (%3$@) در %4$@ رندر نشد. بررسی کنید این ردیف درست پیش‌نمایش می‌شود، سپس دوباره تلاش کنید.",
        "fr": "Impossible de rendre la capture %1$lld pour %2$@ (%3$@) dans %4$@. Vérifiez que cette ligne s’affiche correctement, puis réessayez.",
        "ja": "%4$@の%2$@（%3$@）向けスクリーンショット%1$lldをレンダリングできませんでした。この行が正しくプレビューされることを確認してから、再試行してください。",
        "ko": "%4$@의 %2$@(%3$@)용 스크린샷 %1$lld을(를) 렌더링할 수 없습니다. 이 행이 올바르게 미리보기되는지 확인한 후 다시 시도하세요.",
        "pt-BR": "Não foi possível renderizar a captura %1$lld para %2$@ (%3$@) em %4$@. Verifique se esta linha aparece corretamente e tente de novo.",
        "zh-Hans": "无法渲染 %4$@ 中 %2$@（%3$@）的截图 %1$lld。请检查此行能否正确预览，然后重试。",
    },
    "Select at least one editable version.": {
        "de": "Wähle mindestens eine bearbeitbare Version aus.", "es": "Selecciona al menos una versión editable.",
        "fa": "حداقل یک نسخه قابل ویرایش انتخاب کنید.", "fr": "Sélectionnez au moins une version modifiable.",
        "ja": "編集可能なバージョンを1つ以上選択してください。", "ko": "편집 가능한 버전을 하나 이상 선택하세요.",
        "pt-BR": "Selecione pelo menos uma versão editável.", "zh-Hans": "请选择至少一个可编辑版本。",
    },
    "Version %@ is %@. Screenshots can only be changed when the version is editable.": {
        "de": "Version %@ ist %@. Screenshots können nur geändert werden, wenn die Version bearbeitbar ist.",
        "es": "La versión %@ está en estado %@. Las capturas solo se pueden cambiar cuando la versión es editable.",
        "fa": "نسخه %@ در وضعیت %@ است. اسکرین‌شات‌ها فقط زمانی قابل تغییرند که نسخه قابل ویرایش باشد.",
        "fr": "La version %@ est %@. Les captures ne peuvent être modifiées que lorsque la version est modifiable.",
        "ja": "バージョン%@は%@です。スクリーンショットを変更できるのは、バージョンが編集可能な場合だけです。",
        "ko": "버전 %@의 상태는 %@입니다. 버전을 편집할 수 있을 때만 스크린샷을 변경할 수 있습니다.",
        "pt-BR": "A versão %@ está %@. As capturas só podem ser alteradas quando a versão é editável.",
        "zh-Hans": "版本 %@ 当前为 %@。只有版本可编辑时才能更改截图。",
    },
    "Create a new version in App Store Connect, or wait for this one to return to an editable state.": {
        "de": "Erstelle in App Store Connect eine neue Version oder warte, bis diese Version wieder bearbeitbar ist.",
        "es": "Crea una nueva versión en App Store Connect o espera a que esta vuelva a un estado editable.",
        "fa": "در App Store Connect نسخه جدیدی بسازید یا منتظر بمانید این نسخه دوباره قابل ویرایش شود.",
        "fr": "Créez une nouvelle version dans App Store Connect ou attendez que celle-ci redevienne modifiable.",
        "ja": "App Store Connectで新しいバージョンを作成するか、このバージョンが編集可能な状態に戻るまで待ってください。",
        "ko": "App Store Connect에서 새 버전을 만들거나 이 버전이 편집 가능한 상태로 돌아올 때까지 기다리세요.",
        "pt-BR": "Crie uma nova versão no App Store Connect ou aguarde esta voltar a um estado editável.",
        "zh-Hans": "请在 App Store Connect 中创建新版本，或等待此版本恢复到可编辑状态。",
    },
    "Pick a display type for this row (%@).": {
        "de": "Wähle einen Anzeigetyp für diese Zeile (%@).", "es": "Elige un tipo de pantalla para esta fila (%@).",
        "fa": "برای این ردیف (%@) یک نوع نمایش انتخاب کنید.", "fr": "Choisissez un type d’affichage pour cette ligne (%@).",
        "ja": "この行（%@）の表示タイプを選択してください。", "ko": "이 행(%@)의 표시 유형을 선택하세요.",
        "pt-BR": "Escolha um tipo de exibição para esta linha (%@).", "zh-Hans": "为此行 (%@) 选择显示类型。",
    },
    "Use the \"Display Type\" picker above.": {
        "de": "Verwende oben die Auswahl „Display Type“.", "es": "Usa el selector «Tipo de pantalla» de arriba.",
        "fa": "از انتخابگر «نوع نمایش» در بالا استفاده کنید.", "fr": "Utilisez le sélecteur « Type d’affichage » ci-dessus.",
        "ja": "上の「表示タイプ」ピッカーを使用してください。", "ko": "위의 “Display Type” 선택기를 사용하세요.",
        "pt-BR": "Use o seletor “Tipo de exibição” acima.", "zh-Hans": "使用上方的“显示类型”选择器。",
    },
    "Row size %@ isn't accepted by App Store Connect for %@.": {
        "de": "Die Zeilengröße %@ wird von App Store Connect für %@ nicht akzeptiert.",
        "es": "App Store Connect no acepta el tamaño de fila %@ para %@.",
        "fa": "اندازه ردیف %@ برای %@ در App Store Connect پذیرفته نیست.",
        "fr": "La taille de ligne %@ n’est pas acceptée par App Store Connect pour %@.",
        "ja": "行サイズ%@は%@向けとしてApp Store Connectに受け入れられません。",
        "ko": "행 크기 %@은(는) %@용으로 App Store Connect에서 허용되지 않습니다.",
        "pt-BR": "O tamanho de linha %@ não é aceito pelo App Store Connect para %@.",
        "zh-Hans": "App Store Connect 不接受 %@ 的行尺寸 %@。",
    },
    "Pick a different display type.": {
        "de": "Wähle einen anderen Anzeigetyp.", "es": "Elige otro tipo de pantalla.",
        "fa": "نوع نمایش دیگری انتخاب کنید.", "fr": "Choisissez un autre type d’affichage.",
        "ja": "別の表示タイプを選択してください。", "ko": "다른 표시 유형을 선택하세요.",
        "pt-BR": "Escolha outro tipo de exibição.", "zh-Hans": "请选择其他显示类型。",
    },
    "Resize the row to one of: %@, or pick a matching display type.": {
        "de": "Ändere die Zeile auf eine dieser Größen: %@, oder wähle einen passenden Anzeigetyp.",
        "es": "Cambia el tamaño de la fila a uno de estos: %@, o elige un tipo de pantalla compatible.",
        "fa": "اندازه ردیف را به یکی از این موارد تغییر دهید: %@، یا نوع نمایش سازگار انتخاب کنید.",
        "fr": "Redimensionnez la ligne vers l’une de ces tailles : %@, ou choisissez un type d’affichage correspondant.",
        "ja": "行サイズを次のいずれかに変更するか、対応する表示タイプを選択してください: %@。",
        "ko": "행 크기를 다음 중 하나로 조정하거나 일치하는 표시 유형을 선택하세요: %@.",
        "pt-BR": "Redimensione a linha para um destes tamanhos: %@, ou escolha um tipo de exibição correspondente.",
        "zh-Hans": "将行调整为以下尺寸之一：%@，或选择匹配的显示类型。",
    },
    "%@ can't be uploaded to a %@ version.": {
        "de": "%@ kann nicht zu einer %@-Version hochgeladen werden.", "es": "%@ no se puede subir a una versión %@.",
        "fa": "%@ را نمی‌توان در نسخه %@ آپلود کرد.", "fr": "%@ ne peut pas être téléversé vers une version %@.",
        "ja": "%@は%@バージョンにアップロードできません。", "ko": "%@은(는) %@ 버전에 업로드할 수 없습니다.",
        "pt-BR": "%@ não pode ser enviado para uma versão %@.", "zh-Hans": "%@ 不能上传到 %@ 版本。",
    },
    "Pick a display type that matches the app's platform.": {
        "de": "Wähle einen Anzeigetyp, der zur Plattform der App passt.", "es": "Elige un tipo de pantalla que coincida con la plataforma de la app.",
        "fa": "نوع نمایشی انتخاب کنید که با پلتفرم برنامه سازگار باشد.", "fr": "Choisissez un type d’affichage qui correspond à la plateforme de l’app.",
        "ja": "アプリのプラットフォームに合う表示タイプを選択してください。", "ko": "앱 플랫폼과 일치하는 표시 유형을 선택하세요.",
        "pt-BR": "Escolha um tipo de exibição compatível com a plataforma do app.", "zh-Hans": "请选择与 App 平台匹配的显示类型。",
    },
    "This row has no screenshots to upload.": {
        "de": "Diese Zeile hat keine Screenshots zum Hochladen.", "es": "Esta fila no tiene capturas para subir.",
        "fa": "این ردیف اسکرین‌شاتی برای آپلود ندارد.", "fr": "Cette ligne ne contient aucune capture à téléverser.",
        "ja": "この行にはアップロードするスクリーンショットがありません。", "ko": "이 행에는 업로드할 스크린샷이 없습니다.",
        "pt-BR": "Esta linha não tem capturas para enviar.", "zh-Hans": "此行没有可上传的截图。",
    },
    "Add at least one screenshot column to this row.": {
        "de": "Füge dieser Zeile mindestens eine Screenshot-Spalte hinzu.", "es": "Añade al menos una columna de capturas a esta fila.",
        "fa": "حداقل یک ستون اسکرین‌شات به این ردیف اضافه کنید.", "fr": "Ajoutez au moins une colonne de capture à cette ligne.",
        "ja": "この行にスクリーンショット列を1つ以上追加してください。", "ko": "이 행에 스크린샷 열을 하나 이상 추가하세요.",
        "pt-BR": "Adicione pelo menos uma coluna de captura a esta linha.", "zh-Hans": "请为此行至少添加一列截图。",
    },
    "This row uploads 1 screenshot. App Store Connect accepts %lld–%lld, but most apps show at least %lld.": {
        "de": "Diese Zeile lädt 1 Screenshot hoch. App Store Connect akzeptiert %lld–%lld, aber die meisten Apps zeigen mindestens %lld.",
        "es": "Esta fila sube 1 captura. App Store Connect acepta %lld–%lld, pero la mayoría de apps muestra al menos %lld.",
        "fa": "این ردیف ۱ اسکرین‌شات آپلود می‌کند. App Store Connect تعداد %lld تا %lld را می‌پذیرد، اما بیشتر برنامه‌ها حداقل %lld مورد نشان می‌دهند.",
        "fr": "Cette ligne téléverse 1 capture. App Store Connect accepte %lld à %lld captures, mais la plupart des apps en affichent au moins %lld.",
        "ja": "この行は1枚のスクリーンショットをアップロードします。App Store Connectは%lld〜%lld枚を受け付けますが、ほとんどのアプリは少なくとも%lld枚を表示します。",
        "ko": "이 행은 스크린샷 1개를 업로드합니다. App Store Connect는 %lld–%lld개를 허용하지만 대부분의 앱은 최소 %lld개를 표시합니다.",
        "pt-BR": "Esta linha envia 1 captura. O App Store Connect aceita %lld–%lld, mas a maioria dos apps mostra pelo menos %lld.",
        "zh-Hans": "此行会上传 1 张截图。App Store Connect 接受 %lld–%lld 张，但大多数 App 至少显示 %lld 张。",
    },
    "This row uploads %lld screenshots. App Store Connect accepts %lld–%lld, but most apps show at least %lld.": {
        "de": "Diese Zeile lädt %lld Screenshots hoch. App Store Connect akzeptiert %lld–%lld, aber die meisten Apps zeigen mindestens %lld.",
        "es": "Esta fila sube %lld capturas. App Store Connect acepta %lld–%lld, pero la mayoría de apps muestra al menos %lld.",
        "fa": "این ردیف %lld اسکرین‌شات آپلود می‌کند. App Store Connect تعداد %lld تا %lld را می‌پذیرد، اما بیشتر برنامه‌ها حداقل %lld مورد نشان می‌دهند.",
        "fr": "Cette ligne téléverse %lld captures. App Store Connect accepte %lld à %lld captures, mais la plupart des apps en affichent au moins %lld.",
        "ja": "この行は%lld枚のスクリーンショットをアップロードします。App Store Connectは%lld〜%lld枚を受け付けますが、ほとんどのアプリは少なくとも%lld枚を表示します。",
        "ko": "이 행은 스크린샷 %lld개를 업로드합니다. App Store Connect는 %lld–%lld개를 허용하지만 대부분의 앱은 최소 %lld개를 표시합니다.",
        "pt-BR": "Esta linha envia %lld capturas. O App Store Connect aceita %lld–%lld, mas a maioria dos apps mostra pelo menos %lld.",
        "zh-Hans": "此行会上传 %lld 张截图。App Store Connect 接受 %lld–%lld 张，但大多数 App 至少显示 %lld 张。",
    },
    "Add more screenshot columns, or upload as is.": {
        "de": "Füge weitere Screenshot-Spalten hinzu oder lade unverändert hoch.", "es": "Añade más columnas de capturas o sube tal como está.",
        "fa": "ستون‌های اسکرین‌شات بیشتری اضافه کنید یا همین‌طور آپلود کنید.", "fr": "Ajoutez d’autres colonnes de capture, ou téléversez tel quel.",
        "ja": "スクリーンショット列を追加するか、このままアップロードしてください。", "ko": "스크린샷 열을 더 추가하거나 그대로 업로드하세요.",
        "pt-BR": "Adicione mais colunas de captura ou envie como está.", "zh-Hans": "请添加更多截图列，或按当前状态上传。",
    },
    "App Store Connect allows at most %lld screenshots per display type; this row has %lld.": {
        "de": "App Store Connect erlaubt höchstens %lld Screenshots pro Anzeigetyp; diese Zeile hat %lld.",
        "es": "App Store Connect permite como máximo %lld capturas por tipo de pantalla; esta fila tiene %lld.",
        "fa": "App Store Connect برای هر نوع نمایش حداکثر %lld اسکرین‌شات می‌پذیرد؛ این ردیف %lld مورد دارد.",
        "fr": "App Store Connect autorise au maximum %lld captures par type d’affichage ; cette ligne en contient %lld.",
        "ja": "App Store Connectでは表示タイプごとに最大%lld枚のスクリーンショットを許可しています。この行には%lld枚あります。",
        "ko": "App Store Connect는 표시 유형당 최대 %lld개의 스크린샷을 허용합니다. 이 행에는 %lld개가 있습니다.",
        "pt-BR": "O App Store Connect permite no máximo %lld capturas por tipo de exibição; esta linha tem %lld.",
        "zh-Hans": "App Store Connect 每种显示类型最多允许 %lld 张截图；此行有 %lld 张。",
    },
    "Remove columns to bring the count to %lld or fewer.": {
        "de": "Entferne Spalten, um die Anzahl auf %lld oder weniger zu senken.", "es": "Elimina columnas para bajar el total a %lld o menos.",
        "fa": "ستون‌ها را حذف کنید تا تعداد به %lld یا کمتر برسد.", "fr": "Supprimez des colonnes pour ramener le total à %lld ou moins.",
        "ja": "列を削除して、数を%lld以下にしてください。", "ko": "열을 제거해 개수를 %lld개 이하로 줄이세요.",
        "pt-BR": "Remova colunas para deixar a contagem em %lld ou menos.", "zh-Hans": "请移除列，使数量降至 %lld 或更少。",
    },
    "Pick at least one App Store locale to upload to.": {
        "de": "Wähle mindestens eine App Store-Locale zum Hochladen aus.", "es": "Elige al menos un idioma de App Store al que subir.",
        "fa": "حداقل یک زبان App Store برای آپلود انتخاب کنید.", "fr": "Choisissez au moins une langue App Store vers laquelle téléverser.",
        "ja": "アップロード先のApp Storeロケールを1つ以上選択してください。", "ko": "업로드할 App Store 로케일을 하나 이상 선택하세요.",
        "pt-BR": "Escolha pelo menos uma localidade da App Store para enviar.", "zh-Hans": "请选择至少一个要上传到的 App Store 语言区域。",
    },
    "Enable a locale checkbox and choose an App Store locale.": {
        "de": "Aktiviere ein Locale-Kontrollkästchen und wähle eine App Store-Locale.", "es": "Activa una casilla de idioma y elige un idioma de App Store.",
        "fa": "یک کادر زبان را فعال کنید و یک زبان App Store انتخاب کنید.", "fr": "Cochez une langue et choisissez une langue App Store.",
        "ja": "ロケールのチェックボックスをオンにして、App Storeロケールを選択してください。", "ko": "로케일 체크상자를 켜고 App Store 로케일을 선택하세요.",
        "pt-BR": "Ative uma caixa de localidade e escolha uma localidade da App Store.", "zh-Hans": "启用语言区域复选框并选择 App Store 语言区域。",
    },
    "Choose the App Store locale for %@.": {
        "de": "Wähle die App Store-Locale für %@.", "es": "Elige el idioma de App Store para %@.",
        "fa": "زبان App Store را برای %@ انتخاب کنید.", "fr": "Choisissez la langue App Store pour %@.",
        "ja": "%@のApp Storeロケールを選択してください。", "ko": "%@의 App Store 로케일을 선택하세요.",
        "pt-BR": "Escolha a localidade da App Store para %@.", "zh-Hans": "请选择 %@ 的 App Store 语言区域。",
    },
    "Use the locale picker in this row, or disable this locale.": {
        "de": "Verwende die Locale-Auswahl in dieser Zeile oder deaktiviere diese Locale.",
        "es": "Usa el selector de idioma de esta fila o desactiva este idioma.",
        "fa": "از انتخابگر زبان در این ردیف استفاده کنید یا این زبان را غیرفعال کنید.",
        "fr": "Utilisez le sélecteur de langue dans cette ligne, ou désactivez cette langue.",
        "ja": "この行のロケールピッカーを使うか、このロケールを無効にしてください。",
        "ko": "이 행의 로케일 선택기를 사용하거나 이 로케일을 비활성화하세요.",
        "pt-BR": "Use o seletor de localidade nesta linha ou desative esta localidade.",
        "zh-Hans": "使用此行中的语言区域选择器，或停用此语言区域。",
    },
    "No App Store locale matches %@ on this version.": {
        "de": "Keine App Store-Locale passt in dieser Version zu %@.", "es": "Ningún idioma de App Store coincide con %@ en esta versión.",
        "fa": "هیچ زبان App Store در این نسخه با %@ مطابقت ندارد.", "fr": "Aucune langue App Store ne correspond à %@ sur cette version.",
        "ja": "このバージョンには%@に一致するApp Storeロケールがありません。", "ko": "이 버전에는 %@와 일치하는 App Store 로케일이 없습니다.",
        "pt-BR": "Nenhuma localidade da App Store corresponde a %@ nesta versão.", "zh-Hans": "此版本中没有与 %@ 匹配的 App Store 语言区域。",
    },
    "Add the locale in App Store Connect, or disable this locale here.": {
        "de": "Füge die Locale in App Store Connect hinzu oder deaktiviere sie hier.", "es": "Añade el idioma en App Store Connect o desactívalo aquí.",
        "fa": "زبان را در App Store Connect اضافه کنید یا آن را اینجا غیرفعال کنید.", "fr": "Ajoutez la langue dans App Store Connect, ou désactivez-la ici.",
        "ja": "App Store Connectでロケールを追加するか、ここでこのロケールを無効にしてください。", "ko": "App Store Connect에서 로케일을 추가하거나 여기서 이 로케일을 비활성화하세요.",
        "pt-BR": "Adicione a localidade no App Store Connect ou desative-a aqui.", "zh-Hans": "请在 App Store Connect 中添加该语言区域，或在此处停用它。",
    },
    "This row uploads to the same App Store screenshot set as %@.": {
        "de": "Diese Zeile lädt in dasselbe App Store-Screenshot-Set wie %@ hoch.", "es": "Esta fila sube al mismo conjunto de capturas de App Store que %@.",
        "fa": "این ردیف در همان مجموعه اسکرین‌شات App Store مربوط به %@ آپلود می‌شود.", "fr": "Cette ligne téléverse vers le même ensemble de captures App Store que %@.",
        "ja": "この行は%@と同じApp Storeスクリーンショットセットにアップロードされます。", "ko": "이 행은 %@와 동일한 App Store 스크린샷 세트에 업로드됩니다.",
        "pt-BR": "Esta linha envia para o mesmo conjunto de capturas da App Store que %@.", "zh-Hans": "此行会上传到与 %@ 相同的 App Store 截图集合。",
    },
    "Disable one of these rows or choose a different display type before uploading.": {
        "de": "Deaktiviere vor dem Hochladen eine dieser Zeilen oder wähle einen anderen Anzeigetyp.",
        "es": "Desactiva una de estas filas o elige otro tipo de pantalla antes de subir.",
        "fa": "پیش از آپلود، یکی از این ردیف‌ها را غیرفعال کنید یا نوع نمایش دیگری انتخاب کنید.",
        "fr": "Désactivez l’une de ces lignes ou choisissez un autre type d’affichage avant l’envoi.",
        "ja": "アップロード前に、これらの行のいずれかを無効にするか、別の表示タイプを選択してください。",
        "ko": "업로드하기 전에 이 행 중 하나를 비활성화하거나 다른 표시 유형을 선택하세요.",
        "pt-BR": "Desative uma dessas linhas ou escolha outro tipo de exibição antes de enviar.",
        "zh-Hans": "上传前请停用其中一行，或选择其他显示类型。",
    },
}


def t(lang: str, key: str) -> str:
    return PHRASES[lang][key]


def translate(lang: str, key: str) -> str | None:
    if key in EXACT:
        return EXACT[key][lang]
    if key in VALIDATION:
        return VALIDATION[key][lang]
    if key in QUALITY_OVERRIDES and lang in QUALITY_OVERRIDES[key]:
        return QUALITY_OVERRIDES[key][lang]

    p = PHRASES[lang]

    simple = {
        "1 screenshot": t(lang, "screenshot"), "%lld screenshots": t(lang, "screenshots"),
        "1 set": t(lang, "set"), "%lld sets": t(lang, "sets"),
        "1 locale": t(lang, "locale"), "%lld locales": t(lang, "locales"),
        "1 version": t(lang, "version"), "%lld versions": t(lang, "versions"),
        "1 language": t(lang, "language"), "%lld languages": t(lang, "languages"),
        "1 upload": t(lang, "upload"), "%lld uploads": t(lang, "uploads"),
        "1 removal": t(lang, "removal"), "%lld removals": t(lang, "removals"),
        "1 move": t(lang, "move"), "%lld moves": t(lang, "moves"),
        "1 field": t(lang, "field"), "%lld fields": t(lang, "fields"),
        "1 included": t(lang, "included"), "%lld included": t(lang, "included_many"),
        "1 changed": t(lang, "changed"), "%lld changed": t(lang, "changed_many"),
        "1 blocked": t(lang, "blocked"), "%lld blocked": t(lang, "blocked_many"),
        "1 image file could not be read": {
            "de": "1 Bilddatei konnte nicht gelesen werden", "es": "No se pudo leer 1 archivo de imagen",
            "fa": "۱ فایل تصویر خوانده نشد", "fr": "1 fichier image n’a pas pu être lu",
            "ja": "1個の画像ファイルを読み込めませんでした", "ko": "이미지 파일 1개를 읽을 수 없습니다",
            "pt-BR": "Não foi possível ler 1 arquivo de imagem", "zh-Hans": "无法读取 1 个图像文件",
        }[lang],
        "1 more skipped item": {
            "de": "1 weiteres übersprungenes Element", "es": "1 elemento omitido más",
            "fa": "۱ مورد ردشده دیگر", "fr": "1 élément ignoré de plus",
            "ja": "ほか1件のスキップ項目", "ko": "건너뛴 항목 1개 더",
            "pt-BR": "mais 1 item ignorado", "zh-Hans": "另有 1 个已跳过项目",
        }[lang],
        "%lld more skipped items": {
            "de": "%lld weitere übersprungene Elemente", "es": "%lld elementos omitidos más",
            "fa": "%lld مورد ردشده دیگر", "fr": "%lld éléments ignorés de plus",
            "ja": "ほか%lld件のスキップ項目", "ko": "건너뛴 항목 %lld개 더",
            "pt-BR": "mais %lld itens ignorados", "zh-Hans": "另有 %lld 个已跳过项目",
        }[lang],
        "%lld image files could not be read": {
            "de": "%lld Bilddateien konnten nicht gelesen werden", "es": "No se pudieron leer %lld archivos de imagen",
            "fa": "%lld فایل تصویر خوانده نشد", "fr": "%lld fichiers image n’ont pas pu être lus",
            "ja": "%lld個の画像ファイルを読み込めませんでした", "ko": "이미지 파일 %lld개를 읽을 수 없습니다",
            "pt-BR": "Não foi possível ler %lld arquivos de imagem", "zh-Hans": "无法读取 %lld 个图像文件",
        }[lang],
    }
    if key in simple:
        return simple[key]

    if key == "%@, %@, and %@.":
        return {
            "de": "%@, %@ und %@.", "es": "%@, %@ y %@.", "fa": "%@، %@ و %@.",
            "fr": "%@, %@ et %@.", "ja": "%@、%@、%@。", "ko": "%@, %@ 및 %@.",
            "pt-BR": "%@, %@ e %@.", "zh-Hans": "%@、%@ 和 %@。",
        }[lang]
    if key == "%@ across %@, %@, and %@.":
        return {
            "de": "%@ über %@, %@ und %@.", "es": "%@ en %@, %@ y %@.", "fa": "%@ در %@، %@ و %@.",
            "fr": "%@ sur %@, %@ et %@.", "ja": "%@（%@、%@、%@）。", "ko": "%@, %@, %@ 및 %@ 전체.",
            "pt-BR": "%@ em %@, %@ e %@.", "zh-Hans": "%@，覆盖 %@、%@ 和 %@。",
        }[lang]
    if key == "%@ · %@ · %@":
        return "%@ · %@ · %@"
    if key == "%@ · %@ · %@ · %@":
        return "%@ · %@ · %@ · %@"

    if key in ("%@×%@ · 1 screenshot", "%lld×%lld · 1 screenshot"):
        return key.replace("1 screenshot", t(lang, "screenshot"))
    if key in ("%@×%@ · %lld screenshots", "%lld×%lld · %lld screenshots"):
        return key.replace("%lld screenshots", t(lang, "screenshots"))
    if key == "Source %@ · 1 screenshot · %@":
        return {
            "de": "Quelle %@ · 1 Screenshot · %@", "es": "Origen %@ · 1 captura · %@",
            "fa": "منبع %@ · ۱ اسکرین‌شات · %@", "fr": "Source %@ · 1 capture d’écran · %@",
            "ja": "ソース %@ · 1枚のスクリーンショット · %@", "ko": "소스 %@ · 스크린샷 1개 · %@",
            "pt-BR": "Origem %@ · 1 captura de tela · %@", "zh-Hans": "来源 %@ · 1 张截图 · %@",
        }[lang]
    if key == "Source %@ · %lld screenshots · %@":
        return {
            "de": "Quelle %@ · %lld Screenshots · %@", "es": "Origen %@ · %lld capturas · %@",
            "fa": "منبع %@ · %lld اسکرین‌شات · %@", "fr": "Source %@ · %lld captures d’écran · %@",
            "ja": "ソース %@ · %lld枚のスクリーンショット · %@", "ko": "소스 %@ · 스크린샷 %lld개 · %@",
            "pt-BR": "Origem %@ · %lld capturas de tela · %@", "zh-Hans": "来源 %@ · %lld 张截图 · %@",
        }[lang]

    if key == "%lld screenshots to upload":
        return {
            "de": "%lld Screenshots zum Hochladen", "es": "%lld capturas para subir",
            "fa": "%lld اسکرین‌شات برای آپلود", "fr": "%lld captures d’écran à téléverser",
            "ja": "アップロードする%lld枚のスクリーンショット", "ko": "업로드할 스크린샷 %lld개",
            "pt-BR": "%lld capturas de tela para enviar", "zh-Hans": "%lld 张截图待上传",
        }[lang]
    if key == "1 screenshot to upload":
        return {
            "de": "1 Screenshot zum Hochladen", "es": "1 captura para subir",
            "fa": "۱ اسکرین‌شات برای آپلود", "fr": "1 capture d’écran à téléverser",
            "ja": "アップロードする1枚のスクリーンショット", "ko": "업로드할 스크린샷 1개",
            "pt-BR": "1 captura de tela para enviar", "zh-Hans": "1 张截图待上传",
        }[lang]
    if key == "%lld screenshots exported":
        return {"de": "%lld Screenshots exportiert", "es": "%lld capturas exportadas", "fa": "%lld اسکرین‌شات صادر شد", "fr": "%lld captures d’écran exportées", "ja": "%lld枚のスクリーンショットを書き出しました", "ko": "스크린샷 %lld개를 내보냈습니다", "pt-BR": "%lld capturas de tela exportadas", "zh-Hans": "已导出 %lld 张截图"}[lang]
    if key == "1 screenshot exported":
        return {"de": "1 Screenshot exportiert", "es": "1 captura exportada", "fa": "۱ اسکرین‌شات صادر شد", "fr": "1 capture d’écran exportée", "ja": "1枚のスクリーンショットを書き出しました", "ko": "스크린샷 1개를 내보냈습니다", "pt-BR": "1 captura de tela exportada", "zh-Hans": "已导出 1 张截图"}[lang]
    if key == "%lld screenshots exported · %@":
        return translate(lang, "%lld screenshots exported") + " · %@"
    if key == "1 screenshot exported · %@":
        return translate(lang, "1 screenshot exported") + " · %@"

    m = re.fullmatch(r"(1 screenshot|%lld screenshots) across (1 language|%lld languages)", key)
    if m:
        return {
            "de": f"{simple[m.group(1)]} in {simple[m.group(2)]}",
            "es": f"{simple[m.group(1)]} en {simple[m.group(2)]}",
            "fa": f"{simple[m.group(1)]} در {simple[m.group(2)]}",
            "fr": f"{simple[m.group(1)]} sur {simple[m.group(2)]}",
            "ja": f"{simple[m.group(2)]}の{simple[m.group(1)]}",
            "ko": f"{simple[m.group(2)]}의 {simple[m.group(1)]}",
            "pt-BR": f"{simple[m.group(1)]} em {simple[m.group(2)]}",
            "zh-Hans": f"{simple[m.group(2)]}中的{simple[m.group(1)]}",
        }[lang]

    m = re.fullmatch(r"(1 screenshot|%lld screenshots) across (1 locale|%lld locales) and (1 version|%lld versions)", key)
    if m:
        return {
            "de": f"{simple[m.group(1)]} in {simple[m.group(2)]} und {simple[m.group(3)]}",
            "es": f"{simple[m.group(1)]} en {simple[m.group(2)]} y {simple[m.group(3)]}",
            "fa": f"{simple[m.group(1)]} در {simple[m.group(2)]} و {simple[m.group(3)]}",
            "fr": f"{simple[m.group(1)]} sur {simple[m.group(2)]} et {simple[m.group(3)]}",
            "ja": f"{simple[m.group(2)]}と{simple[m.group(3)]}の{simple[m.group(1)]}",
            "ko": f"{simple[m.group(2)]} 및 {simple[m.group(3)]}의 {simple[m.group(1)]}",
            "pt-BR": f"{simple[m.group(1)]} em {simple[m.group(2)]} e {simple[m.group(3)]}",
            "zh-Hans": f"{simple[m.group(2)]}和{simple[m.group(3)]}中的{simple[m.group(1)]}",
        }[lang]

    m = re.fullmatch(r"(1 screenshot|%lld screenshots) synced across (1 locale|%lld locales) and (1 version|%lld versions)\.", key)
    if m:
        base = translate(lang, f"{m.group(1)} across {m.group(2)} and {m.group(3)}")
        return {
            "de": f"{base} synchronisiert.", "es": f"{base} sincronizadas.", "fa": f"{base} همگام‌سازی شد.",
            "fr": f"{base} synchronisées.", "ja": f"{base}を同期しました。", "ko": f"{base} 동기화됨.",
            "pt-BR": f"{base} sincronizadas.", "zh-Hans": f"已同步{base}。",
        }[lang]

    m = re.fullmatch(r"(1 field|%lld fields) saved across (1 locale|%lld locales) and (1 version|%lld versions)\.", key)
    if m:
        return {
            "de": f"{simple[m.group(1)]} in {simple[m.group(2)]} und {simple[m.group(3)]} gespeichert.",
            "es": f"{simple[m.group(1)]} guardado en {simple[m.group(2)]} y {simple[m.group(3)]}.",
            "fa": f"{simple[m.group(1)]} در {simple[m.group(2)]} و {simple[m.group(3)]} ذخیره شد.",
            "fr": f"{simple[m.group(1)]} enregistré sur {simple[m.group(2)]} et {simple[m.group(3)]}.",
            "ja": f"{simple[m.group(2)]}と{simple[m.group(3)]}で{simple[m.group(1)]}を保存しました。",
            "ko": f"{simple[m.group(2)]} 및 {simple[m.group(3)]}에 {simple[m.group(1)]} 저장됨.",
            "pt-BR": f"{simple[m.group(1)]} salvo em {simple[m.group(2)]} e {simple[m.group(3)]}.",
            "zh-Hans": f"已在{simple[m.group(2)]}和{simple[m.group(3)]}中保存{simple[m.group(1)]}。",
        }[lang]

    if key == "1 screenshot set included.":
        return {"de": "1 Screenshot-Set enthalten.", "es": "1 conjunto de capturas incluido.", "fa": "۱ مجموعه اسکرین‌شات انتخاب شد.", "fr": "1 ensemble de captures inclus.", "ja": "1件のスクリーンショットセットを含みます。", "ko": "스크린샷 세트 1개 포함.", "pt-BR": "1 conjunto de capturas incluído.", "zh-Hans": "已包含 1 个截图集合。"}[lang]
    if key == "1 unchanged screenshot will keep its App Store asset ID.":
        return {"de": "1 unveränderter Screenshot behält seine App Store Asset-ID.", "es": "1 captura sin cambios conservará su ID de recurso de App Store.", "fa": "۱ اسکرین‌شات بدون تغییر شناسه دارایی App Store خود را نگه می‌دارد.", "fr": "1 capture inchangée conservera son identifiant de ressource App Store.", "ja": "変更のない1枚のスクリーンショットはApp StoreのアセットIDを保持します。", "ko": "변경되지 않은 스크린샷 1개는 App Store 에셋 ID를 유지합니다.", "pt-BR": "1 captura inalterada manterá seu ID de recurso da App Store.", "zh-Hans": "1 张未更改的截图将保留其 App Store 资源 ID。"}[lang]
    if key == "1 screenshot must be removed first to stay within Apple's 10-screenshot limit.":
        return {"de": "1 Screenshot muss zuerst entfernt werden, um Apples Limit von 10 Screenshots einzuhalten.", "es": "Primero se debe eliminar 1 captura para respetar el límite de 10 capturas de Apple.", "fa": "برای رعایت محدودیت ۱۰ اسکرین‌شات اپل، ابتدا باید ۱ اسکرین‌شات حذف شود.", "fr": "1 capture doit d’abord être supprimée pour respecter la limite de 10 captures d’Apple.", "ja": "Appleの10枚制限内に収めるには、先に1枚のスクリーンショットを削除する必要があります。", "ko": "Apple의 스크린샷 10개 제한을 지키려면 먼저 스크린샷 1개를 제거해야 합니다.", "pt-BR": "1 captura precisa ser removida primeiro para ficar dentro do limite de 10 capturas da Apple.", "zh-Hans": "必须先移除 1 张截图，才能符合 Apple 的 10 张截图限制。"}[lang]

    m = re.fullmatch(r"Translate (this text|%lld selected texts) into (1 other language|%lld other languages)", key)
    if m:
        text = {
            "this text": {
                "de": "diesen Text", "es": "este texto", "fa": "این متن", "fr": "ce texte",
                "ja": "このテキスト", "ko": "이 텍스트", "pt-BR": "este texto", "zh-Hans": "此文本",
            },
            "%lld selected texts": {
                "de": "%lld ausgewählte Texte", "es": "%lld textos seleccionados",
                "fa": "%lld متن انتخاب‌شده", "fr": "%lld textes sélectionnés",
                "ja": "選択した%lld件のテキスト", "ko": "선택한 텍스트 %lld개",
                "pt-BR": "%lld textos selecionados", "zh-Hans": "%lld 个所选文本",
            },
        }[m.group(1)][lang]
        languages = {
            "1 other language": {
                "de": "1 weitere Sprache", "es": "1 idioma más", "fa": "۱ زبان دیگر",
                "fr": "1 autre langue", "ja": "ほか1言語", "ko": "다른 언어 1개",
                "pt-BR": "1 outro idioma", "zh-Hans": "另外 1 种语言",
            },
            "%lld other languages": {
                "de": "%lld weitere Sprachen", "es": "%lld idiomas más",
                "fa": "%lld زبان دیگر", "fr": "%lld autres langues",
                "ja": "ほか%lld言語", "ko": "다른 언어 %lld개",
                "pt-BR": "%lld outros idiomas", "zh-Hans": "另外 %lld 种语言",
            },
        }[m.group(2)][lang]
        return {
            "de": f"{text} in {languages} übersetzen",
            "es": f"Traducir {text} a {languages}",
            "fa": f"{text} را به {languages} ترجمه کنید",
            "fr": f"Traduire {text} dans {languages}",
            "ja": f"{text}を{languages}に翻訳",
            "ko": f"{text}을(를) {languages}로 번역",
            "pt-BR": f"Traduzir {text} para {languages}",
            "zh-Hans": f"将{text}翻译成{languages}",
        }[lang]

    if key == "Upload compares each screenshot with the store and changes only what differs, keeping the App Store asset IDs of exact matches.":
        return {"de": "Der Upload vergleicht jeden Screenshot mit dem Store und ändert nur Abweichungen; exakte Treffer behalten ihre App Store Asset-IDs.", "es": "La subida compara cada captura con la tienda y cambia solo lo que difiere, conservando los ID de recurso de App Store de las coincidencias exactas.", "fa": "آپلود هر اسکرین‌شات را با فروشگاه مقایسه می‌کند و فقط موارد متفاوت را تغییر می‌دهد؛ موارد کاملاً یکسان شناسه‌های دارایی App Store خود را نگه می‌دارند.", "fr": "L’envoi compare chaque capture avec la boutique et ne modifie que les différences, en conservant les identifiants de ressource App Store des correspondances exactes.", "ja": "アップロードでは各スクリーンショットをストア上のものと比較し、差分だけを変更します。完全一致したものはApp StoreのアセットIDを保持します。", "ko": "업로드는 각 스크린샷을 스토어와 비교해 다른 항목만 변경하며, 정확히 일치하는 항목의 App Store 에셋 ID는 유지합니다.", "pt-BR": "O envio compara cada captura com a loja e altera apenas o que for diferente, mantendo os IDs de recurso da App Store das correspondências exatas.", "zh-Hans": "上传会将每张截图与商店中的截图进行比较，只更改有差异的内容，并保留完全匹配项的 App Store 资源 ID。"}[lang]
    if key == "Replace All Screenshots skips the comparison: everything currently in these sets is deleted and 1 screenshot is uploaded again with a new asset ID. Quicker to prepare, slower to upload.":
        return {"de": "„Alle Screenshots ersetzen“ überspringt den Vergleich: Alles, was derzeit in diesen Sets ist, wird gelöscht und die Screenshots werden mit neuen Asset-IDs erneut hochgeladen. Schneller vorzubereiten, langsamer hochzuladen.", "es": "«Reemplazar todas las capturas» omite la comparación: se elimina todo lo que hay actualmente en estos conjuntos y las capturas se vuelven a subir con nuevos ID de recurso. Más rápido de preparar, más lento de subir.", "fa": "«جایگزینی همه اسکرین‌شات‌ها» مقایسه را رد می‌کند: همه موارد فعلی این مجموعه‌ها حذف می‌شوند و اسکرین‌شات‌ها با شناسه‌های دارایی جدید دوباره آپلود می‌شوند. آماده‌سازی سریع‌تر است، اما آپلود کندتر.", "fr": "« Remplacer toutes les captures » ignore la comparaison : tout le contenu actuel de ces ensembles est supprimé et les captures sont téléversées de nouveau avec de nouveaux identifiants de ressource. Préparation plus rapide, envoi plus lent.", "ja": "「すべてのスクリーンショットを置き換え」は比較を省略します。これらのセット内の現在の内容はすべて削除され、スクリーンショットは新しいアセットIDで再アップロードされます。準備は速く、アップロードは遅くなります。", "ko": "“모든 스크린샷 교체”는 비교를 건너뜁니다. 이 세트의 현재 항목을 모두 삭제하고 스크린샷을 새 에셋 ID로 다시 업로드합니다. 준비는 빠르지만 업로드는 더 느립니다.", "pt-BR": "“Substituir todas as capturas” ignora a comparação: tudo que está nesses conjuntos é excluído e as capturas são reenviadas com novos IDs de recurso. Mais rápido de preparar, mais lento de enviar.", "zh-Hans": "“替换所有截图”会跳过比较：这些集合中当前的所有内容都会被删除，截图会使用新的资源 ID 重新上传。准备更快，但上传更慢。"}[lang]
    if key == "Replace All Screenshots skips the comparison: everything currently in these sets is deleted and all %lld screenshots are uploaded again with new asset IDs. Quicker to prepare, slower to upload.":
        return {"de": "„Alle Screenshots ersetzen“ überspringt den Vergleich: Alles, was derzeit in diesen Sets ist, wird gelöscht und alle %lld Screenshots werden mit neuen Asset-IDs erneut hochgeladen. Schneller vorzubereiten, langsamer hochzuladen.", "es": "«Reemplazar todas las capturas» omite la comparación: se elimina todo lo que hay actualmente en estos conjuntos y las %lld capturas se vuelven a subir con nuevos ID de recurso. Más rápido de preparar, más lento de subir.", "fa": "«جایگزینی همه اسکرین‌شات‌ها» مقایسه را رد می‌کند: همه موارد فعلی این مجموعه‌ها حذف می‌شوند و همه %lld اسکرین‌شات با شناسه‌های دارایی جدید دوباره آپلود می‌شوند. آماده‌سازی سریع‌تر است، اما آپلود کندتر.", "fr": "« Remplacer toutes les captures » ignore la comparaison : tout le contenu actuel de ces ensembles est supprimé et les %lld captures sont téléversées de nouveau avec de nouveaux identifiants de ressource. Préparation plus rapide, envoi plus lent.", "ja": "「すべてのスクリーンショットを置き換え」は比較を省略します。これらのセット内の現在の内容はすべて削除され、%lld枚のスクリーンショットは新しいアセットIDで再アップロードされます。準備は速く、アップロードは遅くなります。", "ko": "“모든 스크린샷 교체”는 비교를 건너뜁니다. 이 세트의 현재 항목을 모두 삭제하고 스크린샷 %lld개를 새 에셋 ID로 다시 업로드합니다. 준비는 빠르지만 업로드는 더 느립니다.", "pt-BR": "“Substituir todas as capturas” ignora a comparação: tudo que está nesses conjuntos é excluído e as %lld capturas são reenviadas com novos IDs de recurso. Mais rápido de preparar, mais lento de enviar.", "zh-Hans": "“替换所有截图”会跳过比较：这些集合中当前的所有内容都会被删除，%lld 张截图会使用新的资源 ID 重新上传。准备更快，但上传更慢。"}[lang]

    if key.startswith("Export finished, but"):
        if "1 image file" in key:
            return {"de": "Export abgeschlossen, aber 1 Bilddatei konnte nicht gelesen werden, daher ist dieser Geräterahmen leer. Prüfe die Zeichenfläche vor dem Hochladen.", "es": "La exportación terminó, pero no se pudo leer 1 archivo de imagen, así que ese marco de dispositivo está en blanco. Revisa el lienzo antes de subir.", "fa": "صدور تمام شد، اما ۱ فایل تصویر خوانده نشد؛ بنابراین آن قاب دستگاه خالی است. پیش از آپلود، بوم را بررسی کنید.", "fr": "L’export est terminé, mais 1 fichier image n’a pas pu être lu ; ce cadre d’appareil est donc vide. Vérifiez le canevas avant l’envoi.", "ja": "書き出しは完了しましたが、1個の画像ファイルを読み込めなかったため、そのデバイスフレームは空白です。アップロード前にキャンバスを確認してください。", "ko": "내보내기는 완료되었지만 이미지 파일 1개를 읽을 수 없어 해당 기기 프레임이 비어 있습니다. 업로드 전에 캔버스를 확인하세요.", "pt-BR": "A exportação terminou, mas 1 arquivo de imagem não pôde ser lido; por isso esse quadro de dispositivo está em branco. Verifique a tela antes de enviar.", "zh-Hans": "导出已完成，但无法读取 1 个图像文件，因此该设备框为空白。上传前请检查画布。"}[lang]
        return {"de": "Export abgeschlossen, aber %lld Bilddateien konnten nicht gelesen werden, daher sind diese Geräterahmen leer. Prüfe die Zeichenfläche vor dem Hochladen.", "es": "La exportación terminó, pero no se pudieron leer %lld archivos de imagen, así que esos marcos de dispositivo están en blanco. Revisa el lienzo antes de subir.", "fa": "صدور تمام شد، اما %lld فایل تصویر خوانده نشد؛ بنابراین آن قاب‌های دستگاه خالی هستند. پیش از آپلود، بوم را بررسی کنید.", "fr": "L’export est terminé, mais %lld fichiers image n’ont pas pu être lus ; ces cadres d’appareil sont donc vides. Vérifiez le canevas avant l’envoi.", "ja": "書き出しは完了しましたが、%lld個の画像ファイルを読み込めなかったため、それらのデバイスフレームは空白です。アップロード前にキャンバスを確認してください。", "ko": "내보내기는 완료되었지만 이미지 파일 %lld개를 읽을 수 없어 해당 기기 프레임이 비어 있습니다. 업로드 전에 캔버스를 확인하세요.", "pt-BR": "A exportação terminou, mas %lld arquivos de imagem não puderam ser lidos; por isso esses quadros de dispositivo estão em branco. Verifique a tela antes de enviar.", "zh-Hans": "导出已完成，但无法读取 %lld 个图像文件，因此这些设备框为空白。上传前请检查画布。"}[lang]

    if key.startswith("Could not read") and " used by " in key:
        if "1 image" in key:
            return {"de": "1 von %@ in %@ verwendetes Bild konnte nicht gelesen werden. Importiere den fehlenden Screenshot erneut vor dem Hochladen, sonst würde er als leerer Bereich veröffentlicht.", "es": "No se pudo leer 1 imagen usada por %@ en %@. Vuelve a importar la captura faltante antes de subir, o se publicaría como un área en blanco.", "fa": "۱ تصویر استفاده‌شده توسط %@ در %@ خوانده نشد. پیش از آپلود، اسکرین‌شات گمشده را دوباره وارد کنید؛ وگرنه به‌صورت ناحیه خالی منتشر می‌شود.", "fr": "Impossible de lire 1 image utilisée par %@ dans %@. Réimportez la capture manquante avant l’envoi, sinon elle serait publiée comme zone vide.", "ja": "%@が%@で使用している1個の画像を読み込めませんでした。アップロード前に不足しているスクリーンショットを再インポートしてください。そうしないと空白として公開されます。", "ko": "%@이(가) %@에서 사용하는 이미지 1개를 읽을 수 없습니다. 업로드 전에 누락된 스크린샷을 다시 가져오지 않으면 빈 영역으로 게시됩니다.", "pt-BR": "Não foi possível ler 1 imagem usada por %@ em %@. Reimporte a captura ausente antes de enviar, ou ela seria publicada como uma área em branco.", "zh-Hans": "无法读取 %@ 在 %@ 中使用的 1 张图像。上传前请重新导入缺失的截图，否则会发布为空白区域。"}[lang]
        return {"de": "%lld von %@ in %@ verwendete Bilder konnten nicht gelesen werden. Importiere die fehlenden Screenshots erneut vor dem Hochladen, sonst würden sie als leere Bereiche veröffentlicht.", "es": "No se pudieron leer %lld imágenes usadas por %@ en %@. Vuelve a importar las capturas faltantes antes de subir, o se publicarían como áreas en blanco.", "fa": "%lld تصویر استفاده‌شده توسط %@ در %@ خوانده نشد. پیش از آپلود، اسکرین‌شات‌های گمشده را دوباره وارد کنید؛ وگرنه به‌صورت نواحی خالی منتشر می‌شوند.", "fr": "Impossible de lire %lld images utilisées par %@ dans %@. Réimportez les captures manquantes avant l’envoi, sinon elles seraient publiées comme zones vides.", "ja": "%2$@が%3$@で使用している%1$lld個の画像を読み込めませんでした。アップロード前に不足しているスクリーンショットを再インポートしてください。そうしないと空白として公開されます。", "ko": "%2$@이(가) %3$@에서 사용하는 이미지 %1$lld개를 읽을 수 없습니다. 업로드 전에 누락된 스크린샷을 다시 가져오지 않으면 빈 영역으로 게시됩니다.", "pt-BR": "Não foi possível ler %lld imagens usadas por %@ em %@. Reimporte as capturas ausentes antes de enviar, ou elas seriam publicadas como áreas em branco.", "zh-Hans": "无法读取 %2$@ 在 %3$@ 中使用的 %1$lld 张图像。上传前请重新导入缺失的截图，否则会发布为空白区域。"}[lang]

    if "uses 1 image file" in key:
        return {"de": "%@ · %@ verwendet 1 Bilddatei, die nicht gelesen werden konnte; die Screenshots würden daher mit fehlendem Inhalt hochgeladen. Füge das betroffene Bild erneut hinzu und versuche es noch einmal.", "es": "%@ · %@ usa 1 archivo de imagen que no se pudo leer, así que las capturas se subirían con contenido faltante. Vuelve a añadir la imagen afectada e inténtalo otra vez.", "fa": "%@ · %@ از ۱ فایل تصویر استفاده می‌کند که خوانده نشد؛ بنابراین اسکرین‌شات‌ها با محتوای ناقص آپلود می‌شوند. تصویر مربوطه را دوباره اضافه کنید و دوباره تلاش کنید.", "fr": "%@ · %@ utilise 1 fichier image qui n’a pas pu être lu ; les captures seraient donc envoyées avec du contenu manquant. Réajoutez l’image concernée, puis réessayez.", "ja": "%@ · %@ は読み込めない画像ファイルを1個使用しているため、スクリーンショットは内容が欠けた状態でアップロードされます。該当する画像を追加し直してから再試行してください。", "ko": "%@ · %@에서 읽을 수 없는 이미지 파일 1개를 사용하므로 스크린샷이 누락된 콘텐츠와 함께 업로드됩니다. 영향을 받은 이미지를 다시 추가한 후 다시 시도하세요.", "pt-BR": "%@ · %@ usa 1 arquivo de imagem que não pôde ser lido, então as capturas seriam enviadas com conteúdo ausente. Adicione a imagem afetada novamente e tente outra vez.", "zh-Hans": "%@ · %@ 使用了 1 个无法读取的图像文件，因此截图上传后会缺少内容。请重新添加受影响的图像，然后重试。"}[lang]
    if "uses %lld image files" in key:
        return {"de": "%@ · %@ verwendet %lld Bilddateien, die nicht gelesen werden konnten; die Screenshots würden daher mit fehlendem Inhalt hochgeladen. Füge die betroffenen Bilder erneut hinzu und versuche es noch einmal.", "es": "%@ · %@ usa %lld archivos de imagen que no se pudieron leer, así que las capturas se subirían con contenido faltante. Vuelve a añadir las imágenes afectadas e inténtalo otra vez.", "fa": "%@ · %@ از %lld فایل تصویر استفاده می‌کند که خوانده نشدند؛ بنابراین اسکرین‌شات‌ها با محتوای ناقص آپلود می‌شوند. تصاویر مربوطه را دوباره اضافه کنید و دوباره تلاش کنید.", "fr": "%@ · %@ utilise %lld fichiers image qui n’ont pas pu être lus ; les captures seraient donc envoyées avec du contenu manquant. Réajoutez les images concernées, puis réessayez.", "ja": "%@ · %@ は読み込めない画像ファイルを%lld個使用しているため、スクリーンショットは内容が欠けた状態でアップロードされます。該当する画像を追加し直してから再試行してください。", "ko": "%@ · %@에서 읽을 수 없는 이미지 파일 %lld개를 사용하므로 스크린샷이 누락된 콘텐츠와 함께 업로드됩니다. 영향을 받은 이미지를 다시 추가한 후 다시 시도하세요.", "pt-BR": "%@ · %@ usa %lld arquivos de imagem que não puderam ser lidos, então as capturas seriam enviadas com conteúdo ausente. Adicione as imagens afetadas novamente e tente outra vez.", "zh-Hans": "%@ · %@ 使用了 %lld 个无法读取的图像文件，因此截图上传后会缺少内容。请重新添加受影响的图像，然后重试。"}[lang]

    return None


def set_translation(entry: dict, lang: str, value: str) -> bool:
    localizations = entry.setdefault("localizations", {})
    current = localizations.get(lang, {}).get("stringUnit", {}).get("value")
    if current == value:
        return False
    localizations[lang] = {"stringUnit": {"state": "translated", "value": value}}
    return True


def main() -> int:
    data = xcstrings_format.load(CATALOG)
    changed = 0
    missing: list[str] = []

    for key, entry in data["strings"].items():
        if key in STALE_KEYS:
            if entry.get("extractionState") != "stale":
                entry["extractionState"] = "stale"
                changed += 1
            continue
        if entry.get("extractionState") == "stale":
            continue
        for lang in LANGUAGES:
            value = translate(lang, key)
            if value is None:
                continue
            if set_translation(entry, lang, value):
                changed += 1

    for key, entry in data["strings"].items():
        if key in STALE_KEYS:
            continue
        if entry.get("extractionState") == "stale":
            continue
        for lang in LANGUAGES:
            if lang not in entry.get("localizations", {}):
                if translate(lang, key) is None:
                    missing.append(key)
                break

    if missing:
        print("No curated translation for:")
        for key in sorted(set(missing)):
            print(f"- {key}")
        return 1

    for entry in data["strings"].values():
        localizations = entry.get("localizations")
        if localizations:
            entry["localizations"] = {k: localizations[k] for k in sorted(localizations)}

    xcstrings_format.write(CATALOG, data)
    print(f"updated {changed} localization entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
