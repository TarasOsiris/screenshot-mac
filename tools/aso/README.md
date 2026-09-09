# ASO metadata

Keyword fields, subtitles and promotional text for the App Store listing,
per locale, per platform. See `RESEARCH.md` for why these values.

| file | holds |
|---|---|
| `keywords.py` | the 100-char keyword field builder; `_reserved()` bans anything the name/subtitle already supply |
| `metadata.py` | subtitle (30) and promotional text (170) per locale, macOS and iOS variants |
| `openings.py` | replacement first paragraph of the description |
| `descriptions.py` | the added locales' descriptions, macOS and iOS, plus the automated review |
| `degoogle.py` | the per-locale deletions that took Google Play out of all 52 live descriptions |
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
python3 tools/aso/descriptions.py                  # review every stored description
python3 tools/aso/apply.py descriptions <id> MAC_OS # write them (editable version only)
python3 tools/aso/degoogle.py <id> --dry-run       # one-shot: strip Google Play from a version
python3 tools/aso/finish.py --dry-run              # only if a locale is ever added again
```

## Descriptions

`descriptions.py` holds the macOS and iOS description for the 10 locales added in
Aug 2026 and the 10 added on 2026-09-09. Both batches were created carrying the en-US
text. The Aug set **is** on 4.10 (macOS) and 4.9 (iOS) as of 2026-09-01: cancelling the
in-flight macOS submission to fix the rejected subtitle made both versions editable
again, so the deferred half went in with it. `appStoreVersionLocalizations` are editable
only while their version is — for any later release, `submit` Step 2b runs the writer
once `/ship` has created the version record.

en-GB and en-AU are derived, not stored: `british()` spelling-passes that version's own
live en-US row, so an English rewrite can never leave them behind. en-CA is deliberately
absent — Canadian English keeps the -ize spellings this copy uses and the source has no
-our/-re word, so a spelling pass would be a no-op that the review would flag as
"identical to the en-US source"; `finish.py` fills it with the en-US text, which is the
correct Canadian copy. zh-Hant is written in Taiwan vocabulary (`專案`, `範本`, `匯出`,
`中繼資料`) rather than character-converted from zh-Hans, and the review fails it if
simplified-only forms leak in.

`python3 tools/aso/descriptions.py` **is** the review — nobody reads 10 languages by hand.
It checks length against the real 4000 ceiling, every verbatim atom, that the text differs
from the live en-US source, that no macOS-only feature (MCP, Finder) appears in an iOS
listing, that vi/tr diacritics and the Thai/Cyrillic/Han scripts survived the round trip,
that Ukrainian carries no Russian-only letter, that no locale mentions price or
discounts, and — since the second 2026-09-01 rejection — that no locale names Google Play
in any script. The 2026-09-09 batch added two guards for languages that sit next to each
other: `FOREIGN_CHARS` catches Slovak letters in Czech (and Czech in Slovak, Croatian in
Slovenian, Castilian `ñ` in Catalan), and `FOREIGN_WORDS` catches Castilian vocabulary in
es-MX and France-French `maquette` in fr-CA. `apply.py descriptions` re-runs the whole
review per text and refuses to write a failing one.

## Adding a locale

**A new locale can only be created while a release is in flight.** That is a
state constraint, not a tooling one — `POST /v1/appInfoLocalizations` returns

```
409  ENTITY_ERROR.RELATIONSHIP.INVALID
     "A relationship cannot be created in current state."
```

against a `READY_FOR_DISTRIBUTION` appInfo. The editable appInfo the call needs
only exists once a version record does, so locale work belongs *inside* a
release, after `/ship` creates the version — not before it.

The `asc` CLI has no app-info localization create either (`asc localizations
create` takes `--version`, so it only makes *version* localizations), so that one
call has to go over raw REST. Everything after it is `asc`.

Once the locale exists at app level, the rest is code:

1. `metadata.SUBTITLE[loc]` — mandatory; every other surface keys off it.
2. `metadata.PROMO_MAC[loc]` and `PROMO_IOS[loc]` — mandatory, or `check()` fails and
   every writer aborts.
3. `keywords.EXTRA[loc]` — mandatory for the keyword field.
4. `descriptions.LOCALES` + `DESC_MAC[loc]` + `DESC_IOS[loc]` — optional. Without it
   `finish.py` writes the version's en-US text, which is legal (an *empty* description
   blocks submission outright) but leaves the locale in English.

Two things bite afterwards:

- Creating an app-level locale makes ASC auto-create an **empty**
  `appStoreVersionLocalization` on every editable version. `finish.py` fills those.
- A new locale needs `supportUrl` (and `marketingUrl`) copied from en-US, or
  `asc review submit` fails preflight.

Do it while nothing is **in review**: the name/subtitle record is app-wide, so
any submission in review locks it on both platforms. The window is therefore
after the version record exists and before it is submitted.

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
flagged only the subtitle in that pass.

The *second* rejection the same day came back for the **description**, again
2.3.10: "Revise the app's description to remove Google Play references." So the
earlier read — that naming the store in a description describes functionality
rather than promotes it — did not survive contact with review. Every Google Play
mention is now gone from all 52 descriptions (26 locales × 2 platforms) and from
the keyword field, which had been spending 7 of its 100 characters on `google`.
`degoogle.py` is the record of exactly which words left. `Android` and `Pixel`
stay: they name device frames the app really draws, which is 2.3.10's own
carve-out, and Apple named only Google Play.

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
