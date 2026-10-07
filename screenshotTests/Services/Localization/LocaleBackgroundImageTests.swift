import AppKit
@testable import Screenshot_Bro
import SwiftUI
import Testing

/// A source that serves images from memory, so a render can draw named background files.
@MainActor
private final class InMemoryRenderSource: RowRenderSource {
    var localeState: LocaleState
    var availableFontFamilySet: Set<String> = PlatformFonts.familyNameSet
    let images: [String: NSImage]

    init(localeState: LocaleState, images: [String: NSImage]) {
        self.localeState = localeState
        self.images = images
    }

    func referencedImageFileNames(forRow row: ScreenshotRow, localeCode: String) -> Set<String> {
        ProjectDocument(rows: [row], localeState: localeState).referencedImageFileNames(forRow: row, localeCode: localeCode)
    }

    func loadFullResolutionImages(fileNames: Set<String>, cache: inout [String: NSImage]) -> [String: NSImage] {
        images.filter { fileNames.contains($0.key) }
    }
}

@MainActor
struct LocaleBackgroundImageTests {
    private let localeState = LocaleState(
        locales: [LocaleDefinition(code: "en", label: "English"), LocaleDefinition(code: "de", label: "German")],
        activeLocaleCode: "en",
        overrides: [:]
    )

    private var images: [String: NSImage] {
        [
            "red.png": makeSolidImage(.red, width: 50, height: 50),
            "green.png": makeSolidImage(.green, width: 50, height: 50),
        ]
    }

    private func makeImageRow(templateCount: Int = 2, spanning: Bool = false, blur: Double = 0) -> ScreenshotRow {
        var row = makeTestRow(label: "Bg", templateCount: templateCount, bgColor: .white)
        row.backgroundStyle = .image
        row.spanBackgroundAcrossRow = spanning
        row.backgroundBlur = blur
        row.backgroundImageConfig.fileName = "red.png"
        row.backgroundImageConfig.localeImages = ["de": BackgroundImageSource(fileName: "green.png")]
        return row
    }

    private func centerPixel(_ data: Data) throws -> NSColor {
        let bitmap = try #require(NSBitmapImageRep(data: data))
        let color = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2))
        return try #require(color.usingColorSpace(.sRGB))
    }

    private func expectRed(_ color: NSColor, _ label: String) {
        #expect(color.redComponent > 0.8 && color.greenComponent < 0.3, "\(label) should be red, got \(color)")
    }

    private func expectGreen(_ color: NSColor, _ label: String) {
        #expect(color.greenComponent > 0.6 && color.redComponent < 0.3, "\(label) should be green, got \(color)")
    }

    // MARK: - Model

    @Test func configWithoutTableDecodesAndEncodesUnchanged() throws {
        let json = Data(#"{"f":"bg.png","fm":"fit"}"#.utf8)
        let config = try JSONDecoder().decode(BackgroundImageConfig.self, from: json)
        #expect(config.localeImages.isEmpty)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any]
        #expect(encoded?["li"] == nil, "An empty table must not change the on-disk shape")
    }

    @Test func configRoundTripsLocaleImages() throws {
        var config = BackgroundImageConfig(fileName: "bg.png")
        config.localeImages = ["fr": BackgroundImageSource(fileName: "fr.png"), "de": BackgroundImageSource(svgContent: "<svg/>")]
        let decoded = try JSONDecoder().decode(BackgroundImageConfig.self, from: JSONEncoder().encode(config))
        #expect(decoded == config)
    }

    @Test func localizedSwapsSourceAndEmptiesTable() {
        var config = BackgroundImageConfig(fileName: "base.png", fillMode: .tile, opacity: 0.5)
        config.localeImages = ["de": BackgroundImageSource(svgContent: "<svg/>")]

        let de = config.localized(to: "de")
        #expect(de.fileName == nil)
        #expect(de.svgContent == "<svg/>")
        #expect(de.fillMode == .tile && de.opacity == 0.5, "Only the source is per-language")
        #expect(de.localeImages.isEmpty)

        for code in ["en", "fr", nil] as [String?] {
            let resolved = config.localized(to: code)
            #expect(resolved.fileName == "base.png")
            #expect(resolved.localeImages.isEmpty)
        }
    }

    @Test func rowResolvesRowAndTemplateImages() {
        var row = makeImageRow()
        row.templates[1].backgroundImageConfig.fileName = "t-base.png"
        row.templates[1].backgroundImageConfig.localeImages = ["de": BackgroundImageSource(fileName: "t-de.png")]

        let de = row.localizingBackgroundImages(to: "de")
        #expect(de.backgroundImageConfig.fileName == "green.png")
        #expect(de.templates[1].backgroundImageConfig.fileName == "t-de.png")

        let en = row.localizingBackgroundImages(to: "en")
        #expect(en.backgroundImageConfig.fileName == "red.png")
        #expect(en.templates[1].backgroundImageConfig.fileName == "t-base.png")
    }

    @Test func rebaseKeepsWhatEveryLanguageDrew() {
        var config = BackgroundImageConfig(fileName: "en.png")
        config.localeImages = ["de": BackgroundImageSource(fileName: "de.png")]

        config.rebaseLocaleImages(to: "de", localeCodes: ["en", "de", "fr"])

        #expect(config.fileName == "de.png")
        #expect(config.localeImages["en"]?.fileName == "en.png")
        #expect(config.localeImages["fr"]?.fileName == "en.png", "fr inherited the old base, so it keeps it")
        #expect(config.localeImages["de"] == nil)
    }

    @Test func rebaseFromImagelessBaseLeavesNoEmptyEntries() {
        var config = BackgroundImageConfig()
        config.localeImages = ["de": BackgroundImageSource(fileName: "de.png")]

        config.rebaseLocaleImages(to: "de", localeCodes: ["en", "de", "fr"])

        #expect(config.fileName == "de.png")
        #expect(config.localeImages.isEmpty)
    }

    @Test func retentionKeepsEveryLanguageAndRenderingTakesOne() {
        let row = makeImageRow()
        let document = ProjectDocument(rows: [row], localeState: localeState)
        #expect(document.allReferencedImageFileNames() == ["red.png", "green.png"])
        #expect(document.referencedImageFileNames(forRow: row, localeCode: "de") == ["green.png"])
        #expect(document.referencedImageFileNames(forRow: row, localeCode: "en") == ["red.png"])
        #expect(document.editorReferencedImageFileNames() == ["red.png"])
        var german = document
        german.localeState.activeLocaleCode = "de"
        #expect(german.editorReferencedImageFileNames() == ["red.png", "green.png"], "The base stays loaded beside it")
    }

    // MARK: - Export

    @Test func backgroundImageOverrideMakesLocaleNonNeutral() {
        var row = makeImageRow()
        #expect(!LocaleService.rowIsLocaleNeutral(row: row, localeCode: "de", localeState: localeState))
        row.backgroundStyle = .color
        #expect(
            LocaleService.rowIsLocaleNeutral(row: row, localeCode: "de", localeState: localeState),
            "An entry under an inactive style draws nothing"
        )
    }

    @Test(arguments: [(false, 0.0), (true, 0.0), (false, 4.0), (true, 4.0)])
    func exportDrawsEachLanguagesBackground(spanning: Bool, blur: Double) async throws {
        let row = makeImageRow(spanning: spanning, blur: blur)
        let tempDir = makeTemporaryDataDirectory(label: "locale-bg-export")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let export = try await ExportService.exportAll(
            rows: [row],
            projectName: "TestProject",
            to: tempDir,
            source: InMemoryRenderSource(localeState: localeState, images: images)
        )

        func files(_ locale: String) -> [URL] {
            export.fileURLs
                .filter { $0.pathComponents.contains(locale) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        #expect(files("en").count == 2 && files("de").count == 2)
        for (index, url) in files("en").enumerated() {
            expectRed(try centerPixel(try Data(contentsOf: url)), "en template \(index)")
        }
        for (index, url) in files("de").enumerated() {
            expectGreen(try centerPixel(try Data(contentsOf: url)), "de template \(index)")
        }
    }

    @Test func templateOverrideBackgroundIsPerLanguage() async throws {
        var row = makeTestRow(label: "Bg", templateCount: 2, bgColor: .white)
        row.templates[1].overrideBackground = true
        row.templates[1].backgroundStyle = .image
        row.templates[1].backgroundImageConfig.fileName = "red.png"
        row.templates[1].backgroundImageConfig.localeImages = ["de": BackgroundImageSource(fileName: "green.png")]
        let source = InMemoryRenderSource(localeState: localeState, images: images)
        var cache: [String: NSImage] = [:]

        var contexts: [RowRenderContext] = []
        let en = RowRenderContext.load(row: row, localeCode: "en", from: source, label: "en", cache: &cache, reusing: &contexts)
        let de = RowRenderContext.load(row: row, localeCode: "de", from: source, label: "de", cache: &cache, reusing: &contexts)
        #expect(contexts.count == 2, "Different background images get their own context")

        expectRed(try centerPixel(try #require(en.templateData(at: 1, format: .png))), "en")
        expectGreen(try centerPixel(try #require(de.templateData(at: 1, format: .png))), "de")
    }
}

// MARK: - Editing

@MainActor
struct LocaleBackgroundImageEditingTests {
    private func makeState() throws -> (AppState, URL, UUID) {
        let (state, tempDir) = makeTestState()
        let rowId = try #require(state.rows.first?.id)
        state.rows[0].backgroundStyle = .image
        state.saveBackgroundImage(makeSolidImage(.red, width: 20, height: 20), for: rowId)
        state.addLocale(.init(code: "fr", label: "French"))
        return (state, tempDir, rowId)
    }

    @Test func imageSetInLanguageIsThatLanguagesOnly() throws {
        let (state, tempDir, rowId) = try makeState()
        defer { cleanupTestState(tempDir) }
        let base = try #require(state.rows[0].backgroundImageConfig.fileName)

        state.saveBackgroundImage(makeSolidImage(.green, width: 20, height: 20), for: rowId)

        let config = state.rows[0].backgroundImageConfig
        #expect(config.fileName == base, "The base image is untouched")
        let french = try #require(config.localeImages["fr"]?.fileName)
        #expect(french != base)
        #expect(state.backgroundImageIsOverridden(forRowAt: 0, templateIndex: nil) == true)
        #expect(state.editorReferencedImageFileNames().contains(french))
        #expect(
            state.editorReferencedImageFileNames().contains(base),
            "The base stays loaded so resetting or undoing back to it draws without a reload"
        )

        try #require(state.undoManager).undo()
        #expect(state.rows[0].backgroundImageConfig.localeImages.isEmpty)
    }

    @Test func firstImageInLanguageAlsoSeedsBase() throws {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        let rowId = try #require(state.rows.first?.id)
        state.addLocale(.init(code: "fr", label: "French"))

        state.saveBackgroundImage(makeSolidImage(.green, width: 20, height: 20), for: rowId, templateIndex: 0)

        let config = state.rows[0].templates[0].backgroundImageConfig
        #expect(config.fileName != nil)
        #expect(config.localeImages["fr"]?.fileName == config.fileName)
    }

    @Test func removeAndResetClearOnlyTheLanguagesImage() throws {
        let (state, tempDir, rowId) = try makeState()
        defer { cleanupTestState(tempDir) }
        let base = state.rows[0].backgroundImageConfig.fileName
        state.saveBackgroundImage(makeSolidImage(.green, width: 20, height: 20), for: rowId)
        let french = try #require(state.rows[0].backgroundImageConfig.localeImages["fr"]?.fileName)

        state.removeBackgroundImage(for: rowId)

        #expect(state.rows[0].backgroundImageConfig.localeImages.isEmpty)
        #expect(state.rows[0].backgroundImageConfig.fileName == base)
        #expect(!state.isImageFileReferenced(french))
    }

    @Test func resetLanguageToBaseAndRemoveLanguageDropBackgroundImages() throws {
        let (state, tempDir, rowId) = try makeState()
        defer { cleanupTestState(tempDir) }
        #expect(!state.activeLocaleHasAnyOverrides)
        state.saveBackgroundImage(makeSolidImage(.green, width: 20, height: 20), for: rowId)
        #expect(state.activeLocaleHasAnyOverrides)

        state.resetActiveLocaleToBase()
        #expect(state.rows[0].backgroundImageConfig.localeImages.isEmpty)

        state.saveBackgroundImage(makeSolidImage(.green, width: 20, height: 20), for: rowId)
        let french = try #require(state.rows[0].backgroundImageConfig.localeImages["fr"]?.fileName)
        state.removeLocale("fr")
        #expect(state.rows[0].backgroundImageConfig.localeImages.isEmpty)
        #expect(!state.isImageFileReferenced(french))
    }

    @Test func settingBaseLanguagePromotesItsImage() throws {
        let (state, tempDir, rowId) = try makeState()
        defer { cleanupTestState(tempDir) }
        let english = try #require(state.rows[0].backgroundImageConfig.fileName)
        state.saveBackgroundImage(makeSolidImage(.green, width: 20, height: 20), for: rowId)
        let french = try #require(state.rows[0].backgroundImageConfig.localeImages["fr"]?.fileName)

        state.setBaseLocale("fr")

        let config = state.rows[0].backgroundImageConfig
        #expect(config.fileName == french)
        #expect(config.localeImages == ["en": BackgroundImageSource(fileName: english)])
    }
}
