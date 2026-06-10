import Testing
import Foundation
import AppKit
@testable import Screenshot_Bro

@Suite(.serialized)
struct TranslationCatalogTests {

    private func textShape(_ text: String, id: UUID = UUID()) -> CanvasShapeModel {
        CanvasShapeModel(id: id, type: .text, x: 0, y: 0, width: 300, height: 50, text: text)
    }

    private func state(locales: [(String, String)], overrides: [String: [String: ShapeLocaleOverride]] = [:]) -> LocaleState {
        LocaleState(
            locales: locales.map { .init(code: $0.0, label: $0.1) },
            activeLocaleCode: locales.first!.0,
            overrides: overrides
        )
    }

    // MARK: - build

    @Test func buildMirrorsBaseStringAndTranslations() {
        let shape = textShape("Hello")
        let row = ScreenshotRow(label: "Hero", shapes: [shape])
        let ls = state(
            locales: [("en", "English"), ("fr", "French")],
            overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
        )

        let catalog = TranslationCatalog.build(rows: [row], localeState: ls)

        #expect(catalog.sourceLanguage == "en")
        let entry = catalog.strings[shape.id.uuidString]
        #expect(entry?.localizations["en"]?.stringUnit.value == "Hello")
        #expect(entry?.localizations["fr"]?.stringUnit.value == "Bonjour")
        #expect(entry?.comment == "Row: Hero")
    }

    @Test func buildSkipsEmptyAndNonTextShapes() {
        let empty = textShape("   ")
        let rect = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 10, height: 10)
        let real = textShape("Track every match")
        let row = ScreenshotRow(label: "Row", shapes: [empty, rect, real])

        let catalog = TranslationCatalog.build(rows: [row], localeState: state(locales: [("en", "English")]))

        #expect(catalog.strings.count == 1)
        #expect(catalog.strings[real.id.uuidString] != nil)
        #expect(catalog.strings[empty.id.uuidString] == nil)
        #expect(catalog.strings[rect.id.uuidString] == nil)
    }

    @Test func buildFlattensRichTextOnlyTranslationToPlain() {
        let shape = textShape("Hello")
        let row = ScreenshotRow(label: "Row", shapes: [shape])
        let rtf = RichTextUtils.encode(NSAttributedString(string: "Hola"))!
        let ls = state(
            locales: [("en", "English"), ("es", "Spanish")],
            overrides: ["es": [shape.id.uuidString: ShapeLocaleOverride(richText: rtf)]]
        )

        let catalog = TranslationCatalog.build(rows: [row], localeState: ls)

        #expect(catalog.strings[shape.id.uuidString]?.localizations["es"]?.stringUnit.value == "Hola")
    }

    @Test func encodeDecodeRoundTripPreservesStrings() throws {
        let shape = textShape("Hello")
        let row = ScreenshotRow(label: "Hero", shapes: [shape])
        let ls = state(
            locales: [("en", "English"), ("fr", "French"), ("ja", "Japanese")],
            overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")],
                        "ja": [shape.id.uuidString: ShapeLocaleOverride(text: "こんにちは")]]
        )
        let catalog = TranslationCatalog.build(rows: [row], localeState: ls)

        let data = try JSONEncoder().encode(catalog)
        let decoded = try JSONDecoder().decode(TranslationCatalog.self, from: data)

        #expect(decoded == catalog)
    }

    // MARK: - apply

    @Test func applyTakesCatalogTextAndClearsRichText() {
        let id = UUID()
        var ls = state(
            locales: [("en", "English"), ("fr", "French")],
            overrides: ["fr": [id.uuidString: ShapeLocaleOverride(offsetX: 12, richText: "stale-rtf")]]
        )
        let catalog = TranslationCatalog(sourceLanguage: "en", strings: [
            id.uuidString: .init(comment: nil, localizations: [
                "en": .init(stringUnit: .init(state: "translated", value: "Hello")),
                "fr": .init(stringUnit: .init(state: "translated", value: "Bonjour"))
            ])
        ])

        catalog.apply(to: &ls)

        let override = ls.override(forCode: "fr", shapeId: id)
        #expect(override?.text == "Bonjour")
        #expect(override?.richText == nil)
        #expect(override?.offsetX == 12, "Non-text override fields are preserved")
    }

    @Test func applyEmptyCatalogValueClearsExistingTranslation() {
        let id = UUID()
        var ls = state(
            locales: [("en", "English"), ("fr", "French")],
            overrides: ["fr": [id.uuidString: ShapeLocaleOverride(offsetX: 12, text: "Bonjour")]]
        )
        let catalog = TranslationCatalog(sourceLanguage: "en", strings: [
            id.uuidString: .init(comment: nil, localizations: [
                "fr": .init(stringUnit: .init(state: "translated", value: ""))
            ])
        ])

        catalog.apply(to: &ls)

        let override = ls.override(forCode: "fr", shapeId: id)
        #expect(override?.text == nil)
        #expect(override?.offsetX == 12, "Non-text override fields are preserved")
    }

    @Test func applyIgnoresCatalogEntriesWithoutLiveTextKeys() {
        let deletedKey = UUID().uuidString
        var ls = state(locales: [("en", "English"), ("fr", "French")])
        let catalog = TranslationCatalog(sourceLanguage: "en", strings: [
            deletedKey: .init(comment: nil, localizations: [
                "fr": .init(stringUnit: .init(state: "translated", value: "Bonjour"))
            ])
        ])

        catalog.apply(to: &ls, validKeys: [])

        #expect(ls.overrides["fr"]?[deletedKey] == nil)
    }

    @Test func applyKeepsRichTextWhenCatalogMirrorsItsPlainValue() {
        let id = UUID()
        let rtf = RichTextUtils.encode(NSAttributedString(string: "Hola"))!
        var ls = state(
            locales: [("en", "English"), ("es", "Spanish")],
            overrides: ["es": [id.uuidString: ShapeLocaleOverride(text: "Hola", richText: rtf)]]
        )
        let catalog = TranslationCatalog(sourceLanguage: "en", strings: [
            id.uuidString: .init(comment: nil, localizations: [
                "es": .init(stringUnit: .init(state: "translated", value: "Hola"))
            ])
        ])

        catalog.apply(to: &ls)

        // The catalog only mirrors the plain text; the user's formatting must survive the round-trip.
        #expect(ls.override(forCode: "es", shapeId: id)?.richText == rtf)
    }

    @Test func applyReplacesRichTextWhenCatalogValueChanged() {
        let id = UUID()
        let rtf = RichTextUtils.encode(NSAttributedString(string: "Hola"))!
        var ls = state(
            locales: [("en", "English"), ("es", "Spanish")],
            overrides: ["es": [id.uuidString: ShapeLocaleOverride(text: "Hola", richText: rtf)]]
        )
        let catalog = TranslationCatalog(sourceLanguage: "en", strings: [
            id.uuidString: .init(comment: nil, localizations: [
                "es": .init(stringUnit: .init(state: "translated", value: "Buenas"))
            ])
        ])

        catalog.apply(to: &ls)

        let override = ls.override(forCode: "es", shapeId: id)
        #expect(override?.text == "Buenas")
        #expect(override?.richText == nil, "A genuine catalog edit drops the stale formatting")
    }

    @Test func applyIgnoresBaseLanguageAndUnknownLocales() {
        let id = UUID()
        var ls = state(locales: [("en", "English"), ("fr", "French")])
        let catalog = TranslationCatalog(sourceLanguage: "en", strings: [
            id.uuidString: .init(comment: nil, localizations: [
                "en": .init(stringUnit: .init(state: "translated", value: "EDITED BASE")),
                "de": .init(stringUnit: .init(state: "translated", value: "Hallo")) // de not in project
            ])
        ])

        catalog.apply(to: &ls)

        #expect(ls.override(forCode: "en", shapeId: id) == nil, "Base language is owned by the shape")
        #expect(ls.override(forCode: "de", shapeId: id) == nil, "Locales absent from the project are skipped")
    }

    // MARK: - PersistenceService integration

    @MainActor
    private func withTempDataDir(_ body: (UUID) throws -> Void) rethrows {
        let dir = makeTemporaryDataDirectory(label: "catalog-tests")
        setenv("SCREENSHOT_DATA_DIR", dir.path, 1)
        defer { unsetenv("SCREENSHOT_DATA_DIR"); try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        PersistenceService.ensureProjectDirs(id)
        try body(id)
    }

    @MainActor
    @Test func saveWritesCatalogAndRetainsInlineText() throws {
        try withTempDataDir { id in
            let shape = textShape("Hello")
            let ls = state(
                locales: [("en", "English"), ("fr", "French")],
                overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
            )
            try PersistenceService.saveProject(id, data: ProjectData(rows: [ScreenshotRow(label: "Hero", shapes: [shape])], localeState: ls))

            let catalog = try #require(TranslationCatalogService.read(projectId: id))
            #expect(catalog.strings[shape.id.uuidString]?.localizations["fr"]?.stringUnit.value == "Bonjour")

            // Dual-write: inline text must still live in project.json.
            let json = try String(contentsOf: PersistenceService.projectDataURL(id), encoding: .utf8)
            #expect(json.contains("Bonjour"))
        }
    }

    // Regression: saveProject must create the project directory itself. A multi-locale save into a
    // project whose directory was never materialized (iCloud index entry, skipped ensureProjectDirs)
    // used to throw "The folder 'project.json' doesn't exist."
    @MainActor
    @Test func saveCreatesProjectDirectoryWhenMissing() throws {
        let dir = makeTemporaryDataDirectory(label: "catalog-tests")
        setenv("SCREENSHOT_DATA_DIR", dir.path, 1)
        defer { unsetenv("SCREENSHOT_DATA_DIR"); try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        // Deliberately do NOT call ensureProjectDirs — the directory is absent.
        #expect(FileManager.default.fileExists(atPath: PersistenceService.projectDirectoryURL(id).path) == false)

        let shape = textShape("Hello")
        let ls = state(
            locales: [("en", "English"), ("fr", "French")],
            overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
        )
        try PersistenceService.saveProject(id, data: ProjectData(rows: [ScreenshotRow(label: "Hero", shapes: [shape])], localeState: ls))

        let loaded = try #require(PersistenceService.loadProject(id))
        #expect(loaded.localeState?.override(forCode: "fr", shapeId: shape.id)?.text == "Bonjour")
    }

    @MainActor
    @Test func loadMergesCatalogOverInlineText() throws {
        try withTempDataDir { id in
            let shape = textShape("Hello")
            let ls = state(
                locales: [("en", "English"), ("fr", "French")],
                overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
            )
            try PersistenceService.saveProject(id, data: ProjectData(rows: [ScreenshotRow(shapes: [shape])], localeState: ls))

            // Simulate a translator editing the catalog directly.
            var catalog = try #require(TranslationCatalogService.read(projectId: id))
            catalog.strings[shape.id.uuidString]?.localizations["fr"] = .init(stringUnit: .init(state: "translated", value: "Salut"))
            try TranslationCatalogService.write(catalog, projectId: id)

            let loaded = try #require(PersistenceService.loadProject(id))
            #expect(loaded.localeState?.override(forCode: "fr", shapeId: shape.id)?.text == "Salut")
        }
    }

    @MainActor
    @Test func loadWithoutCatalogKeepsInlineText() throws {
        try withTempDataDir { id in
            let shape = textShape("Hello")
            let ls = state(
                locales: [("en", "English"), ("fr", "French")],
                overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
            )
            // Write project.json directly, bypassing saveProject, so no catalog exists (old project).
            try PersistenceService.save(ProjectData(rows: [ScreenshotRow(shapes: [shape])], localeState: ls), to: PersistenceService.projectDataURL(id))
            #expect(FileManager.default.fileExists(atPath: PersistenceService.translationCatalogURL(id).path) == false)

            let loaded = try #require(PersistenceService.loadProject(id))
            #expect(loaded.localeState?.override(forCode: "fr", shapeId: shape.id)?.text == "Bonjour")
        }
    }

    @MainActor
    @Test func saveOverwritesStaleCatalogWhenNoTranslatableStringsRemain() throws {
        try withTempDataDir { id in
            let shape = textShape("Hello")
            let translated = state(
                locales: [("en", "English"), ("fr", "French")],
                overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
            )
            try PersistenceService.saveProject(
                id,
                data: ProjectData(rows: [ScreenshotRow(label: "Hero", shapes: [shape])], localeState: translated)
            )

            let emptyState = state(locales: [("en", "English"), ("fr", "French")])
            try PersistenceService.saveProject(
                id,
                data: ProjectData(rows: [ScreenshotRow(label: "Hero", shapes: [])], localeState: emptyState)
            )

            let catalog = try #require(TranslationCatalogService.read(projectId: id))
            #expect(catalog.strings.isEmpty)
            let loaded = try #require(PersistenceService.loadProject(id))
            #expect(loaded.localeState?.overrides.isEmpty == true)
        }
    }

    @MainActor
    @Test func saveThrowsWhenCatalogMirrorCannotBeWritten() throws {
        try withTempDataDir { id in
            try FileManager.default.createDirectory(
                at: PersistenceService.translationCatalogURL(id),
                withIntermediateDirectories: false
            )
            let shape = textShape("Hello")
            let ls = state(
                locales: [("en", "English"), ("fr", "French")],
                overrides: ["fr": [shape.id.uuidString: ShapeLocaleOverride(text: "Bonjour")]]
            )

            var didThrow = false
            do {
                try PersistenceService.saveProject(
                    id,
                    data: ProjectData(rows: [ScreenshotRow(label: "Hero", shapes: [shape])], localeState: ls)
                )
            } catch {
                didThrow = true
            }

            #expect(didThrow)
        }
    }
}
