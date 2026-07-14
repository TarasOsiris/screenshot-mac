import SwiftUI

extension AppState {

    // MARK: - Shapes

    func shapeCenter(for row: ScreenshotRow) -> CGPoint {
        let rawX = visibleCanvasModelCenter?.x ?? row.templateWidth / 2
        let templateIndex = min(Int(floor(rawX / row.templateWidth)), max(row.templates.count - 1, 0))
        return CGPoint(
            x: row.templateCenterX(at: templateIndex),
            y: row.templateHeight / 2
        )
    }

    func addShape(_ shape: CanvasShapeModel) {
        guard let idx = selectedRowIndex else { return }
        withRowUndo("Add Shape", rowId: rows[idx].id) {
            rows[idx].shapes.append(shape)
            selectShape(shape.id, in: rows[idx].id)
            justAddedShapeId = shape.id
        }
    }

    func updateShape(_ shape: CanvasShapeModel) {
        guard let location = shapeLocation(for: shape.id) else { return }
        let shouldRebase = continuousEditShapeId == shape.id
        let staleBaseShape = shouldRebase ? rows[location.rowIndex].shapes[location.shapeIndex] : nil
        // withRowUndo finishes any in-flight continuous burst first, so the rebase reads the
        // post-flush base while staleBaseShape holds the pre-flush value.
        withRowUndo("Edit Shape", rowId: rows[location.rowIndex].id) {
            guard let loc = shouldRebase ? shapeLocation(for: shape.id) : location else { return }
            let baseShape = rows[loc.rowIndex].shapes[loc.shapeIndex]
            let updated = staleBaseShape.map { shape.rebased(from: $0, onto: baseShape) } ?? shape
            rows[loc.rowIndex].shapes[loc.shapeIndex] = LocaleService.splitUpdate(base: baseShape, updated: updated, localeState: &localeState)
        }
    }

    /// Commit inline-text-editor output for `shapeId` under a specific locale. Applies only the
    /// text/richText onto the *live* base shape (resolved for `code`), so concurrent geometry or
    /// override changes made while the editor was open aren't reverted by a stale captured model,
    /// and the edit always lands in the locale it was typed in regardless of the active locale.
    func commitInlineText(shapeId: UUID, text: String, richText: String?, forLocaleCode code: String) {
        guard shapeLocation(for: shapeId) != nil else { return }
        withUndo("Edit Text") {
            guard let loc = shapeLocation(for: shapeId) else { return }
            let baseShape = rows[loc.rowIndex].shapes[loc.shapeIndex]
            var resolved = LocaleService.resolveShape(baseShape, localeCode: code, localeState: localeState)
            resolved.text = text
            resolved.richText = richText
            if resolved.text?.isEmpty != false {
                resolved.richText = nil
            }
            rows[loc.rowIndex].shapes[loc.shapeIndex] = LocaleService.splitUpdate(
                base: baseShape, updated: resolved, localeState: &localeState, forLocaleCode: code
            )
            // A reused string's base text is shared: propagate a base-locale edit to every member.
            if baseShape.translationKey != nil, code == localeState.baseLocaleCode {
                setSharedBaseText(key: baseShape.textTranslationKey, text: text)
            }
        }
    }

    // Shared by the shape- and row-level continuous-edit paths (AppState+Rows).
    static let continuousEditInterval: CFAbsoluteTime = 1.0 / 30
    static let continuousUndoDebounceDelay: TimeInterval = 0.5

    /// Update shape without registering undo on every call — undo is captured once
    /// at the start and finalized after changes stop (debounced). Throttled to ~30fps
    /// to avoid expensive re-renders on every slider tick.
    func updateShapeContinuous(_ shape: CanvasShapeModel) {
        if let activeShapeId = continuousEditShapeId, activeShapeId != shape.id {
            finishContinuousEditIfNeeded()
        }

        if continuousEditBaseRow == nil {
            commitAllPendingEdits()
            if let location = shapeLocation(for: shape.id) {
                continuousEditBaseRow = rows[location.rowIndex]
                continuousEditBaseLocaleState = localeState
                continuousEditShapeId = shape.id
            }
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
            self.resetContinuousEditState()
        }
        continuousEditUndoTask = undoTask
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.continuousUndoDebounceDelay, execute: undoTask)
    }

    func flushPendingContinuousEdit() {
        guard let pending = continuousEditPending else { return }
        applyContinuousEdit(pending)
        continuousEditPending = nil
        continuousEditFlushTask?.cancel()
        continuousEditFlushTask = nil
        continuousEditLastApply = CFAbsoluteTimeGetCurrent()
    }

    private func applyContinuousEdit(_ shape: CanvasShapeModel) {
        guard let location = shapeLocation(for: shape.id) else { return }
        let rowIdx = location.rowIndex
        let shapeIdx = location.shapeIndex
        let baseShape = rows[rowIdx].shapes[shapeIdx]
        rows[rowIdx].shapes[shapeIdx] = LocaleService.splitUpdate(base: baseShape, updated: shape, localeState: &localeState)
        scheduleSave()
    }

    func deleteAllShapes(ofType type: ShapeType, in rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        let matching = rows[idx].shapes.filter { $0.type == type }
        guard !matching.isEmpty else { return }
        withRowUndo("Delete All \(type.pluralLabel)", rowId: rowId) {
            let allCandidates = imageFileNames(for: matching)
            let matchingIds = Set(matching.map(\.id))
            for shape in matching {
                LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
            }
            selectedShapeIds.subtract(matchingIds)
            rows[idx].shapes.removeAll { $0.type == type }
            cleanupOrphanedTranslationOverrides()
            cleanupUnreferencedImages(allCandidates)
        }
    }

    enum CenterAxis {
        case vertically, horizontally, both
    }

    func centerAllDevices(in rowId: UUID, axis: CenterAxis) {
        guard let idx = rowIndex(for: rowId) else { return }
        centerDevices(Set(rows[idx].shapes.map(\.id)), in: rowId, axis: axis)
    }

    func centerDevices(_ shapeIds: Set<UUID>, in rowId: UUID, axis: CenterAxis) {
        centerShapes(shapeIds, in: rowId, axis: axis, onlyDevices: true)
    }

    func centerShapes(_ shapeIds: Set<UUID>, in rowId: UUID, axis: CenterAxis, onlyDevices: Bool = false) {
        guard let idx = rowIndex(for: rowId) else { return }
        let row = rows[idx]
        let indices = row.shapes.indices.filter {
            shapeIds.contains(row.shapes[$0].id) &&
            (!onlyDevices || row.shapes[$0].type == .device) &&
            !row.shapes[$0].resolvedIsLocked
        }
        guard !indices.isEmpty else { return }
        let noun = onlyDevices ? "Device" : "Element"
        withRowUndo(indices.count == 1 ? "Center \(noun)" : "Center \(noun)s", rowId: rowId) {
            for i in indices {
                centerShape(at: i, in: idx, axis: axis)
            }
        }
    }

    private func centerShape(at shapeIndex: Int, in rowIndex: Int, axis: CenterAxis) {
        let row = rows[rowIndex]
        let shape = row.shapes[shapeIndex]
        if axis != .vertically {
            let templateIndex = row.owningTemplateIndex(for: shape)
            let templateLeft = CGFloat(templateIndex) * row.templateWidth
            rows[rowIndex].shapes[shapeIndex].x = templateLeft + (row.templateWidth - shape.width) / 2
        }
        if axis != .horizontally {
            rows[rowIndex].shapes[shapeIndex].y = (row.templateHeight - shape.height) / 2
        }
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
        let deviceIndices = shapes.indices.filter { shapes[$0].type == .device && !shapes[$0].resolvedIsLocked }
        guard !deviceIndices.isEmpty else { return }
        withRowUndo("Change All Row Devices", rowId: rowId) {
            for i in deviceIndices {
                mutate(&rows[idx].shapes[i])
            }
        }
    }

    func deleteShape(_ id: UUID) {
        guard let location = shapeLocation(for: id) else { return }
        guard !rows[location.rowIndex].shapes[location.shapeIndex].resolvedIsLocked else { return }
        withRowUndo("Delete Shape", rowId: rows[location.rowIndex].id) {
            let removedShape = rows[location.rowIndex].shapes.remove(at: location.shapeIndex)
            let localeImageFiles = localeOverrideImageFileNames(for: id)
            LocaleService.removeShapeOverrides(&localeState, shapeId: id)
            cleanupOrphanedTranslationOverrides()
            let allCandidates: [String?] = removedShape.allImageFileNames + localeImageFiles
            cleanupUnreferencedImages(allCandidates)
            selectedShapeIds.remove(id)
        }
    }

    func deleteSelectedShapes() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let idsToDelete = selectedShapeIds
        let matching = rows[rowIdx].shapes.filter { idsToDelete.contains($0.id) && !$0.resolvedIsLocked }
        guard !matching.isEmpty else { return }
        let deletedIds = Set(matching.map(\.id))
        withRowUndo("Delete Shapes", rowId: rows[rowIdx].id) {
            var allCandidates: [String?] = []
            for shape in matching {
                allCandidates.append(contentsOf: shape.allImageFileNames)
                allCandidates.append(contentsOf: localeOverrideImageFileNames(for: shape.id))
                LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
            }
            rows[rowIdx].shapes.removeAll { deletedIds.contains($0.id) }
            cleanupOrphanedTranslationOverrides()
            selectedShapeIds.subtract(deletedIds)
            cleanupUnreferencedImages(allCandidates)
        }
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
        withRowUndo("Duplicate Shapes", rowId: rows[rowIdx].id) {
            var newIds: Set<UUID> = []
            for shape in shapes {
                var copy = shape.duplicated(offsetX: 50, offsetY: 50)
                LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
                copyImageFiles(for: &copy, originalId: shape.id)
                rows[rowIdx].shapes.append(copy)
                newIds.insert(copy.id)
            }
            selectedShapeIds = newIds
        }
    }

    @discardableResult
    func insertDuplicate(of shapeId: UUID, offsetX: CGFloat = 0, offsetY: CGFloat = 0, undoName: String) -> UUID? {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shapeId }) else { return nil }
        var copy = rows[rowIdx].shapes[shapeIdx].duplicated(offsetX: offsetX, offsetY: offsetY)
        withRowUndo(undoName, rowId: rows[rowIdx].id) {
            LocaleService.copyShapeOverrides(&localeState, fromId: shapeId, toId: copy.id)
            copyImageFiles(for: &copy, originalId: shapeId)
            rows[rowIdx].shapes.append(copy)
            selectShape(copy.id, in: rows[rowIdx].id)
        }
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
        withRowUndo("Duplicate to Screenshots", rowId: row.id) {
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
        }
    }

    func bringShapeToFront(_ id: UUID) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == id }),
              shapeIdx < rows[rowIdx].shapes.count - 1 else { return }
        withRowUndo("Bring to Front", rowId: rows[rowIdx].id) {
            let shape = rows[rowIdx].shapes.remove(at: shapeIdx)
            rows[rowIdx].shapes.append(shape)
            selectShape(id, in: rows[rowIdx].id)
        }
    }

    func sendShapeToBack(_ id: UUID) {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == id }),
              shapeIdx > 0 else { return }
        withRowUndo("Send to Back", rowId: rows[rowIdx].id) {
            let shape = rows[rowIdx].shapes.remove(at: shapeIdx)
            rows[rowIdx].shapes.insert(shape, at: 0)
            selectShape(id, in: rows[rowIdx].id)
        }
    }

    func bringSelectedShapesToFront() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        let suffixIds = Set(rows[rowIdx].shapes.suffix(ids.count).map(\.id))
        guard suffixIds != ids else { return }
        withRowUndo("Bring to Front", rowId: rows[rowIdx].id) {
            let selected = rows[rowIdx].shapes.filter { ids.contains($0.id) }
            rows[rowIdx].shapes.removeAll { ids.contains($0.id) }
            rows[rowIdx].shapes.append(contentsOf: selected)
        }
    }

    func sendSelectedShapesToBack() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        let prefixIds = Set(rows[rowIdx].shapes.prefix(ids.count).map(\.id))
        guard prefixIds != ids else { return }
        withRowUndo("Send to Back", rowId: rows[rowIdx].id) {
            let selected = rows[rowIdx].shapes.filter { ids.contains($0.id) }
            rows[rowIdx].shapes.removeAll { ids.contains($0.id) }
            rows[rowIdx].shapes.insert(contentsOf: selected, at: 0)
        }
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

        let ids = selectedShapeIds
        let hasMovable = rows[rowIdx].shapes.contains { ids.contains($0.id) && !$0.resolvedIsLocked }
        guard hasMovable else { return }

        // Capture undo state only at the start of a nudge sequence — and only when
        // we know at least one shape will actually move, so a fully-locked nudge
        // doesn't poison the baseline for a later, unrelated nudge.
        if nudgeBaseRow == nil {
            commitAllPendingEdits()
            nudgeBaseRow = rows[rowIdx]
        }
        nudgeActionName = ids.count > 1 ? "Move Shapes" : "Move Shape"

        for i in rows[rowIdx].shapes.indices {
            if ids.contains(rows[rowIdx].shapes[i].id) && !rows[rowIdx].shapes[i].resolvedIsLocked {
                rows[rowIdx].shapes[i].x += dx
                rows[rowIdx].shapes[i].y += dy
            }
        }
        scheduleSave()

        // Debounce the undo registration so rapid key repeats collapse into one entry
        nudgeUndoTask?.cancel()
        let nudgeTask = DispatchWorkItem { [weak self] in
            self?.finishNudgeIfNeeded()
        }
        nudgeUndoTask = nudgeTask
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: nudgeTask)
    }

    /// Commits a pending arrow-key nudge as one undo step. No-op when no nudge is captured.
    func finishNudgeIfNeeded() {
        nudgeUndoTask?.cancel()
        nudgeUndoTask = nil
        guard let baseRow = nudgeBaseRow else { return }
        nudgeBaseRow = nil
        registerUndoForRowWithBase(nudgeActionName, baseRow: baseRow)
    }

    // MARK: - Option+Drag Duplicate

    func duplicateShapeForOptionDrag(_ shapeId: UUID) -> UUID? {
        guard let location = shapeLocation(for: shapeId),
              !rows[location.rowIndex].shapes[location.shapeIndex].resolvedIsLocked else { return nil }
        return insertDuplicate(of: shapeId, undoName: "Duplicate Shape")
    }

    // MARK: - Clipboard

    func copySelectedShapes() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        clipboard = rows[rowIdx].shapes.filter { ids.contains($0.id) }
        #if os(macOS)
        clipboardPasteboardChangeCount = NSPasteboard.general.changeCount
        #endif
    }

    func pasteShapes() {
        guard let rowIdx = selectedRowIndex else { return }

        #if os(macOS)
        let pasteboardChanged = NSPasteboard.general.changeCount != clipboardPasteboardChangeCount

        // If pasteboard changed since last internal copy, try system image first
        if pasteboardChanged,
           let image = NSImage(pasteboard: NSPasteboard.general), image.isValid {
            let row = rows[rowIdx]
            let center = canvasMouseModelPosition ?? CGPoint(x: row.templateWidth / 2, y: row.templateHeight / 2)
            addImageShape(image: image, centerX: center.x, centerY: center.y)
            return
        }
        #endif

        // Otherwise paste from internal shape clipboard
        guard !clipboard.isEmpty else { return }
        withRowUndo(clipboard.count == 1 ? "Paste Shape" : "Paste Shapes", rowId: rows[rowIdx].id) {
            var newIds: Set<UUID> = []
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
        }
    }

    // MARK: - Group Drag

    func applyGroupDrag(offset: CGSize) {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        let movableIndices = rows[rowIdx].shapes.indices.filter {
            ids.contains(rows[rowIdx].shapes[$0].id) && !rows[rowIdx].shapes[$0].resolvedIsLocked
        }
        guard !movableIndices.isEmpty else { return }
        withRowUndo(movableIndices.count > 1 ? "Move Shapes" : "Move Shape", rowId: rows[rowIdx].id) {
            for i in movableIndices {
                rows[rowIdx].shapes[i].x += offset.width
                rows[rowIdx].shapes[i].y += offset.height
            }
        }
    }

    // MARK: - Option+Drag Duplicate for Multi-Selection

    func duplicateShapesForOptionDrag() {
        guard let rowIdx = selectedRowIndex, selectedShapeIds.count > 1 else { return }
        let ids = selectedShapeIds
        let shapes = rows[rowIdx].shapes.filter { ids.contains($0.id) && !$0.resolvedIsLocked }
        guard !shapes.isEmpty else { return }
        withRowUndo("Duplicate Shapes", rowId: rows[rowIdx].id) {
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
        }
    }

    // MARK: - Align Selected Shapes

    enum ShapeAlignment: Equatable {
        case left, centerH, right, top, centerV, bottom
        case distributeH, distributeV
    }

    func alignSelectedShapes(_ alignment: ShapeAlignment) {
        guard let rowIdx = selectedRowIndex, selectedShapeIds.count >= 2 else { return }
        let ids = selectedShapeIds
        let indices = rows[rowIdx].shapes.indices.filter {
            ids.contains(rows[rowIdx].shapes[$0].id) && !rows[rowIdx].shapes[$0].resolvedIsLocked
        }
        guard indices.count >= 2 else { return }
        if alignment == .distributeH || alignment == .distributeV {
            guard indices.count >= 3 else { return }
        }

        withRowUndo("Align Shapes", rowId: rows[rowIdx].id) {
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
        }
    }

    // MARK: - Match Geometry to Source

    enum GeometryMatchMode { case position, size, both }

    /// Pushes the source shape's geometry onto the other selected shapes. Position is
    /// template-relative: each target keeps its own column but adopts the source's offset
    /// within that column (shape X is absolute across all columns). Size copies exactly.
    /// Routes through `updateShapes` so a non-base locale records the change as a per-locale
    /// override instead of mutating base geometry, matching what the canvas shows.
    func matchShapeGeometry(toSource sourceId: UUID, mode: GeometryMatchMode) {
        guard let rowIdx = selectedRowIndex else { return }
        let ids = selectedShapeIds
        guard ids.contains(sourceId),
              let baseSource = rows[rowIdx].shapes.first(where: { $0.id == sourceId }) else { return }

        let targetIds = Set(rows[rowIdx].shapes.filter {
            ids.contains($0.id) && $0.id != sourceId && !$0.resolvedIsLocked
        }.map(\.id))
        guard !targetIds.isEmpty else { return }

        let source = LocaleService.resolveShape(baseSource, localeState: localeState)
        let templateWidth = rows[rowIdx].templateWidth
        let templateCount = rows[rowIdx].templates.count
        let sourceTemplate = rows[rowIdx].owningTemplateIndex(for: source)
        let sourceRelX = source.x - CGFloat(sourceTemplate) * templateWidth

        let undoName: String
        switch mode {
        case .position: undoName = "Match Position"
        case .size: undoName = "Match Size"
        case .both: undoName = "Match Position & Size"
        }

        updateShapes(targetIds, in: rows[rowIdx].id, undoName: undoName) { shape in
            if mode != .size {
                let centerX = shape.x + shape.width / 2
                let targetTemplate = max(0, min(Int(floor(centerX / templateWidth)), templateCount - 1))
                shape.x = sourceRelX + CGFloat(targetTemplate) * templateWidth
                shape.y = source.y
            }
            if mode != .position {
                shape.width = source.width
                shape.height = source.height
            }
        }
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

    /// Batch property edit. Affects every shape in the selection (including locked
    /// shapes) — lock blocks direct canvas manipulation, not inspector/properties-bar
    /// edits. Gesture-driven mutations (drag/nudge/align/delete) live in dedicated
    /// methods and filter locked shapes themselves.
    func updateShapes(
        _ ids: Set<UUID>,
        in rowId: UUID? = nil,
        undoName: String = "Edit Shapes",
        update: (inout CanvasShapeModel) -> Void
    ) {
        let rowIdx: Int
        if let rowId, let idx = rowIndex(for: rowId) {
            rowIdx = idx
        } else if let idx = selectedRowIndex {
            rowIdx = idx
        } else {
            return
        }
        withRowUndo(undoName, rowId: rows[rowIdx].id) {
            for i in rows[rowIdx].shapes.indices {
                guard ids.contains(rows[rowIdx].shapes[i].id) else { continue }
                let baseShape = rows[rowIdx].shapes[i]
                var resolved = LocaleService.resolveShape(baseShape, localeState: localeState)
                update(&resolved)
                rows[rowIdx].shapes[i] = LocaleService.splitUpdate(base: baseShape, updated: resolved, localeState: &localeState)
            }
        }
    }

    /// Multi-shape sibling of `updateShapeContinuous` for slider drags over a selection.
    /// Routes through the row-scoped continuous path (throttled ~30fps, single debounced
    /// undo step) instead of running `withUndo` per tick. Writes the closure directly onto
    /// the base shapes in the buffered working row, so it's correct only for non-localized
    /// properties (opacity/rotation/borderRadius/outline/shadow). Localized text edits must
    /// stay on `updateShapes`/`updateShape`.
    func updateShapesContinuous(
        _ ids: Set<UUID>,
        in rowId: UUID? = nil,
        undoName: String = "Edit Shapes",
        update: @escaping (inout CanvasShapeModel) -> Void
    ) {
        let targetRowId: UUID
        if let rowId {
            targetRowId = rowId
        } else if let idx = selectedRowIndex {
            targetRowId = rows[idx].id
        } else {
            return
        }
        updateRowContinuous(targetRowId, actionName: undoName) { row in
            for i in row.shapes.indices where ids.contains(row.shapes[i].id) {
                update(&row.shapes[i])
            }
        }
    }

    // MARK: - Lock

    /// True when every selected shape is locked. False if there's no selection.
    var isSelectionFullyLocked: Bool {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return false }
        let ids = selectedShapeIds
        var anyMatch = false
        for shape in rows[rowIdx].shapes where ids.contains(shape.id) {
            if !shape.resolvedIsLocked { return false }
            anyMatch = true
        }
        return anyMatch
    }

    /// True when at least one selected shape is locked.
    var isSelectionPartiallyLocked: Bool {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return false }
        let ids = selectedShapeIds
        return rows[rowIdx].shapes.contains { ids.contains($0.id) && $0.resolvedIsLocked }
    }

    /// Locks the selection if any shape is unlocked; otherwise unlocks all.
    func toggleLockOnSelection() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let rowId = rows[rowIdx].id
        let shouldLock = !isSelectionFullyLocked
        updateShapes(
            selectedShapeIds,
            in: rowId,
            undoName: shouldLock ? "Lock" : "Unlock"
        ) { shape in
            // nil keeps "lk" out of JSON when unlocked; matches the encodeIfPresent pattern.
            shape.isLocked = shouldLock ? true : nil
        }
    }
}
