import Foundation

extension AppState {
    /// Every (translation key, locale) whose text doesn't fit its box, for the translation table.
    func overflowingTranslations() -> Set<TranslationCell> {
        TextOverflowCheck.overflowingTranslations(
            rows: rows,
            localeState: localeState,
            availableFontFamilies: availableFontFamilySet
        )
    }

    /// Writes a translation as one discrete undo step and, with `autoFits`, refits every box showing it.
    /// Text goes in through the text-only path, so the geometry override and its auto-fit record survive.
    @discardableResult
    func setTranslation(
        shapeId: UUID, localeCode: String, text: String, richText: String? = nil, autoFits: Bool = true
    ) -> [UUID: TextAutoFitResult] {
        guard let textKey = translatableTextKey(shapeId: shapeId, localeCode: localeCode) else { return [:] }
        var results: [UUID: TextAutoFitResult] = [:]
        withUndo("Edit Translation") {
            let value = text.isEmpty ? nil : text
            LocaleService.setTextFieldsOverride(
                &localeState, localeCode: localeCode, key: textKey,
                text: value, richText: value == nil ? nil : richText, clearsRichText: nil
            )
            if autoFits { results = refitTranslatedText(textKey: textKey, localeCode: localeCode) }
        }
        return results
    }

    /// Takes back each box's earlier fit for this translation, then fits it again.
    private func refitTranslatedText(textKey: String, localeCode: String) -> [UUID: TextAutoFitResult] {
        let hasTranslation = localeState.overrides[localeCode]?[textKey]?.hasTranslatedTextField == true
        var results: [UUID: TextAutoFitResult] = [:]
        for rowIndex in rows.indices {
            for shapeIndex in rows[rowIndex].shapes.indices {
                let shape = rows[rowIndex].shapes[shapeIndex]
                guard shape.type == .text, shape.textTranslationKey == textKey else { continue }
                let override = (localeState.override(forCode: localeCode, shapeId: shape.id) ?? ShapeLocaleOverride()).removingAutoFit()
                writeShapeOverride(override, shapeId: shape.id, localeCode: localeCode)
                // A cleared translation shows the base text, which is the base layout's business.
                guard hasTranslation else { continue }

                let result = TextAutoFitService.fit(
                    shape: shape, localeCode: localeCode, row: rows[rowIndex],
                    localeState: localeState, availableFontFamilies: availableFontFamilySet
                )
                results[shape.id] = result
                if result.enablesShrinkToFit { rows[rowIndex].shapes[shapeIndex].shrinkToFit = true }
                writeShapeOverride(override.addingAutoFit(result.contribution), shapeId: shape.id, localeCode: localeCode)
            }
        }
        return results
    }

    private func writeShapeOverride(_ override: ShapeLocaleOverride, shapeId: UUID, localeCode: String) {
        LocaleService.setShapeOverride(
            &localeState, localeCode: localeCode, shapeId: shapeId, override: override.isEmpty ? nil : override
        )
    }
}
