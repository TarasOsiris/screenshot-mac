import Foundation

struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var modifiedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?
    var ascAppId: String?
    var isStarred: Bool

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.modifiedAt = Date()
        self.isDeleted = false
        self.deletedAt = nil
        self.ascAppId = nil
        self.isStarred = false
    }

    enum CodingKeys: String, CodingKey {
        case id, name, modifiedAt, isDeleted, deletedAt, ascAppId, isStarred
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        ascAppId = try c.decodeIfPresent(String.self, forKey: .ascAppId)
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
    }

    mutating func markDeleted() {
        let now = Date()
        isDeleted = true
        deletedAt = now
        modifiedAt = now
    }
}

extension Array where Element == Project {
    /// Merge two project lists by UUID. Union of both; tombstone-aware, delete-wins.
    ///
    /// For projects present in both lists:
    /// - Both alive: higher `modifiedAt` wins
    /// - Both deleted: later `deletedAt` wins
    /// - One deleted, one alive: the tombstone always wins until `purgingOldTombstones()`
    ///   drops it. A delete is an explicit user action and must stick across devices; we do
    ///   not resurrect on `modifiedAt > deletedAt` because the active project's `modifiedAt`
    ///   is bumped on every open/autosave, which would let an open copy out-race a real delete.
    ///
    /// `base` ordering is preserved first, then `incoming`-only projects are appended.
    func merged(with incoming: [Project]) -> [Project] {
        var byId: [UUID: Project] = [:]
        for project in self {
            byId[project.id] = project
        }
        for project in incoming {
            if let existing = byId[project.id] {
                byId[project.id] = Self.mergeWinner(existing, project)
            } else {
                byId[project.id] = project
            }
        }
        var seen = Set<UUID>()
        var result: [Project] = []
        for project in self {
            result.append(byId[project.id]!)
            seen.insert(project.id)
        }
        for project in incoming where !seen.contains(project.id) {
            result.append(byId[project.id]!)
        }
        return result
    }

    /// Determine the winning version of two copies of the same project.
    private static func mergeWinner(_ a: Project, _ b: Project) -> Project {
        switch (a.isDeleted, b.isDeleted) {
        case (false, false):
            return b.modifiedAt > a.modifiedAt ? b : a
        case (true, true):
            return (b.deletedAt ?? .distantPast) > (a.deletedAt ?? .distantPast) ? b : a
        case (true, false):
            return a
        case (false, true):
            return b
        }
    }

    /// Remove tombstones older than the given cutoff (default 30 days).
    func purgingOldTombstones(olderThan cutoff: Date = Date().addingTimeInterval(-30 * 24 * 60 * 60)) -> [Project] {
        filter { !$0.isDeleted || ($0.deletedAt ?? .distantPast) > cutoff }
    }
}

struct ProjectIndex: Codable {
    var projects: [Project]
    var activeProjectId: UUID?
}

struct ProjectData: Codable {
    var rows: [ScreenshotRow]
    var localeState: LocaleState?
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case rows = "r", localeState = "ls", modifiedAt = "m"
    }

    init(rows: [ScreenshotRow], localeState: LocaleState? = nil) {
        self.rows = rows
        self.localeState = localeState
        self.modifiedAt = Date()
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decode([ScreenshotRow].self, forKey: .rows)
        localeState = try c.decodeIfPresent(LocaleState.self, forKey: .localeState)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }
}
