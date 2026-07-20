---
name: update-app-store-descriptions
description: Localize an App Store listing's "description" into every App Store locale and push it to App Store Connect via the app's in-app MCP tools. Use when the user wants to update/refresh/translate the App Store description text for the linked app (macOS and/or iOS). Asks for the English source and which platform(s) to target, and keeps iOS copy free of macOS-only features.
disable-model-invocation: true
---

# Update App Store Descriptions

Localize the App Store **description** from an English source into every locale the
listing supports, and apply it to the editable App Store Connect version(s) via the
running app's MCP tools (`get_app_store_metadata` / `update_app_store_description`,
defined in `Code/Services/MCP/MCPToolExecutor+AppStore.swift`).

The English source is the single source of truth — every other locale is a translation
of it (see [[feedback_translate_from_base_only]]). This skill only *applies* text; the
translating is done here by fan-out subagents.

`SCRATCH` below = the session scratchpad directory; keep all temp files there.

## Step 1 — Get the English source

Ask the user for the English (`en-US`) description if they didn't already provide it.
Accept either pasted text or a file path. Save it to `SCRATCH/english_source.txt` and
confirm its shape:

```
python3 - <<'PY'
t=open('SCRATCH/english_source.txt').read()
print('chars:', len(t))
print('paragraphs:', len(t.split(chr(10)+chr(10))))
print('bullets:', sum(1 for l in t.split(chr(10)) if l.startswith('- ')))
print('ends with EULA url:', t.rstrip().endswith('stdeula/'))
PY
```

Note the paragraph/bullet counts — translations must preserve the **same structure**.

## Step 2 — Ask which platform(s)

Use the **AskUserQuestion** tool (single question): **macOS**, **iOS**, **Both**
(default recommendation: Both). Skip only if the invocation already names it
(`/update-app-store-descriptions ios`, `… mac`, `… both`).

The app ships both platforms from one target; each has its **own** editable App Store
version, so platform choice decides which version id(s) get written.

## Step 3 — Make the iOS copy Mac-free (platform parity)

**The macOS and iOS versions need different source text.** The one editor builds both
listings, but several described features are **macOS-only**, so the iOS description must
not mention them (accuracy + App Review). If iOS is in scope, derive an **iOS variant**
of the English (`SCRATCH/english_ios.txt`) by removing macOS-only content; the macOS
version uses the full source unchanged.

Remove from the iOS copy (macOS-only):
- **MCP server / Model Context Protocol / local AI-assistant automation** — the whole
  MCP server is `#if os(macOS)` (`MCPServerService`); iOS never compiles it. Strip the
  MCP paragraph, the "automate edits with MCP" clause, the "connect an MCP assistant"
  bullet, and "MCP-ready … tool" from the keyword paragraph.
- **Finder** — macOS concept (iOS uses the Files app). Drop/replace "open … folders in
  Finder".
- **"Mac app" phrasing** — change "one focused Mac app" → "one focused app".
- **Mac-centric upload framing** — e.g. "Upload iOS and Mac screenshots … in one flow".
- Anything else you confirm is gated behind `#if os(macOS)` (e.g. Simulator capture).

Keep on iOS (these work on iPhone/iPad — verify in code before trusting this list, things
change):
- **App Store Connect upload** and **Google Play upload** — iPad has a full push-per-step
  upload wizard (`UploadToAppStoreConnectView` / `UploadToGooglePlayView` compile on iOS).
- **iCloud sync**, **ZIP backups**, locale overrides, auto-translate, showcase export.
- **Mac device frames** — an *output* target (you can build Mac App Store screenshots
  from the iPad app), not a desktop-only runtime feature. Keep "Mac" in device lists.

Rule of thumb: before asserting a feature is Mac-only or cross-platform, grep the code
for its `#if os(macOS)` gating rather than guessing.

## Step 4 — Reach the MCP tools (usually over HTTP)

The two tools frequently are **not** callable through the normal MCP integration in the
current Claude Code session: the session caches the server's tool list at connect time,
and these tools are recent. Don't rely on `mcp__screenshot-bro__*` being present — drive
the server directly over HTTP instead.

Endpoint: `http://127.0.0.1:8722/mcp` (streamable HTTP; port override is UserDefaults
`mcpServerPort`). Confirm the tools are live:

```
curl -s -X POST http://127.0.0.1:8722/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | tr ',' '\n' | grep -o '"name":"[a-z_]*"' | grep app_store
```

- **No output / connection refused** → the app isn't running, the MCP server is off
  (enable at **Settings ▸ Automation ▸ Enable MCP server**), or the running build
  predates the AppStore tools. If the tools are missing, the app must be **rebuilt and
  relaunched** with the current code (the AppStore MCP files may be uncommitted). A
  running app can't hot-load them; after relaunch, keep using HTTP (this session still
  won't see them).
- **Auth:** a **DEBUG** build has no token — no header needed. A **Release** build
  requires `-H "Authorization: Bearer <token>"` (get it from **Settings ▸ Automation ▸
  Copy Connection Command**). Add that header to every curl below when on Release.

A `tools/call` over HTTP looks like:

```
curl -s -X POST http://127.0.0.1:8722/mcp \
  -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
  --data-binary @request.json -o response.json
# result payload is JSON-stringified at .result.content[0].text
```

## Step 5 — Discover editable versions and locales

Call `get_app_store_metadata` (no args). Parse `.versions[]` and keep those with
`editable == true` (state `PREPARE_FOR_SUBMISSION`) whose `platform` matches the Step-2
choice (`MAC_OS` and/or `IOS`). Record each selected version's `version_id` and its
`locales[].locale` codes.

Gotchas:
- **Portuguese is `pt-PT` only — there is no `pt-BR` slot.** Translate into **European**
  Portuguese (ecrã/aplicação), and route any Brazilian copy to `pt-PT`.
- `en-US` is the source: apply it **verbatim** (the macOS source for the MAC version, the
  iOS variant for the IOS version).
- `update_app_store_description` only writes locales that already exist on the version;
  anything else is reported under `skipped`.

## Step 6 — Translate into every locale

Do this **per source variant**: translate `english_source.txt` for the macOS version and
`english_ios.txt` for the iOS version (they have different paragraph/bullet counts, so
keep the two sets of translations in separate folders, e.g. `SCRATCH/trans/` and
`SCRATCH/trans_ios/`). For each target locale except `en-US`, spawn a subagent (fan them
out — one Agent call per locale, in a single message) that reads the relevant source and
writes to `<folder>/<locale>.txt`. Prompt each with:

- Translate the **entire** text into <language> as natural, idiomatic App Store marketing
  copy (not word-for-word).
- **Preserve structure exactly**: same paragraph count/order; the "Key features:" header
  (translated) followed by the **same number of `- ` bullets in the same order**; the
  final Terms-of-Use line ending with the **exact** URL
  `https://www.apple.com/legal/internet-services/itunes/dev/stdeula/` (translate only the
  label). No added/removed/reordered/merged content, no commentary.
- Keep these **verbatim in English** (do not translate/transliterate): Screenshot Bro,
  App Store, App Store Connect, Google Play, iPhone, iPad, Mac, Android, Pixel, iOS,
  iCloud, ZIP, PNG, JPEG, SVG — plus, for the macOS variant only: MCP, Model Context
  Protocol, Claude Code, Claude Desktop, Cursor, Finder.
- For **RTL** locales (`ar-SA`, `he`): those Latin-script terms stay LTR, embedded
  normally; bullets still start with an ASCII `- `.
- Write only the translation (UTF-8, real newlines) to the given path; reply with just
  the char count.

## Step 7 — Enforce the 4000-character limit

App Store descriptions are capped at **4000 characters**, hard. The Mac-stripped iOS
variant is short enough that translations usually fit. The full macOS source is longer,
so a faithful translation overflows for the wordier languages (de, es, fr, it, nl, da,
no, sv, fi typically ~4100–5100; ar, he, ja, ko, zh usually fit). Trim over-limit locales
**without gutting** them — target ≤ 3960 for margin — in this order, stopping as soon as
you're under:

1. Drop the few **redundant/minor** bullets (dup the prose or low value): "upload iOS+Mac
   in one flow", "connect an MCP assistant …", "get completion notifications", "open …
   folders in Finder".
2. If still over, drop the **fluff closing paragraph** — "Whether you are preparing a
   first launch …" (no ASO keywords). It's the 3rd-from-last paragraph.
3. If still over, drop a few more **canvas-detail** bullets (multi-shot rows,
   batch-import, placement/snapping, review-metadata).

Never drop: the intro, the device/localization/upload core bullets, the keyword-dense
"If you need an App Store screenshot creator …" paragraph, or the EULA line. Trim is
mechanical once you pick ordinals: split on `\n`, remove the chosen `- ` lines; split on
`\n\n`, remove the chosen paragraph; rejoin. Locales may differ in which bullets they keep
— invisible to users.

## Step 8 — Validate and apply

Before sending, validate each final string: `len ≤ 4000`, ends with `stdeula/`, contains
the exact EULA URL, no `\n\n\n` artifact, expected paragraph/bullet counts, and — for the
iOS set — **no Mac-only leakage** (grep for `MCP`, `Model Context Protocol`, `Finder`,
`Claude`, `loopback`; all must be absent). Then apply **per selected version id** so
platform scoping and the right copy variant are exact — one `update_app_store_description`
call per `version_id`:

```
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{
  "name":"update_app_store_description",
  "arguments":{
    "version_id":"<selected version id>",
    "descriptions":[{"locale":"en-US","description":"..."}, {"locale":"de-DE","description":"..."}, ...]
  }}}
```

For **Both**, send the macOS translations to the MAC_OS `version_id` and the iOS
translations to the IOS `version_id` — two separate calls, never one shared payload
(omitting `version_id` would write the same text to both platforms, which is exactly the
mistake this skill prevents). Build each request in Python from the `*.txt` files +
verbatim `en-US` to avoid JSON-escaping mistakes. Check the response's `updated` /
`skipped` arrays per platform.

## Step 9 — Verify

Re-fetch `get_app_store_metadata` for each written `version_id` and confirm **every**
locale: `len ≤ 4000`, ends with the EULA URL, contains the expected new copy, and — for
IOS — contains **no** `MCP`/`Finder`/`Claude` strings. Report a per-locale table, and a
count of `with_MCP` on MAC (should be all) vs IOS (should be zero).

## Notes

- Updates land in the **`PREPARE_FOR_SUBMISSION`** version(s) — staged in App Store
  Connect, not submitted. They go out with the next submission (see `ship` skill).
- "Update where not yet up to date": by default translate + apply **all** locales from
  the given English (safe and consistent). If some locales are already current this cycle,
  you may restrict `descriptions` to the rest — check current text first (does it contain
  the new copy's marker / is it Mac-free on iOS) and skip ones already correct.
- Related: [[project_appstore_description_update]] (locale set, gotchas),
  [[feedback_translate_from_base_only]], [[feedback_release_notes_default]].
