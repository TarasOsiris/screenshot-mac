import Foundation

/// Where a text shape's string loses lines once it is resolved for a locale — the case a long
/// translation creates and the canvas otherwise shows only by quietly dropping the last line.
/// Measures with fonts as found; wrap calls in the document's `withResolvedFonts` when the
/// project may not be the one open in the editor.
enum TextOverflowCheck {
    /// Project locale codes, in project order, whose text overflows this shape's box.
    static func overflowingLocaleCodes(
        of shape: CanvasShapeModel,
        localeState: LocaleState,
        availableFontFamilies: Set<String>
    ) -> [String] {
        guard shape.type == .text else { return [] }
        return localeState.locales.map(\.code).filter { code in
            let resolved = LocaleService.resolveShape(shape, localeCode: code, localeState: localeState)
            guard !(resolved.text ?? "").isEmpty else { return false }
            return TextFitMeasurer.overflows(
                TextFitInput(shape: resolved, availableFontFamilies: availableFontFamilies),
                shrinksToFit: resolved.shrinkToFit == true
            )
        }
    }

    static func overflowingLocaleCodes(
        in row: ScreenshotRow,
        localeState: LocaleState,
        availableFontFamilies: Set<String>
    ) -> [String] {
        let overflowing = Set(row.shapes.flatMap {
            overflowingLocaleCodes(of: $0, localeState: localeState, availableFontFamilies: availableFontFamilies)
        })
        return localeState.locales.map(\.code).filter(overflowing.contains)
    }

    /// Every (translation key, locale) whose text overflows in any box that shows it — one string
    /// can sit in boxes of different sizes. One pass for a whole translation table.
    static func overflowingTranslations(
        rows: [ScreenshotRow],
        localeState: LocaleState,
        availableFontFamilies: Set<String>
    ) -> Set<TranslationCell> {
        var cells = Set<TranslationCell>()
        for row in rows {
            for shape in row.shapes where shape.type == .text {
                for code in overflowingLocaleCodes(of: shape, localeState: localeState, availableFontFamilies: availableFontFamilies) {
                    cells.insert(TranslationCell(translationKey: shape.textTranslationKey, localeCode: code))
                }
            }
        }
        return cells
    }

    /// Warnings, never errors: a clipped line is a design problem, not a reason the store would
    /// reject the upload.
    static func uploadIssues(rows: [ScreenshotRow], localeState: LocaleState, availableFontFamilies: Set<String>) -> [UploadIssue] {
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

struct TranslationCell: Hashable {
    let translationKey: String
    let localeCode: String
}

/// The upload flows read their issues from computed properties that re-run on every body
/// evaluation; each flow keeps its last answer for as long as the document is unchanged.
@MainActor
final class TextOverflowIssueCache {
    private struct Input: Equatable {
        let rows: [ScreenshotRow]
        let localeState: LocaleState
        let families: Set<String>
    }

    private var last: (input: Input, issues: [UploadIssue])?

    func issues(rows: [ScreenshotRow], source: some RowRenderSource) -> [UploadIssue] {
        let input = Input(rows: rows, localeState: source.localeState, families: source.availableFontFamilySet)
        if let last, last.input == input { return last.issues }
        let issues = source.withResolvedFonts {
            TextOverflowCheck.uploadIssues(rows: rows, localeState: input.localeState, availableFontFamilies: input.families)
        }
        last = (input, issues)
        return issues
    }
}
