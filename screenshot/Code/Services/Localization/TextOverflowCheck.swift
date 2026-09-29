import Foundation

/// Where a text shape's string loses lines once it is resolved for a locale — the case a long
/// translation creates and the canvas otherwise shows only by quietly dropping the last line.
enum TextOverflowCheck {
    static func overflows(
        _ shape: CanvasShapeModel,
        localeCode: String,
        localeState: LocaleState,
        availableFontFamilies: Set<String>
    ) -> Bool {
        guard shape.type == .text else { return false }
        let resolved = LocaleService.resolveShape(shape, localeCode: localeCode, localeState: localeState)
        guard !(resolved.text ?? "").isEmpty else { return false }
        return TextFitMeasurer.overflows(
            TextFitInput(shape: resolved, availableFontFamilies: availableFontFamilies),
            shrinksToFit: resolved.shrinkToFit == true
        )
    }

    /// Checks every shape that shares the key, since one string can sit in boxes of different sizes.
    static func overflows(
        translationKey: String,
        localeCode: String,
        rows: [ScreenshotRow],
        localeState: LocaleState,
        availableFontFamilies: Set<String>
    ) -> Bool {
        rows.contains { row in
            row.shapes.contains { shape in
                shape.type == .text && shape.textTranslationKey == translationKey
                    && overflows(shape, localeCode: localeCode, localeState: localeState,
                                 availableFontFamilies: availableFontFamilies)
            }
        }
    }

    static func overflowingLocaleCodes(
        in row: ScreenshotRow,
        localeState: LocaleState,
        availableFontFamilies: Set<String>
    ) -> [String] {
        localeState.locales.map(\.code).filter { code in
            row.shapes.contains {
                overflows($0, localeCode: code, localeState: localeState, availableFontFamilies: availableFontFamilies)
            }
        }
    }

    /// Warnings, never errors: a clipped line is a design problem, not a reason the store would
    /// reject the upload.
    static func uploadIssues(
        rows: [ScreenshotRow],
        localeState: LocaleState,
        availableFontFamilies: Set<String> = PlatformFonts.familyNameSet
    ) -> [UploadIssue] {
        rows.compactMap { row in
            let codes = overflowingLocaleCodes(in: row, localeState: localeState, availableFontFamilies: availableFontFamilies)
            guard !codes.isEmpty else { return nil }
            let languages = codes.map { $0.uppercased() }.formatted(.list(type: .and))
            return UploadIssue(
                severity: .warning,
                scope: StoreUploadChecks.rowName(row.label),
                message: String(localized: "Text doesn't fit its box in \(languages)."),
                hint: String(localized: "Enlarge the text box, shorten the translation, or turn on Shrink to Fit.")
            )
        }
    }
}
