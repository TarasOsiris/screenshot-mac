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

    private func makeTemplateDirectory() throws -> URL {
        let source = makeTemporaryDataDirectory(label: "persistence-copy-source")
        let data = try PersistenceService.encoder.encode(ProjectData(rows: [ScreenshotRow(label: "Hero")]))
        try data.write(to: source.appendingPathComponent("project.json"), options: .atomic)
        return source
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
}
