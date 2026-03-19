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

    func deleteAllShapes(ofType type: ShapeType, in rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        let matching = rows[idx].shapes.filter { $0.type == type }
        guard !matching.isEmpty else { return }
        registerUndo("Delete All \(type.pluralLabel)")
        let allCandidates = imageFileNames(for: matching)
        for shape in matching {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        if let selectedId = selectedShapeId, matching.contains(where: { $0.id == selectedId }) {
            selectedShapeId = nil
        }
        rows[idx].shapes.removeAll { $0.type == type }
        cleanupUnreferencedImages(allCandidates)
        scheduleSave()
    }

    func changeAllDevices(in rowId: UUID, toCategory category: DeviceCategory) {
        changeAllDevices(in: rowId) { $0.selectAbstractDevice(category) }
    }

    func changeAllDevices(in rowId: UUID, toFrame frame: DeviceFrame) {
        changeAllDevices(in: rowId) { $0.selectRealFrame(frame) }
    }

    private func changeAllDevices(in rowId: UUID, mutate: (inout CanvasShapeModel) -> Void) {
        guard let idx = rowIndex(for: rowId) else { return }
        let shapes = rows[idx].shapes
        let deviceIndices = shapes.indices.filter { shapes[$0].type == .device }
        guard !deviceIndices.isEmpty else { return }
        registerUndo("Change All Row Devices")
        for i in deviceIndices {
            mutate(&rows[idx].shapes[i])
        }
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
    func insertDuplicate(of shapeId: UUID, offsetX: CGFloat = 0, offsetY: CGFloat = 0, undoName: String) -> UUID? {
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

    func focusShapeOnCanvas(shapeId: UUID, rowId: UUID) {
        selectShape(shapeId, in: rowId)
        canvasFocusRowId = rowId
        canvasFocusRequestNonce += 1
    }

    // MARK: - Nudge

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

    // MARK: - Clipboard

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
        guard let source = clipboard else { return }
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
}
