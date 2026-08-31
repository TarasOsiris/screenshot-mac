# ASO metadata

Keyword fields, subtitles and promotional text for the App Store listing,
per locale, per platform. See `RESEARCH.md` for why these values.

| file | holds |
|---|---|
| `keywords.py` | the 100-char keyword field builder; `_reserved()` bans anything the name/subtitle already supply |
| `metadata.py` | subtitle (30) and promotional text (170) per locale, macOS and iOS variants |
| `openings.py` | replacement first paragraph of the description |
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
```

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
