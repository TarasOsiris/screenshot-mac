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
| `finish.py` | subtitle everywhere, then fill any locale left empty or stale on an editable version |

Transport is the **`asc` CLI** (`asc auth status` — credentials live in the
system keychain). It replaced the vibe-aso plugin's `asc.rb`, whose
`~/.vibe-aso/config.json` no longer exists on this machine. Every write is read
back and compared; a 2xx alone is not treated as success.

## Commands

```bash
python3 tools/aso/metadata.py                      # every subtitle + the compliance check
python3 tools/aso/keywords.py                      # print every field + what was dropped
python3 tools/aso/apply.py check                   # preflight: compliance + no token spent twice
python3 tools/aso/apply.py subtitle                # app-level subtitle, every locale
python3 tools/aso/apply.py version <id> MAC_OS     # keywords + promo text
python3 tools/aso/descriptions.py                  # review all 20 descriptions
python3 tools/aso/apply.py descriptions <id> MAC_OS # write them (editable version only)
python3 tools/aso/finish.py --dry-run              # only if a locale is ever added again
```

## Descriptions

`descriptions.py` holds the macOS and iOS description for each of the 10 locales added in
Aug 2026, which were created carrying the en-US text. They **are** on 4.10 (macOS) and
4.9 (iOS) as of 2026-09-01: cancelling the in-flight macOS submission to fix the rejected
subtitle made both versions editable again, so the deferred half went in with it.
`appStoreVersionLocalizations` are editable only while their version is — for any later
release, `submit` Step 2b runs the writer once `/ship` has created the version record.

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

The keyword fields are derived from the subtitle, so **apply the subtitle
first**. `keywords.field()` bans whatever the name and that locale's subtitle
already supply; run it against a stale subtitle and the fields duplicate tokens
that are already spent.

`apply.py check` fails loudly while the two are out of sync, and `apply.py
subtitle` refuses to run while the appInfo is `WAITING_FOR_REVIEW` /
`IN_REVIEW` / `PENDING_DEVELOPER_RELEASE`: the name/subtitle record is shared
app-wide, and editing it mid-review is a classic Metadata Rejected trigger. To
edit it during a review you must cancel that submission first
(`asc submit cancel --id <submission> --confirm`), which is what unblocked the
2026-09-01 fix.

## The subtitle is the surface Apple polices

`App Store & Play Screenshots` was rejected on 2026-09-01 under **5.2.5**
(Apple's mark) and **2.3.10** (competitor platform) — see RESEARCH.md. Apple
flagged only the subtitle; the description names both stores and was not
flagged, because there the words describe functionality rather than promote it.

`metadata.check()` encodes that line and every writer calls it: no Apple mark
and no competitor platform in any subtitle (Latin script or local), and no bare
`App Store` in promotional text — `App Store Connect` is allowed there, since it
is the real name of the service the app really uploads to.

## iOS

macOS and iOS have independent version trains and independent keyword fields
(`aso` is macOS-only — on the iOS store that query belongs to ASOS the
retailer). Once an iOS version is editable:

```bash
python3 tools/aso/apply.py version <ios-version-id> IOS
```

The iOS promotional text deliberately omits MCP — `MCPServerService` is
entirely `#if os(macOS)`, and the iOS listing must not advertise it.
