import SwiftUI

@Observable
final class AppState {
    var projects: [Project] = []
    var activeProjectId: UUID?
    var rows: [ScreenshotRow] = []
    var selectedRowId: UUID?
    var selectedShapeId: UUID?
    var zoomLevel: CGFloat = 1.0

    private var saveTask: DispatchWorkItem?

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
        PersistenceService.ensureDirectories()
        load()
    }

    // MARK: - Load

    private func load() {
        if let index = PersistenceService.loadIndex() {
            projects = index.projects
            activeProjectId = index.activeProjectId

            if let activeId = activeProjectId {
                loadRowsForProject(activeId)
            }
        }

        if projects.isEmpty {
            let project = Project(name: "My App")
            projects = [project]
            activeProjectId = project.id
            PersistenceService.ensureProjectDirs(project.id)
            rows = [makeDefaultRow()]
            selectedRowId = rows.first?.id
            saveAll()
        }
    }

    // MARK: - Save

    func scheduleSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.saveAll()
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    private func saveAll() {
        saveIndex()
        saveCurrentProject()
    }

    private func saveIndex() {
        let index = ProjectIndex(projects: projects, activeProjectId: activeProjectId)
        PersistenceService.saveIndex(index)
    }

    private func saveCurrentProject() {
        guard let activeId = activeProjectId else { return }
        PersistenceService.saveProject(activeId, data: ProjectData(rows: rows))
    }

    // MARK: - Projects

    func createProject(name: String) {
        saveCurrentProject()

        let project = Project(name: name)
        projects.append(project)
        activeProjectId = project.id
        PersistenceService.ensureProjectDirs(project.id)
        rows = [makeDefaultRow()]
        selectedRowId = rows.first?.id
        saveAll()
    }

    func selectProject(_ id: UUID) {
        guard id != activeProjectId else { return }

        saveCurrentProject()

        activeProjectId = id
        loadRowsForProject(id)
        saveIndex()
    }

    func renameProject(_ id: UUID, to name: String) {
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].name = name
            scheduleSave()
        }
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        PersistenceService.deleteProject(id)

        if activeProjectId == id {
            activeProjectId = projects.first?.id
            if let activeId = activeProjectId {
                loadRowsForProject(activeId)
            } else {
                rows = [makeDefaultRow()]
                selectedRowId = rows.first?.id
            }
        }
        saveAll()
    }

    // MARK: - Templates

    func addTemplate(to rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]
        let color = colors[rows[idx].templates.count % colors.count]
        rows[idx].templates.append(ScreenshotTemplate(backgroundColor: color))
        scheduleSave()
    }

    func removeTemplate(_ templateId: UUID, from rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        rows[idx].templates.removeAll { $0.id == templateId }
        scheduleSave()
    }

    // MARK: - Rows

    func addRow() {
        let row = makeDefaultRow(label: "Screenshot \(rows.count + 1)")
        rows.append(row)
        selectedRowId = row.id
        scheduleSave()
    }

    func duplicateRow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        let source = rows[idx]
        let copy = ScreenshotRow(
            label: "\(source.label) copy",
            templates: source.templates.map { ScreenshotTemplate(backgroundColor: $0.bgColor) },
            templateWidth: source.templateWidth,
            templateHeight: source.templateHeight,
            bgColor: source.bgColor,
            showDevice: source.showDevice,
            showBorders: source.showBorders,
            shapes: source.shapes.map { $0.duplicated() }
        )
        rows.insert(copy, at: idx + 1)
        selectedRowId = copy.id
        scheduleSave()
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
        scheduleSave()
    }

    func moveRowUp(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        rows.swapAt(idx, idx - 1)
        scheduleSave()
    }

    func moveRowDown(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), idx < rows.count - 1 else { return }
        rows.swapAt(idx, idx + 1)
        scheduleSave()
    }

    // MARK: - Shapes

    func addShape(_ shape: CanvasShapeModel) {
        guard let idx = selectedRowIndex else { return }
        rows[idx].shapes.append(shape)
        selectedShapeId = shape.id
        scheduleSave()
    }

    func updateShape(_ shape: CanvasShapeModel) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        rows[rowIdx].shapes[shapeIdx] = shape
        scheduleSave()
    }

    func deleteShape(_ id: UUID) {
        guard let rowIdx = selectedRowIndex else { return }
        rows[rowIdx].shapes.removeAll { $0.id == id }
        if selectedShapeId == id {
            selectedShapeId = nil
        }
        scheduleSave()
    }

    func duplicateSelectedShape() {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == selectedShapeId }) else { return }
        let copy = rows[rowIdx].shapes[shapeIdx].duplicated(offsetX: 20, offsetY: 20)
        rows[rowIdx].shapes.append(copy)
        selectedShapeId = copy.id
        scheduleSave()
    }

    func deleteSelectedShape() {
        guard let id = selectedShapeId else { return }
        deleteShape(id)
    }

    func deselectShape() {
        selectedShapeId = nil
    }

    // MARK: - Helpers

    private func loadRowsForProject(_ id: UUID) {
        if let data = PersistenceService.loadProject(id) {
            rows = data.rows
        } else {
            rows = [makeDefaultRow()]
        }
        selectedRowId = rows.first?.id
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
