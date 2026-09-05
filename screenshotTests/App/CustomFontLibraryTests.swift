import Foundation
@testable import Screenshot_Bro
import Testing

@MainActor
@Suite(.serialized)
struct CustomFontLibraryTests {

    private func withTempDataDir(_ body: () throws -> Void) rethrows {
        let dir = makeTemporaryDataDirectory(label: "custom-font-library-tests")
        setenv("SCREENSHOT_DATA_DIR", dir.path, 1)
        defer { unsetenv("SCREENSHOT_DATA_DIR"); try? FileManager.default.removeItem(at: dir) }
        try body()
    }

    /// Copies a real shipped font into a fresh project's resources, the way
    /// `PersistenceService.copySharedFonts` does, and returns the library that sees it.
    private func makeLibraryWithSharedFont(named fileName: String, projectId: UUID) throws -> (CustomFontLibrary, CustomFont) {
        let sharedFontsURL = try #require(TemplateService.sharedFontsURL)
        let source = sharedFontsURL.appendingPathComponent(fileName)
        let resources = PersistenceService.resourcesDir(projectId)
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let destination = resources.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: source, to: destination)

        let font = try #require(CustomFont.parseMetadata(at: destination))
        return (CustomFontLibrary(customFonts: [fileName: font]), font)
    }

    private func fontFileExists(_ fileName: String, projectId: UUID) -> Bool {
        FileManager.default.fileExists(atPath: PersistenceService.resourcesDir(projectId).appendingPathComponent(fileName).path)
    }

    private let dmSans = "DMSans-VariableFont_opsz,wght.ttf"

    @Test func reclaimRemovesAShippedFontTheProjectNeverUsed() throws {
        try withTempDataDir {
            let id = UUID()
            let (library, _) = try makeLibraryWithSharedFont(named: dmSans, projectId: id)

            library.reclaimUnusedSharedFonts(referenced: ["Avenir Next"], projectId: id)

            #expect(library.customFonts.isEmpty)
            #expect(!fontFileExists(dmSans, projectId: id))
        }
    }

    @Test func reclaimKeepsAShippedFontTheProjectUses() throws {
        try withTempDataDir {
            let id = UUID()
            let (library, font) = try makeLibraryWithSharedFont(named: dmSans, projectId: id)

            library.reclaimUnusedSharedFonts(referenced: [font.familyName], projectId: id)

            #expect(library.customFonts.keys.contains(dmSans))
            #expect(fontFileExists(dmSans, projectId: id))
        }
    }

    /// The file name is the only thing separating a font we copied in from one the user imported,
    /// and a user font that hasn't been applied yet must survive — that is what
    /// `cleanupUnreferenced`'s `everReferencedFontFamilies` guard protects, and this path skips it.
    @Test func reclaimKeepsAnUnreferencedFontWeDontShip() throws {
        try withTempDataDir {
            let id = UUID()
            let sharedFontsURL = try #require(TemplateService.sharedFontsURL)
            let resources = PersistenceService.resourcesDir(id)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            let imported = resources.appendingPathComponent("UserImported.ttf")
            try FileManager.default.copyItem(at: sharedFontsURL.appendingPathComponent(dmSans), to: imported)

            let font = try #require(CustomFont.parseMetadata(at: imported))
            let library = CustomFontLibrary(customFonts: ["UserImported.ttf": font])

            library.reclaimUnusedSharedFonts(referenced: [], projectId: id)

            #expect(library.customFonts.keys.contains("UserImported.ttf"))
            #expect(fontFileExists("UserImported.ttf", projectId: id))
        }
    }

    @Test func reclaimIsANoOpForAProjectWithNoFonts() throws {
        try withTempDataDir {
            let library = CustomFontLibrary()

            library.reclaimUnusedSharedFonts(referenced: [], projectId: UUID())

            #expect(library.customFonts.isEmpty)
        }
    }

    // MARK: - The hook

    /// The reclaim only pays off if `applyProjectData` reaches it with the loaded rows in hand.
    /// Seeds the shape 4.12 and earlier left on disk — a project carrying a bundled font it never
    /// references — and drives the real open path.
    @Test func openingAProjectHandsBackABundledFontItNeverUsed() throws {
        let id = UUID()
        let sharedFontsURL = try #require(TemplateService.sharedFontsURL)

        let (state, tempDir) = try makeTestStateSeedingDataDirectory { _ in
            let dir = PersistenceService.projectDirectoryURL(id)
            let resources = dir.appendingPathComponent("resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: sharedFontsURL.appendingPathComponent(dmSans),
                to: resources.appendingPathComponent(dmSans)
            )
            let row = ScreenshotRow(label: "Hero")
            let data = ProjectData(rows: [row], name: "Verdant")
            try PersistenceService.encoder.encode(data).write(to: dir.appendingPathComponent("project.json"), options: .atomic)
        }
        defer { cleanupTestState(tempDir) }

        state.activeProjectId = id
        state.loadCustomFonts()
        #expect(state.fonts.customFonts.keys.contains(dmSans))

        state.loadRowsForProject(id)

        #expect(state.fonts.customFonts.isEmpty)
        #expect(!fontFileExists(dmSans, projectId: id))
    }

    /// Same open path, but the document uses the font — it has to survive.
    @Test func openingAProjectKeepsABundledFontItUses() throws {
        let id = UUID()
        let sharedFontsURL = try #require(TemplateService.sharedFontsURL)

        let (state, tempDir) = try makeTestStateSeedingDataDirectory { _ in
            let dir = PersistenceService.projectDirectoryURL(id)
            let resources = dir.appendingPathComponent("resources", isDirectory: true)
            try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
            try FileManager.default.copyItem(
                at: sharedFontsURL.appendingPathComponent(dmSans),
                to: resources.appendingPathComponent(dmSans)
            )
            var row = ScreenshotRow(label: "Hero")
            row.shapes = [CanvasShapeModel(type: .text, text: "Hello", fontName: "DM Sans")]
            let data = ProjectData(rows: [row], name: "Aurora")
            try PersistenceService.encoder.encode(data).write(to: dir.appendingPathComponent("project.json"), options: .atomic)
        }
        defer { cleanupTestState(tempDir) }

        state.activeProjectId = id
        state.loadCustomFonts()
        state.loadRowsForProject(id)

        #expect(state.fonts.customFonts.keys.contains(dmSans))
        #expect(fontFileExists(dmSans, projectId: id))
    }
}
