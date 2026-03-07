import SwiftUI

@Observable
final class AppState {
    var projects: [Project] = []
    var activeProjectId: UUID?
    var rows: [ScreenshotRow] = []
    var selectedRowId: UUID?
    var selectedShapeId: UUID?
    var zoomLevel: CGFloat = 1.0
    var screenshotImages: [String: NSImage] = [:]
    var undoManager: UndoManager?

    private static let templateColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]

    // MARK: - Undo

    private func registerUndo(_ actionName: String) {
        guard let undoManager else { return }
        let savedRows = rows
        undoManager.registerUndo(withTarget: self) { target in
            let redoRows = target.rows
            target.undoManager?.registerUndo(withTarget: target) { t in
                t.rows = redoRows
                t.normalizeSelection()
                t.scheduleSave()
                t.undoManager?.setActionName(actionName)
            }
            target.rows = savedRows
            target.normalizeSelection()
            target.scheduleSave()
            target.undoManager?.setActionName(actionName)
        }
        undoManager.setActionName(actionName)
    }

    // MARK: - Zoom

    func zoomIn() {
        withAnimation(.smooth(duration: 0.3)) {
            zoomLevel = min(ZoomConstants.max, zoomLevel + ZoomConstants.step)
        }
    }

    func zoomOut() {
        withAnimation(.smooth(duration: 0.3)) {
            zoomLevel = max(ZoomConstants.min, zoomLevel - ZoomConstants.step)
        }
    }

    func resetZoom() {
        let defaultLevel = UserDefaults.standard.double(forKey: "defaultZoomLevel")
        withAnimation(.smooth(duration: 0.3)) {
            zoomLevel = defaultLevel > 0 ? defaultLevel : 1.0
        }
    }

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
        let stored = UserDefaults.standard.double(forKey: "defaultZoomLevel")
        if stored > 0 { zoomLevel = stored }
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
                loadScreenshotImages()
            }
        }

        if projects.isEmpty {
            let project = Project(name: "My App")
            projects = [project]
            activeProjectId = project.id
            PersistenceService.ensureProjectDirs(project.id)
            rows = [makeDefaultRow()]
            selectRow(rows.first?.id)
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
        selectRow(rows.first?.id)
        saveAll()
    }

    func selectProject(_ id: UUID) {
        guard id != activeProjectId else { return }

        saveCurrentProject()
        undoManager?.removeAllActions()

        activeProjectId = id
        screenshotImages.removeAll()
        loadRowsForProject(id)
        loadScreenshotImages()
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
            screenshotImages.removeAll()
            if let nextProject = projects.first {
                activeProjectId = nextProject.id
                loadRowsForProject(nextProject.id)
                loadScreenshotImages()
            } else {
                // No projects left — create a new one
                createProject(name: "Project 1")
                return
            }
        }
        saveAll()
    }

    // MARK: - Templates

    func addTemplate(to rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        registerUndo("Add Template")
        let color = Self.templateColors[rows[idx].templates.count % Self.templateColors.count]
        rows[idx].templates.append(ScreenshotTemplate(backgroundColor: color))
        scheduleSave()
    }

    func removeTemplate(_ templateId: UUID, from rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        registerUndo("Remove Template")
        rows[idx].templates.removeAll { $0.id == templateId }
        scheduleSave()
    }

    // MARK: - Rows

    func addRow() {
        registerUndo("Add Row")
        let row = makeDefaultRow(label: "Screenshot \(rows.count + 1)")
        rows.append(row)
        selectRow(row.id)
        scheduleSave()
    }

    func duplicateRow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        registerUndo("Duplicate Row")
        let source = rows[idx]
        let copy = ScreenshotRow(
            label: "\(source.label) copy",
            templates: source.templates.map { ScreenshotTemplate(backgroundColor: $0.bgColor) },
            templateWidth: source.templateWidth,
            templateHeight: source.templateHeight,
            bgColor: source.bgColor,
            backgroundStyle: source.backgroundStyle,
            gradientConfig: source.gradientConfig,
            showDevice: source.showDevice,
            showBorders: source.showBorders,
            shapes: source.shapes.map { $0.duplicated() }
        )
        rows.insert(copy, at: idx + 1)
        selectRow(copy.id)
        scheduleSave()
    }

    func deleteRow(_ id: UUID) {
        guard rows.count > 1 else { return }
        registerUndo("Delete Row")
        let idx = rows.firstIndex { $0.id == id }
        let wasSelectedRow = selectedRowId == id
        rows.removeAll { $0.id == id }
        if wasSelectedRow {
            if let idx, idx < rows.count {
                selectRow(rows[idx].id)
            } else {
                selectRow(rows.last?.id)
            }
        } else {
            normalizeSelection()
        }
        scheduleSave()
    }

    func moveRowUp(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        registerUndo("Move Row Up")
        rows.swapAt(idx, idx - 1)
        scheduleSave()
    }

    func moveRowDown(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), idx < rows.count - 1 else { return }
        registerUndo("Move Row Down")
        rows.swapAt(idx, idx + 1)
        scheduleSave()
    }

    // MARK: - Shapes

    func addShape(_ shape: CanvasShapeModel) {
        guard let idx = selectedRowIndex else { return }
        registerUndo("Add Shape")
        rows[idx].shapes.append(shape)
        selectShape(shape.id, in: rows[idx].id)
        scheduleSave()
    }

    func updateShape(_ shape: CanvasShapeModel) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        registerUndo("Edit Shape")
        rows[rowIdx].shapes[shapeIdx] = shape
        scheduleSave()
    }

    func deleteShape(_ id: UUID) {
        guard let rowIdx = selectedRowIndex else { return }
        registerUndo("Delete Shape")
        if let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == id }) {
            for fileName in rows[rowIdx].shapes[shapeIdx].allImageFileNames {
                screenshotImages.removeValue(forKey: fileName)
            }
        }
        rows[rowIdx].shapes.removeAll { $0.id == id }
        if selectedShapeId == id {
            selectedShapeId = nil
        }
        scheduleSave()
    }

    func duplicateSelectedShape() {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == selectedShapeId }) else { return }
        registerUndo("Duplicate Shape")
        let copy = rows[rowIdx].shapes[shapeIdx].duplicated(offsetX: 50, offsetY: 50)
        rows[rowIdx].shapes.append(copy)
        selectShape(copy.id, in: rows[rowIdx].id)
        scheduleSave()
    }

    func bringShapeToFront(_ id: UUID) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == id }),
              shapeIdx < rows[rowIdx].shapes.count - 1 else { return }
        registerUndo("Bring to Front")
        let shape = rows[rowIdx].shapes.remove(at: shapeIdx)
        rows[rowIdx].shapes.append(shape)
        selectShape(id, in: rows[rowIdx].id)
        scheduleSave()
    }

    func sendShapeToBack(_ id: UUID) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == id }),
              shapeIdx > 0 else { return }
        registerUndo("Send to Back")
        let shape = rows[rowIdx].shapes.remove(at: shapeIdx)
        rows[rowIdx].shapes.insert(shape, at: 0)
        selectShape(id, in: rows[rowIdx].id)
        scheduleSave()
    }

    func selectRow(_ id: UUID?) {
        guard let id else {
            deselectAll()
            return
        }
        guard rows.contains(where: { $0.id == id }) else { return }
        selectedRowId = id
        selectedShapeId = nil
    }

    func selectShape(_ shapeId: UUID, in rowId: UUID) {
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              rows[rowIdx].shapes.contains(where: { $0.id == shapeId }) else { return }
        selectedRowId = rowId
        selectedShapeId = shapeId
    }

    func bringSelectedShapeToFront() {
        guard let id = selectedShapeId else { return }
        bringShapeToFront(id)
    }

    func sendSelectedShapeToBack() {
        guard let id = selectedShapeId else { return }
        sendShapeToBack(id)
    }

    func deleteSelectedShape() {
        guard let id = selectedShapeId else { return }
        deleteShape(id)
    }

    func deselectAll() {
        selectedShapeId = nil
        selectedRowId = nil
    }

    // MARK: - Screenshot Images

    func saveImage(_ image: NSImage, for shapeId: UUID) {
        guard let activeId = activeProjectId else { return }
        let fileName = "\(shapeId.uuidString).png"
        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)

        guard let pngData = ExportService.pngData(from: image) else { return }

        try? pngData.write(to: url, options: .atomic)
        screenshotImages[fileName] = image

        // Update shape with the filename
        for rowIdx in rows.indices {
            if let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shapeId }) {
                if rows[rowIdx].shapes[shapeIdx].type == .image {
                    rows[rowIdx].shapes[shapeIdx].imageFileName = fileName
                } else {
                    rows[rowIdx].shapes[shapeIdx].screenshotFileName = fileName
                }
                scheduleSave()
                return
            }
        }
    }


    func loadScreenshotImages() {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        for row in rows {
            for shape in row.shapes {
                for fileName in shape.allImageFileNames {
                    if screenshotImages[fileName] == nil {
                        let url = resourcesURL.appendingPathComponent(fileName)
                        if let image = NSImage(contentsOf: url) {
                            screenshotImages[fileName] = image
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadRowsForProject(_ id: UUID) {
        if let data = PersistenceService.loadProject(id) {
            rows = data.rows
        } else {
            rows = [makeDefaultRow()]
        }
        selectRow(rows.first?.id)
    }

    private func normalizeSelection() {
        if let selectedRowId, !rows.contains(where: { $0.id == selectedRowId }) {
            self.selectedRowId = rows.first?.id
        }

        if let selectedShapeId {
            guard let rowIdx = selectedRowIndex,
                  rows[rowIdx].shapes.contains(where: { $0.id == selectedShapeId }) else {
                self.selectedShapeId = nil
                return
            }
        }
    }

    private func makeDefaultRow(label: String = "Screenshot 1") -> ScreenshotRow {
        let defaultSize = UserDefaults.standard.string(forKey: "defaultScreenshotSize") ?? "1242x2688"
        let parsedSize = parseSize(defaultSize)
        let w: CGFloat = parsedSize?.width ?? 1242
        let h: CGFloat = parsedSize?.height ?? 2688
        let storedTemplateCount = UserDefaults.standard.integer(forKey: "defaultTemplateCount")
        let templateCount = storedTemplateCount > 0 ? storedTemplateCount : 3
        let templates = (0..<templateCount).map { index in
            ScreenshotTemplate(backgroundColor: Self.templateColors[index % Self.templateColors.count])
        }
        let device = CanvasShapeModel.defaultDevice(centerX: w / 2, centerY: h / 2, templateHeight: h)
        return ScreenshotRow(
            label: label,
            templates: templates,
            templateWidth: w,
            templateHeight: h,
            shapes: [device]
        )
    }

    private func parseSize(_ value: String) -> (width: CGFloat, height: CGFloat)? {
        parseSizeString(value)
    }
}
