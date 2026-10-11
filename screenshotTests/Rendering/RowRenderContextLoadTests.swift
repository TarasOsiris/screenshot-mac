import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// Records each batch the loader is asked for.
@MainActor
private final class RecordingRenderSource: RowRenderSource {
    var localeState = LocaleState(
        locales: [LocaleDefinition(code: "en", label: "English")],
        activeLocaleCode: "en",
        overrides: [:]
    )
    var availableFontFamilySet: Set<String> = []
    let images: [String: NSImage]
    private(set) var requests: [Set<String>] = []

    init(images: [String: NSImage]) { self.images = images }

    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> {
        ProjectDocument(rows: [row], localeState: localeState).referencedImageFileNames(forRow: row, localeCode: localeCode)
    }

    func loadFullResolutionImages(fileNames: Set<String>) async -> [String: NSImage] {
        requests.append(fileNames)
        return images.filter { fileNames.contains($0.key) }
    }
}

/// Sentry `SCREENSHOT-BRO-2C`: an MCP preview read full-resolution PNGs from an iCloud project on
/// the main thread and hung for 3 s+. `load` now reads through the async loader exactly once.
@MainActor
struct RowRenderContextLoadTests {
    private func imageRow() -> ScreenshotRow {
        var row = makeTestRow(label: "Bg", templateCount: 1, bgColor: .white)
        row.backgroundStyle = .image
        row.backgroundImageConfig.fileName = "red.png"
        return row
    }

    @Test func loadReadsUncachedFilesAndFillsTheCache() async {
        let source = RecordingRenderSource(images: ["red.png": makeSolidImage(.red, width: 10, height: 10)])
        var cache: [String: NSImage] = [:]

        let context = await RowRenderContext.load(row: imageRow(), localeCode: "en", from: source, label: "test", cache: &cache)

        #expect(source.requests == [["red.png"]])
        #expect(cache["red.png"] != nil)
        #expect(context.images["red.png"] != nil)
        #expect(context.unrenderableImageFileNames.isEmpty)
    }

    @Test func loadSkipsCachedAndSeededFiles() async {
        let source = RecordingRenderSource(images: [:])
        var cache: [String: NSImage] = ["red.png": makeSolidImage(.red, width: 10, height: 10)]
        _ = await RowRenderContext.load(row: imageRow(), localeCode: "en", from: source, label: "test", cache: &cache)

        var empty: [String: NSImage] = [:]
        _ = await RowRenderContext.load(
            row: imageRow(), localeCode: "en", from: source, label: "test", cache: &empty,
            seedImages: ["red.png": makeSolidImage(.red, width: 10, height: 10)]
        )

        #expect(source.requests.isEmpty)
    }

    @Test func aFailedReadIsReportedMissingWithoutARetry() async {
        let source = RecordingRenderSource(images: [:])
        var cache: [String: NSImage] = [:]

        let context = await RowRenderContext.load(row: imageRow(), localeCode: "en", from: source, label: "test", cache: &cache)

        #expect(source.requests == [["red.png"]])
        #expect(context.missingImageFileNames == ["red.png"])
    }
}
