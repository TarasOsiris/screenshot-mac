import Foundation

nonisolated struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var modifiedAt: Date
    var isDeleted: Bool
    var deletedAt: Date?
    var ascAppId: String?
    var googlePlayPackageName: String?
    var isStarred: Bool

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.modifiedAt = Date()
        self.isDeleted = false
        self.deletedAt = nil
        self.ascAppId = nil
        self.googlePlayPackageName = nil
        self.isStarred = false
    }

    enum CodingKeys: String, CodingKey {
        case id, name, modifiedAt, isDeleted, deletedAt, ascAppId, googlePlayPackageName, isStarred
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        modifiedAt = try c.decode(Date.self, forKey: .modifiedAt)
        isDeleted = try c.decodeIfPresent(Bool.self, forKey: .isDeleted) ?? false
        deletedAt = try c.decodeIfPresent(Date.self, forKey: .deletedAt)
        ascAppId = try c.decodeIfPresent(String.self, forKey: .ascAppId)
        googlePlayPackageName = try c.decodeIfPresent(String.self, forKey: .googlePlayPackageName)
        isStarred = try c.decodeIfPresent(Bool.self, forKey: .isStarred) ?? false
    }

    mutating func markDeleted() {
        let now = Date()
        isDeleted = true
        deletedAt = now
        modifiedAt = now
    }
}

nonisolated extension Array where Element == Project {
    /// Alphabetical order using localized, numeric-aware comparison (e.g. "App 2" before "App 10").
    func sortedByName() -> [Project] {
        sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

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
            result.append(byId[project.id] ?? project)
            seen.insert(project.id)
        }
        for project in incoming where !seen.contains(project.id) {
            result.append(byId[project.id] ?? project)
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

nonisolated struct ProjectIndex: Codable {
    var projects: [Project]
    var activeProjectId: UUID?
}

nonisolated struct ProjectData: Codable {
    var rows: [ScreenshotRow]
    var localeState: LocaleState?
    var modifiedAt: Date
    /// Mirrors the index entry (the source of truth) so a lost `projects.json` can be rebuilt with
    /// real names. Only refreshed when the project is saved, so a rename while closed leaves it stale.
    var name: String?

    enum CodingKeys: String, CodingKey {
        case rows = "r", localeState = "ls", modifiedAt = "m", name = "n"
    }

    init(rows: [ScreenshotRow], localeState: LocaleState? = nil, name: String? = nil) {
        self.rows = rows
        self.localeState = localeState
        self.modifiedAt = Date()
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decode([ScreenshotRow].self, forKey: .rows)
        localeState = try c.decodeIfPresent(LocaleState.self, forKey: .localeState)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
        name = try c.decodeIfPresent(String.self, forKey: .name)
    }
}

extension ProjectData {
    /// Font names exactly as the picker stored them on shapes and locale overrides. Deliberately
    /// not resolved through `CustomFontRegistry`: the copy path runs before this project's fonts
    /// are registered, so the registry still holds the outgoing project's. `CustomFont.identityKeys`
    /// is what closes the family-vs-display-name gap instead.
    nonisolated func referencedFontNames() -> Set<String> {
        var names = Set<String>()
        for row in rows {
            for shape in row.shapes {
                if let name = shape.fontName, !name.isEmpty { names.insert(name) }
            }
        }
        for shapeOverrides in (localeState?.overrides ?? [:]).values {
            for override in shapeOverrides.values {
                if let name = override.fontName, !name.isEmpty { names.insert(name) }
            }
        }
        return names
    }
}
