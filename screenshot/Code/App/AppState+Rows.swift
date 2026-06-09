import SwiftUI

extension AppState {

    // MARK: - Rows

    func addRow() {
        withUndo("Add New Row") {
            let row = makeDefaultRow()
            rows.append(row)
            selectRow(row.id)
        }
    }

    func addRowAbove(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        withUndo("Add New Row Above") {
            let row = makeDefaultRow()
            rows.insert(row, at: idx)
            selectRow(row.id)
        }
    }

    func addRowBelow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        withUndo("Add New Row Below") {
            let row = makeDefaultRow()
            rows.insert(row, at: idx + 1)
            selectRow(row.id)
        }
    }

    func duplicateRow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        withUndo("Duplicate Row") {
            let source = rows[idx]
            var newShapes = source.shapes.map { $0.duplicated() }
            for i in newShapes.indices {
                let originalId = source.shapes[i].id
                LocaleService.copyShapeOverrides(&localeState, fromId: originalId, toId: newShapes[i].id)
                copyImageFiles(for: &newShapes[i], originalId: originalId)
            }
            let copy = ScreenshotRow(
                label: String(localized: "\(source.label) copy"),
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
                backgroundBlur: source.backgroundBlur,
                defaultDeviceFrameId: source.defaultDeviceFrameId,
                hiddenShapeTypes: source.hiddenShapeTypes,
                showBorders: source.showBorders,
                shapes: newShapes,
                isLabelManuallySet: true
            )
            rows.insert(copy, at: idx + 1)
            selectRow(copy.id)
        }
    }

    func deleteRow(_ id: UUID) {
        guard rows.count > 1,
              let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        withUndo("Delete Row") {
            let row = rows[idx]

            let shapeImageCandidates = imageFileNames(for: row.shapes)
            let templateBgImages = row.templates.compactMap { $0.backgroundImageConfig.fileName }
            let rowBgImage = row.backgroundImageConfig.fileName

            for shape in row.shapes {
                LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
            }

            let wasSelectedRow = selectedRowId == id
            exitPreview(for: id)
            rows.remove(at: idx)
            if wasSelectedRow {
                let newIdx = min(idx, rows.count - 1)
                selectRow(rows[newIdx].id)
            } else {
                normalizeSelection()
            }

            let allCandidates: [String?] = shapeImageCandidates + templateBgImages + [rowBgImage]
            cleanupUnreferencedImages(allCandidates)
        }
    }

    func resetRow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        withUndo("Reset Row") {
            let oldRow = rows[idx]

            let shapeImageCandidates = imageFileNames(for: oldRow.shapes)
            let templateBgImages = oldRow.templates.compactMap { $0.backgroundImageConfig.fileName }
            let rowBgImage = oldRow.backgroundImageConfig.fileName

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

            selectedShapeIds = []

            let allCandidates: [String?] = shapeImageCandidates + templateBgImages + [rowBgImage]
            cleanupUnreferencedImages(allCandidates)
        }
    }

    func updateRowLabel(_ rowId: UUID, text: String) {
        guard let ri = rowIndex(for: rowId) else { return }
        withUndo("Edit Row Label") {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                let row = rows[ri]
                rows[ri].label = presetLabel(forWidth: row.templateWidth, height: row.templateHeight)
                rows[ri].isLabelManuallySet = false
            } else {
                rows[ri].label = String(trimmed.prefix(50))
                rows[ri].isLabelManuallySet = true
            }
        }
    }

    /// Mutate a row without registering undo on every call — undo is captured once
    /// at the start of a burst and finalized after edits stop (debounced). A working
    /// row composes all in-flight changes while visible row updates are throttled to
    /// ~30fps, so delayed flushes cannot replay stale intermediate values.
    func updateRowContinuous(_ rowId: UUID, actionName: String = "Edit Background", _ mutate: @escaping (inout ScreenshotRow) -> Void) {
        guard let idx = rowIndex(for: rowId) else { return }

        if let activeId = continuousRowEditId, activeId != rowId {
            finishContinuousRowEditIfNeeded()
        }
        if continuousRowEditBaseRow == nil {
            commitAllPendingEdits()
            continuousRowEditBaseRow = rows[idx]
            continuousRowEditBaseLocaleState = localeState
            continuousRowEditId = rowId
        }
        // Reflect the latest edit so the coalesced undo entry isn't mislabeled when a
        // burst mixes sources (e.g. row background then per-template override).
        continuousRowEditActionName = actionName
        var workingRow = continuousRowEditWorkingRow ?? rows[idx]
        mutate(&workingRow)
        continuousRowEditWorkingRow = workingRow
        continuousRowEditHasPendingApply = true

        let now = CFAbsoluteTimeGetCurrent()
        let interval = Self.continuousEditInterval
        if now - continuousRowEditLastApply >= interval {
            applyContinuousRowEdit(rowId)
            continuousRowEditLastApply = now
            continuousRowEditFlushTask?.cancel()
            continuousRowEditFlushTask = nil
        } else {
            if continuousRowEditFlushTask == nil {
                let task = DispatchWorkItem { [weak self] in
                    self?.flushPendingContinuousRowEdit()
                }
                continuousRowEditFlushTask = task
                let delay = interval - (now - continuousRowEditLastApply)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
            }
        }

        continuousRowEditUndoTask?.cancel()
        let undoTask = DispatchWorkItem { [weak self] in
            self?.finishContinuousRowEditIfNeeded()
        }
        continuousRowEditUndoTask = undoTask
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.continuousUndoDebounceDelay, execute: undoTask)
    }

    @discardableResult
    private func applyContinuousRowEdit(_ rowId: UUID) -> Bool {
        guard continuousRowEditHasPendingApply,
              let row = continuousRowEditWorkingRow,
              let idx = rowIndex(for: rowId)
        else { return false }
        rows[idx] = row
        continuousRowEditHasPendingApply = false
        scheduleSave()
        return true
    }

    func flushPendingContinuousRowEdit() {
        guard let rowId = continuousRowEditId else { return }
        let didApply = applyContinuousRowEdit(rowId)
        continuousRowEditFlushTask?.cancel()
        continuousRowEditFlushTask = nil
        if didApply {
            continuousRowEditLastApply = CFAbsoluteTimeGetCurrent()
        }
    }

    func finishContinuousRowEditIfNeeded() {
        continuousRowEditUndoTask?.cancel()
        continuousRowEditUndoTask = nil
        flushPendingContinuousRowEdit()
        guard let baseRow = continuousRowEditBaseRow else { return }
        registerUndoForRowWithBase(continuousRowEditActionName, baseRow: baseRow, baseLocaleState: continuousRowEditBaseLocaleState)
        continuousRowEditBaseRow = nil
        continuousRowEditBaseLocaleState = nil
        continuousRowEditId = nil
        continuousRowEditWorkingRow = nil
        continuousRowEditHasPendingApply = false
        continuousRowEditLastApply = 0
    }

    func moveRowUp(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        withUndo("Move Row Up") {
            rows.swapAt(idx, idx - 1)
        }
    }

    func moveRowDown(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }), idx < rows.count - 1 else { return }
        withUndo("Move Row Down") {
            rows.swapAt(idx, idx + 1)
        }
    }

    func resizeRow(at rowIndex: Int, newWidth: CGFloat, newHeight: CGFloat) {
        var row = rows[rowIndex]
        guard row.templateWidth != newWidth || row.templateHeight != newHeight else { return }

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
        withUndo("Resize Row") { rows[rowIndex] = row }
    }

    func updateRowDefaultDeviceBodyColor(_ color: Color, for rowId: UUID) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }) else { return }
        let oldDefault = rows[rowIndex].defaultDeviceBodyColorData
        let newDefault = CodableColor(color)
        guard oldDefault != newDefault else { return }

        withUndo("Change Device Color") {
            rows[rowIndex].defaultDeviceBodyColorData = newDefault

            // Legacy projects stored the default frame color on each device shape.
            // When row default changes, convert matching legacy values to inheritance.
            for shapeIndex in rows[rowIndex].shapes.indices {
                guard rows[rowIndex].shapes[shapeIndex].type == .device else { continue }
                if rows[rowIndex].shapes[shapeIndex].deviceBodyColorData == oldDefault {
                    rows[rowIndex].shapes[shapeIndex].deviceBodyColorData = nil
                }
            }
        }
    }

    // MARK: - Default Device

    func setDefaultDevice(for rowId: UUID, category: DeviceCategory?, frameId: String?) {
        guard let idx = rowIndex(for: rowId) else { return }
        let row = rows[idx]
        guard row.defaultDeviceCategory != category || row.defaultDeviceFrameId != frameId else { return }
        withUndo("Change Default Device") {
            rows[idx].defaultDeviceCategory = category
            rows[idx].defaultDeviceFrameId = frameId
        }
    }

    // MARK: - Visibility

    func toggleShowDevice(for rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        withUndo(rows[idx].showDevice ? String(localized: "Hide Devices") : String(localized: "Show Devices")) {
            rows[idx].showDevice.toggle()
        }
    }

    func toggleRowCollapsed(for rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        rows[idx].isCollapsed.toggle()
        scheduleSave()
    }

    func toggleShowBorders(for rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        withUndo(rows[idx].showBorders ? String(localized: "Hide Borders") : String(localized: "Show Borders")) {
            rows[idx].showBorders.toggle()
        }
    }

    func setAllShapeTypesVisibility(for rowId: UUID, visible: Bool) {
        guard let idx = rowIndex(for: rowId) else { return }
        withUndo(visible ? "Show All" : "Hide All") {
            rows[idx].showBorders = visible
            rows[idx].hiddenShapeTypes = visible ? [] : Set(ShapeType.allCases)
        }
    }

    func toggleShapeTypeVisibility(for rowId: UUID, type: ShapeType) {
        guard let idx = rowIndex(for: rowId) else { return }
        let isCurrentlyVisible = !rows[idx].hiddenShapeTypes.contains(type)
        withUndo(isCurrentlyVisible ? "Hide \(type.pluralLabel)" : "Show \(type.pluralLabel)") {
            if isCurrentlyVisible {
                rows[idx].hiddenShapeTypes.insert(type)
            } else {
                rows[idx].hiddenShapeTypes.remove(type)
            }
        }
    }

}
