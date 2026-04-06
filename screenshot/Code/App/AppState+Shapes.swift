import SwiftUI

extension AppState {

    // MARK: - Shapes

    func shapeCenter(for row: ScreenshotRow) -> CGPoint {
        CGPoint(
            x: visibleCanvasModelCenter?.x ?? row.templateWidth / 2,
            y: visibleCanvasModelCenter?.y ?? row.templateHeight / 2
        )
    }

    func addShape(_ shape: CanvasShapeModel) {
        guard let idx = selectedRowIndex else { return }
        registerUndoForRow(at: idx, "Add Shape")
        rows[idx].shapes.append(shape)
        selectShape(shape.id, in: rows[idx].id)
        justAddedShapeId = shape.id
        scheduleSave()
    }

    func updateShape(_ shape: CanvasShapeModel) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        registerUndoForRow(at: rowIdx, "Edit Shape")
        let baseShape = rows[rowIdx].shapes[shapeIdx]
        rows[rowIdx].shapes[shapeIdx] = LocaleService.splitUpdate(base: baseShape, updated: shape, localeState: &localeState)
        scheduleSave()
    }

    private static let continuousEditInterval: CFAbsoluteTime = 1.0 / 30

    /// Update shape without registering undo on every call — undo is captured once
    /// at the start and finalized after changes stop (debounced). Throttled to ~30fps
    /// to avoid expensive re-renders on every slider tick.
    func updateShapeContinuous(_ shape: CanvasShapeModel) {
        if continuousEditBaseRow == nil, let rowIdx = selectedRowIndex {
            continuousEditBaseRow = rows[rowIdx]
            continuousEditBaseLocaleState = localeState
        }

        let now = CFAbsoluteTimeGetCurrent()
        let interval = Self.continuousEditInterval

        if now - continuousEditLastApply >= interval {
            applyContinuousEdit(shape)
            continuousEditLastApply = now
            flushPendingContinuousEdit()
        } else {
            continuousEditPending = shape
            if continuousEditFlushTask == nil {
                let task = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.flushPendingContinuousEdit()
                }
                continuousEditFlushTask = task
                let delay = interval - (now - continuousEditLastApply)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
            }
        }

        // Debounced undo registration
        continuousEditUndoTask?.cancel()
        let undoTask = DispatchWorkItem { [weak self] in
            guard let self, let baseRow = self.continuousEditBaseRow else { return }
            self.flushPendingContinuousEdit()
            self.registerUndoForRowWithBase("Edit Shape", baseRow: baseRow, baseLocaleState: self.continuousEditBaseLocaleState)
            self.continuousEditBaseRow = nil
            self.continuousEditBaseLocaleState = nil
        }
        continuousEditUndoTask = undoTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: undoTask)
    }

    private func flushPendingContinuousEdit() {
        guard let pending = continuousEditPending else { return }
        applyContinuousEdit(pending)
        continuousEditPending = nil
        continuousEditFlushTask?.cancel()
        continuousEditFlushTask = nil
        continuousEditLastApply = CFAbsoluteTimeGetCurrent()
    }

    private func applyContinuousEdit(_ shape: CanvasShapeModel) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shape.id }) else { return }
        let baseShape = rows[rowIdx].shapes[shapeIdx]
        rows[rowIdx].shapes[shapeIdx] = LocaleService.splitUpdate(base: baseShape, updated: shape, localeState: &localeState)
        scheduleSave()
    }

    func deleteAllShapes(ofType type: ShapeType, in rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        let matching = rows[idx].shapes.filter { $0.type == type }
        guard !matching.isEmpty else { return }
        registerUndoForRow(at: idx, "Delete All \(type.pluralLabel)")
        let allCandidates = imageFileNames(for: matching)
        let matchingIds = Set(matching.map(\.id))
        for shape in matching {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        selectedShapeIds.subtract(matchingIds)
        rows[idx].shapes.removeAll { $0.type == type }
        cleanupUnreferencedImages(allCandidates)
        scheduleSave()
    }

    enum CenterAxis {
        case vertically, horizontally, both
    }

    func centerAllDevices(in rowId: UUID, axis: CenterAxis) {
        guard let idx = rowIndex(for: rowId) else { return }
        let row = rows[idx]
        let deviceIndices = row.shapes.indices.filter { row.shapes[$0].type == .device }
        guard !deviceIndices.isEmpty else { return }
        registerUndoForRow(at: idx, "Center All Devices")
        for i in deviceIndices {
            let shape = rows[idx].shapes[i]
            if axis != .vertically {
                let templateIndex = row.owningTemplateIndex(for: shape)
                let templateLeft = CGFloat(templateIndex) * row.templateWidth
                rows[idx].shapes[i].x = templateLeft + (row.templateWidth - shape.width) / 2
            }
            if axis != .horizontally {
                rows[idx].shapes[i].y = (row.templateHeight - shape.height) / 2
            }
        }
        scheduleSave()
    }

    func changeAllDevices(in rowId: UUID, toCategory category: DeviceCategory) {
        changeAllDevices(in: rowId) {
            let imageSize = category == .invisible
                ? $0.displayImageFileName.flatMap { self.screenshotImages[$0] }?.size
                : nil
            $0.selectAbstractDevice(category, screenshotImageSize: imageSize)
        }
    }

    func changeAllDevices(in rowId: UUID, toFrame frame: DeviceFrame) {
        changeAllDevices(in: rowId) { $0.selectRealFrame(frame) }
    }

    private func changeAllDevices(in rowId: UUID, mutate: (inout CanvasShapeModel) -> Void) {
        guard let idx = rowIndex(for: rowId) else { return }
        let shapes = rows[idx].shapes
        let deviceIndices = shapes.indices.filter { shapes[$0].type == .device }
        guard !deviceIndices.isEmpty else { return }
        registerUndoForRow(at: idx, "Change All Row Devices")
        for i in deviceIndices {
            mutate(&rows[idx].shapes[i])
        }
        scheduleSave()
    }

    func deleteShape(_ id: UUID) {
        guard let location = shapeLocation(for: id) else { return }
        registerUndoForRow(at: location.rowIndex, "Delete Shape")
        let removedShape = rows[location.rowIndex].shapes.remove(at: location.shapeIndex)
        // Collect locale override image filenames before removing overrides
        let localeImageFiles = localeOverrideImageFileNames(for: id)
        LocaleService.removeShapeOverrides(&localeState, shapeId: id)
        // Cleanup orphaned images (single-pass batch check)
        let allCandidates: [String?] = removedShape.allImageFileNames + localeImageFiles
        cleanupUnreferencedImages(allCandidates)
        selectedShapeIds.remove(id)
        scheduleSave()
    }

    func deleteSelectedShapes() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let idsToDelete = selectedShapeIds
        let matching = rows[rowIdx].shapes.filter { idsToDelete.contains($0.id) }
        guard !matching.isEmpty else { return }
        registerUndoForRow(at: rowIdx, "Delete Shapes")
        var allCandidates: [String?] = []
        for shape in matching {
            allCandidates.append(contentsOf: shape.allImageFileNames)
            allCandidates.append(contentsOf: localeOverrideImageFileNames(for: shape.id))
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        rows[rowIdx].shapes.removeAll { idsToDelete.contains($0.id) }
        selectedShapeIds = []
        cleanupUnreferencedImages(allCandidates)
        scheduleSave()
    }

    func duplicateSelectedShape() {
        guard let id = selectedShapeId else { return }
        _ = insertDuplicate(of: id, offsetX: 50, offsetY: 50, undoName: "Duplicate Shape")
    }

    func duplicateSelectedShapes() {
        guard let rowIdx = selectedRowIndex, selectedShapeIds.count > 1 else {
            duplicateSelectedShape()
            return
        }
        let ids = selectedShapeIds
        let shapes = rows[rowIdx].shapes.filter { ids.contains($0.id) }
        guard !shapes.isEmpty else { return }
        registerUndoForRow(at: rowIdx, "Duplicate Shapes")
        var newIds: Set<UUID> = []
        for shape in shapes {
            var copy = shape.duplicated(offsetX: 50, offsetY: 50)
            LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
            copyImageFiles(for: &copy, originalId: shape.id)
            rows[rowIdx].shapes.append(copy)
            newIds.insert(copy.id)
        }
        selectedShapeIds = newIds
        scheduleSave()
    }

    @discardableResult
    func insertDuplicate(of shapeId: UUID, offsetX: CGFloat = 0, offsetY: CGFloat = 0, undoName: String) -> UUID? {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shapeId }) else { return nil }
        registerUndoForRow(at: rowIdx, undoName)
        var copy = rows[rowIdx].shapes[shapeIdx].duplicated(offsetX: offsetX, offsetY: offsetY)
        LocaleService.copyShapeOverrides(&localeState, fromId: shapeId, toId: copy.id)
        copyImageFiles(for: &copy, originalId: shapeId)
        rows[rowIdx].shapes.append(copy)
        selectShape(copy.id, in: rows[rowIdx].id)
        scheduleSave()
        return copy.id
    }

    enum DuplicateDirection {
        case all, left, right
    }

    func duplicateShapesToTemplates(_ shapeIds: Set<UUID>, direction: DuplicateDirection = .all) {
        guard let rowIdx = selectedRowIndex else { return }
        let row = rows[rowIdx]
        guard row.templates.count > 1 else { return }
        let shapes = row.shapes.filter { shapeIds.contains($0.id) }
        guard !shapes.isEmpty else { return }
        registerUndoForRow(at: rowIdx, "Duplicate to Screenshots")
        for shape in shapes {
            let sourceIndex = row.owningTemplateIndex(for: shape)
            let sourceCenterX = row.templateCenterX(at: sourceIndex)
            let targetIndices: Range<Int>
            switch direction {
            case .all: targetIndices = 0..<row.templates.count
            case .left: targetIndices = 0..<sourceIndex
            case .right: targetIndices = (sourceIndex + 1)..<row.templates.count
            }
            for targetIndex in targetIndices where targetIndex != sourceIndex {
                let targetCenterX = row.templateCenterX(at: targetIndex)
                let offset = targetCenterX - sourceCenterX
                var copy = shape.duplicated(offsetX: offset)
                LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
                copyImageFiles(for: &copy, originalId: shape.id)
                rows[rowIdx].shapes.append(copy)
            }
        }
        scheduleSave()
    }

    func bringShapeToFront(_ id: UUID) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == id }),
              shapeIdx < rows[rowIdx].shapes.count - 1 else { return }
        registerUndoForRow(at: rowIdx, "Bring to Front")
        let shape = rows[rowIdx].shapes.remove(at: shapeIdx)
        rows[rowIdx].shapes.append(shape)
        selectShape(id, in: rows[rowIdx].id)
        scheduleSave()
    }

    func sendShapeToBack(_ id: UUID) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == id }),
              shapeIdx > 0 else { return }
        registerUndoForRow(at: rowIdx, "Send to Back")
        let shape = rows[rowIdx].shapes.remove(at: shapeIdx)
        rows[rowIdx].shapes.insert(shape, at: 0)
        selectShape(id, in: rows[rowIdx].id)
        scheduleSave()
    }

    func bringSelectedShapesToFront() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        // Check if already at front
        let suffixIds = Set(rows[rowIdx].shapes.suffix(ids.count).map(\.id))
        guard suffixIds != ids else { return }
        registerUndoForRow(at: rowIdx, "Bring to Front")
        let selected = rows[rowIdx].shapes.filter { ids.contains($0.id) }
        rows[rowIdx].shapes.removeAll { ids.contains($0.id) }
        rows[rowIdx].shapes.append(contentsOf: selected)
        scheduleSave()
    }

    func sendSelectedShapesToBack() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        let prefixIds = Set(rows[rowIdx].shapes.prefix(ids.count).map(\.id))
        guard prefixIds != ids else { return }
        registerUndoForRow(at: rowIdx, "Send to Back")
        let selected = rows[rowIdx].shapes.filter { ids.contains($0.id) }
        rows[rowIdx].shapes.removeAll { ids.contains($0.id) }
        rows[rowIdx].shapes.insert(contentsOf: selected, at: 0)
        scheduleSave()
    }

    func deleteSelectedShape() {
        if selectedShapeIds.count > 1 {
            deleteSelectedShapes()
        } else if let id = selectedShapeId {
            deleteShape(id)
        }
    }

    // MARK: - Nudge

    func nudgeSelectedShapes(dx: CGFloat, dy: CGFloat) {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }

        // Capture undo state only at the start of a nudge sequence
        if nudgeBaseRow == nil {
            nudgeBaseRow = rows[rowIdx]
        }

        let ids = selectedShapeIds
        for i in rows[rowIdx].shapes.indices {
            if ids.contains(rows[rowIdx].shapes[i].id) {
                rows[rowIdx].shapes[i].x += dx
                rows[rowIdx].shapes[i].y += dy
            }
        }
        scheduleSave()

        // Debounce the undo registration so rapid key repeats collapse into one entry
        nudgeUndoTask?.cancel()
        guard let savedBaseRow = nudgeBaseRow else { return }
        let actionName = ids.count > 1 ? "Move Shapes" : "Move Shape"
        let nudgeTask = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.registerUndoForRowWithBase(actionName, baseRow: savedBaseRow)
            self.nudgeBaseRow = nil
        }
        nudgeUndoTask = nudgeTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: nudgeTask)
    }

    // MARK: - Option+Drag Duplicate

    func duplicateShapeForOptionDrag(_ shapeId: UUID) -> UUID? {
        insertDuplicate(of: shapeId, undoName: "Duplicate Shape")
    }

    // MARK: - Clipboard

    func copySelectedShapes() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        clipboard = rows[rowIdx].shapes.filter { ids.contains($0.id) }
        clipboardPasteboardChangeCount = NSPasteboard.general.changeCount
    }

    func pasteShapes() {
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
        guard !clipboard.isEmpty else { return }
        registerUndoForRow(at: rowIdx, clipboard.count == 1 ? "Paste Shape" : "Paste Shapes")
        var newIds: Set<UUID> = []
        // Compute group center for mouse-relative positioning
        let groupMinX = clipboard.map(\.x).min() ?? 0
        let groupMinY = clipboard.map(\.y).min() ?? 0
        let groupMaxX = clipboard.map { $0.x + $0.width }.max() ?? 0
        let groupMaxY = clipboard.map { $0.y + $0.height }.max() ?? 0
        let groupCenterX = (groupMinX + groupMaxX) / 2
        let groupCenterY = (groupMinY + groupMaxY) / 2

        for source in clipboard {
            var pasted: CanvasShapeModel
            if let mousePos = canvasMouseModelPosition, clipboard.count == 1 {
                pasted = source.duplicated()
                pasted.x = mousePos.x - pasted.width / 2
                pasted.y = mousePos.y - pasted.height / 2
            } else if let mousePos = canvasMouseModelPosition {
                pasted = source.duplicated()
                pasted.x = mousePos.x + (source.x - groupCenterX)
                pasted.y = mousePos.y + (source.y - groupCenterY)
            } else {
                pasted = source.duplicated(offsetX: 20, offsetY: 20)
            }
            LocaleService.copyShapeOverrides(&localeState, fromId: source.id, toId: pasted.id)
            copyImageFiles(for: &pasted, originalId: source.id)
            rows[rowIdx].shapes.append(pasted)
            newIds.insert(pasted.id)
        }
        selectedShapeIds = newIds
        scheduleSave()
    }

    // MARK: - Group Drag

    func applyGroupDrag(offset: CGSize) {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        registerUndoForRow(at: rowIdx, ids.count > 1 ? "Move Shapes" : "Move Shape")
        for i in rows[rowIdx].shapes.indices {
            if ids.contains(rows[rowIdx].shapes[i].id) {
                rows[rowIdx].shapes[i].x += offset.width
                rows[rowIdx].shapes[i].y += offset.height
            }
        }
        scheduleSave()
    }

    // MARK: - Option+Drag Duplicate for Multi-Selection

    func duplicateShapesForOptionDrag() {
        guard let rowIdx = selectedRowIndex, selectedShapeIds.count > 1 else { return }
        let ids = selectedShapeIds
        let shapes = rows[rowIdx].shapes.filter { ids.contains($0.id) }
        guard !shapes.isEmpty else { return }
        registerUndoForRow(at: rowIdx, "Duplicate Shapes")
        var newIds: Set<UUID> = []
        for shape in shapes {
            var copy = shape.duplicated()
            copy.x = shape.x  // No offset — drag will position them
            copy.y = shape.y
            LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
            copyImageFiles(for: &copy, originalId: shape.id)
            rows[rowIdx].shapes.append(copy)
            newIds.insert(copy.id)
        }
        selectedShapeIds = newIds
        scheduleSave()
    }

    // MARK: - Align Selected Shapes

    enum ShapeAlignment: Equatable {
        case left, centerH, right, top, centerV, bottom
        case distributeH, distributeV
    }

    func alignSelectedShapes(_ alignment: ShapeAlignment) {
        guard let rowIdx = selectedRowIndex, selectedShapeIds.count >= 2 else { return }
        let ids = selectedShapeIds
        let indices = rows[rowIdx].shapes.indices.filter { ids.contains(rows[rowIdx].shapes[$0].id) }
        guard indices.count >= 2 else { return }
        if alignment == .distributeH || alignment == .distributeV {
            guard indices.count >= 3 else { return }
        }

        registerUndoForRow(at: rowIdx, "Align Shapes")

        let shapes = indices.map { rows[rowIdx].shapes[$0] }

        switch alignment {
        case .left:
            let target = shapes.map(\.x).min()!
            for i in indices { rows[rowIdx].shapes[i].x = target }
        case .centerH:
            let centers = shapes.map { $0.x + $0.width / 2 }
            let target = centers.reduce(0, +) / CGFloat(centers.count)
            for i in indices { rows[rowIdx].shapes[i].x = target - rows[rowIdx].shapes[i].width / 2 }
        case .right:
            let target = shapes.map { $0.x + $0.width }.max()!
            for i in indices { rows[rowIdx].shapes[i].x = target - rows[rowIdx].shapes[i].width }
        case .top:
            let target = shapes.map(\.y).min()!
            for i in indices { rows[rowIdx].shapes[i].y = target }
        case .centerV:
            let centers = shapes.map { $0.y + $0.height / 2 }
            let target = centers.reduce(0, +) / CGFloat(centers.count)
            for i in indices { rows[rowIdx].shapes[i].y = target - rows[rowIdx].shapes[i].height / 2 }
        case .bottom:
            let target = shapes.map { $0.y + $0.height }.max()!
            for i in indices { rows[rowIdx].shapes[i].y = target - rows[rowIdx].shapes[i].height }
        case .distributeH:
            distributeShapes(indices: indices, rowIdx: rowIdx, posKey: \.x, sizeKey: \.width)
        case .distributeV:
            distributeShapes(indices: indices, rowIdx: rowIdx, posKey: \.y, sizeKey: \.height)
        }
        scheduleSave()
    }

    private func distributeShapes(indices: [Int], rowIdx: Int, posKey: WritableKeyPath<CanvasShapeModel, CGFloat>, sizeKey: KeyPath<CanvasShapeModel, CGFloat>) {
        let sorted = indices.sorted { rows[rowIdx].shapes[$0][keyPath: posKey] < rows[rowIdx].shapes[$1][keyPath: posKey] }
        let first = rows[rowIdx].shapes[sorted.first!]
        let last = rows[rowIdx].shapes[sorted.last!]
        let totalSpan = (last[keyPath: posKey] + last[keyPath: sizeKey]) - first[keyPath: posKey]
        let totalSize = sorted.map { rows[rowIdx].shapes[$0][keyPath: sizeKey] }.reduce(0, +)
        let gap = (totalSpan - totalSize) / CGFloat(sorted.count - 1)
        var current = first[keyPath: posKey]
        for idx in sorted {
            rows[rowIdx].shapes[idx][keyPath: posKey] = current
            current += rows[rowIdx].shapes[idx][keyPath: sizeKey] + gap
        }
    }

    // MARK: - Batch Property Update

    func updateShapes(_ ids: Set<UUID>, in rowId: UUID? = nil, update: (inout CanvasShapeModel) -> Void) {
        let rowIdx: Int
        if let rowId, let idx = rowIndex(for: rowId) {
            rowIdx = idx
        } else if let idx = selectedRowIndex {
            rowIdx = idx
        } else {
            return
        }
        registerUndoForRow(at: rowIdx, "Edit Shapes")
        for i in rows[rowIdx].shapes.indices {
            if ids.contains(rows[rowIdx].shapes[i].id) {
                let baseShape = rows[rowIdx].shapes[i]
                var resolved = LocaleService.resolveShape(baseShape, localeState: localeState)
                update(&resolved)
                rows[rowIdx].shapes[i] = LocaleService.splitUpdate(base: baseShape, updated: resolved, localeState: &localeState)
            }
        }
        scheduleSave()
    }
}
