import Foundation
@testable import Screenshot_Bro
import Testing

/// The index conflict path is the one place where discarding the losing version loses a project
/// outright: project *data* still sits in `projects/<uuid>/`, but nothing else records that the
/// project exists, and on any document last saved before 4.10 nothing else records its name.
struct IndexConflictRecoveryTests {

    private func writeIndex(_ projects: [Project], to directory: URL, named name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try PersistenceService.encoder.encode(ProjectIndex(projects: projects, activeProjectId: nil)).write(to: url)
        return url
    }

    private func project(_ name: String, modifiedAt: Date = Date()) -> Project {
        var project = Project(name: name)
        project.modifiedAt = modifiedAt
        return project
    }

    @Test func recoversProjectsFromEveryReadableVersion() throws {
        let dir = makeTemporaryDataDirectory(label: "index-conflict-tests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let mine = project("Mine")
        let theirs = project("Theirs")
        let urls = [
            try writeIndex([mine], to: dir, named: "a.json"),
            try writeIndex([theirs], to: dir, named: "b.json"),
        ]

        let (recovered, unreadable) = ICloudSyncService.shared.recoveredProjects(fromConflictVersionsAt: urls)

        #expect(unreadable == 0)
        #expect(Set(recovered.map(\.id)) == [mine.id, theirs.id])
    }

    /// Union by UUID, not concatenation — the same project in two versions is one project, and the
    /// newer edit is the one that survives.
    @Test func mergesTheSameProjectAcrossVersionsKeepingTheNewer() throws {
        let dir = makeTemporaryDataDirectory(label: "index-conflict-tests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = project("Old name", modifiedAt: Date(timeIntervalSince1970: 1_000))
        var renamed = old
        renamed.name = "New name"
        renamed.modifiedAt = Date(timeIntervalSince1970: 2_000)
        let urls = [
            try writeIndex([old], to: dir, named: "a.json"),
            try writeIndex([renamed], to: dir, named: "b.json"),
        ]

        let (recovered, _) = ICloudSyncService.shared.recoveredProjects(fromConflictVersionsAt: urls)

        #expect(recovered.count == 1)
        #expect(recovered.first?.name == "New name")
    }

    /// A deleted project must not come back from a peer's stale index.
    @Test func doesNotResurrectATombstonedProject() throws {
        let dir = makeTemporaryDataDirectory(label: "index-conflict-tests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let alive = project("Doomed", modifiedAt: Date(timeIntervalSince1970: 2_000))
        var deleted = alive
        deleted.markDeleted()
        let urls = [
            try writeIndex([alive], to: dir, named: "a.json"),
            try writeIndex([deleted], to: dir, named: "b.json"),
        ]

        let (recovered, _) = ICloudSyncService.shared.recoveredProjects(fromConflictVersionsAt: urls)

        #expect(recovered.count == 1)
        #expect(recovered.first?.isDeleted == true)
    }

    /// An unreadable version is the case that is still a real loss, and the only one that should
    /// still raise `iCloudConflictDiscardedVersions` — the readable ones no longer lose anything.
    @Test func countsVersionsItCouldNotRead() throws {
        let dir = makeTemporaryDataDirectory(label: "index-conflict-tests")
        defer { try? FileManager.default.removeItem(at: dir) }
        let good = try writeIndex([project("Kept")], to: dir, named: "a.json")
        let garbage = dir.appendingPathComponent("b.json")
        try Data("not an index".utf8).write(to: garbage)
        let absent = dir.appendingPathComponent("missing.json")

        let (recovered, unreadable) = ICloudSyncService.shared.recoveredProjects(
            fromConflictVersionsAt: [good, garbage, absent]
        )

        #expect(recovered.count == 1)
        #expect(unreadable == 2)
    }
}
