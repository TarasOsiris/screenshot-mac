import SwiftUI

@Observable
final class AppState {
    var projects: [Project] = [
        Project(name: "My App")
    ]
    var activeProjectId: UUID?
    var rows: [ScreenshotRow] = []
    var selectedRowId: UUID?

    var activeProject: Project? {
        projects.first { $0.id == activeProjectId }
    }

    var selectedRow: ScreenshotRow? {
        rows.first { $0.id == selectedRowId }
    }

    var selectedRowIndex: Int? {
        rows.firstIndex { $0.id == selectedRowId }
    }

    init() {
        activeProjectId = projects.first?.id
        rows = [makeDefaultRow()]
        selectedRowId = rows.first?.id
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

    func addRow() {
        let row = makeDefaultRow(label: "Screenshot \(rows.count + 1)")
        rows.append(row)
        selectedRowId = row.id
    }

    func duplicateRow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        let source = rows[idx]
        var copy = ScreenshotRow(
            label: "\(source.label) copy",
            templates: source.templates.map { ScreenshotTemplate(backgroundColor: $0.backgroundColor) },
            templateWidth: source.templateWidth,
            templateHeight: source.templateHeight,
            bgColor: source.bgColor,
            showDevice: source.showDevice
        )
        rows.insert(copy, at: idx + 1)
        selectedRowId = copy.id
    }

    func deleteRow(_ id: UUID) {
        guard rows.count > 1 else { return }
        let idx = rows.firstIndex { $0.id == id }
        rows.removeAll { $0.id == id }
        if selectedRowId == id {
            if let idx, idx < rows.count {
                selectedRowId = rows[idx].id
            } else {
                selectedRowId = rows.last?.id
            }
        }
    }

    func moveRowUp(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        rows.swapAt(idx, idx - 1)
    }

    func moveRowDown(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), idx < rows.count - 1 else { return }
        rows.swapAt(idx, idx + 1)
    }

    private func makeDefaultRow(label: String = "Screenshot 1") -> ScreenshotRow {
        ScreenshotRow(
            label: label,
            templates: [
                ScreenshotTemplate(backgroundColor: .blue),
                ScreenshotTemplate(backgroundColor: .purple),
                ScreenshotTemplate(backgroundColor: .orange)
            ]
        )
    }
}
