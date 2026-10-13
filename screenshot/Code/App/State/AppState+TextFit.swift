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
            results = DocumentEditing.setTranslation(
                textKey: textKey, localeCode: localeCode, text: text, richText: richText, autoFits: autoFits,
                rows: rows, localeState: &localeState, availableFontFamilies: availableFontFamilySet
            )
        }
        return results
    }

    /// Every write to a translation's text calls this, so an earlier fit never outlives the text it was made for.
    func takeBackAutoFit(textKey: String, localeCode: String) {
        DocumentEditing.takeBackAutoFit(textKey: textKey, localeCode: localeCode, rows: rows, localeState: &localeState)
    }
}
