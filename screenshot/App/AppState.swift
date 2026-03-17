import SwiftUI
import UniformTypeIdentifiers

@Observable
final class AppState {
    private static let maxProjectNameLength = 100

    var projects: [Project] = []
    var projectTemplates: [ProjectTemplate] = []
    var activeProjectId: UUID?
    var rows: [ScreenshotRow] = []
    var localeState: LocaleState = .default
    var selectedRowId: UUID?
    var selectedShapeId: UUID?
    var zoomLevel: CGFloat = 1.0
    @ObservationIgnored var canvasMouseModelPosition: CGPoint?
    @ObservationIgnored var visibleCanvasModelCenter: CGPoint?
    @ObservationIgnored var justAddedShapeId: UUID?
    var screenshotImages: [String: NSImage] = [:]
    var customFonts: [String: String] = [:]  // fileName → familyName
    var undoManager: UndoManager?
    var saveError: String?
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

    func setZoomLevel(_ level: CGFloat, animated: Bool = true) {
        let clamped = min(ZoomConstants.max, max(ZoomConstants.min, level))
        guard clamped != zoomLevel else { return }
        if animated {
            withAnimation(.smooth(duration: 0.3)) {
                zoomLevel = clamped
            }
        } else {
            zoomLevel = clamped
        }
    }

    func zoomIn() {
        setZoomLevel(zoomLevel + ZoomConstants.step)
    }

    func zoomOut() {
        setZoomLevel(zoomLevel - ZoomConstants.step)
    }

    func resetZoom() {
        let defaultLevel = UserDefaults.standard.double(forKey: "defaultZoomLevel")
        setZoomLevel(defaultLevel > 0 ? defaultLevel : 1.0)
    }

    private var saveTask: DispatchWorkItem?
    @ObservationIgnored private var imageLoadTask: Task<Void, Never>?
    var isLoadingImages = false

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
        }

        if let templateIndex = PersistenceService.loadTemplateIndex() {
            projectTemplates = templateIndex.templates
        }

        if let activeId = activeProjectId {
            loadRowsForProject(activeId)
            loadScreenshotImages()
            loadCustomFonts()
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
        do {
            try PersistenceService.saveIndex(index)
        } catch {
            saveError = "Failed to save project index: \(error.localizedDescription)"
        }
    }

    private func saveTemplateIndex() {
        let index = ProjectTemplateIndex(templates: projectTemplates)
        do {
            try PersistenceService.saveTemplateIndex(index)
        } catch {
            saveError = "Failed to save template index: \(error.localizedDescription)"
        }
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
        do {
            try PersistenceService.saveProject(activeId, data: ProjectData(rows: rows, localeState: localeState))
        } catch {
            saveError = "Failed to save project: \(error.localizedDescription)"
        }
    }

    // MARK: - Projects

    func createProject(name: String) {
        saveCurrentProject()

        let sanitized = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength))
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
        unregisterCustomFonts()
        activeProjectId = id
        screenshotImages.removeAll()
        loadRowsForProject(id)
        loadScreenshotImages()
        loadCustomFonts()
    }

    func renameProject(_ id: UUID, to name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength))
        guard !trimmed.isEmpty else { return }
        if let idx = projects.firstIndex(where: { $0.id == id }) {
            projects[idx].name = uniqueProjectName(trimmed, excludingId: id)
            scheduleSave()
        }
    }

    private func uniqueProjectName(_ baseName: String, excludingId: UUID? = nil) -> String {
        let existingNames = Set(projects.filter { $0.id != excludingId }.map { $0.name })
        return Self.uniqueName(baseName, among: existingNames)
    }

    private func uniqueTemplateName(_ baseName: String, excludingId: UUID? = nil) -> String {
        let existingNames = Set(projectTemplates.filter { $0.id != excludingId }.map { $0.name })
        return Self.uniqueName(baseName, among: existingNames)
    }

    private static func uniqueName(_ baseName: String, among existingNames: Set<String>) -> String {
        let cappedBase = String(baseName.prefix(maxProjectNameLength))
        if !existingNames.contains(cappedBase) { return cappedBase }
        var counter = 2
        while true {
            let suffix = " \(counter)"
            let availableCount = max(0, maxProjectNameLength - suffix.count)
            let candidate = String(cappedBase.prefix(availableCount)) + suffix
            if !existingNames.contains(candidate) {
                return candidate
            }
            counter += 1
        }
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

    func saveCurrentProjectAsTemplate(name: String) {
        guard let activeId = activeProjectId else { return }

        saveCurrentProject()

        let sanitized = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxProjectNameLength))
        let fallbackName = activeProject?.name ?? "Template"
        let baseName = sanitized.isEmpty ? fallbackName : sanitized
        let template = ProjectTemplate(name: uniqueTemplateName(baseName))
        PersistenceService.copyProjectToTemplate(from: activeId, to: template.id)
        projectTemplates.append(template)
        saveTemplateIndex()
    }

    func createProject(fromTemplate templateId: UUID) {
        saveCurrentProject()

        guard let template = projectTemplates.first(where: { $0.id == templateId }) else { return }
        let newProject = Project(name: uniqueProjectName(template.name))
        PersistenceService.copyTemplateToProject(from: templateId, to: newProject.id)
        projects.append(newProject)

        switchToProject(newProject.id)
        saveAll()
    }

    func resetProject(_ id: UUID) {
        guard id == activeProjectId else { return }
        undoManager?.removeAllActions()
        cancelPendingDebounceTasks()
        unregisterCustomFonts()
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
            unregisterCustomFonts()
            screenshotImages.removeAll()
            if let nextProject = projects.first {
                activeProjectId = nextProject.id
                loadRowsForProject(nextProject.id)
                loadScreenshotImages()
                loadCustomFonts()
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
        if let defaultCategory = rows[idx].defaultDeviceCategory {
            var device = CanvasShapeModel.defaultDevice(
                centerX: rows[idx].templateCenterX(at: templateIndex),
                centerY: rows[idx].templateHeight / 2,
                templateHeight: rows[idx].templateHeight,
                category: defaultCategory
            )
            if let frameId = rows[idx].defaultDeviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
                device.deviceCategory = frame.fallbackCategory
                device.deviceFrameId = frame.id
                device.adjustToDeviceAspectRatio(centerX: rows[idx].templateCenterX(at: templateIndex))
            }
            rows[idx].shapes.append(device)
        }
        scheduleSave()
    }

    func removeTemplate(_ templateId: UUID, from rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[idx].templates.firstIndex(where: { $0.id == templateId }) else { return }
        registerUndo("Remove Template")
        let shapesToRemove = rows[idx].shapes.filter { rows[idx].owningTemplateIndex(for: $0) == templateIndex }
        let templateBgImage = rows[idx].templates[templateIndex].backgroundImageConfig.fileName
        // Collect locale override images before removing overrides
        let localeImages = shapesToRemove.flatMap { localeOverrideImageFileNames(for: $0.id) }
        for shape in shapesToRemove {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        let shapeIdsToRemove = Set(shapesToRemove.map(\.id))
        if let selectedId = selectedShapeId, shapeIdsToRemove.contains(selectedId) {
            selectedShapeId = nil
        }
        rows[idx].shapes.removeAll { shapeIdsToRemove.contains($0.id) }
        rows[idx].templates.remove(at: templateIndex)
        // Cleanup orphaned images after removal (single-pass batch check)
        let allCandidates: [String?] = shapesToRemove.flatMap { $0.allImageFileNames } + localeImages + [templateBgImage]
        cleanupUnreferencedImages(allCandidates)
        scheduleSave()
    }

    func duplicateTemplate(_ templateId: UUID, in rowId: UUID) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == templateId }) else { return }
        registerUndo("Duplicate Screenshot")
        let sourceTemplate = rows[rowIndex].templates[templateIndex]
        var newTemplate = sourceTemplate.duplicated()

        // Copy template background image if present
        if let bgFileName = sourceTemplate.backgroundImageConfig.fileName,
           let activeId = activeProjectId {
            let resourcesURL = PersistenceService.resourcesDir(activeId)
            let newBgFile = "\(newTemplate.id.uuidString)-bg.png"
            let srcURL = resourcesURL.appendingPathComponent(bgFileName)
            let dstURL = resourcesURL.appendingPathComponent(newBgFile)
            if FileManager.default.fileExists(atPath: srcURL.path) {
                try? FileManager.default.copyItem(at: srcURL, to: dstURL)
                newTemplate.backgroundImageConfig.fileName = newBgFile
                screenshotImages[newBgFile] = screenshotImages[bgFileName]
            }
        }

        // Insert the new template right after the original
        rows[rowIndex].templates.insert(newTemplate, at: templateIndex + 1)

        // Duplicate shapes belonging to this template and shift to the new column
        let columnWidth = rows[rowIndex].templateWidth
        let sourceShapes = rows[rowIndex].shapes.filter {
            rows[rowIndex].owningTemplateIndex(for: $0) == templateIndex
        }

        // Shift existing shapes in templates after the insertion point to the right
        for i in rows[rowIndex].shapes.indices {
            let owner = rows[rowIndex].owningTemplateIndex(for: rows[rowIndex].shapes[i])
            if owner > templateIndex {
                rows[rowIndex].shapes[i].x += columnWidth
            }
        }

        // Create duplicated shapes for the new template
        var newShapes: [CanvasShapeModel] = []
        for shape in sourceShapes {
            var copy = shape.duplicated()
            copy.x += columnWidth
            LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
            copyImageFiles(for: &copy, originalId: shape.id)
            newShapes.append(copy)
        }
        rows[rowIndex].shapes.append(contentsOf: newShapes)

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
        // Shapes that span multiple templates stay in place — they aren't tied to one column.
        let columnWidth = row.templateWidth
        let lo = min(sourceIndex, destinationIndex)
        let hi = max(sourceIndex, destinationIndex)
        let betweenShift = sourceIndex < destinationIndex ? -columnWidth : columnWidth
        for shapeIndex in row.shapes.indices {
            let shape = row.shapes[shapeIndex]

            // Shapes spanning multiple templates stay in place unless clipped to one template.
            if shape.clipToTemplate != true {
                let bb = shape.aabb
                let firstTemplate = max(0, Int(floor(bb.minX / columnWidth)))
                let lastTemplate = min(row.templates.count - 1, Int(floor((bb.maxX - 0.5) / columnWidth)))
                if firstTemplate != lastTemplate { continue }
            }

            let owner = row.owningTemplateIndex(for: shape)
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
        var newShapes = source.shapes.map { $0.duplicated() }
        // Copy locale overrides and image files for each duplicated shape
        for i in newShapes.indices {
            let originalId = source.shapes[i].id
            LocaleService.copyShapeOverrides(&localeState, fromId: originalId, toId: newShapes[i].id)
            copyImageFiles(for: &newShapes[i], originalId: originalId)
        }
        let copy = ScreenshotRow(
            label: "\(source.label) copy",
            templates: source.templates.map { $0.duplicated() },
            templateWidth: source.templateWidth,
            templateHeight: source.templateHeight,
            bgColor: source.bgColor,
            defaultDeviceBodyColor: source.defaultDeviceBodyColor,
            defaultDeviceCategory: source.defaultDeviceCategory,
            backgroundStyle: source.backgroundStyle,
            gradientConfig: source.gradientConfig,
            spanBackgroundAcrossRow: source.spanBackgroundAcrossRow,
            backgroundImageConfig: source.backgroundImageConfig,
            defaultDeviceFrameId: source.defaultDeviceFrameId,
            showDevice: source.showDevice,
            showBorders: source.showBorders,
            shapes: newShapes,
            isLabelManuallySet: true
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

    func resetRow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        registerUndo("Reset Row")
        let oldRow = rows[idx]

        // Collect all image filenames to clean up
        let shapeImages = oldRow.shapes.flatMap { $0.allImageFileNames }
        let localeImages = oldRow.shapes.flatMap { localeOverrideImageFileNames(for: $0.id) }
        let templateBgImages = oldRow.templates.compactMap { $0.backgroundImageConfig.fileName }
        let rowBgImage = oldRow.backgroundImageConfig.fileName

        // Remove locale overrides for all shapes
        for shape in oldRow.shapes {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }

        // Replace with a fresh default row, preserving id and dimensions
        rows[idx] = makeDefaultRow(
            id: oldRow.id,
            label: oldRow.isLabelManuallySet ? oldRow.label : nil,
            width: oldRow.templateWidth,
            height: oldRow.templateHeight
        )

        selectedShapeId = nil

        // Cleanup orphaned images (single-pass batch check)
        let allCandidates: [String?] = shapeImages + localeImages + templateBgImages + [rowBgImage]
        cleanupUnreferencedImages(allCandidates)

        scheduleSave()
    }

    func updateRowLabel(_ rowId: UUID, text: String) {
        guard let ri = rowIndex(for: rowId) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let row = rows[ri]
            rows[ri].label = presetLabel(forWidth: row.templateWidth, height: row.templateHeight)
            rows[ri].isLabelManuallySet = false
        } else {
            rows[ri].label = String(trimmed.prefix(50))
            rows[ri].isLabelManuallySet = true
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
        // Devices keep aspect ratio using geometric mean — round-trip stable
        // unlike min(scaleX, scaleY) which shrinks on every aspect-ratio change
        let uniformScale = sqrt(scaleX * scaleY)

        for i in row.shapes.indices {
            let shape = row.shapes[i]
            let templateIndex = row.owningTemplateIndex(for: shape)
            let oldOriginX = CGFloat(templateIndex) * row.templateWidth
            let newOriginX = CGFloat(templateIndex) * newWidth
            let sx = shape.type == .device ? uniformScale : scaleX
            let sy = shape.type == .device ? uniformScale : scaleY

            let scaledW = shape.width * sx
            let scaledH = shape.height * sy
            let clampDevice = shape.type == .device && (scaledW < CanvasShapeModel.deviceMinSize || scaledH < CanvasShapeModel.deviceMinSize)
            if !clampDevice {
                row.shapes[i].width = scaledW
                row.shapes[i].height = scaledH
            }

            let relX = shape.x - oldOriginX
            row.shapes[i].x = newOriginX + relX * scaleX
            row.shapes[i].y = shape.y * scaleY
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

    func shapeCenter(for row: ScreenshotRow) -> CGPoint {
        CGPoint(
            x: visibleCanvasModelCenter?.x ?? row.templateWidth / 2,
            y: visibleCanvasModelCenter?.y ?? row.templateHeight / 2
        )
    }

    func addShape(_ shape: CanvasShapeModel) {
        guard let idx = selectedRowIndex else { return }
        registerUndo("Add Shape")
        rows[idx].shapes.append(shape)
        selectShape(shape.id, in: rows[idx].id)
        justAddedShapeId = shape.id
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
        // Collect locale override image filenames before removing overrides
        let localeImageFiles = localeOverrideImageFileNames(for: id)
        LocaleService.removeShapeOverrides(&localeState, shapeId: id)
        // Cleanup orphaned images (single-pass batch check)
        let allCandidates: [String?] = removedShape.allImageFileNames + localeImageFiles
        cleanupUnreferencedImages(allCandidates)
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
        var copy = rows[rowIdx].shapes[shapeIdx].duplicated(offsetX: offsetX, offsetY: offsetY)
        LocaleService.copyShapeOverrides(&localeState, fromId: shapeId, toId: copy.id)
        copyImageFiles(for: &copy, originalId: shapeId)
        rows[rowIdx].shapes.append(copy)
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
        visibleCanvasModelCenter = nil
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

    /// All text shapes across all rows with their base text and override for the requested locale.
    func textShapesForTranslation(localeCode: String? = nil) -> [(shape: CanvasShapeModel, rowId: UUID, rowLabel: String, overrideText: String?)] {
        var results: [(shape: CanvasShapeModel, rowId: UUID, rowLabel: String, overrideText: String?)] = []
        let code = localeCode ?? localeState.activeLocaleCode
        for row in rows {
            for shape in row.shapes where shape.type == .text {
                let overrideText = localeState.override(forCode: code, shapeId: shape.id)?.text
                results.append((shape: shape, rowId: row.id, rowLabel: row.label, overrideText: overrideText))
            }
        }
        return results
    }

    func textShapesForTranslationMatrix() -> [(shape: CanvasShapeModel, rowLabel: String)] {
        textShapesForTranslation().map { (shape: $0.shape, rowLabel: $0.rowLabel) }
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
    private var baseTextUndoTask: DispatchWorkItem?
    private var baseTextBaseRows: [ScreenshotRow]?

    func updateBaseText(shapeId: UUID, text: String) {
        guard let loc = shapeLocation(for: shapeId) else { return }

        // Capture undo state only at the start of a base text editing sequence
        if baseTextBaseRows == nil {
            baseTextBaseRows = rows
        }

        rows[loc.rowIndex].shapes[loc.shapeIndex].text = text
        scheduleSave()

        // Debounce undo registration so rapid keystrokes collapse into one entry
        baseTextUndoTask?.cancel()
        guard let savedRows = baseTextBaseRows else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.registerUndoWithBase("Edit Base Text", base: savedRows, baseLocaleState: self.localeState)
            self.baseTextBaseRows = nil
        }
        baseTextUndoTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: task)
    }

    func updateTranslationText(shapeId: UUID, text: String) {
        updateTranslationText(shapeId: shapeId, localeCode: localeState.activeLocaleCode, text: text)
    }

    func updateTranslationText(shapeId: UUID, localeCode code: String, text: String) {
        guard code != localeState.baseLocaleCode else { return }

        // Capture undo state only at the start of a translation editing sequence
        if translationBaseLocaleState == nil {
            translationBaseLocaleState = localeState
        }

        let key = shapeId.uuidString
        var override = localeState.overrides[code]?[key] ?? ShapeLocaleOverride()
        override.text = text.isEmpty ? nil : text
        LocaleService.setShapeOverride(&localeState, localeCode: code, shapeId: shapeId, override: override.isEmpty ? nil : override)
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

    func resetTranslationText(shapeId: UUID) {
        resetTranslationText(shapeId: shapeId, localeCode: localeState.activeLocaleCode)
    }

    func resetTranslationText(shapeId: UUID, localeCode code: String) {
        guard code != localeState.baseLocaleCode else { return }
        guard var override = localeState.override(forCode: code, shapeId: shapeId) else { return }

        registerUndo("Reset Translation")
        translationUndoTask?.cancel()
        translationUndoTask = nil
        translationBaseLocaleState = nil
        override.text = nil
        LocaleService.setShapeOverride(&localeState, localeCode: code, shapeId: shapeId, override: override.isEmpty ? nil : override)
        scheduleSave()
    }

    func resetLocaleImageOverride(shapeId: UUID) {
        let code = localeState.activeLocaleCode
        guard var override = localeState.override(forCode: code, shapeId: shapeId),
              let oldFile = override.overrideImageFileName else { return }
        registerUndo("Reset Image Override")
        override.overrideImageFileName = nil
        if override.isEmpty {
            LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: nil)
        } else {
            LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override)
        }
        cleanupUnreferencedImage(oldFile)
        scheduleSave()
    }

    func resetActiveLocaleToBase() {
        let code = localeState.activeLocaleCode
        guard code != localeState.baseLocaleCode else { return }
        guard let localeOverrides = localeState.overrides[code], !localeOverrides.isEmpty else { return }

        registerUndo("Reset Locale to Base")
        translationUndoTask?.cancel()
        translationUndoTask = nil
        translationBaseLocaleState = nil

        let overrideImages = localeOverrides.values.compactMap(\.overrideImageFileName)
        localeState.overrides.removeValue(forKey: code)
        cleanupUnreferencedImages(overrideImages)
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
        // Collect override image filenames before removing the locale
        let overrideImages = localeState.overrides[code]?.values.compactMap(\.overrideImageFileName) ?? []
        LocaleService.removeLocale(&localeState, code: code)
        cleanupUnreferencedImages(overrideImages)
        scheduleSave()
    }

    // MARK: - Clipboard

    var clipboard: CanvasShapeModel?
    private var clipboardPasteboardChangeCount: Int = 0

    func copySelectedShape() {
        guard let rowIdx = selectedRowIndex,
              let shape = rows[rowIdx].shapes.first(where: { $0.id == selectedShapeId }) else { return }
        clipboard = shape
        clipboardPasteboardChangeCount = NSPasteboard.general.changeCount
    }

    func pasteShape() {
        guard let rowIdx = selectedRowIndex else { return }

        let pasteboardChanged = NSPasteboard.general.changeCount != clipboardPasteboardChangeCount

        // If pasteboard changed since last internal copy, try system image first
        if pasteboardChanged,
           let image = NSImage(pasteboard: NSPasteboard.general), image.isValid {
            let row = rows[rowIdx]
            let center = canvasMouseModelPosition ?? CGPoint(x: row.templateWidth / 2, y: row.templateHeight / 2)
            addImageShape(image: image, centerX: center.x, centerY: center.y)
            return
        }

        // Otherwise paste from internal shape clipboard
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
        LocaleService.copyShapeOverrides(&localeState, fromId: source.id, toId: pasted.id)
        copyImageFiles(for: &pasted, originalId: source.id)
        rows[rowIdx].shapes.append(pasted)
        selectShape(pasted.id, in: rows[rowIdx].id)
        scheduleSave()
    }

    func addImageShape(image: NSImage, centerX: CGFloat, centerY: CGFloat) {
        guard let rowIdx = selectedRowIndex else { return }
        let row = rows[rowIdx]

        if let detectedCategory = Self.detectScreenshotDevice(image) {
            let shape = CanvasShapeModel.defaultDeviceFromRow(row, centerX: centerX, centerY: centerY, detectedCategory: detectedCategory)
            addShape(shape)
            saveImage(image, for: shape.id)
            return
        }

        let imgW = image.size.width
        let imgH = image.size.height
        let maxW = row.templateWidth * 0.8
        let maxH = row.templateHeight * 0.8
        let scale = min(maxW / imgW, maxH / imgH, 1.0)
        let w = imgW * scale
        let h = imgH * scale
        let shape = CanvasShapeModel(
            type: .image,
            x: centerX - w / 2,
            y: centerY - h / 2,
            width: w,
            height: h,
            color: .clear
        )
        addShape(shape)
        saveImage(image, for: shape.id)
    }

    // Known screenshot pixel sizes (portrait "WxH") → device category
    private static let knownScreenshotSizes: [String: DeviceCategory] = {
        var map = [String: DeviceCategory]()
        // iPhone
        for size in [
            "750x1334",   // iPhone SE / 8
            "828x1792",   // iPhone XR / 11
            "1080x1920",  // iPhone 6/7/8 Plus
            "1125x2436",  // iPhone X / XS / 11 Pro
            "1080x2340",  // iPhone 12 mini / 13 mini
            "1170x2532",  // iPhone 12 / 13 / 14
            "1179x2556",  // iPhone 14 Pro / 15 / 16
            "1206x2622",  // iPhone 16 Pro / 17 / 17 Pro
            "1260x2736",  // iPhone Air
            "1242x2688",  // iPhone XS Max / 11 Pro Max
            "1284x2778",  // iPhone 12/13 Pro Max
            "1290x2796",  // iPhone 14 Pro Max / 15 Pro Max / 16 Plus
            "1320x2868",  // iPhone 16 Pro Max / 17 Pro Max
        ] { map[size] = .iphone }
        // iPad Pro 11"
        for size in [
            "1668x2388",  // iPad Pro 11" (3rd/4th gen)
            "1668x2420",  // iPad Pro 11" (M4)
        ] { map[size] = .ipadPro11 }
        // iPad Pro 13"
        for size in [
            "2048x2732",  // iPad Pro 12.9" (3rd-6th gen)
            "2064x2752",  // iPad Pro 13" (M4)
        ] { map[size] = .ipadPro13 }
        return map
    }()

    /// Detect if an image looks like a device screenshot. Returns the matching category or nil.
    static func detectScreenshotDevice(_ image: NSImage) -> DeviceCategory? {
        guard let rep = image.representations.first else { return nil }
        let pw = rep.pixelsWide
        let ph = rep.pixelsHigh
        guard pw > 0, ph > 0 else { return nil }
        // Normalize to portrait for lookup
        let (w, h) = pw > ph ? (ph, pw) : (pw, ph)
        if let category = knownScreenshotSizes["\(w)x\(h)"] { return category }
        // Heuristic fallback for phones
        let ratio = CGFloat(h) / CGFloat(w)
        if w >= 640 && w <= 1600 && ratio >= 1.7 && ratio <= 2.4 { return .iphone }
        // Heuristic fallback for iPads
        if w >= 1600 && w <= 2200 && ratio >= 1.2 && ratio <= 1.5 { return w >= 2000 ? .ipadPro13 : .ipadPro11 }
        return nil
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

        let isNonBaseLocale = !localeState.isBaseLocale
        let suffix = isNonBaseLocale ? "-\(localeState.activeLocaleCode)" : ""
        let fileName = "\(shapeId.uuidString)\(suffix).png"
        let url = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)

        guard let pngData = ExportService.pngData(from: image) else { return }

        try? pngData.write(to: url, options: .atomic)
        screenshotImages[fileName] = image

        if isNonBaseLocale {
            // Store as locale override instead of modifying the base shape
            let shape = rows[location.rowIndex].shapes[location.shapeIndex]
            let existingOverride = localeState.override(forCode: localeState.activeLocaleCode, shapeId: shapeId)
            var override = existingOverride ?? ShapeLocaleOverride()
            let previousOverrideFile = override.overrideImageFileName
            override.overrideImageFileName = fileName
            LocaleService.setShapeOverride(&localeState, shapeId: shape.id, override: override)
            if let oldFile = previousOverrideFile, oldFile != fileName {
                cleanupUnreferencedImage(oldFile)
            }
        } else {
            // Update the shape's image reference directly (base locale)
            var shape = rows[location.rowIndex].shapes[location.shapeIndex]
            let previousFile = shape.displayImageFileName
            shape.displayImageFileName = fileName
            rows[location.rowIndex].shapes[location.shapeIndex] = shape

            if let oldFile = previousFile, oldFile != fileName {
                cleanupUnreferencedImage(oldFile)
            }
        }
        scheduleSave()
    }

    func clearImage(for shapeId: UUID) {
        guard let location = shapeLocation(for: shapeId) else { return }

        if !localeState.isBaseLocale {
            let existingOverride = localeState.override(forCode: localeState.activeLocaleCode, shapeId: shapeId)
            guard var override = existingOverride, override.overrideImageFileName != nil else { return }
            let oldFile = override.overrideImageFileName
            override.overrideImageFileName = nil
            LocaleService.setShapeOverride(&localeState, shapeId: shapeId, override: override)
            if let oldFile { cleanupUnreferencedImage(oldFile) }
        } else {
            var shape = rows[location.rowIndex].shapes[location.shapeIndex]
            let previousFile = shape.displayImageFileName
            shape.displayImageFileName = nil
            rows[location.rowIndex].shapes[location.shapeIndex] = shape
            if let oldFile = previousFile { cleanupUnreferencedImage(oldFile) }
        }
        scheduleSave()
    }

    func loadScreenshotImages() {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)

        // Cancel any in-flight load from a previous call
        imageLoadTask?.cancel()

        let toLoad = allReferencedImageFileNames().filter { screenshotImages[$0] == nil }
        guard !toLoad.isEmpty else { return }

        isLoadingImages = true

        // Load images on a background thread, then update on main
        imageLoadTask = Task.detached { [weak self] in
            var loaded: [String: NSImage] = [:]
            for fileName in toLoad {
                if Task.isCancelled { return }
                let url = resourcesURL.appendingPathComponent(fileName)
                if let image = NSImage(contentsOf: url) {
                    loaded[fileName] = image
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.activeProjectId == activeId else { return }
                for (key, image) in loaded {
                    self.screenshotImages[key] = image
                }
                self.isLoadingImages = false
            }
        }
    }

    // MARK: - Custom Fonts

    private static let fontExtensions: Set<String> = ["ttf", "otf", "ttc"]

    private func loadCustomFonts() {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: resourcesURL, includingPropertiesForKeys: nil) else { return }

        for file in files where Self.fontExtensions.contains(file.pathExtension.lowercased()) {
            let fileName = file.lastPathComponent
            guard customFonts[fileName] == nil else { continue }
            if let familyName = registerFont(at: file) {
                customFonts[fileName] = familyName
            }
        }
    }

    private func unregisterCustomFonts() {
        guard let activeId = activeProjectId else {
            customFonts.removeAll()
            return
        }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        for fileName in customFonts.keys {
            let url = resourcesURL.appendingPathComponent(fileName) as CFURL
            CTFontManagerUnregisterFontsForURL(url, .process, nil)
        }
        customFonts.removeAll()
    }

    func importCustomFont(from url: URL) {
        guard let activeId = activeProjectId else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let fileName = url.lastPathComponent
        let destURL = PersistenceService.resourcesDir(activeId).appendingPathComponent(fileName)
        let fm = FileManager.default

        if fm.fileExists(atPath: destURL.path) {
            // Already imported — just make sure it's registered
            if customFonts[fileName] == nil, let familyName = registerFont(at: destURL) {
                customFonts[fileName] = familyName
            }
            return
        }

        guard (try? fm.copyItem(at: url, to: destURL)) != nil else { return }
        if let familyName = registerFont(at: destURL) {
            customFonts[fileName] = familyName
        }
    }

    func removeCustomFont(_ fileName: String) {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let url = resourcesURL.appendingPathComponent(fileName)

        CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: url)
        customFonts.removeValue(forKey: fileName)
    }

    private func registerFont(at url: URL) -> String? {
        // May fail if already registered — that's OK
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let first = descriptors.first,
              let familyName = CTFontDescriptorCopyAttribute(first, kCTFontFamilyNameAttribute) as? String else {
            return nil
        }
        return familyName
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
        removeImageFile(fileName)
    }

    /// Batch cleanup: collects all referenced filenames once, then removes any candidate that is unreferenced.
    private func cleanupUnreferencedImages(_ fileNames: [String?]) {
        let candidates = Set(fileNames.compactMap { $0 })
        guard !candidates.isEmpty else { return }
        let referenced = allReferencedImageFileNames()
        for fileName in candidates where !referenced.contains(fileName) {
            removeImageFile(fileName)
        }
    }

    private func removeImageFile(_ fileName: String) {
        screenshotImages.removeValue(forKey: fileName)
        if let projectId = activeProjectId {
            let fileURL = PersistenceService.resourcesDir(projectId).appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: fileURL)
        }
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

    /// Copy image files for a duplicated shape so it has its own independent files.
    /// Updates the shape's image references in-place and copies locale override image files.
    private func copyImageFiles(for newShape: inout CanvasShapeModel, originalId: UUID) {
        guard let activeId = activeProjectId else { return }
        let resourcesURL = PersistenceService.resourcesDir(activeId)
        let fm = FileManager.default

        // Copy base image file (imageFileName or screenshotFileName)
        if let originalFile = newShape.displayImageFileName {
            let srcURL = resourcesURL.appendingPathComponent(originalFile)
            let newFile = "\(newShape.id.uuidString).png"
            let dstURL = resourcesURL.appendingPathComponent(newFile)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.copyItem(at: srcURL, to: dstURL)
                newShape.displayImageFileName = newFile
                screenshotImages[newFile] = screenshotImages[originalFile]
            }
        }

        // Copy locale override image files
        let originalKey = originalId.uuidString
        let newKey = newShape.id.uuidString
        for localeCode in localeState.overrides.keys {
            guard var override = localeState.overrides[localeCode]?[originalKey],
                  let originalFile = override.overrideImageFileName else { continue }
            let srcURL = resourcesURL.appendingPathComponent(originalFile)
            let newFile = "\(newShape.id.uuidString)-\(localeCode).png"
            let dstURL = resourcesURL.appendingPathComponent(newFile)
            if fm.fileExists(atPath: srcURL.path) {
                try? fm.copyItem(at: srcURL, to: dstURL)
                override.overrideImageFileName = newFile
                localeState.overrides[localeCode]?[newKey] = override
                screenshotImages[newFile] = screenshotImages[originalFile]
            }
        }
    }

    /// Collect all screenshot filenames from locale overrides for a shape.
    private func localeOverrideImageFileNames(for shapeId: UUID) -> [String] {
        let key = shapeId.uuidString
        return localeState.overrides.values.compactMap { $0[key]?.overrideImageFileName }
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
        // Check base shape and background references
        let referencedInRows = rows.contains { row in
            row.backgroundImageConfig.fileName == fileName ||
            row.templates.contains { $0.backgroundImageConfig.fileName == fileName } ||
            row.shapes.contains { shape in
                shape.allImageFileNames.contains(fileName)
            }
        }
        if referencedInRows { return true }

        // Check locale override image references
        return localeState.overrides.values.contains { shapeOverrides in
            shapeOverrides.values.contains { $0.overrideImageFileName == fileName }
        }
    }

    /// Collect all referenced image filenames in a single pass (for batch cleanup).
    private func allReferencedImageFileNames() -> Set<String> {
        var result = Set<String>()
        for row in rows {
            if let f = row.backgroundImageConfig.fileName { result.insert(f) }
            for template in row.templates {
                if let f = template.backgroundImageConfig.fileName { result.insert(f) }
            }
            for shape in row.shapes {
                for f in shape.allImageFileNames { result.insert(f) }
            }
        }
        for shapeOverrides in localeState.overrides.values {
            for override in shapeOverrides.values {
                if let f = override.overrideImageFileName { result.insert(f) }
            }
        }
        return result
    }

    private func makeDefaultRow(id: UUID = UUID(), label: String? = nil, width: CGFloat? = nil, height: CGFloat? = nil) -> ScreenshotRow {
        let defaultSize = UserDefaults.standard.string(forKey: "defaultScreenshotSize") ?? "1242x2688"
        let parsedSize = parseSizeString(defaultSize)
        let w: CGFloat = width ?? parsedSize?.width ?? 1242
        let h: CGFloat = height ?? parsedSize?.height ?? 2688
        let storedTemplateCount = UserDefaults.standard.integer(forKey: "defaultTemplateCount")
        let templateCount = storedTemplateCount > 0 ? storedTemplateCount : 3
        let templates = (0..<templateCount).map { index in
            ScreenshotTemplate(backgroundColor: Self.templateColors[index % Self.templateColors.count])
        }
        let deviceCategoryRaw = UserDefaults.standard.string(forKey: "defaultDeviceCategory") ?? "iphone"
        let deviceCategory = DeviceCategory(rawValue: deviceCategoryRaw)
        let deviceFrameId = UserDefaults.standard.string(forKey: "defaultDeviceFrameId").flatMap { $0.isEmpty ? nil : $0 }
        let resolvedFrame = deviceFrameId.flatMap { DeviceFrameCatalog.frame(for: $0) }

        var shapes: [CanvasShapeModel] = []
        if let deviceCategory {
            shapes = (0..<templateCount).map { index in
                var device = CanvasShapeModel.defaultDevice(
                    centerX: CGFloat(index) * w + w / 2,
                    centerY: h / 2,
                    templateHeight: h,
                    category: deviceCategory
                )
                if let resolvedFrame {
                    device.deviceCategory = resolvedFrame.fallbackCategory
                    device.deviceFrameId = resolvedFrame.id
                    device.adjustToDeviceAspectRatio(centerX: CGFloat(index) * w + w / 2)
                }
                return device
            }
        }
        let resolvedLabel = label ?? presetLabel(forWidth: w, height: h)
        return ScreenshotRow(
            id: id,
            label: resolvedLabel,
            templates: templates,
            templateWidth: w,
            templateHeight: h,
            defaultDeviceCategory: deviceCategory,
            defaultDeviceFrameId: deviceFrameId,
            shapes: shapes,
            isLabelManuallySet: label != nil
        )
    }

}
