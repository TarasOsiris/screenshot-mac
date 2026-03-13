import Foundation

struct Project: Identifiable, Codable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
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
}
