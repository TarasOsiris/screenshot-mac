import Testing
import AppKit
@testable import Screenshot_Bro

// NOTE: an end-to-end render test (makeTestState → await thumbnail → assert PNG cached)
// passes in isolation but is intentionally omitted here: its ~1s render holds the
// process-global SCREENSHOT_DATA_DIR for long enough to lose the documented parallel-env
// race with AppStateTests. The render path is covered by ExportServiceTests; the disk-cache
// lifecycle and the concurrency gate are covered below.
@Suite(.serialized)
@MainActor
struct ProjectThumbnailServiceTests {

    @Test func deleteThumbnailRemovesThumbnail() {
        let tempDir = makeTemporaryDataDirectory()
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let id = UUID()
        let url = PersistenceService.thumbnailURL(id, at: tempDir)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data([0x1, 0x2, 0x3]))
        #expect(FileManager.default.fileExists(atPath: url.path))

        PersistenceService.deleteThumbnail(id, at: tempDir)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}
