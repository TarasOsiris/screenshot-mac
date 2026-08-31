# ASO research — Screenshot Bro (2026-08-31)

App `6760177675` · `xyz.tleskiv.screenshot` · macOS + iOS, one shared listing.

## Method

No paid ASO tool was available (`keyword_source: none`), so popularity is read
from **Apple's own search autosuggest**, which is ordered by real query volume,
swept across **25 storefronts** via `MZSearchHints` with an
`X-Apple-Store-Front` header. Difficulty is read from the competitive field
returned by the iTunes Search API (rating counts as an authority proxy).

Autosuggest order is weak-but-real evidence. Popularity/difficulty numbers are
**not** available; every call below is an intent-and-evidence argument, not a
metric. Validate the main keyword with a real data tool before betting the app
*name* on it.

## Finding 1 — the name's keywords are the wrong ones

| query (macOS store) | Screenshot Bro rank |
|---|---|
| `screenshot bro` | 1 (brand) |
| `mockup maker` | 1 |
| `screenshot maker` | 3 |
| `app store screenshots` | not in top 12 |
| `app screenshots` | not in top 25 |
| `app store screenshot generator` | not in top 12 |

`screenshot` alone autosuggests to *stitching, organizing, capturing* apps —
consumer intent, and dominated by apps with thousands of ratings (Picsew 3076,
Stitch It 2671). `mockup` alone autosuggests to **clothing/t-shirt** mockups.
Both are high-volume and wrong-intent. The right-intent cluster is
**`app screenshot(s)`** / **`app store screenshots`**, and the listing had no
clean path to it.

## Finding 2 — the keyword field was leaking ~30 of 100 characters

Old en-US: `screenshots,screenshot,mockup,appstore,aso,localization,templates,frames,device,marketing,generator`

- `screenshots` + `screenshot` — same stem, twice.
- `mockup` — already in the app name.
- `appstore` — one token; it does **not** match the query "app store".
- `aso` — on the **iOS** store this autosuggests to ASOS the fashion retailer;
  unwinnable and wrong intent. On the **Mac** store it returns a genuine
  ASO-tool field, so it is kept for macOS only. Keywords are per-platform.
- `de-DE` and `es-ES` used **17 of 100** characters.

## Finding 3 — developers search English in every market

Swept `de fr es it nl sv da no fi pt-PT pt-BR ja ko zh-Hans zh-Hant ru uk pl tr id vi th ar he en-GB`.
In **every** storefront the English phrase `app screenshot` returns a full page
of category competitors. The local-language equivalents return **nothing**:

> `screenshots do app` · `скриншоты приложения` · `screeny aplikacji` ·
> `uygulama görseli` · `screenshot aplikasi` · `應用截圖` · `สกรีนช็อต` ·
> `ảnh chụp màn hình` · `capturas de la app` · `schermate app`

Local terms that *do* have volume — `captura de tela`, `скриншот`,
`zrzut ekranu`, `ekran görüntüsü`, `tangkapan layar`, `截圖`, `스크린샷` —
return consumer capture/stitch apps. Wrong intent.

Three exceptions carry real local dev vocabulary and are used:

| locale | term | evidence |
|---|---|---|
| zh-Hans | `应用截图` | `应用截图制作工具`, `应用截图生成器-开发者适用…`, `tepilot`, `yada studio` |
| ja | `モックアップ` | `ストアイメージ作成`, `モックアップジェネレーター`, `mockmaker`, `niceshots` |
| ru / uk | `мокап` | `мокапы`, `генератор мокапов` |

Consequence: the subtitle stays **English in every Latin-script locale**, and
mixes local script with a Latin `App Store` / `Google Play` elsewhere — which is
how developers write those names in Japanese, Korean, Chinese and Russian too.

## Finding 4 — the category is winnable

The macOS field for `app store screenshots` is almost entirely 0-rating free
apps; the leaders are tiny (StoreView 52 ratings, Picasso 45, Screenshot Studio
13, Frame Screenshots 87). Low difficulty. Contrast the generic `screenshot`
field, which is unwinnable and would not convert anyway.

## Assignment

| surface | value | why |
|---|---|---|
| name (30) | `Screenshot Bro: Mockup Maker` *(unchanged)* | already #1 `mockup maker`, #3 `screenshot maker` — don't spend that |
| subtitle (30) | `App Store & Play Screenshots` | supplies the missing `app` · `store` · `play` tokens |
| keywords (100) | see `keywords.py` | only tokens Apple cannot get from name+subtitle |

Apple combines tokens across all three surfaces, so a word spent twice is
budget burned. `_reserved()` in `keywords.py` derives the ban list from the
real name and the real per-locale subtitle rather than a hardcoded list —
that is what caught `google` being free budget in the Latin subtitle but
already present in the CJK one, and `스크린샷` / `ภาพหน้าจอ` / `شاشة` / `מסך`
being reserved in their own locales.

Newly reachable queries: `app store screenshots`, `google play screenshots`,
`app screenshot generator`, `app store connect`, `device frames`,
`app screenshot design`, `screenshot template`, `android screenshots`.

## Deviation from the skill's reference

`reference/keyword-research.md` asks for complete readable phrases in the
keyword field. That is Google Play doctrine. **Apple** auto-combines single
tokens across name, subtitle and keywords, so comma-separated single words
yield strictly more query coverage per character. Single tokens are used here
deliberately.
