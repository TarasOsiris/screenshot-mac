import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    var projects: [Project] = []
    var activeProjectId: UUID?
    var rows: [ScreenshotRow] = []
    var localeState: LocaleState = .default
    var selectedRowId: UUID?
    var selectedShapeId: UUID?
    var zoomLevel: CGFloat = 1.0
    var canvasMouseModelPosition: CGPoint?
    var screenshotImages: [String: NSImage] = [:]
    var undoManager: UndoManager?
    var canvasFocusRowId: UUID?
    var canvasFocusRequestNonce = 0

    private static let templateColors: [Color] = [.blue, .purple, .orange, .green, .pink, .teal]

    // MARK: - Undo

    private func registerUndo(_ actionName: String) {
        registerUndoWithBase(actionName, base: rows, baseLocaleState: localeState)
    }

    private func registerUndoWithBase(_ actionName: String, base: [ScreenshotRow], baseLocaleState: LocaleState? = nil) {
        guard let undoManager else { return }
        let savedLocaleState = baseLocaleState ?? localeState
        undoManager.registerUndo(withTarget: self) { target in
            let redoRows = target.rows
            let redoLocaleState = target.localeState
            target.undoManager?.registerUndo(withTarget: target) { t in
                t.rows = redoRows
                t.localeState = redoLocaleState
                t.normalizeSelection()
                t.scheduleSave()
                t.undoManager?.setActionName(actionName)
            }
            target.rows = base
            target.localeState = savedLocaleState
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

    func rowIndex(for rowId: UUID) -> Int? {
        rows.firstIndex { $0.id == rowId }
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

    private func cancelPendingDebounceTasks() {
        translationUndoTask?.cancel()
        translationUndoTask = nil
        translationBaseLocaleState = nil
        nudgeUndoTask?.cancel()
        nudgeUndoTask = nil
        nudgeBaseRows = nil
    }

    private func saveCurrentProject() {
        guard let activeId = activeProjectId else { return }
        PersistenceService.saveProject(activeId, data: ProjectData(rows: rows, localeState: localeState))
    }

    // MARK: - Projects

    func createProject(name: String) {
        saveCurrentProject()

        let sanitized = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
        let baseName = sanitized.isEmpty ? "Project" : sanitized
        let project = Project(name: uniqueProjectName(baseName))
        projects.append(project)
        activeProjectId = project.id
        PersistenceService.ensureProjectDirs(project.id)
        cancelPendingDebounceTasks()
        rows = [makeDefaultRow()]
        localeState = .default
        selectRow(rows.first?.id)
        saveAll()
    }

    func selectProject(_ id: UUID) {
        guard id != activeProjectId else { return }

        saveCurrentProject()
        switchToProject(id)
        saveIndex()
    }

    private func switchToProject(_ id: UUID) {
        undoManager?.removeAllActions()
        cancelPendingDebounceTasks()
        activeProjectId = id
        screenshotImages.removeAll()
        loadRowsForProject(id)
        loadScreenshotImages()
    }

    func renameProject(_ id: UUID, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(50))
        guard !trimmed.isEmpty else { return }
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].name = uniqueProjectName(trimmed, excludingId: id)
            scheduleSave()
        }
    }

    private func uniqueProjectName(_ baseName: String, excludingId: UUID? = nil) -> String {
        let existingNames = Set(projects.filter { $0.id != excludingId }.map { $0.name })
        if !existingNames.contains(baseName) { return baseName }
        var counter = 2
        while existingNames.contains("\(baseName) \(counter)") {
            counter += 1
        }
        return "\(baseName) \(counter)"
    }

    func duplicateProject(_ id: UUID) {
        saveCurrentProject()

        guard let source = projects.first(where: { $0.id == id }) else { return }
        let newProject = Project(name: uniqueProjectName(source.name + " Copy"))
        PersistenceService.copyProject(from: id, to: newProject.id)
        projects.append(newProject)

        switchToProject(newProject.id)
        saveAll()
    }

    func resetProject(_ id: UUID) {
        guard id == activeProjectId else { return }
        undoManager?.removeAllActions()
        cancelPendingDebounceTasks()
        screenshotImages.removeAll()
        rows = [makeDefaultRow()]
        localeState = .default
        selectRow(rows.first?.id)
        saveAll()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        PersistenceService.deleteProject(id)

        if activeProjectId == id {
            cancelPendingDebounceTasks()
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
        let templateIndex = rows[idx].templates.count - 1
        let device = CanvasShapeModel.defaultDevice(
            centerX: rows[idx].templateCenterX(at: templateIndex),
            centerY: rows[idx].templateHeight / 2,
            templateHeight: rows[idx].templateHeight,
            category: rows[idx].defaultDeviceCategory
        )
        rows[idx].shapes.append(device)
        scheduleSave()
    }

    func removeTemplate(_ templateId: UUID, from rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[idx].templates.firstIndex(where: { $0.id == templateId }) else { return }
        registerUndo("Remove Template")
        let shapesToRemove = rows[idx].shapes.filter { rows[idx].owningTemplateIndex(for: $0) == templateIndex }
        let templateBgImage = rows[idx].templates[templateIndex].backgroundImageConfig.fileName
        for shape in shapesToRemove {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        let shapeIdsToRemove = Set(shapesToRemove.map(\.id))
        if let selectedId = selectedShapeId, shapeIdsToRemove.contains(selectedId) {
            selectedShapeId = nil
        }
        rows[idx].shapes.removeAll { shapeIdsToRemove.contains($0.id) }
        rows[idx].templates.remove(at: templateIndex)
        // Cleanup orphaned images after removal
        for shape in shapesToRemove {
            for fileName in shape.allImageFileNames { cleanupUnreferencedImage(fileName) }
        }
        cleanupUnreferencedImage(templateBgImage)
        scheduleSave()
    }

    func moveTemplateLeft(_ templateId: UUID, in rowId: UUID) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == templateId }),
              templateIndex > 0 else { return }
        moveTemplate(inRowAt: rowIndex, from: templateIndex, to: templateIndex - 1, undoName: "Move Screenshot Left")
    }

    func moveTemplateRight(_ templateId: UUID, in rowId: UUID) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == templateId }),
              templateIndex < rows[rowIndex].templates.count - 1 else { return }
        moveTemplate(inRowAt: rowIndex, from: templateIndex, to: templateIndex + 1, undoName: "Move Screenshot Right")
    }

    private func moveTemplate(inRowAt rowIndex: Int, from sourceIndex: Int, to destinationIndex: Int, undoName: String) {
        guard sourceIndex != destinationIndex else { return }

        var row = rows[rowIndex]
        guard row.templates.indices.contains(sourceIndex),
              row.templates.indices.contains(destinationIndex) else { return }

        registerUndo(undoName)

        // Keep each shape visually attached to its screenshot column while columns are reordered.
        let columnWidth = row.templateWidth
        let lo = min(sourceIndex, destinationIndex)
        let hi = max(sourceIndex, destinationIndex)
        let betweenShift = sourceIndex < destinationIndex ? -columnWidth : columnWidth
        for shapeIndex in row.shapes.indices {
            let owner = row.owningTemplateIndex(for: row.shapes[shapeIndex])
            if owner == sourceIndex {
                row.shapes[shapeIndex].x += columnWidth * CGFloat(destinationIndex - sourceIndex)
            } else if owner >= lo && owner <= hi {
                row.shapes[shapeIndex].x += betweenShift
            }
        }

        let movedTemplate = row.templates.remove(at: sourceIndex)
        row.templates.insert(movedTemplate, at: destinationIndex)
        rows[rowIndex] = row
        scheduleSave()
    }

    // MARK: - Rows

    func addRow() {
        registerUndo("Add Row")
        let row = makeDefaultRow()
        rows.append(row)
        selectRow(row.id)
        scheduleSave()
    }

    func duplicateRow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        registerUndo("Duplicate Row")
        let source = rows[idx]
        let newShapes = source.shapes.map { $0.duplicated() }
        let copy = ScreenshotRow(
            label: "\(source.label) copy",
            templates: source.templates.map { $0.duplicated() },
            templateWidth: source.templateWidth,
            templateHeight: source.templateHeight,
            bgColor: source.bgColor,
            defaultDeviceBodyColor: source.defaultDeviceBodyColor,
            backgroundStyle: source.backgroundStyle,
            gradientConfig: source.gradientConfig,
            showDevice: source.showDevice,
            showBorders: source.showBorders,
            shapes: newShapes,
            isLabelManuallySet: true
        )
        // Copy locale overrides for each duplicated shape
        for (originalShape, newShape) in zip(source.shapes, newShapes) {
            LocaleService.copyShapeOverrides(&localeState, fromId: originalShape.id, toId: newShape.id)
        }
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

    func resizeRow(at rowIndex: Int, newWidth: CGFloat, newHeight: CGFloat) {
        var row = rows[rowIndex]
        guard row.templateWidth != newWidth || row.templateHeight != newHeight else { return }

        registerUndo("Resize Row")

        let scaleX = newWidth / row.templateWidth
        let scaleY = newHeight / row.templateHeight

        for i in row.shapes.indices {
            let shape = row.shapes[i]
            let templateIndex = row.owningTemplateIndex(for: shape)
            let oldOriginX = CGFloat(templateIndex) * row.templateWidth
            let newOriginX = CGFloat(templateIndex) * newWidth
            // Devices keep aspect ratio; other shapes stretch with the template
            let sx = shape.type == .device ? min(scaleX, scaleY) : scaleX
            let sy = shape.type == .device ? min(scaleX, scaleY) : scaleY

            let relX = shape.x - oldOriginX
            row.shapes[i].x = newOriginX + relX * scaleX
            row.shapes[i].y = shape.y * scaleY
            row.shapes[i].width = shape.width * sx
            row.shapes[i].height = shape.height * sy
        }

        row.templateWidth = newWidth
        row.templateHeight = newHeight
        if !row.isLabelManuallySet {
            row.label = presetLabel(forWidth: newWidth, height: newHeight)
        }
        rows[rowIndex] = row
        scheduleSave()
    }

    func updateRowDefaultDeviceBodyColor(_ color: Color, for rowId: UUID) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }
        let oldDefault = rows[rowIndex].defaultDeviceBodyColorData
        let newDefault = CodableColor(color)
        guard oldDefault != newDefault else { return }

        rows[rowIndex].defaultDeviceBodyColorData = newDefault

        // Legacy projects stored the default frame color on each device shape.
        // When row default changes, convert matching legacy values to inheritance.
        for shapeIndex in rows[rowIndex].shapes.indices {
            guard rows[rowIndex].shapes[shapeIndex].type == .device else { continue }
            if rows[rowIndex].shapes[shapeIndex].deviceBodyColorData == oldDefault {
                rows[rowIndex].shapes[shapeIndex].deviceBodyColorData = nil
            }
        }

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
        let baseShape = rows[rowIdx].shapes[shapeIdx]
        rows[rowIdx].shapes[shapeIdx] = LocaleService.splitUpdate(base: baseShape, updated: shape, localeState: &localeState)
        scheduleSave()
    }

    func deleteShape(_ id: UUID) {
        guard let location = shapeLocation(for: id) else { return }
        registerUndo("Delete Shape")
        let removedShape = rows[location.rowIndex].shapes.remove(at: location.shapeIndex)
        for fileName in removedShape.allImageFileNames {
            cleanupUnreferencedImage(fileName)
        }
        LocaleService.removeShapeOverrides(&localeState, shapeId: id)
        if selectedShapeId == id {
            selectedShapeId = nil
        }
        scheduleSave()
    }

    func duplicateSelectedShape() {
        guard let id = selectedShapeId else { return }
        _ = insertDuplicate(of: id, offsetX: 50, offsetY: 50, undoName: "Duplicate Shape")
    }

    @discardableResult
    private func insertDuplicate(of shapeId: UUID, offsetX: CGFloat = 0, offsetY: CGFloat = 0, undoName: String) -> UUID? {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shapeId }) else { return nil }
        registerUndo(undoName)
        let copy = rows[rowIdx].shapes[shapeIdx].duplicated(offsetX: offsetX, offsetY: offsetY)
        rows[rowIdx].shapes.append(copy)
        LocaleService.copyShapeOverrides(&localeState, fromId: shapeId, toId: copy.id)
        selectShape(copy.id, in: rows[rowIdx].id)
        scheduleSave()
        return copy.id
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

    // MARK: - Locales

    func setActiveLocale(_ code: String) {
        guard code != localeState.activeLocaleCode else { return }
        guard localeState.locales.contains(where: { $0.code == code }) else { return }
        localeState.activeLocaleCode = code
        scheduleSave()
    }

    func cycleLocaleForward() { cycleLocale(forward: true) }
    func cycleLocaleBackward() { cycleLocale(forward: false) }

    private func cycleLocale(forward: Bool) {
        let locales = localeState.locales
        guard locales.count > 1 else { return }
        guard let idx = locales.firstIndex(where: { $0.code == localeState.activeLocaleCode }) else { return }
        let offset = forward ? 1 : locales.count - 1
        let target = locales[(idx + offset) % locales.count]
        setActiveLocale(target.code)
    }

    func moveLocale(from source: IndexSet, to destination: Int) {
        guard let fromIdx = source.first, fromIdx != 0, destination != 0 else { return }
        registerUndo("Reorder Locale")
        localeState.locales.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    /// All text shapes across all rows with their base text and override for the active locale.
    func textShapesForTranslation() -> [(shape: CanvasShapeModel, rowId: UUID, rowLabel: String, overrideText: String?)] {
        var results: [(shape: CanvasShapeModel, rowId: UUID, rowLabel: String, overrideText: String?)] = []
        let code = localeState.activeLocaleCode
        for row in rows {
            for shape in row.shapes where shape.type == .text {
                let overrideText = localeState.override(forCode: code, shapeId: shape.id)?.text
                results.append((shape: shape, rowId: row.id, rowLabel: row.label, overrideText: overrideText))
            }
        }
        return results
    }

    func focusShapeOnCanvas(shapeId: UUID, rowId: UUID) {
        selectShape(shapeId, in: rowId)
        canvasFocusRowId = rowId
        canvasFocusRequestNonce += 1
    }

    /// Translation progress for a locale (defaults to active locale).
    func translationProgress(for localeCode: String? = nil) -> (translated: Int, total: Int) {
        let code = localeCode ?? localeState.activeLocaleCode
        let textShapes = allTextShapes()
        let total = textShapes.count
        guard total > 0 else { return (0, 0) }

        if code == localeState.baseLocaleCode {
            return (total, total)
        }

        let translated = textShapes.reduce(into: 0) { count, shape in
            if let text = localeState.override(forCode: code, shapeId: shape.id)?.text,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                count += 1
            }
        }
        return (translated, total)
    }

    private var translationUndoTask: DispatchWorkItem?
    private var translationBaseLocaleState: LocaleState?

    func updateTranslationText(shapeId: UUID, text: String) {
        let code = localeState.activeLocaleCode
        guard code != localeState.baseLocaleCode else { return }

        // Capture undo state only at the start of a translation editing sequence
        if translationBaseLocaleState == nil {
            translationBaseLocaleState = localeState
        }

        let key = shapeId.uuidString
        var override = localeState.overrides[code]?[key] ?? ShapeLocaleOverride()
        override.text = text.isEmpty ? nil : text
        LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override.isEmpty ? nil : override)
        scheduleSave()

        // Debounce undo registration so rapid keystrokes collapse into one entry
        translationUndoTask?.cancel()
        guard let savedBase = translationBaseLocaleState else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.registerUndoWithBase("Edit Translation", base: self.rows, baseLocaleState: savedBase)
            self.translationBaseLocaleState = nil
        }
        translationUndoTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func resetLocaleOverride(shapeId: UUID) {
        registerUndo("Reset Override")
        LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: nil)
        scheduleSave()
    }

    func addLocale(_ locale: LocaleDefinition) {
        guard !localeState.locales.contains(where: { $0.code == locale.code }) else { return }
        registerUndo("Add Locale")
        LocaleService.addLocale(&localeState, locale: locale)
        localeState.activeLocaleCode = locale.code
        scheduleSave()
    }

    func removeLocale(_ code: String) {
        guard code != localeState.baseLocaleCode else { return }
        guard localeState.locales.contains(where: { $0.code == code }) else { return }
        registerUndo("Remove Locale")
        LocaleService.removeLocale(&localeState, code: code)
        scheduleSave()
    }

    // MARK: - Clipboard

    var clipboard: CanvasShapeModel?

    func copySelectedShape() {
        guard let rowIdx = selectedRowIndex,
              let shape = rows[rowIdx].shapes.first(where: { $0.id == selectedShapeId }) else { return }
        clipboard = shape
    }

    func pasteShape() {
        guard let source = clipboard, let rowIdx = selectedRowIndex else { return }
        registerUndo("Paste Shape")
        var pasted: CanvasShapeModel
        if let mousePos = canvasMouseModelPosition {
            pasted = source.duplicated()
            pasted.x = mousePos.x - pasted.width / 2
            pasted.y = mousePos.y - pasted.height / 2
        } else {
            pasted = source.duplicated(offsetX: 20, offsetY: 20)
        }
        rows[rowIdx].shapes.append(pasted)
        LocaleService.copyShapeOverrides(&localeState, fromId: source.id, toId: pasted.id)
        selectShape(pasted.id, in: rows[rowIdx].id)
        scheduleSave()
    }

    // MARK: - Nudge

    private var nudgeUndoTask: DispatchWorkItem?
    private var nudgeBaseRows: [ScreenshotRow]?

    func nudgeSelectedShape(dx: CGFloat, dy: CGFloat) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == selectedShapeId }) else { return }

        // Capture undo state only at the start of a nudge sequence
        if nudgeBaseRows == nil {
            nudgeBaseRows = rows
        }

        rows[rowIdx].shapes[shapeIdx].x += dx
        rows[rowIdx].shapes[shapeIdx].y += dy
        scheduleSave()

        // Debounce the undo registration so rapid key repeats collapse into one entry
        nudgeUndoTask?.cancel()
        guard let savedBase = nudgeBaseRows else { return }
        let nudgeTask = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.registerUndoWithBase("Move Shape", base: savedBase)
            self.nudgeBaseRows = nil
        }
        nudgeUndoTask = nudgeTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: nudgeTask)
    }

    // MARK: - Option+Drag Duplicate

    func duplicateShapeForOptionDrag(_ shapeId: UUID) -> UUID? {
        insertDuplicate(of: shapeId, undoName: "Duplicate Shape")
    }

    // MARK: - Screenshot Images

    func saveImage(_ image: NSImage, for shapeId: UUID) {
        guard let activeId = activeProjectId else { return }
        guard let location = shapeLocation(for: shapeId) else { return }
        let fileName = "\(shapeId.uuidString).png"
        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)

        guard let pngData = ExportService.pngData(from: image) else { return }

        try? pngData.write(to: url, options: .atomic)
        screenshotImages[fileName] = image

        // Update the shape's image reference if it still exists.
        var shape = rows[location.rowIndex].shapes[location.shapeIndex]
        let previousFiles = shape.allImageFileNames
        if shape.type == .image {
            shape.imageFileName = fileName
        } else {
            shape.screenshotFileName = fileName
        }
        rows[location.rowIndex].shapes[location.shapeIndex] = shape

        for oldFile in previousFiles where oldFile != fileName {
            cleanupUnreferencedImage(oldFile)
        }
        scheduleSave()
    }


    func loadScreenshotImages() {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)

        func loadIfNeeded(_ fileName: String?) {
            guard let fileName, screenshotImages[fileName] == nil else { return }
            let url = resourcesURL.appendingPathComponent(fileName)
            if let image = NSImage(contentsOf: url) {
                screenshotImages[fileName] = image
            }
        }

        for row in rows {
            // Shape images
            for shape in row.shapes {
                for fileName in shape.allImageFileNames {
                    loadIfNeeded(fileName)
                }
            }
            // Row background image
            loadIfNeeded(row.backgroundImageConfig.fileName)
            // Template background images
            for template in row.templates {
                loadIfNeeded(template.backgroundImageConfig.fileName)
            }
        }
    }

    func saveBackgroundImage(_ image: NSImage, for rowId: UUID, templateIndex: Int? = nil) {
        guard let activeId = activeProjectId,
              let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }

        let fileId = UUID().uuidString
        let fileName = "bg-\(fileId).png"
        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)

        guard let pngData = ExportService.pngData(from: image) else { return }
        try? pngData.write(to: url, options: .atomic)
        screenshotImages[fileName] = image

        setBackgroundImageFileName(fileName, rowIndex: rowIndex, templateIndex: templateIndex)
        scheduleSave()
    }

    func removeBackgroundImage(for rowId: UUID, templateIndex: Int? = nil) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }
        setBackgroundImageFileName(nil, rowIndex: rowIndex, templateIndex: templateIndex)
        scheduleSave()
    }

    private func setBackgroundImageFileName(_ newFile: String?, rowIndex: Int, templateIndex: Int?) {
        let oldFile: String?
        if let templateIndex, templateIndex < rows[rowIndex].templates.count {
            oldFile = rows[rowIndex].templates[templateIndex].backgroundImageConfig.fileName
            rows[rowIndex].templates[templateIndex].backgroundImageConfig.fileName = newFile
        } else {
            oldFile = rows[rowIndex].backgroundImageConfig.fileName
            rows[rowIndex].backgroundImageConfig.fileName = newFile
        }
        cleanupUnreferencedImage(oldFile)
    }

    private func cleanupUnreferencedImage(_ fileName: String?) {
        guard let fileName, !isImageFileReferenced(fileName) else { return }
        screenshotImages.removeValue(forKey: fileName)
    }

    func pickAndSaveBackgroundImage(for rowId: UUID, templateIndex: Int? = nil) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = NSImage.fromSecurityScopedURL(url) else { return }
        saveBackgroundImage(image, for: rowId, templateIndex: templateIndex)
    }

    // MARK: - Helpers

    private func loadRowsForProject(_ id: UUID) {
        if let data = PersistenceService.loadProject(id) {
            rows = data.rows
            localeState = data.localeState ?? .default
        } else {
            rows = [makeDefaultRow()]
            localeState = .default
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

    private func shapeLocation(for shapeId: UUID) -> (rowIndex: Int, shapeIndex: Int)? {
        for rowIndex in rows.indices {
            if let shapeIndex = rows[rowIndex].shapes.firstIndex(where: { $0.id == shapeId }) {
                return (rowIndex, shapeIndex)
            }
        }
        return nil
    }

    private func allTextShapes() -> [CanvasShapeModel] {
        rows.flatMap { row in
            row.shapes.filter { $0.type == .text }
        }
    }

    private func isImageFileReferenced(_ fileName: String) -> Bool {
        rows.contains { row in
            row.backgroundImageConfig.fileName == fileName ||
            row.templates.contains { $0.backgroundImageConfig.fileName == fileName } ||
            row.shapes.contains { shape in
                shape.allImageFileNames.contains(fileName)
            }
        }
    }

    private func makeDefaultRow(label: String? = nil) -> ScreenshotRow {
        let defaultSize = UserDefaults.standard.string(forKey: "defaultScreenshotSize") ?? "1242x2688"
        let parsedSize = parseSizeString(defaultSize)
        let w: CGFloat = parsedSize?.width ?? 1242
        let h: CGFloat = parsedSize?.height ?? 2688
        let storedTemplateCount = UserDefaults.standard.integer(forKey: "defaultTemplateCount")
        let templateCount = storedTemplateCount > 0 ? storedTemplateCount : 3
        let templates = (0..<templateCount).map { index in
            ScreenshotTemplate(backgroundColor: Self.templateColors[index % Self.templateColors.count])
        }
        let shapes = (0..<templateCount).map { index in
            CanvasShapeModel.defaultDevice(
                centerX: CGFloat(index) * w + w / 2,
                centerY: h / 2,
                templateHeight: h
            )
        }
        let resolvedLabel = label ?? presetLabel(forWidth: w, height: h)
        return ScreenshotRow(
            label: resolvedLabel,
            templates: templates,
            templateWidth: w,
            templateHeight: h,
            shapes: shapes,
            isLabelManuallySet: label != nil
        )
    }

}
