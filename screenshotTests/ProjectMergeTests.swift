import Testing
import Foundation
@testable import Screenshot_Bro

@Suite(.serialized)
struct ProjectMergeTests {

    private func project(_ name: String, modifiedAt: Date, isDeleted: Bool = false, deletedAt: Date? = nil) -> Project {
        var p = Project(name: name)
        p.modifiedAt = modifiedAt
        p.isDeleted = isDeleted
        p.deletedAt = deletedAt
        return p
    }

    private let t1 = Date(timeIntervalSince1970: 1000)
    private let t2 = Date(timeIntervalSince1970: 2000)
    private let t3 = Date(timeIntervalSince1970: 3000)

    // MARK: - Basic merge (no tombstones)

    @Test func mergeDisjointSets() {
        let a = [project("A", modifiedAt: t1)]
        let b = [project("B", modifiedAt: t1)]
        let merged = a.merged(with: b)
        #expect(merged.count == 2)
    }

    @Test func mergeLWWPicksNewer() {
        var p1 = project("Old", modifiedAt: t1)
        var p2 = project("New", modifiedAt: t2)
        p2 = Project(id: p1.id, name: "New")
        p2.modifiedAt = t2
        p1.modifiedAt = t1

        let merged = [p1].merged(with: [p2])
        #expect(merged.count == 1)
        #expect(merged[0].name == "New")
    }

    // MARK: - Tombstone wins over older alive

    @Test func tombstoneWinsOverOlderAlive() {
        let id = UUID()
        var alive = Project(id: id, name: "Alive")
        alive.modifiedAt = t1

        var deleted = Project(id: id, name: "Alive")
        deleted.modifiedAt = t2
        deleted.isDeleted = true
        deleted.deletedAt = t2

        let merged = [alive].merged(with: [deleted])
        #expect(merged.count == 1)
        #expect(merged[0].isDeleted == true)
    }

    // MARK: - Resurrection: alive modified after deletion wins

    @Test func resurrectionWhenModifiedAfterDeletion() {
        let id = UUID()
        var deleted = Project(id: id, name: "X")
        deleted.isDeleted = true
        deleted.deletedAt = t1
        deleted.modifiedAt = t1

        var alive = Project(id: id, name: "X Resurrected")
        alive.modifiedAt = t2

        let merged = [deleted].merged(with: [alive])
        #expect(merged.count == 1)
        #expect(merged[0].isDeleted == false)
        #expect(merged[0].name == "X Resurrected")
    }

    // MARK: - Both deleted: later deletedAt wins

    @Test func bothDeletedKeepsLater() {
        let id = UUID()
        var d1 = Project(id: id, name: "X")
        d1.isDeleted = true
        d1.deletedAt = t1
        d1.modifiedAt = t1

        var d2 = Project(id: id, name: "X")
        d2.isDeleted = true
        d2.deletedAt = t2
        d2.modifiedAt = t2

        let merged = [d1].merged(with: [d2])
        #expect(merged.count == 1)
        #expect(merged[0].deletedAt == t2)
    }

    // MARK: - Tombstone cleanup

    @Test func purgingRemovesOldTombstones() {
        let old = Date().addingTimeInterval(-31 * 24 * 60 * 60) // 31 days ago
        let recent = Date().addingTimeInterval(-1 * 24 * 60 * 60) // 1 day ago

        let oldTombstone = project("Old", modifiedAt: old, isDeleted: true, deletedAt: old)
        let recentTombstone = project("Recent", modifiedAt: recent, isDeleted: true, deletedAt: recent)
        let alive = project("Alive", modifiedAt: recent)

        let list = [oldTombstone, recentTombstone, alive]
        let purged = list.purgingOldTombstones()

        #expect(purged.count == 2)
        #expect(purged.contains(where: { $0.name == "Alive" }))
        #expect(purged.contains(where: { $0.name == "Recent" }))
        #expect(!purged.contains(where: { $0.name == "Old" }))
    }

    // MARK: - Ordering preserved

    @Test func mergePreservesBaseOrdering() {
        let a = project("A", modifiedAt: t1)
        let b = project("B", modifiedAt: t1)
        let c = project("C", modifiedAt: t1)

        let base = [a, b]
        let incoming = [c]

        let merged = base.merged(with: incoming)
        #expect(merged[0].name == "A")
        #expect(merged[1].name == "B")
        #expect(merged[2].name == "C")
    }

    @Test func legacyProjectIndexWithoutTombstoneFieldsDecodesAsAlive() throws {
        let projectId = UUID()
        let data = Data("""
        {
          "projects": [
            {
              "id": "\(projectId.uuidString)",
              "name": "Legacy Project",
              "modifiedAt": 1000
            }
          ],
          "activeProjectId": "\(projectId.uuidString)"
        }
        """.utf8)

        let index = try JSONDecoder().decode(ProjectIndex.self, from: data)

        #expect(index.projects.count == 1)
        #expect(index.projects[0].id == projectId)
        #expect(index.projects[0].isDeleted == false)
        #expect(index.projects[0].deletedAt == nil)
        #expect(index.activeProjectId == projectId)
    }
}

@MainActor
struct AppStateDeleteTests {
    private func makeState() -> (AppState, URL) { makeTestState() }
    private func cleanup(_ tempDir: URL) { cleanupTestState(tempDir) }

    @Test func deleteProjectCreatesTombstone() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        state.createProject(name: "Second")
        #expect(state.visibleProjects.count == 2)

        let toDelete = state.visibleProjects.first!.id
        state.deleteProject(toDelete)

        // Still in raw projects as tombstone
        #expect(state.projects.contains(where: { $0.id == toDelete && $0.isDeleted }))
        // Not in visible projects
        #expect(!state.visibleProjects.contains(where: { $0.id == toDelete }))
        #expect(state.visibleProjects.count == 1)
    }

    @Test func deleteLastProjectCreatesNewOne() {
        let (state, tempDir) = makeState()
        defer { cleanup(tempDir) }

        let onlyId = state.visibleProjects.first!.id
        state.deleteProject(onlyId)

        #expect(state.visibleProjects.count == 1)
        #expect(state.visibleProjects.first!.id != onlyId)
    }
}
