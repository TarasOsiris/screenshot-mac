import Foundation

/// Apple String Catalog (`.xcstrings`) representation of one project's screenshot-content
/// translations. Keyed by text-shape UUID: the source language holds the base string and
/// every other locale holds its translation. Persisted at `projects/<uuid>/translations.xcstrings`
/// so it can be opened and round-tripped in Xcode's String Catalog editor or external tools.
///
/// This is a *mirror* of the runtime translation data, which still lives in `LocaleState`.
/// `build` produces it from the live model; `apply` merges an (possibly translator-edited)
/// catalog back into a `LocaleState` on load. Only plain text is represented — per-range
/// rich-text formatting can't live in a String Catalog, so it's flattened to plain text and
/// the base shape's styling is re-applied at render time.
nonisolated struct TranslationCatalog: Codable, Equatable {
    var sourceLanguage: String
    var version: String
    var strings: [String: CatalogEntry]

    init(sourceLanguage: String, version: String = "1.0", strings: [String: CatalogEntry] = [:]) {
        self.sourceLanguage = sourceLanguage
        self.version = version
        self.strings = strings
    }

    struct CatalogEntry: Codable, Equatable {
        var comment: String?
        var localizations: [String: CatalogLocalization]
    }

    struct CatalogLocalization: Codable, Equatable {
        var stringUnit: CatalogStringUnit
    }

    struct CatalogStringUnit: Codable, Equatable {
        var state: String
        var value: String
    }

    static let translatedState = "translated"

    // MARK: - Build

    /// Build a catalog from the live model: one entry per text shape with a non-empty base
    /// string, carrying the base value under the source language and each non-base locale's
    /// translation. Legacy rich-text-only translations are flattened to plain text.
    static func build(rows: [ScreenshotRow], localeState: LocaleState) -> TranslationCatalog {
        let base = localeState.baseLocaleCode
        var strings: [String: CatalogEntry] = [:]
        var rowLabelsByKey: [String: [String]] = [:]

        for row in rows {
            let label = row.label.trimmingCharacters(in: .whitespacesAndNewlines)
            for shape in row.shapes where shape.type == .text {
                guard let baseText = visibleText(plain: shape.text, richText: shape.richText) else { continue }
                // Reused strings share one translation key, so they collapse into a single entry.
                let key = shape.textTranslationKey
                if !label.isEmpty, rowLabelsByKey[key]?.contains(label) != true { rowLabelsByKey[key, default: []].append(label) }
                if strings[key] != nil { continue }

                var localizations: [String: CatalogLocalization] = [
                    base: .init(stringUnit: .init(state: translatedState, value: baseText))
                ]
                for locale in localeState.locales where locale.code != base {
                    guard let override = localeState.overrides[locale.code]?[key],
                          let translated = visibleText(plain: override.text, richText: override.richText)
                    else { continue }
                    localizations[locale.code] = .init(stringUnit: .init(state: translatedState, value: translated))
                }

                strings[key] = CatalogEntry(comment: nil, localizations: localizations)
            }
        }

        for (key, labels) in rowLabelsByKey {
            strings[key]?.comment = labels.count == 1 ? "Row: \(labels[0])" : "Rows: \(labels.joined(separator: ", "))"
        }

        return TranslationCatalog(sourceLanguage: base, strings: strings)
    }

    // MARK: - Apply

    /// Merge this catalog's translations into a `LocaleState`, taking the catalog as the source
    /// of truth for non-base locale text (so a translator's edits win). Base-language values are
    /// ignored — the base string is owned by the shape. Clears any prior rich-text override for a
    /// translated locale so re-applied base styling matches.
    func apply(to localeState: inout LocaleState) {
        apply(to: &localeState, validKeys: nil)
    }

    func apply(to localeState: inout LocaleState, validKeys: Set<String>? = nil) {
        for (shapeKey, entry) in strings {
            if let validKeys, !validKeys.contains(shapeKey) { continue }
            for (code, localization) in entry.localizations where code != sourceLanguage {
                guard localeState.hasLocale(code) else { continue }
                let value = localization.stringUnit.value
                guard !value.isEmpty else {
                    clearTranslatedText(in: &localeState, localeCode: code, key: shapeKey)
                    continue
                }
                let existing = localeState.overrides[code]?[shapeKey]
                // The catalog can't carry RTF, so it stores a formatted translation's plain mirror.
                // When that plain value is unchanged, keep the inline rich-text override rather than
                // flattening the user's formatting on every load.
                if let existing, let rich = existing.richText, !rich.isEmpty,
                   (existing.text ?? RichTextUtils.plainText(from: rich)) == value {
                    continue
                }
                var override = existing ?? ShapeLocaleOverride()
                override.text = value
                override.richText = nil
                override.clearsRichText = nil
                localeState.overrides[code, default: [:]][shapeKey] = override
            }
        }
    }

    // MARK: - Helpers

    static func representedKeys(rows: [ScreenshotRow]) -> Set<String> {
        Set(rows.flatMap { row in
            row.shapes.compactMap { shape in
                guard shape.type == .text,
                      visibleText(plain: shape.text, richText: shape.richText) != nil
                else { return nil }
                return shape.textTranslationKey
            }
        })
    }

    private func clearTranslatedText(in localeState: inout LocaleState, localeCode: String, key: String) {
        guard var override = localeState.overrides[localeCode]?[key] else { return }
        override.clearTranslatedText()
        if override.isEmpty {
            localeState.overrides[localeCode]?.removeValue(forKey: key)
            if localeState.overrides[localeCode]?.isEmpty == true {
                localeState.overrides.removeValue(forKey: localeCode)
            }
        } else {
            localeState.overrides[localeCode]?[key] = override
        }
    }

    /// The visible plain string for a text field: prefer plain `text`, fall back to decoding
    /// rich-text RTF. Returns nil when there's no non-whitespace content.
    private static func visibleText(plain: String?, richText: String?) -> String? {
        let resolved = plain ?? richText.flatMap { RichTextUtils.plainText(from: $0) }
        guard let resolved, !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return resolved
    }
}
