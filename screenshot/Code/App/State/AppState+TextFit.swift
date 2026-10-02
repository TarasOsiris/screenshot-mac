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
            takeBackAutoFit(textKey: textKey, localeCode: localeCode)
            if autoFits { results = fitTranslatedText(textKey: textKey, localeCode: localeCode) }
        }
        return results
    }

    /// Every write to a translation's text calls this, so an earlier fit never outlives the text it was made for.
    func takeBackAutoFit(textKey: String, localeCode: String) {
        for shape in rows.flatMap(\.shapes) where shape.textTranslationKey == textKey {
            guard let override = localeState.override(forCode: localeCode, shapeId: shape.id), override.autoFit != nil else { continue }
            writeShapeOverride(override.removingAutoFit(), shapeId: shape.id, localeCode: localeCode)
        }
    }

    private func fitTranslatedText(textKey: String, localeCode: String) -> [UUID: TextAutoFitResult] {
        // A cleared translation shows the base text, which is the base layout's business.
        guard localeState.overrides[localeCode]?[textKey]?.hasTranslatedTextField == true else { return [:] }
        var results: [UUID: TextAutoFitResult] = [:]
        for row in rows {
            for shape in row.shapes where shape.type == .text && shape.textTranslationKey == textKey {
                let result = TextAutoFitService.fit(
                    shape: shape, localeCode: localeCode, row: row,
                    localeState: localeState, availableFontFamilies: availableFontFamilySet
                )
                results[shape.id] = result
                let override = localeState.override(forCode: localeCode, shapeId: shape.id) ?? ShapeLocaleOverride()
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
