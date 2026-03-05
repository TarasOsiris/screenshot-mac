import SwiftUI

@Observable
final class AppState {
    var projects: [Project] = [
        Project(name: "My App")
    ]
    var activeProjectId: UUID?
    var rows: [ScreenshotRow] = []

    var activeProject: Project? {
        projects.first { $0.id == activeProjectId }
    }

    init() {
        activeProjectId = projects.first?.id
        rows = [makeDefaultRow()]
    }

    func createProject(name: String) {
        let project = Project(name: name)
        projects.append(project)
        activeProjectId = project.id
        rows = [makeDefaultRow()]
    }

    func selectProject(_ id: UUID) {
        activeProjectId = id
    }

    func renameProject(_ id: UUID, to name: String) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].name = name
        }
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        if activeProjectId == id {
            activeProjectId = projects.first?.id
        }
    }

    func addTemplate(to rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]
        let color = colors[rows[idx].templates.count % colors.count]
        rows[idx].templates.append(ScreenshotTemplate(backgroundColor: color))
    }

    func removeTemplate(_ templateId: UUID, from rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        rows[idx].templates.removeAll { $0.id == templateId }
    }

    private func makeDefaultRow() -> ScreenshotRow {
        ScreenshotRow(
            label: "Screenshot 1",
            templates: [
                ScreenshotTemplate(backgroundColor: .blue),
                ScreenshotTemplate(backgroundColor: .purple),
                ScreenshotTemplate(backgroundColor: .orange)
            ]
        )
    }
}
