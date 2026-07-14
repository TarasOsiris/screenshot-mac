import Testing
import AppKit
import SwiftUI
@testable import Screenshot_Bro

/// Covers the locale-dedupe export path: rows untouched by a locale render once
/// and the encoded bytes are shared across that locale group's folders.
@MainActor
struct ExportAllTests {

    private func makeLocaleState(overrides: [String: [String: ShapeLocaleOverride]] = [:]) -> LocaleState {
        LocaleState(
            locales: [
                LocaleDefinition(code: "en", label: "English"),
                LocaleDefinition(code: "de", label: "German"),
            ],
            activeLocaleCode: "en",
            overrides: overrides
        )
    }

    private func makeTextRow(label: String, text: String) -> ScreenshotRow {
        var row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 200,
            templateHeight: 400,
            bgColor: .white
        )
        row.label = label
        row.shapes = [CanvasShapeModel(
            type: .text, x: 10, y: 10, width: 180, height: 100,
            color: .black, text: text, fontSize: 40, fontWeight: 700
        )]
        return row
    }

    // MARK: - rowIsLocaleNeutral

    @Test func baseLocaleIsAlwaysNeutral() {
        let row = makeTextRow(label: "A", text: "Hello")
        let state = makeLocaleState()
        #expect(LocaleService.rowIsLocaleNeutral(row: row, localeCode: "en", localeState: state))
    }

    @Test func localeWithNoOverridesIsNeutral() {
        let row = makeTextRow(label: "A", text: "Hello")
        let state = makeLocaleState()
        #expect(LocaleService.rowIsLocaleNeutral(row: row, localeCode: "de", localeState: state))
    }

    @Test func textOverrideMakesLocaleNonNeutral() throws {
        let row = makeTextRow(label: "A", text: "Hello")
        let shape = try #require(row.shapes.first)
        let state = makeLocaleState(overrides: [
            "de": [shape.textTranslationKey: ShapeLocaleOverride(text: "Hallo")]
        ])
        #expect(!LocaleService.rowIsLocaleNeutral(row: row, localeCode: "de", localeState: state))
    }

    @Test func styleOverrideMakesLocaleNonNeutral() throws {
        var row = makeTextRow(label: "A", text: "Hello")
        // Link the shape to a shared translation key so the style override
        // (keyed by shape id) is exercised separately from the text key.
        row.shapes[0].translationKey = "shared-key"
        let shape = try #require(row.shapes.first)
        let state = makeLocaleState(overrides: [
            "de": [shape.id.uuidString: ShapeLocaleOverride(offsetX: 12)]
        ])
        #expect(!LocaleService.rowIsLocaleNeutral(row: row, localeCode: "de", localeState: state))
    }

    @Test func imageOverrideMakesLocaleNonNeutral() throws {
        let row = makeTextRow(label: "A", text: "Hello")
        let shape = try #require(row.shapes.first)
        let state = makeLocaleState(overrides: [
            "de": [shape.id.uuidString: ShapeLocaleOverride(overrideImageFileName: "de-shot.png")]
        ])
        #expect(!LocaleService.rowIsLocaleNeutral(row: row, localeCode: "de", localeState: state))
    }

    @Test func overrideOnOtherRowsShapeStaysNeutral() {
        let rowA = makeTextRow(label: "A", text: "Hello")
        let rowB = makeTextRow(label: "B", text: "World")
        let shapeA = rowA.shapes[0]
        let state = makeLocaleState(overrides: [
            "de": [shapeA.textTranslationKey: ShapeLocaleOverride(text: "Hallo")]
        ])
        #expect(LocaleService.rowIsLocaleNeutral(row: rowB, localeCode: "de", localeState: state))
        #expect(!LocaleService.rowIsLocaleNeutral(row: rowA, localeCode: "de", localeState: state))
    }

    // MARK: - exportAll locale dedupe

    @Test func exportAllSharesNeutralRowBytesAndRendersOverriddenRowPerLocale() async throws {
        let rowA = makeTextRow(label: "Localized", text: "Hello")
        let rowB = makeTextRow(label: "Neutral", text: "Same everywhere")
        let shapeA = rowA.shapes[0]
        let localeState = makeLocaleState(overrides: [
            "de": [shapeA.textTranslationKey: ShapeLocaleOverride(text: "Hallo Welt")]
        ])

        let tempDir = makeTemporaryDataDirectory(label: "export-all-tests")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let export = try await ExportService.exportAll(
            rows: [rowA, rowB],
            projectName: "TestProject",
            to: tempDir,
            imageProvider: { _, _ in [:] },
            localeState: localeState
        )

        // 2 locales × 2 rows × 2 templates
        #expect(export.fileURLs.count == 8)
        for url in export.fileURLs {
            #expect(FileManager.default.fileExists(atPath: url.path), "missing \(url.lastPathComponent)")
        }

        func data(locale: String, row: String, file: String) throws -> Data {
            let url = export.folderURL
                .appendingPathComponent(locale)
                .appendingPathComponent(row)
                .appendingPathComponent(file)
            return try Data(contentsOf: url)
        }

        // Neutral row: byte-identical across locale folders (filenames embed the locale).
        let neutralEN = try data(locale: "en", row: "Neutral — 200x400", file: "01_Neutral_en.png")
        let neutralDE = try data(locale: "de", row: "Neutral — 200x400", file: "01_Neutral_de.png")
        #expect(neutralEN == neutralDE)

        // Localized row: German render must differ from English.
        let localizedEN = try data(locale: "en", row: "Localized — 200x400", file: "01_Localized_en.png")
        let localizedDE = try data(locale: "de", row: "Localized — 200x400", file: "01_Localized_de.png")
        #expect(localizedEN != localizedDE)
    }

    /// exportAll now renders per-template; a blurred spanning background is the case
    /// that must keep using the full-width composed strip for parity.
    @Test func exportAllMatchesSingleTemplateRenderForBlurredSpanningRow() async throws {
        var row = ScreenshotRow(
            templates: [ScreenshotTemplate(), ScreenshotTemplate()],
            templateWidth: 200,
            templateHeight: 400,
            bgColor: .white
        )
        row.label = "Blurry"
        row.backgroundStyle = .gradient
        row.spanBackgroundAcrossRow = true
        row.backgroundBlur = 12

        let tempDir = makeTemporaryDataDirectory(label: "export-all-tests")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let export = try await ExportService.exportAll(
            rows: [row],
            projectName: "BlurProject",
            to: tempDir,
            imageProvider: { _, _ in [:] },
            localeState: .default
        )
        #expect(export.fileURLs.count == 2)

        for (index, url) in export.fileURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).enumerated() {
            let exported = try Data(contentsOf: url)
            let direct = try #require(ExportService.renderTemplateData(index: index, row: row, format: .png))
            #expect(exported == direct, "template \(index) diverges from renderTemplateData")
        }
    }
}
