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
}
