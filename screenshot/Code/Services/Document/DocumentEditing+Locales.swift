import Foundation

extension DocumentEditing {

    // MARK: - Locales

    /// Removes the locale, its overrides and the rows' background images for it. Returns the image files it freed.
    static func removeLocale(_ code: String, rows: inout [ScreenshotRow], localeState: inout LocaleState) -> [String] {
        let freed = resetLocale(code, rows: &rows, localeState: &localeState)
        LocaleService.removeLocale(&localeState, code: code)
        return freed
    }

    /// Drops everything `code` overrides — text, layout and images — but keeps the language. Returns the image files it freed.
    static func resetLocale(_ code: String, rows: inout [ScreenshotRow], localeState: inout LocaleState) -> [String] {
        let overrideImages = localeState.overrides[code]?.values.compactMap(\.overrideImageFileName) ?? []
        localeState.overrides.removeValue(forKey: code)
        return overrideImages + removeBackgroundImageOverrides(forLocale: code, in: &rows)
    }

    private static func removeBackgroundImageOverrides(forLocale code: String, in rows: inout [ScreenshotRow]) -> [String] {
        var freed: [String] = []
        for index in rows.indices where rows[index].hasBackgroundImageEntry(forLocale: code) {
            freed += rows[index].removeBackgroundImageOverrides(forLocale: code)
        }
        return freed
    }

    // MARK: - Translations

    /// Writes a translation through the text-only path, so the geometry override and its auto-fit
    /// record survive, then (with `autoFits`) refits every box showing it.
    static func setTranslation(
        textKey: String, localeCode: String, text: String, richText: String?, autoFits: Bool,
        rows: [ScreenshotRow], localeState: inout LocaleState, availableFontFamilies: Set<String>
    ) -> [UUID: TextAutoFitResult] {
        let value = text.isEmpty ? nil : text
        LocaleService.setTextFieldsOverride(
            &localeState, localeCode: localeCode, key: textKey,
            text: value, richText: value == nil ? nil : richText, clearsRichText: nil
        )
        takeBackAutoFit(textKey: textKey, localeCode: localeCode, rows: rows, localeState: &localeState)
        guard autoFits else { return [:] }
        return fitTranslatedText(
            textKey: textKey, localeCode: localeCode, rows: rows,
            localeState: &localeState, availableFontFamilies: availableFontFamilies
        )
    }

    /// Every write to a translation's text calls this, so an earlier fit never outlives the text it was made for.
    static func takeBackAutoFit(textKey: String, localeCode: String, rows: [ScreenshotRow], localeState: inout LocaleState) {
        for shape in rows.flatMap(\.shapes) where shape.textTranslationKey == textKey {
            guard let override = localeState.override(forCode: localeCode, shapeId: shape.id), override.autoFit != nil else { continue }
            writeShapeOverride(override.removingAutoFit(), shapeId: shape.id, localeCode: localeCode, localeState: &localeState)
        }
    }

    /// Carries a shape-level restyle (or a formatting clear) into every translation that has its
    /// own rich text, which the base shape's richText doesn't reach.
    static func restyleTranslations(
        of shape: CanvasShapeModel,
        properties: [RichTextUtils.ShapeStyleProperty],
        clearingFormatting: Bool,
        localeState: inout LocaleState
    ) {
        guard clearingFormatting || !properties.isEmpty else { return }
        let key = shape.textTranslationKey
        for (code, overrides) in localeState.overrides where overrides[key]?.richText != nil {
            var resolved = LocaleService.resolveShape(shape, localeCode: code, localeState: localeState)
            if clearingFormatting {
                resolved.richText = nil
            } else {
                for property in properties {
                    RichTextUtils.syncShapeStyle(in: &resolved, property: property)
                }
            }
            localeState.overrides[code]?[key]?.text = resolved.text
            localeState.overrides[code]?[key]?.richText = resolved.richText
        }
    }

    private static func fitTranslatedText(
        textKey: String, localeCode: String, rows: [ScreenshotRow],
        localeState: inout LocaleState, availableFontFamilies: Set<String>
    ) -> [UUID: TextAutoFitResult] {
        // A cleared translation shows the base text, which is the base layout's business.
        guard localeState.overrides[localeCode]?[textKey]?.hasTranslatedTextField == true else { return [:] }
        var results: [UUID: TextAutoFitResult] = [:]
        for row in rows {
            for shape in row.shapes where shape.type == .text && shape.textTranslationKey == textKey {
                let result = TextAutoFitService.fit(
                    shape: shape, localeCode: localeCode, row: row,
                    localeState: localeState, availableFontFamilies: availableFontFamilies
                )
                results[shape.id] = result
                let override = localeState.override(forCode: localeCode, shapeId: shape.id) ?? ShapeLocaleOverride()
                writeShapeOverride(override.addingAutoFit(result.contribution), shapeId: shape.id, localeCode: localeCode, localeState: &localeState)
            }
        }
        return results
    }

    private static func writeShapeOverride(_ override: ShapeLocaleOverride, shapeId: UUID, localeCode: String, localeState: inout LocaleState) {
        LocaleService.setShapeOverride(
            &localeState, localeCode: localeCode, shapeId: shapeId, override: override.isEmpty ? nil : override
        )
    }

    /// Set `text` as the base text of every text shape sharing `key` — the members of a reused string.
    static func setSharedBaseText(key: String, text: String, rows: inout [ScreenshotRow]) {
        for r in rows.indices {
            for s in rows[r].shapes.indices where rows[r].shapes[s].type == .text && rows[r].shapes[s].textTranslationKey == key {
                rows[r].shapes[s].text = text
            }
        }
    }

    /// Drop any override entry whose key is no longer a live shape id or a live text shape's
    /// translation key — e.g. after deleting every member of a reused string.
    static func cleanupOrphanedTranslationOverrides(rows: [ScreenshotRow], localeState: inout LocaleState) {
        var live = Set<String>()
        for row in rows {
            for shape in row.shapes {
                live.insert(shape.id.uuidString)
                if shape.type == .text { live.insert(shape.textTranslationKey) }
            }
        }
        for code in Array(localeState.overrides.keys) {
            guard let keys = localeState.overrides[code]?.keys else { continue }
            for key in Array(keys) where !live.contains(key) {
                localeState.overrides[code]?.removeValue(forKey: key)
            }
            if localeState.overrides[code]?.isEmpty == true {
                localeState.overrides.removeValue(forKey: code)
            }
        }
    }
}
