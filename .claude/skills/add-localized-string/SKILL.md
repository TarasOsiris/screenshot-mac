---
name: add-localized-string
description: Add a new user-facing string to the codebase using String(localized:) and translate it yourself into Localizable.xcstrings (merged by tools/translate_catalog.py, written through tools/xcstrings_format.py). Use when adding any UI label, button title, alert message, accessibility text, or other text the user will see, so all 43 app UI languages stay in sync.
disable-model-invocation: true
---

# Add a Localized String

Add a new user-facing string and propagate translations through Localizable.xcstrings.

`Localizable.xcstrings` is generated/updated by `tools/translate_catalog.py` and `tools/translate_popular_languages.py`. Never hand-edit the xcstrings file (a hook in `.claude/settings.json` blocks direct edits).

## Step 1 — Add the string to Swift

In the Swift file where the text appears, use `String(localized:)`:

```swift
Text(String(localized: "Clear Credentials…"))
// or for SwiftUI text-accepting initializers:
Button("Clear Credentials…") { … }
```

SwiftUI auto-localizes `LocalizedStringKey` (the string-literal initializer overload of `Text`, `Button`, `Label`, `Toggle`, `Picker`, etc.). For runtime strings (alerts, dynamic content, computed properties), wrap with `String(localized:)` explicitly.

For interpolated strings, keep the variable inline so xcstrings can extract the format:

```swift
String(localized: "Missing: \(missing.joined(separator: \", \")).")
```

One key has one translation everywhere it appears. When the same English word needs a different translation in another place (e.g. "Center" as text alignment vs. the gradient's center point), give the second use its own key and keep the English:

```swift
String(localized: "gradient.center", defaultValue: "Center", comment: "Caption for the gradient's center point")
```

`translate_catalog.py` merges such keys with their English, and the translation and audit tools read it from there (`xcstrings_format.source_text`).

## Step 2 — Run the build to extract keys

Xcode's xcstrings extraction runs as part of the build. Trigger it:

```
xcodebuild -scheme screenshot -destination 'platform=macOS' build 2>&1 | tail -10
```

A string behind `#if DIRECT_DISTRIBUTION` is only extracted by the `screenshot Direct` target, which has extraction off in the project; build it with the setting overridden so `translate_catalog.py` can merge it:

```
xcodebuild -scheme "screenshot Direct" -destination 'platform=macOS' SWIFT_EMIT_LOC_STRINGS=YES build 2>&1 | tail -10
```

After this, `screenshot/Localizable.xcstrings` will contain the new key with `state: "new"` and no translations.

## Step 3 — Translate

**Write the translations yourself.** Don't use Google Translate (`translate_popular_languages.py`) unless the user asks for it: its output is lower quality, it gets rate-limited, and it also fills unrelated missing keys across the catalog.

1. Merge the extracted keys into the catalog. Build macOS first, or a stale `.stringsdata` merges nothing:

   ```
   python3 tools/translate_catalog.py   # merges new keys; its "Missing translations" list is your to-do list
   ```

2. Translate each new key into every UI language: ar, bn, ca, cs, da, de, el, es, fa, fi, fr, gu, he, hi, hr, hu, id, it, ja, kn, ko, ml, mr, ms, nl, no, pl, pt-BR, pt-PT, ro, ru, sk, sl, sv, ta, te, th, tr, uk, ur, vi, zh-Hans, zh-Hant. Write them through `tools/xcstrings_format.py` so Xcode's serialization is preserved:

   ```python
   import sys; sys.path.insert(0, "tools")
   import xcstrings_format as x
   from pathlib import Path
   p = Path("screenshot/Localizable.xcstrings")
   d = x.load(p)
   d["strings"]["No screenshots"]["localizations"]["de"] = {"stringUnit": {"state": "translated", "value": "Keine Screenshots"}}
   x.write(p, d)
   ```

   Keep `%lld` / `%@` placeholders and markdown intact. When a Help sentence quotes a UI label in bold, reuse that label's own translation.

3. Check the result:

   ```
   python3 tools/audit_localizations.py   # placeholder / missing-language check
   git diff --numstat screenshot/Localizable.xcstrings   # should be purely additive
   ```

Adding a UI language means adding it to `TARGET_LANGUAGES` in both `translate_popular_languages.py` and `audit_localizations.py`, and to `localizations.supported` in `project.xcproj`.

## Step 4 — Verify

```
git diff screenshot/Localizable.xcstrings | head -80
```

Confirm the new key has translations for the locales you expect. Run the app or relevant unit tests to make sure nothing about the call site broke.

## When to skip Step 3

If the user only wants the English string staged and intends to translate later, stop after Step 2 and tell them which key was added. They will translate before shipping.

## Conventions

- Use sentence case for buttons (`Clear Credentials…` not `Clear credentials…`).
- Use `…` (ellipsis character) when the action opens a confirmation or sheet.
- Keep punctuation inside the localized string — different languages punctuate differently.
- Never concatenate localized fragments. One key per displayed sentence.
