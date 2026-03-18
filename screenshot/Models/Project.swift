import Foundation

struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        self.modifiedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case id, name, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }
}

extension Array where Element == Project {
    /// Merge two project lists by UUID. Union of both; last-writer-wins for duplicates.
    /// `base` ordering is preserved first, then `incoming`-only projects are appended.
    func merged(with incoming: [Project]) -> [Project] {
        var byId: [UUID: Project] = [:]
        for project in self {
            byId[project.id] = project
        }
        for project in incoming {
            if let existing = byId[project.id] {
                if project.modifiedAt > existing.modifiedAt {
                    byId[project.id] = project
                }
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
}

struct ProjectIndex: Codable {
    var projects: [Project]
    var activeProjectId: UUID?
}

struct ProjectData: Codable {
    var rows: [ScreenshotRow]
    var localeState: LocaleState?
    var modifiedAt: Date

    init(rows: [ScreenshotRow], localeState: LocaleState? = nil) {
        self.rows = rows
        self.localeState = localeState
        self.modifiedAt = Date()
    }

    enum CodingKeys: String, CodingKey {
        case rows, localeState, modifiedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decode([ScreenshotRow].self, forKey: .rows)
        localeState = try c.decodeIfPresent(LocaleState.self, forKey: .localeState)
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? .distantPast
    }
}
