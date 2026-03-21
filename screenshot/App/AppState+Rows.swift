import SwiftUI

extension AppState {

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
            hiddenShapeTypes: source.hiddenShapeTypes,
            showBorders: source.showBorders,
            shapes: newShapes,
            isLabelManuallySet: true
        )
        rows.insert(copy, at: idx + 1)
        selectRow(copy.id)
        scheduleSave()
    }

    func deleteRow(_ id: UUID) {
        guard rows.count > 1,
              let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        registerUndo("Delete Row")
        let row = rows[idx]

        // Collect all image filenames to clean up before removing the row
        let shapeImageCandidates = imageFileNames(for: row.shapes)
        let templateBgImages = row.templates.compactMap { $0.backgroundImageConfig.fileName }
        let rowBgImage = row.backgroundImageConfig.fileName

        // Remove locale overrides for all shapes in the row
        for shape in row.shapes {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }

        let wasSelectedRow = selectedRowId == id
        rows.remove(at: idx)
        if wasSelectedRow {
            let newIdx = min(idx, rows.count - 1)
            selectRow(rows[newIdx].id)
        } else {
            normalizeSelection()
        }

        // Cleanup orphaned images
        let allCandidates: [String?] = shapeImageCandidates + templateBgImages + [rowBgImage]
        cleanupUnreferencedImages(allCandidates)
        scheduleSave()
    }

    func resetRow(_ id: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        registerUndo("Reset Row")
        let oldRow = rows[idx]

        // Collect all image filenames to clean up
        let shapeImageCandidates = imageFileNames(for: oldRow.shapes)
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

        selectedShapeIds = []

        // Cleanup orphaned images (single-pass batch check)
        let allCandidates: [String?] = shapeImageCandidates + templateBgImages + [rowBgImage]
        cleanupUnreferencedImages(allCandidates)

        scheduleSave()
    }

    func updateRowLabel(_ rowId: UUID, text: String) {
        guard let ri = rowIndex(for: rowId) else { return }
        registerUndo("Edit Row Label")
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

        registerUndo("Change Device Color")
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

    // MARK: - Default Device

    func setDefaultDevice(for rowId: UUID, category: DeviceCategory?, frameId: String?) {
        guard let idx = rowIndex(for: rowId) else { return }
        let row = rows[idx]
        guard row.defaultDeviceCategory != category || row.defaultDeviceFrameId != frameId else { return }
        registerUndo("Change Default Device")
        rows[idx].defaultDeviceCategory = category
        rows[idx].defaultDeviceFrameId = frameId
        scheduleSave()
    }

    // MARK: - Visibility

    func toggleShowDevice(for rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        registerUndo(rows[idx].showDevice ? "Hide Devices" : "Show Devices")
        rows[idx].showDevice.toggle()
        scheduleSave()
    }

    func toggleShowBorders(for rowId: UUID) {
        guard let idx = rowIndex(for: rowId) else { return }
        registerUndo(rows[idx].showBorders ? "Hide Borders" : "Show Borders")
        rows[idx].showBorders.toggle()
        scheduleSave()
    }

    func setAllShapeTypesVisibility(for rowId: UUID, visible: Bool) {
        guard let idx = rowIndex(for: rowId) else { return }
        registerUndo(visible ? "Show All" : "Hide All")
        rows[idx].showBorders = visible
        rows[idx].hiddenShapeTypes = visible ? [] : Set(ShapeType.allCases)
        scheduleSave()
    }

    func toggleShapeTypeVisibility(for rowId: UUID, type: ShapeType) {
        guard let idx = rowIndex(for: rowId) else { return }
        let isCurrentlyVisible = !rows[idx].hiddenShapeTypes.contains(type)
        registerUndo(isCurrentlyVisible ? "Hide \(type.pluralLabel)" : "Show \(type.pluralLabel)")
        if isCurrentlyVisible {
            rows[idx].hiddenShapeTypes.insert(type)
        } else {
            rows[idx].hiddenShapeTypes.remove(type)
        }
        scheduleSave()
    }

}
