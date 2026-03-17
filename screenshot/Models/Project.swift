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

struct ProjectIndex: Codable {
    var projects: [Project]
    var activeProjectId: UUID?
}

struct ProjectTemplate: Identifiable, Codable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct ProjectTemplateIndex: Codable {
    var templates: [ProjectTemplate]
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
