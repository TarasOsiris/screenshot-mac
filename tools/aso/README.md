# ASO metadata

Keyword fields, subtitles and promotional text for the App Store listing,
per locale, per platform. See `RESEARCH.md` for why these values.

| file | holds |
|---|---|
| `keywords.py` | the 100-char keyword field builder; `_reserved()` bans anything the name/subtitle already supply |
| `metadata.py` | subtitle (30) and promotional text (170) per locale, macOS and iOS variants |
| `openings.py` | replacement first paragraph of the description |
| `descriptions.py` | the 10 added locales' descriptions, macOS and iOS, plus the automated review |
| `apply.py` | push to App Store Connect, verified by read-back |
| `finish.py` | the deferred half — subtitle + the 10 added locales |

Credentials come from `~/.vibe-aso/config.json` via the vibe-aso plugin's
`asc.rb`. Every write is read back and compared; a 2xx alone is not treated as
success.

## Commands

```bash
python3 tools/aso/keywords.py                      # print every field + what was dropped
python3 tools/aso/apply.py check                   # preflight: no token spent twice
python3 tools/aso/apply.py version <id> MAC_OS     # keywords + promo text
python3 tools/aso/finish.py --dry-run              # the deferred half
python3 tools/aso/descriptions.py                  # review all 20 descriptions
python3 tools/aso/apply.py descriptions <id> MAC_OS # write them (editable version only)
```

## Descriptions

`descriptions.py` holds the macOS and iOS description for each of the 10 locales added in
Aug 2026, which were created carrying the en-US text. They are **not** on 4.10 (macOS) /
4.9 (iOS): `appStoreVersionLocalizations` are editable only while their version is, and
both went to review before the copy existed. They ride the next release — `submit`
Step 2b runs the writer once `/ship` has created the version record.

en-GB is derived, not stored: `british()` spelling-passes that version's own live en-US
row, so an English rewrite can never leave en-GB behind. zh-Hant is written in Taiwan
vocabulary (`專案`, `範本`, `匯出`, `中繼資料`) rather than character-converted from
zh-Hans, and the review fails it if simplified-only forms leak in.

`python3 tools/aso/descriptions.py` **is** the review — nobody reads 10 languages by hand.
It checks length against the real 4000 ceiling, every verbatim atom, that the text differs
from the live en-US source, that no macOS-only feature (MCP, Finder) appears in an iOS
listing, that vi/tr diacritics and the Thai/Cyrillic/Han scripts survived the round trip,
that Ukrainian carries no Russian-only letter, and that no locale mentions price or
discounts. `apply.py descriptions` re-runs it per text and refuses to write a failing one.

## Ordering matters

The keyword fields assume the subtitle is `App Store & Play Screenshots`.
While the old subtitle is still live they duplicate `design` (and `aso` /
`localization` in en-US), which wastes budget.

**Run `finish.py` before submitting a version.** `apply.py check` fails loudly
while the two are out of sync — it is the guard for exactly this.

`finish.py` refuses to run while a submission is `WAITING_FOR_REVIEW` or
`IN_REVIEW`: the name/subtitle record is shared app-wide, and editing it
mid-review is a classic Metadata Rejected trigger.

## iOS

macOS and iOS have independent version trains and independent keyword fields
(`aso` is macOS-only — on the iOS store that query belongs to ASOS the
retailer). Once an iOS version is editable:

```bash
python3 tools/aso/apply.py version <ios-version-id> IOS
```

The iOS promotional text deliberately omits MCP — `MCPServerService` is
entirely `#if os(macOS)`, and the iOS listing must not advertise it.
