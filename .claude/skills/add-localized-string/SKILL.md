---
name: add-localized-string
description: Add a new user-facing string to the codebase using String(localized:) and propagate it through Localizable.xcstrings via the project's Python translation scripts. Use when adding any UI label, button title, alert message, accessibility text, or other text the user will see, so all 30 supported locales stay in sync.
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

## Step 2 — Run the build to extract keys

Xcode's xcstrings extraction runs as part of the build. Trigger it:

```
xcodebuild -scheme screenshot -destination 'platform=macOS' build 2>&1 | tail -10
```

After this, `screenshot/Localizable.xcstrings` will contain the new key with `state: "new"` and no translations.

## Step 3 — Translate

The two translation scripts have **different jobs** — they're not interchangeable:

- **`tools/translate_popular_languages.py`** — uses Google Translate (via `deep-translator`) to fill missing entries for fr, de, ja, ko, pt-BR, zh-Hans. Run it first for any new key. Requires `python3 -m pip install deep-translator`.
- **`tools/translate_catalog.py`** — Spanish-only. Uses a hand-curated English→Spanish dictionary baked into the script. It also merges new keys from Xcode's `.stringsdata` files into the catalog (workaround for xcodebuild CLI not always running the catalog-merge step). If your new key isn't in its `ES` dict, add a translation to the dict first, then run the script.

Typical flow:

```
python3 tools/translate_catalog.py            # merges new keys + Spanish
python3 tools/translate_popular_languages.py  # fills the 6 popular langs
```

Other locales beyond these 7 (the catalog supports 30) are translated manually or skipped — there is no script for them.

## Step 4 — Verify

```
git diff screenshot/Localizable.xcstrings | head -80
```

Confirm the new key has translations for the locales you expect. Run the app or relevant unit tests to make sure nothing about the call site broke.

## When to skip Step 3

If the user only wants the English string staged and intends to translate later, stop after Step 2 and tell them which key was added. They will run the translation script before shipping.

## Conventions

- Use sentence case for buttons (`Clear Credentials…` not `Clear credentials…`).
- Use `…` (ellipsis character) when the action opens a confirmation or sheet.
- Keep punctuation inside the localized string — different languages punctuate differently.
- Never concatenate localized fragments. One key per displayed sentence.
