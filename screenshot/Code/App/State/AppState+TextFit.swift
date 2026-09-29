import Foundation

extension AppState {
    func textOverflows(translationKey: String, localeCode: String) -> Bool {
        TextOverflowCheck.overflows(
            translationKey: translationKey,
            localeCode: localeCode,
            rows: rows,
            localeState: localeState,
            availableFontFamilies: availableFontFamilySet
        )
    }
}
