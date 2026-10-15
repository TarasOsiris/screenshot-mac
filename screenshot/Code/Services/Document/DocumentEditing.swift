import Foundation

/// The editing verbs' document logic, shared by the editor (`AppState`) and MCP edits to any project.
enum DocumentEditing {

    // MARK: - Rows

    /// Rescales every shape with the row; devices keep their aspect ratio. False when the size is unchanged.
    @discardableResult
    static func resize(_ row: inout ScreenshotRow, width newWidth: CGFloat, height newHeight: CGFloat) -> Bool {
        guard row.templateWidth != newWidth || row.templateHeight != newHeight else { return false }

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
        return true
    }

    /// An empty `text` restores the automatic size label. Renames reach the row's linked variant copies.
    static func setLabel(_ text: String, ofRowAt index: Int, in rows: inout [ScreenshotRow]) {
        // Named by hand, a copy no longer follows the row it came from.
        rows[index].originRowId = nil
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            let row = rows[index]
            rows[index].label = presetLabel(forWidth: row.templateWidth, height: row.templateHeight)
            rows[index].isLabelManuallySet = false
        } else {
            rows[index].label = String(trimmed.prefix(50))
            rows[index].isLabelManuallySet = true
        }
        propagateLabel(from: rows[index].id, in: &rows)
    }

    static func propagateLabel(from rowId: UUID, in rows: inout [ScreenshotRow]) {
        guard FeatureFlags.abTesting, let source = rows.first(where: { $0.id == rowId }) else { return }
        for i in rows.indices where rows[i].originRowId == rowId && rows[i].variantId != nil {
            if source.isLabelManuallySet {
                rows[i].label = source.label
            } else {
                rows[i].label = presetLabel(forWidth: rows[i].templateWidth, height: rows[i].templateHeight)
            }
            rows[i].isLabelManuallySet = source.isLabelManuallySet
        }
    }

    /// The row a variant copy takes its name from: its source, while that row exists and is named by
    /// hand. An automatic size label describes one row's size, so it is never shared.
    static func labelSource(of row: ScreenshotRow, in rows: [ScreenshotRow]) -> ScreenshotRow? {
        guard FeatureFlags.abTesting, row.variantId != nil, let originId = row.originRowId, originId != row.id,
              let source = rows.first(where: { $0.id == originId }), source.isLabelManuallySet else { return nil }
        return source
    }

    /// A variant holds one App Store row per screenshot size; this is the one already in `row`'s slot.
    static func rowOccupyingSlot(of row: ScreenshotRow, in variantId: UUID?, rows: [ScreenshotRow]) -> ScreenshotRow? {
        guard let variantId, !row.excludeFromAppStoreConnect else { return nil }
        let slot = screenshotSlot(of: row)
        return rows.first {
            $0.id != row.id && $0.uploadsToAppStore(from: variantId) && screenshotSlot(of: $0) == slot
        }
    }

    static func screenshotSlot(of row: ScreenshotRow) -> String {
        ASCDisplayType.detect(width: row.templateWidth, height: row.templateHeight)?.appStoreConnectValue
            ?? "\(Int(row.templateWidth))x\(Int(row.templateHeight))"
    }

    /// Copies an Original row in place, right after it; nil for a variant row, whose size slot is taken.
    static func copyRow(
        at index: Int,
        label: String,
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) -> ScreenshotRow? {
        let source = rows[index]
        guard source.isOriginal else { return nil }
        return insertDuplicate(
            of: source, at: index + 1, label: label, variantId: source.activeVariantId,
            rows: &rows, localeState: &localeState, resources: resources
        )
    }

    /// A default row for `variantId`, or for the Original when the variant already holds that size.
    static func newRow(inVariant variantId: UUID?, rows: [ScreenshotRow], defaults: NewRowDefaults) -> ScreenshotRow {
        var row = ScreenshotRow.makeDefault(defaults: defaults)
        row.variantId = variantId
        if rowOccupyingSlot(of: row, in: variantId, rows: rows) != nil { row.variantId = nil }
        return row
    }

    /// Replaces the row with a fresh default of the same id, size, variant and upload setting.
    /// Returns the image files the old row referenced.
    static func resetRow(at index: Int, rows: inout [ScreenshotRow], localeState: inout LocaleState, defaults: NewRowDefaults) -> [String] {
        let old = rows[index]
        let imageCandidates = imageFileNames(for: old.shapes, localeState: localeState) + old.allBackgroundImageFileNames
        for shape in old.shapes {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        var row = ScreenshotRow.makeDefault(
            id: old.id,
            label: old.isLabelManuallySet ? old.label : nil,
            width: old.templateWidth,
            height: old.templateHeight,
            defaults: defaults
        )
        row.variantId = old.variantId
        row.originRowId = old.originRowId
        row.excludeFromAppStoreConnect = old.excludeFromAppStoreConnect
        if let source = labelSource(of: row, in: rows) {
            row.label = source.label
            row.isLabelManuallySet = source.isLabelManuallySet
        }
        rows[index] = row
        cleanupOrphanedTranslationOverrides(rows: rows, localeState: &localeState)
        return imageCandidates
    }

    /// The nearest row above (or below) `index` that `isVisible` accepts — where a move swaps it to,
    /// so a filtered editor never moves a row past hidden ones.
    static func rowMoveTarget(
        from index: Int,
        up: Bool,
        in rows: [ScreenshotRow],
        among isVisible: (ScreenshotRow) -> Bool = { _ in true }
    ) -> Int? {
        up ? rows[..<index].lastIndex(where: isVisible) : rows[(index + 1)...].firstIndex(where: isVisible)
    }

    // MARK: - Variants

    /// Unique ignoring case and never "Original"; nil when `name` is blank.
    static func variantName(_ name: String, among variants: [ScreenshotVariant], excluding id: UUID? = nil) -> String? {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ScreenshotVariant.maxNameLength))
        return trimmed.isEmpty ? nil : variants.uniqueName(trimmed, excluding: id)
    }

    /// Starts a variant seeded with a copy of the row at `rowIndex`, inserted right after it.
    static func createVariant(
        fromRowAt rowIndex: Int,
        name: String?,
        variants: inout [ScreenshotVariant],
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) -> (variantId: UUID, copy: ScreenshotRow?) {
        var variant = ScreenshotVariant(
            name: variants.uniqueName(variants.nextDefaultName()),
            colorIndex: variants.nextColorIndex(among: ScreenshotVariant.colorSlots)
        )
        if let name, let unique = variantName(name, among: variants) { variant.name = unique }
        variants.append(variant)
        let copy = duplicateRow(at: rowIndex, into: variant.id, variants: variants, rows: &rows, localeState: &localeState, resources: resources)
        return (variant.id, copy)
    }

    /// Copies the row at `rowIndex` into `variantId` (nil: the Original), right after the source.
    /// Nil when the variant is unknown or already holds a row of that size.
    @discardableResult
    static func duplicateRow(
        at rowIndex: Int,
        into variantId: UUID?,
        variants: [ScreenshotVariant],
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) -> ScreenshotRow? {
        let source = rows[rowIndex]
        guard variantId == nil || variants.variant(withId: variantId) != nil,
              rowOccupyingSlot(of: source, in: variantId, rows: rows) == nil else { return nil }
        // A copy of a copy follows the same row, so a rename reaches the whole family.
        let origin = variantId == nil ? nil : (source.originRowId.flatMap { id in rows.contains { $0.id == id } ? id : nil } ?? source.id)
        return insertDuplicate(
            of: source, at: rowIndex + 1, label: source.label, isLabelManuallySet: source.isLabelManuallySet,
            variantId: variantId, originRowId: origin, rows: &rows, localeState: &localeState, resources: resources
        )
    }

    /// Moving a row back to the Original detaches it from the row it was copied from.
    static func setVariant(_ variantId: UUID?, ofRowAt index: Int, rows: inout [ScreenshotRow]) {
        rows[index].variantId = variantId
        if variantId == nil { rows[index].originRowId = nil }
    }

    /// Removes the variant and its rows; if that would empty the project, its rows move to the Original.
    static func deleteVariant(
        _ id: UUID,
        variants: inout [ScreenshotVariant],
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState
    ) -> (deletedRowIds: Set<UUID>, imageCandidates: [String?]) {
        let variantRowIds = Set(rows.inVariant(id).map(\.id))
        variants.removeAll { $0.id == id }
        if variantRowIds.count < rows.count {
            return (variantRowIds, deleteRows(variantRowIds, rows: &rows, localeState: &localeState) ?? [])
        }
        for i in rows.indices {
            rows[i].variantId = nil
            rows[i].originRowId = nil
        }
        return ([], [])
    }

    // MARK: - Row copies and removal

    /// Removes `ids` and their shapes' overrides. Returns the image files they referenced. Refuses
    /// (returns nil) when it would delete every row.
    static func deleteRows(_ ids: Set<UUID>, rows: inout [ScreenshotRow], localeState: inout LocaleState) -> [String?]? {
        guard rows.contains(where: { ids.contains($0.id) }), rows.contains(where: { !ids.contains($0.id) }) else { return nil }
        var imageCandidates: [String?] = []
        for row in rows where ids.contains(row.id) {
            imageCandidates += imageFileNames(for: row.shapes, localeState: localeState)
            imageCandidates += row.allBackgroundImageFileNames
            for shape in row.shapes {
                LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
            }
        }
        rows.removeAll { ids.contains($0.id) }
        cleanupOrphanedTranslationOverrides(rows: rows, localeState: &localeState)
        return imageCandidates
    }

    /// Copies `source` (new shape ids, their overrides and image files) into `rows` at `index`.
    @discardableResult
    static func insertDuplicate(
        of source: ScreenshotRow,
        at index: Int,
        label: String,
        isLabelManuallySet: Bool = true,
        variantId: UUID?,
        originRowId: UUID? = nil,
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) -> ScreenshotRow {
        var newShapes = source.shapes.map { $0.duplicated() }
        for i in newShapes.indices {
            let originalId = source.shapes[i].id
            LocaleService.copyShapeOverrides(&localeState, fromId: originalId, toId: newShapes[i].id)
            copyImageFiles(for: &newShapes[i], originalId: originalId, localeState: &localeState, resources: resources)
            // A variant's copy must be editable on its own: left in a Reuse Translation group, its
            // edits would rewrite the Original's text — the control — and the product page with it.
            if variantId != nil, let sharedKey = newShapes[i].translationKey {
                LocaleService.copyTextOverrides(&localeState, fromKey: sharedKey, toKey: newShapes[i].id.uuidString)
                newShapes[i].translationKey = nil
            }
        }
        let copy = ScreenshotRow(
            label: label,
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
            isLabelManuallySet: isLabelManuallySet,
            excludeFromAppStoreConnect: source.excludeFromAppStoreConnect,
            variantId: variantId,
            originRowId: originRowId
        )
        rows.insert(copy, at: index)
        return copy
    }
}

// MARK: - Lookups

extension ProjectDocument {
    func rowIndex(for rowId: UUID) -> Int? {
        rows.firstIndex { $0.id == rowId }
    }

    func shapeLocation(for shapeId: UUID) -> (rowIndex: Int, shapeIndex: Int)? {
        for (rowIndex, row) in rows.enumerated() {
            if let shapeIndex = row.shapes.firstIndex(where: { $0.id == shapeId }) {
                return (rowIndex, shapeIndex)
            }
        }
        return nil
    }
}
