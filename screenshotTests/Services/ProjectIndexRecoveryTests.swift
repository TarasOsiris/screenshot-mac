import Foundation
@testable import Screenshot_Bro
import Testing

/// The index is the one file whose loss hides every project even though each project's data is
/// still on disk, so both halves are covered here: the write can't fail for a missing directory,
/// and a lost index rebuilds from `projects/`.
@Suite(.serialized)
struct ProjectIndexRecoveryTests {

    private func withTempDataDir(_ body: (URL) throws -> Void) rethrows {
        let dir = makeTemporaryDataDirectory(label: "project-index-recovery-tests")
        setenv("SCREENSHOT_DATA_DIR", dir.path, 1)
        defer { unsetenv("SCREENSHOT_DATA_DIR"); try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @discardableResult
    private func writeProject(_ id: UUID, name: String?, modifiedAt: Date = Date()) throws -> URL {
        let dir = PersistenceService.projectDirectoryURL(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var data = ProjectData(rows: [ScreenshotRow(label: "Hero")], name: name)
        data.modifiedAt = modifiedAt
        let encoded = try PersistenceService.encoder.encode(data)
        let url = dir.appendingPathComponent("project.json")
        try encoded.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Self-healing writes

    @Test func saveIndexRecreatesADeletedRoot() throws {
        try withTempDataDir { root in
            try FileManager.default.removeItem(at: root)
            #expect(!FileManager.default.fileExists(atPath: root.path))

            try PersistenceService.saveIndex(ProjectIndex(projects: [], activeProjectId: nil))

            #expect(FileManager.default.fileExists(atPath: PersistenceService.indexURL.path))
        }
    }

    @Test func saveIndexAtRootRecreatesADeletedRoot() throws {
        try withTempDataDir { _ in
            let destination = makeTemporaryDataDirectory(label: "project-index-recovery-dest")
            try FileManager.default.removeItem(at: destination)
            defer { try? FileManager.default.removeItem(at: destination) }

            try PersistenceService.saveIndex(ProjectIndex(projects: [], activeProjectId: nil), at: destination)

            #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("projects.json").path))
        }
    }

    // MARK: - Rebuild

    @Test func rebuildRecoversProjectsWithTheirPersistedNames() throws {
        try withTempDataDir { _ in
            let older = UUID()
            let newer = UUID()
            try writeProject(older, name: "Older App", modifiedAt: Date(timeIntervalSince1970: 1_000))
            try writeProject(newer, name: "Newer App", modifiedAt: Date(timeIntervalSince1970: 2_000))

            let rebuilt = try #require(PersistenceService.rebuildIndexFromProjectDirs())

            #expect(rebuilt.projects.count == 2)
            #expect(rebuilt.projects.map(\.name) == ["Newer App", "Older App"])
            #expect(rebuilt.activeProjectId == newer)
            #expect(rebuilt.projects.first?.modifiedAt == Date(timeIntervalSince1970: 2_000))
        }
    }

    @Test func rebuildFallsBackToAPlaceholderNameForProjectsSavedBeforeTheNameShipped() throws {
        try withTempDataDir { _ in
            try writeProject(UUID(), name: nil)

            let rebuilt = try #require(PersistenceService.rebuildIndexFromProjectDirs())

            #expect(rebuilt.projects.count == 1)
            #expect(rebuilt.projects[0].name == String(localized: "Recovered Project"))
        }
    }

    @Test func rebuildSkipsJunkInsteadOfFailing() throws {
        try withTempDataDir { _ in
            let good = UUID()
            try writeProject(good, name: "Real")

            let projectsDir = PersistenceService.projectDirectoryURL(good).deletingLastPathComponent()
            let notAUUID = projectsDir.appendingPathComponent("scratch", isDirectory: true)
            try FileManager.default.createDirectory(at: notAUUID, withIntermediateDirectories: true)
            try Data("{".utf8).write(to: notAUUID.appendingPathComponent("project.json"))

            let undecodable = PersistenceService.projectDirectoryURL(UUID())
            try FileManager.default.createDirectory(at: undecodable, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: undecodable.appendingPathComponent("project.json"))

            let empty = PersistenceService.projectDirectoryURL(UUID())
            try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

            let rebuilt = try #require(PersistenceService.rebuildIndexFromProjectDirs())

            #expect(rebuilt.projects.map(\.id) == [good])
        }
    }

    @Test func rebuildReturnsNilWhenThereIsNothingToRecover() {
        withTempDataDir { _ in
            #expect(PersistenceService.rebuildIndexFromProjectDirs() == nil)
        }
    }

    // MARK: - loadIndexOrRecover

    @Test func loadPrefersTheIndexOnDisk() throws {
        try withTempDataDir { _ in
            let id = UUID()
            try writeProject(id, name: "On Disk")
            try PersistenceService.saveIndex(ProjectIndex(projects: [Project(id: id, name: "From Index")], activeProjectId: id))

            let loaded = try #require(PersistenceService.loadIndexOrRecover())

            #expect(!loaded.wasRecovered)
            #expect(loaded.index.projects.map(\.name) == ["From Index"])
        }
    }

    @Test func loadRecoversWhenTheIndexIsAbsent() throws {
        try withTempDataDir { _ in
            let id = UUID()
            try writeProject(id, name: "Survivor")

            let loaded = try #require(PersistenceService.loadIndexOrRecover())

            #expect(loaded.wasRecovered)
            #expect(loaded.index.projects.map(\.id) == [id])
        }
    }

    @Test func loadRecoversAnUnreadableIndexAndKeepsTheBytesItCouldNotParse() throws {
        try withTempDataDir { _ in
            let id = UUID()
            try writeProject(id, name: "Survivor")
            try FileManager.default.createDirectory(
                at: PersistenceService.indexURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("}} not an index".utf8).write(to: PersistenceService.indexURL, options: .atomic)

            let loaded = try #require(PersistenceService.loadIndexOrRecover())

            #expect(loaded.wasRecovered)
            #expect(loaded.index.projects.map(\.id) == [id])
            let backup = PersistenceService.indexURL.appendingPathExtension("corrupt")
            #expect(FileManager.default.fileExists(atPath: backup.path))
            #expect(try Data(contentsOf: backup) == Data("}} not an index".utf8))
        }
    }

    /// The guard that stops an index which merely hasn't downloaded from being replaced by an
    /// empty one: no decodable project directory means no rebuild, so the caller keeps its list.
    @Test func loadReturnsNilWhenTheIndexIsGoneAndThereIsNothingToRebuildFrom() {
        withTempDataDir { _ in
            #expect(PersistenceService.loadIndexOrRecover() == nil)
        }
    }

    // MARK: - Launch path

    /// The wiring, not just the service: a launch that finds project directories but no index has
    /// to show the projects *and* write the rebuilt index back, or the next launch recovers again.
    @MainActor
    @Test func launchingWithAMissingIndexRecoversTheProjectsAndPersistsTheRebuild() throws {
        let id = UUID()
        let (state, tempDir) = try makeTestStateSeedingDataDirectory { _ in
            try writeProject(id, name: "Rescued App")
            #expect(!FileManager.default.fileExists(atPath: PersistenceService.indexURL.path))
        }
        defer { cleanupTestState(tempDir) }

        #expect(state.projects.map(\.id) == [id])
        #expect(state.projects.map(\.name) == ["Rescued App"])
        #expect(state.activeProjectId == id)

        let rewritten = try #require(PersistenceService.loadIndex())
        #expect(rewritten.projects.map(\.id) == [id])
    }

    // MARK: - Backward compatibility

    @Test func projectDataWithoutTheNameKeyStillDecodes() throws {
        let legacy = Data(#"{"r":[],"m":123.0}"#.utf8)

        let decoded = try PersistenceService.decoder.decode(ProjectData.self, from: legacy)

        #expect(decoded.name == nil)
        #expect(decoded.rows.isEmpty)
    }
}
