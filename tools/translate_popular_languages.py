#!/usr/bin/env python3
"""Populate popular app UI localizations in Localizable.xcstrings.

This keeps existing translations intact and fills missing entries for a
high-impact set of languages:
  - French (`fr`)
  - German (`de`)
  - Japanese (`ja`)
  - Korean (`ko`)
  - Portuguese, Brazil (`pt-BR`)
  - Chinese, Simplified (`zh-Hans`)
  - Persian (`fa`)

Requirements:
  python3 -m pip install deep-translator

Run from repo root:
  python3 tools/translate_popular_languages.py           # every target language
  python3 tools/translate_popular_languages.py fa        # just one
"""

from __future__ import annotations

import math
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from deep_translator import GoogleTranslator

import xcstrings_format

CATALOG = Path(__file__).parent.parent / "screenshot" / "Localizable.xcstrings"

TARGET_LANGUAGES = {
    "fr": "fr",
    "de": "de",
    "ja": "ja",
    "ko": "ko",
    "pt-BR": "pt",
    "zh-Hans": "zh-CN",
    "fa": "fa",
}

KEEP_AS_IS = {
    "",
    " · ",
    "%",
    "-> %@",
    "%@ -> %@",
    "%@ · %@: %@",
    "%lld",
    "%lld / %lld",
    "%lld × %lld px",
    "%lld of %lld",
    "%lld/%lld",
    "%lld%%",
    "%lld°",
    "%lld×%lld",
    "%lld×%lld · %lld screenshot%@",
    "%lld pt",
    "%lld screenshot%@",
    "%lld screenshot%@ uploaded across %lld locale%@.",
    "%lld shapes",
    "%lld stops",
    "%lld more skipped item%@",
    "X: %lld%%",
    "Y: %lld%%",
    "PNG",
    "JPEG",
    "SVG",
    "RevenueCat",
    "Pro",
    "Beta",
    "API Key",
    "Issuer ID",
    "Key ID",
    "Private Key (.p8)",
    "Import .p8 File…",
    "App Store Connect",
    "iPhone 17 Pro",
    "by Ibrahim.Bhl",
    "© 2025 Your Company",
    "e.g. 57246542-96fe-1a63-e053-0824d011072a",
    "W",
    "H",
    "Switch to the base language (⌥⌘0)",
}

PROTECTED_TERMS = (
    "App Store Connect",
    "Screenshot Bro Pro",
    "Screenshot Bro",
    "RevenueCat",
    "App Store",
    "Google Play",
    "API",
    "Issuer ID",
    "Key ID",
    "iCloud",
    "System Settings",
    "Translation Languages",
    ".p8",
    "PNG",
    "JPEG",
    "SVG",
    "iPhone",
    "iPad",
    "Mac",
    "macOS",
    "iOS",
    "tvOS",
    "visionOS",
    "YouTube",
    "TikTok",
    "Instagram",
    "Pinterest",
    "Facebook",
    "LinkedIn",
    "Xcode",
    "Quick Look",
)

FORMAT_SPECIFIER_RE = re.compile(
    r"%(?:\d+\$)?[-+#0 ]*(?:\d+)?(?:\.\d+)?(?:hh|h|ll|l|L|z|j|t)?[@dDuUxXoOfFeEgGaAcCsSpP%]"
)

BATCH_SIZE = 25
SEPARATOR = "\n[[SEP_BLOCK]]\n"
MAX_RETRIES = 4


def needs_verbatim_copy(source: str) -> bool:
    if source in KEEP_AS_IS:
        return True
    return not any(ch.isalpha() for ch in source)


def positional_specifier(specifier: str, position: int) -> str:
    if specifier == "%%":
        return specifier
    match = re.match(r"%((?:\d+\$)?)(.*)", specifier)
    if not match:
        return specifier
    existing_position, remainder = match.groups()
    if existing_position:
        return specifier
    return f"%{position}${remainder}"


def protect(source: str) -> tuple[str, dict[str, str]]:
    replacements: dict[str, str] = {}

    def swap(prefix: str, value: str) -> str:
        token = f"[[{prefix}_{len(replacements)}]]"
        replacements[token] = value
        return token

    # Each format occurrence gets a stable token so translated strings can
    # reorder placeholders safely via positional specifiers.
    rebuilt: list[str] = []
    cursor = 0
    for format_index, match in enumerate(FORMAT_SPECIFIER_RE.finditer(source), start=1):
        rebuilt.append(source[cursor:match.start()])
        rebuilt.append(swap("FMT", positional_specifier(match.group(0), format_index)))
        cursor = match.end()
    rebuilt.append(source[cursor:])
    protected = "".join(rebuilt)

    for term in sorted(PROTECTED_TERMS, key=len, reverse=True):
        escaped = re.escape(term)
        protected = re.sub(
            escaped,
            lambda match: swap("TERM", match.group(0)),
            protected,
        )

    return protected, replacements


def restore(translated: str, replacements: dict[str, str]) -> str:
    restored = translated
    for token, value in replacements.items():
        restored = restored.replace(token, value)
    return restored


def translate_batch(translator: GoogleTranslator, batch: list[str]) -> list[str]:
    joined = SEPARATOR.join(batch)
    for attempt in range(MAX_RETRIES):
        try:
            translated = translator.translate(joined)
            parts = translated.split(SEPARATOR)
            if len(parts) != len(batch):
                raise ValueError(
                    f"separator split mismatch: expected {len(batch)}, got {len(parts)}"
                )
            return parts
        except Exception:
            if attempt == MAX_RETRIES - 1:
                raise
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError("unreachable")


def translate_language(strings: dict[str, dict], xcstrings_language: str, service_language: str) -> int:
    translator = GoogleTranslator(source="en", target=service_language)
    pending: list[tuple[str, str, dict[str, str]]] = []
    translated_count = 0
    skipped: list[str] = []

    for key, payload in strings.items():
        localizations = payload.setdefault("localizations", {})
        if xcstrings_language in localizations:
            continue

        source = key
        if needs_verbatim_copy(source):
            localizations[xcstrings_language] = {
                "stringUnit": {
                    "state": "translated",
                    "value": source,
                }
            }
            translated_count += 1
            continue

        protected, replacements = protect(source)
        pending.append((key, protected, replacements))

    for batch_index in range(math.ceil(len(pending) / BATCH_SIZE)):
        start = batch_index * BATCH_SIZE
        end = start + BATCH_SIZE
        chunk = pending[start:end]
        protected_batch = [item[1] for item in chunk]
        try:
            translated_batch = translate_batch(translator, protected_batch)
        except Exception as error:
            # One bad string must not discard a whole run's work: retry the batch
            # one item at a time and leave anything still failing untranslated, so
            # the next run picks it up.
            print(f"[{xcstrings_language}] batch {batch_index} failed ({error}); retrying item by item", flush=True)
            translated_batch = []
            for protected in protected_batch:
                try:
                    translated_batch.append(translate_batch(translator, [protected])[0])
                except Exception:
                    translated_batch.append(None)

        for (key, _protected, replacements), translated in zip(chunk, translated_batch):
            if translated is None:
                skipped.append(key)
                continue
            strings[key]["localizations"][xcstrings_language] = {
                "stringUnit": {
                    "state": "translated",
                    "value": restore(translated, replacements),
                }
            }
            translated_count += 1

        print(
            f"[{xcstrings_language}] {min(end, len(pending))}/{len(pending)}",
            flush=True,
        )

    if skipped:
        print(f"[{xcstrings_language}] {len(skipped)} string(s) left untranslated: {skipped[:5]}", flush=True)
    return translated_count


def main() -> int:
    requested = sys.argv[1:]
    unknown = [language for language in requested if language not in TARGET_LANGUAGES]
    if unknown:
        print(f"unknown language(s): {', '.join(unknown)}", file=sys.stderr)
        print(f"known: {', '.join(TARGET_LANGUAGES)}", file=sys.stderr)
        return 2
    targets = {language: TARGET_LANGUAGES[language] for language in requested} or TARGET_LANGUAGES

    data = xcstrings_format.load(CATALOG)
    strings = data["strings"]

    summary: list[tuple[str, int]] = []
    for xcstrings_language, service_language in targets.items():
        count = translate_language(strings, xcstrings_language, service_language)
        summary.append((xcstrings_language, count))

    for payload in strings.values():
        localizations = payload.get("localizations")
        if localizations:
            payload["localizations"] = {k: localizations[k] for k in sorted(localizations)}

    xcstrings_format.write(CATALOG, data)

    for language, count in summary:
        print(f"{language}: added {count} entries")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as error:
        print(f"translate_popular_languages.py failed: {error}", file=sys.stderr)
        raise
