import Foundation
@testable import Screenshot_Bro
import Testing

@Suite(.serialized)
struct PersistenceCopyTests {

    private func withTempDataDir(_ body: (URL) throws -> Void) rethrows {
        let dir = makeTemporaryDataDirectory(label: "persistence-copy-tests")
        setenv("SCREENSHOT_DATA_DIR", dir.path, 1)
        defer { unsetenv("SCREENSHOT_DATA_DIR"); try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    private func makeTemplateDirectory(fontName: String? = nil) throws -> URL {
        let source = makeTemporaryDataDirectory(label: "persistence-copy-source")
        var row = ScreenshotRow(label: "Hero")
        if let fontName {
            row.shapes = [CanvasShapeModel(type: .text, text: "Hello", fontName: fontName)]
        }
        let data = try PersistenceService.encoder.encode(ProjectData(rows: [row]))
        try data.write(to: source.appendingPathComponent("project.json"), options: .atomic)
        return source
    }

    private func copiedFontFileNames(for id: UUID) -> Set<String> {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: PersistenceService.resourcesDir(id),
            includingPropertiesForKeys: nil
        )) ?? []
        return Set(
            files
                .filter { CustomFontLibrary.fontExtensions.contains($0.pathExtension.lowercased()) }
                .map(\.lastPathComponent)
        )
    }

    private func shippedSharedFontFileNames() throws -> Set<String> {
        let sharedFontsURL = try #require(TemplateService.sharedFontsURL)
        let files = try FileManager.default.contentsOfDirectory(
            at: sharedFontsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return Set(files.map(\.lastPathComponent))
    }

    @Test func copyFromURLSucceedsWhenProjectsDirectoryIsMissing() throws {
        try withTempDataDir { root in
            let source = try makeTemplateDirectory()
            defer { try? FileManager.default.removeItem(at: source) }
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("projects").path))

            let id = UUID()
            #expect(PersistenceService.copyProjectFromURL(source, to: id))
            #expect(PersistenceService.loadProject(id) != nil)
        }
    }

    @Test func copyFromURLReportsFailureForAMissingSource() throws {
        try withTempDataDir { _ in
            let missing = makeTemporaryDataDirectory(label: "persistence-copy-source")
                .appendingPathComponent("nope", isDirectory: true)

            #expect(!PersistenceService.copyProjectFromURL(missing, to: UUID()))
        }
    }

    /// verdant-calm's exact shape: every text shape on a system family, so none of the bundled
    /// fonts belong in the project. Copying all four is what put ~1.2 MB of dead weight in it.
    @Test func copyFromURLCopiesNoSharedFontsForASystemFontTemplate() throws {
        try withTempDataDir { _ in
            let source = try makeTemplateDirectory(fontName: "Avenir Next")
            defer { try? FileManager.default.removeItem(at: source) }

            let id = UUID()
            #expect(PersistenceService.copyProjectFromURL(source, to: id))
            #expect(copiedFontFileNames(for: id).isEmpty)
        }
    }

    @Test func copyFromURLCopiesOnlyTheFontMatchedByFamilyName() throws {
        try withTempDataDir { _ in
            let source = try makeTemplateDirectory(fontName: "DM Sans")
            defer { try? FileManager.default.removeItem(at: source) }

            let id = UUID()
            #expect(PersistenceService.copyProjectFromURL(source, to: id))
            #expect(copiedFontFileNames(for: id) == ["DMSans-VariableFont_opsz,wght.ttf"])
        }
    }

    /// The picker writes a style-qualified display name, which is not the file's family name —
    /// matching on the family alone would silently drop this template's font.
    @Test func copyFromURLCopiesOnlyTheFontMatchedByDisplayName() throws {
        try withTempDataDir { _ in
            let source = try makeTemplateDirectory(fontName: "Playfair Display Italic")
            defer { try? FileManager.default.removeItem(at: source) }

            let id = UUID()
            #expect(PersistenceService.copyProjectFromURL(source, to: id))
            #expect(copiedFontFileNames(for: id) == ["PlayfairDisplay-Italic-VariableFont_wght.ttf"])
        }
    }

    private func bundledTemplateURL(_ name: String) throws -> URL {
        let bundleURL = try #require(Bundle.main.url(forResource: "Templates", withExtension: "bundle"))
        let templateURL = bundleURL.appendingPathComponent(name, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: templateURL.appendingPathComponent("project.json").path))
        return templateURL
    }

    /// The bug as reported: verdant-calm is entirely Avenir Next, and used to land four fonts.
    @Test func copyingTheRealVerdantCalmTemplateCopiesNoFonts() throws {
        try withTempDataDir { _ in
            let template = try bundledTemplateURL("verdant-calm")
            let id = UUID()
            #expect(PersistenceService.copyProjectFromURL(template, to: id))
            #expect(copiedFontFileNames(for: id).isEmpty)
        }
    }

    /// The other end of the range: a template that genuinely uses three of the four still gets them.
    @Test func copyingTheRealPaperTemplateCopiesTheThreeFontsItUses() throws {
        try withTempDataDir { _ in
            let template = try bundledTemplateURL("paper")
            let id = UUID()
            #expect(PersistenceService.copyProjectFromURL(template, to: id))
            #expect(copiedFontFileNames(for: id) == [
                "DMSans-VariableFont_opsz,wght.ttf",
                "PlayfairDisplay-Italic-VariableFont_wght.ttf",
                "Tinos-Bold.ttf",
            ])
        }
    }

    @Test func copyFromURLCopiesEverySharedFontWhenTheProjectCannotBeDecoded() throws {
        try withTempDataDir { _ in
            let source = makeTemporaryDataDirectory(label: "persistence-copy-source")
            defer { try? FileManager.default.removeItem(at: source) }
            try Data("not json".utf8).write(to: source.appendingPathComponent("project.json"), options: .atomic)

            let id = UUID()
            #expect(PersistenceService.copyProjectFromURL(source, to: id))
            #expect(copiedFontFileNames(for: id) == (try shippedSharedFontFileNames()))
        }
    }
}
