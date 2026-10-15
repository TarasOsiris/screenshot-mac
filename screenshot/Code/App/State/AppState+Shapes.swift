import SwiftUI
import UniformTypeIdentifiers

extension AppState {

    // MARK: - Shapes

    func shapeCenter(for row: ScreenshotRow) -> CGPoint {
        let rawX = canvasHints.visibleModelCenterX ?? row.templateWidth / 2
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
            canvasHints.justAddedShapeId = shape.id
        }
    }

    /// Adds a default `type` shape to `rowId` and selects it — at `center`, else the middle of the
    /// template currently in view. SVG needs content, so it goes through `insertSvgShape`.
    func insertDefaultShape(_ type: ShapeType, inRow rowId: UUID, at center: CGPoint? = nil) {
        guard let row = rows.first(where: { $0.id == rowId }) else { return }
        let center = center ?? shapeCenter(for: row)
        guard let shape = CanvasShapeModel.defaultShape(for: type, row: row, centerX: center.x, centerY: center.y) else { return }
        selectRow(rowId)
        addShape(shape)
    }

    func insertSvgShape(content: String, naturalSize: CGSize, customColor: Color? = nil, inRow rowId: UUID, at center: CGPoint? = nil) {
        guard let row = rows.first(where: { $0.id == rowId }) else { return }
        let center = center ?? shapeCenter(for: row)
        let scaledSize = SvgHelper.scaledSize(naturalSize, maxDim: row.svgMaxDimension)
        var shape = CanvasShapeModel.defaultSvg(centerX: center.x, centerY: center.y, svgContent: content, size: scaledSize)
        if let customColor {
            shape.svgUseColor = true
            shape.color = customColor
        }
        selectRow(rowId)
        addShape(shape)
    }

    /// Pass `forLocaleCode` to commit against a specific locale (e.g. the MCP tools always
    /// edit the base shape regardless of which locale the UI is viewing); nil = active locale.
    func updateShape(_ shape: CanvasShapeModel, forLocaleCode code: String? = nil) {
        guard let location = shapeLocation(for: shape.id) else { return }
        let shouldRebase = continuousEditShapeId == shape.id
        let staleBaseShape = shouldRebase ? rows[location.rowIndex].shapes[location.shapeIndex] : nil
        // withRowUndo finishes any in-flight continuous burst first, so the rebase reads the
        // post-flush base while staleBaseShape holds the pre-flush value.
        withRowUndo("Edit Shape", rowId: rows[location.rowIndex].id) {
            guard let loc = shouldRebase ? shapeLocation(for: shape.id) : location else { return }
            let baseShape = rows[loc.rowIndex].shapes[loc.shapeIndex]
            let updated = staleBaseShape.map { shape.rebased(from: $0, onto: baseShape) } ?? shape
            rows[loc.rowIndex].shapes[loc.shapeIndex] = LocaleService.splitUpdate(
                base: baseShape,
                updated: updated,
                localeState: &localeState,
                forLocaleCode: code ?? localeState.activeLocaleCode
            )
        }
    }

    /// SVG content isn't localized, so the artwork and its fitted frame land on the base shape.
    func replaceSvg(shapeId: UUID, content: String, naturalSize: CGSize, useColor: Bool, color: Color) {
        guard let location = shapeLocation(for: shapeId) else { return }
        withRowUndo("Replace SVG", rowId: rows[location.rowIndex].id) {
            guard let loc = shapeLocation(for: shapeId) else { return }
            var shape = rows[loc.rowIndex].shapes[loc.shapeIndex]
            shape.svgContent = content
            shape.fitFrame(toAspectOf: naturalSize)
            if (shape.svgUseColor == true) != useColor {
                shape.svgUseColor = useColor
            }
            if useColor, color.hexString != shape.color.hexString {
                shape.color = color
            }
            rows[loc.rowIndex].shapes[loc.shapeIndex] = shape
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
            var resolved = LocaleService.resolveShape(rows[loc.rowIndex].shapes[loc.shapeIndex], localeCode: code, localeState: localeState)
            resolved.text = text
            resolved.richText = richText
            if resolved.text?.isEmpty != false {
                resolved.richText = nil
            }
            DocumentEditing.commitShapeEdit(resolved, at: loc, forLocaleCode: code, rows: &rows, localeState: &localeState)
        }
    }

    /// Update shape without registering undo on every call — undo is captured once at the start
    /// and finalized after changes stop (debounced via `edits.shapeEdit`).
    ///
    /// The value does **not** reach `rows` per tick. It goes to `liveShapeEdit`, which only the
    /// edited shape and the control being dragged observe; `rows` is written once when the burst
    /// settles. Writing `rows` at the throttle's ~30fps re-ran the row builder, the whole edited
    /// row, the properties bar and any open popover on every tick, which cost more main-thread
    /// time than the drag had. The throttle stays, so the canvas re-renders at most ~30fps.
    func updateShapeContinuous(_ shape: CanvasShapeModel) {
        if let activeShapeId = edits.shapeEdit.activeId, activeShapeId != shape.id {
            finishContinuousEditIfNeeded()
        }

        if !edits.shapeEdit.isActive {
            commitAllPendingEdits()
            guard let location = shapeLocation(for: shape.id) else { return }
            let baseRow = rows[location.rowIndex]
            let baseLocaleState = localeState
            edits.shapeEdit.begin(id: shape.id) { [weak self] in
                guard let self else { return }
                self.edits.shapeEditThrottle.flush()
                self.commitLiveShapeEdit()
                self.registerUndoForRowWithBase("Edit Shape", baseRow: baseRow, baseLocaleState: baseLocaleState)
                self.edits.shapeEditThrottle.reset()
            }
        }

        edits.shapeEditThrottle.submit { [weak self] in self?.liveShapeEdit.update(shape) }
        edits.shapeEdit.arm()
    }

    /// Commits a pending continuous shape edit as one undo step. No-op when none is captured.
    func finishContinuousEditIfNeeded() {
        edits.shapeEdit.finish()
    }

    /// Writes the burst's final value into the document and clears the session. Called from the
    /// coalescer's finish action, *before* the undo step is registered — the step is registered
    /// against a base captured at the start of the burst, so it has to see the landed value.
    func commitLiveShapeEdit() {
        guard let shape = liveShapeEdit.takeShape() else { return }
        applyContinuousEdit(shape)
    }

    private func applyContinuousEdit(_ shape: CanvasShapeModel) {
        guard let location = shapeLocation(for: shape.id) else { return }
        let rowIdx = location.rowIndex
        let shapeIdx = location.shapeIndex
        let baseShape = rows[rowIdx].shapes[shapeIdx]
        let baseLocaleState = localeState
        let updated = LocaleService.splitUpdate(base: baseShape, updated: shape, localeState: &localeState)
        // On a non-base locale the whole edit lands in `localeState` and the base shape comes back
        // unchanged, so the no-op test has to cover both or the override is never persisted.
        let shapeChanged = updated != baseShape
        guard shapeChanged || localeState != baseLocaleState else { return }
        if shapeChanged {
            rows[rowIdx].shapes[shapeIdx] = updated
        }
        scheduleSave()
    }

    func deleteAllShapes(ofType type: ShapeType, in rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        guard rows[idx].shapes.contains(where: { $0.type == type }) else { return }
        withRowUndo("Delete All \(type.rawValue) shapes", rowId: rowId) {
            let removed = DocumentEditing.deleteShapes(ofType: type, inRowAt: idx, rows: &rows, localeState: &localeState)
            selectedShapeIds.subtract(removed.removedIds)
            cleanupUnreferencedImages(removed.imageCandidates)
        }
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
                DocumentEditing.center(shapeAt: i, in: &rows[idx], axis: axis)
            }
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
        guard let idx = rowIndex(for: rowId),
              rows[idx].shapes.contains(where: { $0.type == .device && !$0.resolvedIsLocked }) else { return }
        withRowUndo("Change All Row Devices", rowId: rowId) {
            DocumentEditing.changeAllDevices(in: &rows[idx], mutate)
        }
    }

    func deleteShape(_ id: UUID) {
        guard let location = shapeLocation(for: id) else { return }
        withRowUndo("Delete Shape", rowId: rows[location.rowIndex].id) {
            guard let freed = DocumentEditing.deleteShape(at: location, rows: &rows, localeState: &localeState) else { return }
            cleanupUnreferencedImages(freed)
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
                let copy = DocumentEditing.duplicateShape(
                    shape, offsetX: 50, offsetY: 50, in: &rows[rowIdx], localeState: &localeState, resources: self
                )
                newIds.insert(copy.id)
            }
            selectedShapeIds = newIds
        }
    }

    @discardableResult
    func insertDuplicate(of shapeId: UUID, offsetX: CGFloat = 0, offsetY: CGFloat = 0, undoName: String) -> UUID? {
        guard let rowIdx = selectedRowIndex,
              let shapeIdx = rows[rowIdx].shapes.firstIndex(where: { $0.id == shapeId }) else { return nil }
        let shape = rows[rowIdx].shapes[shapeIdx]
        var copyId: UUID?
        withRowUndo(undoName, rowId: rows[rowIdx].id) {
            let copy = DocumentEditing.duplicateShape(
                shape, offsetX: offsetX, offsetY: offsetY, in: &rows[rowIdx], localeState: &localeState, resources: self
            )
            selectShape(copy.id, in: rows[rowIdx].id)
            copyId = copy.id
        }
        return copyId
    }

    func duplicateShapesToTemplates(_ shapeIds: Set<UUID>, direction: DuplicateDirection = .all) {
        guard let rowIdx = selectedRowIndex else { return }
        let row = rows[rowIdx]
        guard row.templates.count > 1 else { return }
        let shapes = row.shapes.filter { shapeIds.contains($0.id) }
        guard !shapes.isEmpty else { return }
        withRowUndo("Duplicate to Screenshots", rowId: row.id) {
            DocumentEditing.duplicateShapesToTemplates(
                shapes, direction: direction, in: &rows[rowIdx],
                localeState: &localeState, resources: self
            )
        }
    }

    func bringShapeToFront(_ id: UUID) {
        guard let location = shapeLocation(for: id), location.shapeIndex < rows[location.rowIndex].shapes.count - 1 else { return }
        let rowId = rows[location.rowIndex].id
        withRowUndo("Bring to Front", rowId: rowId) {
            DocumentEditing.reorderShape(at: location, toFront: true, rows: &rows)
            selectShape(id, in: rowId)
        }
    }

    func sendShapeToBack(_ id: UUID) {
        guard let location = shapeLocation(for: id), location.shapeIndex > 0 else { return }
        let rowId = rows[location.rowIndex].id
        withRowUndo("Send to Back", rowId: rowId) {
            DocumentEditing.reorderShape(at: location, toFront: false, rows: &rows)
            selectShape(id, in: rowId)
        }
    }

    func bringSelectedShapesToFront() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        guard !rows[rowIdx].areFrontmost(ids) else { return }
        withRowUndo("Bring to Front", rowId: rows[rowIdx].id) {
            let selected = rows[rowIdx].shapes.filter { ids.contains($0.id) }
            rows[rowIdx].shapes.removeAll { ids.contains($0.id) }
            rows[rowIdx].shapes.append(contentsOf: selected)
        }
    }

    func sendSelectedShapesToBack() {
        guard let rowIdx = selectedRowIndex, !selectedShapeIds.isEmpty else { return }
        let ids = selectedShapeIds
        guard !rows[rowIdx].areBackmost(ids) else { return }
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
}
