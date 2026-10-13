#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import SwiftUI

/// A resource the document already points at, written off the main actor after the edit lands (SCREENSHOT-BRO-W).
struct StagedImageWrite {
    let fileName: String
    let source: StagedImageSource
}

/// The document half of an import, waiting for its files to be written.
struct StagedImport {
    var staged: [StagedImageWrite] = []
    var replaced: [String?] = []
    var imported = 0

    static func += (lhs: inout StagedImport, rhs: StagedImport) {
        lhs.staged += rhs.staged
        lhs.replaced += rhs.replaced
        lhs.imported += rhs.imported
    }
}

/// Copies an image resource inside one project's resources folder, under a new name.
@MainActor
protocol ImageResourceCopying {
    /// False when the source is missing or the copy failed; the duplicate then keeps the original's reference.
    func copyImageResource(_ fileName: String, to newFileName: String) -> Bool
}

extension PersistenceService {
    static func copyImageResource(_ fileName: String, to newFileName: String, inProject projectId: UUID) -> Bool {
        let resources = resourcesDir(projectId)
        let source = resources.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: source.path) else { return false }
        do {
            try FileManager.default.copyItem(at: source, to: resources.appendingPathComponent(newFileName))
            return true
        } catch {
            CrashReportingService.report(.imageResourceCopyFailed, error: error, extra: ["kind": "duplicate"])
            return false
        }
    }
}

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

    // MARK: - Templates

    /// Inserts a new template at `insertIndex`, shifting later shapes right and adding the row's default device.
    static func insertTemplate(in row: inout ScreenshotRow, at insertIndex: Int) {
        let columnWidth = row.templateWidth
        for i in row.shapes.indices where row.owningTemplateIndex(for: row.shapes[i]) >= insertIndex {
            row.shapes[i].x += columnWidth
        }
        let color = ScreenshotRow.templateColors[row.templates.count % ScreenshotRow.templateColors.count]
        row.templates.insert(ScreenshotTemplate(backgroundColor: color), at: insertIndex)
        if let defaultCategory = row.defaultDeviceCategory {
            var device = CanvasShapeModel.defaultDevice(
                centerX: row.templateCenterX(at: insertIndex),
                centerY: row.templateHeight / 2,
                templateHeight: row.templateHeight,
                category: defaultCategory
            )
            if let frameId = row.defaultDeviceFrameId, let frame = DeviceFrameCatalog.frame(for: frameId) {
                device.deviceCategory = frame.fallbackCategory
                device.deviceFrameId = frame.id
                device.adjustToDeviceAspectRatio(centerX: row.templateCenterX(at: insertIndex))
            }
            row.shapes.append(device)
        }
    }

    /// Removes the template and the shapes contained in it; spanning shapes survive so their visible
    /// portion on neighboring templates is preserved.
    static func removeTemplate(
        at templateIndex: Int,
        fromRowAt rowIndex: Int,
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState
    ) -> (removedShapeIds: Set<UUID>, imageCandidates: [String?]) {
        let shapesToRemove = rows[rowIndex].shapesContained(inTemplateAt: templateIndex)
        var imageCandidates: [String?] = imageFileNames(for: shapesToRemove, localeState: localeState)
        imageCandidates += rows[rowIndex].templates[templateIndex].backgroundImageConfig.allImageFileNames
        for shape in shapesToRemove {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        let removedIds = Set(shapesToRemove.map(\.id))
        rows[rowIndex].shapes.removeAll { removedIds.contains($0.id) }
        let width = rows[rowIndex].templateWidth
        for i in rows[rowIndex].shapes.indices where rows[rowIndex].owningTemplateIndex(for: rows[rowIndex].shapes[i]) > templateIndex {
            rows[rowIndex].shapes[i].x -= width
        }
        rows[rowIndex].templates.remove(at: templateIndex)
        cleanupOrphanedTranslationOverrides(rows: rows, localeState: &localeState)
        return (removedIds, imageCandidates)
    }

    /// Moves a template, keeping each single-column shape attached to its screenshot. Spanning shapes stay put.
    static func moveTemplate(in row: inout ScreenshotRow, from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex != destinationIndex,
              row.templates.indices.contains(sourceIndex),
              row.templates.indices.contains(destinationIndex) else { return }
        let columnWidth = row.templateWidth
        let lo = min(sourceIndex, destinationIndex)
        let hi = max(sourceIndex, destinationIndex)
        let betweenShift = sourceIndex < destinationIndex ? -columnWidth : columnWidth
        for shapeIndex in row.shapes.indices {
            let shape = row.shapes[shapeIndex]
            if row.spansMultipleTemplates(shape) { continue }

            let owner = row.owningTemplateIndex(for: shape)
            if owner == sourceIndex {
                row.shapes[shapeIndex].x += columnWidth * CGFloat(destinationIndex - sourceIndex)
            } else if owner >= lo && owner <= hi {
                row.shapes[shapeIndex].x += betweenShift
            }
        }
        let movedTemplate = row.templates.remove(at: sourceIndex)
        row.templates.insert(movedTemplate, at: destinationIndex)
    }

    /// Copies the template and the shapes it owns to `insertIndex`, shifting later columns right.
    static func duplicateTemplate(
        at templateIndex: Int,
        to insertIndex: Int,
        in row: inout ScreenshotRow,
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) {
        let sourceTemplate = row.templates[templateIndex]
        var newTemplate = sourceTemplate.duplicated()
        if let bgFileName = sourceTemplate.backgroundImageConfig.fileName {
            let newBgFile = "\(newTemplate.id.uuidString)-bg.png"
            if resources.copyImageResource(bgFileName, to: newBgFile) {
                newTemplate.backgroundImageConfig.fileName = newBgFile
            }
        }
        row.templates.insert(newTemplate, at: insertIndex)

        let columnWidth = row.templateWidth
        let sourceShapes = row.shapes.filter { row.owningTemplateIndex(for: $0) == templateIndex }
        for i in row.shapes.indices where row.owningTemplateIndex(for: row.shapes[i]) >= insertIndex {
            row.shapes[i].x += columnWidth
        }

        let shapeOffset = row.templateCenterX(at: insertIndex) - row.templateCenterX(at: templateIndex)
        for shape in sourceShapes {
            var copy = shape.duplicated()
            copy.x += shapeOffset
            LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
            copyImageFiles(for: &copy, originalId: shape.id, localeState: &localeState, resources: resources)
            row.shapes.append(copy)
        }
    }

    // MARK: - Shapes

    /// Appends a copy of `shape` (its translations and images too) at an offset, and returns it.
    @discardableResult
    static func duplicateShape(
        _ shape: CanvasShapeModel,
        offsetX: CGFloat,
        offsetY: CGFloat,
        in row: inout ScreenshotRow,
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) -> CanvasShapeModel {
        var copy = shape.duplicated(offsetX: offsetX, offsetY: offsetY)
        LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
        copyImageFiles(for: &copy, originalId: shape.id, localeState: &localeState, resources: resources)
        row.shapes.append(copy)
        return copy
    }

    /// Copies of `shapes` centered in each other template of `row`, or only those to one side.
    static func duplicateShapesToTemplates(
        _ shapes: [CanvasShapeModel],
        direction: DuplicateDirection,
        in row: inout ScreenshotRow,
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) {
        let source = row
        for shape in shapes {
            let sourceIndex = source.owningTemplateIndex(for: shape)
            let sourceCenterX = source.templateCenterX(at: sourceIndex)
            let targetIndices: Range<Int>
            switch direction {
            case .all: targetIndices = 0..<source.templates.count
            case .left: targetIndices = 0..<sourceIndex
            case .right: targetIndices = (sourceIndex + 1)..<source.templates.count
            }
            for targetIndex in targetIndices where targetIndex != sourceIndex {
                var copy = shape.duplicated(offsetX: source.templateCenterX(at: targetIndex) - sourceCenterX)
                LocaleService.copyShapeOverrides(&localeState, fromId: shape.id, toId: copy.id)
                copyImageFiles(for: &copy, originalId: shape.id, localeState: &localeState, resources: resources)
                row.shapes.append(copy)
            }
        }
    }

    /// Gives a duplicated shape its own copies of its image files, base and per locale.
    static func copyImageFiles(
        for newShape: inout CanvasShapeModel,
        originalId: UUID,
        localeState: inout LocaleState,
        resources: ImageResourceCopying
    ) {
        if let originalFile = newShape.displayImageFileName {
            let newFile = "\(newShape.id.uuidString).png"
            if resources.copyImageResource(originalFile, to: newFile) {
                newShape.displayImageFileName = newFile
            }
        }
        if let originalFillFile = newShape.fillImageConfig?.fileName {
            let newFillFile = "fill-\(newShape.id.uuidString).png"
            if resources.copyImageResource(originalFillFile, to: newFillFile) {
                newShape.fillImageConfig?.fileName = newFillFile
            }
        }
        let originalKey = originalId.uuidString
        let newKey = newShape.id.uuidString
        for localeCode in localeState.overrides.keys {
            guard var override = localeState.overrides[localeCode]?[originalKey],
                  let originalFile = override.overrideImageFileName else { continue }
            let newFile = "\(newShape.id.uuidString)-\(localeCode).png"
            if resources.copyImageResource(originalFile, to: newFile) {
                override.overrideImageFileName = newFile
                localeState.overrides[localeCode]?[newKey] = override
            }
        }
    }

    /// Removes the shape at `location` with its overrides. Returns the image files it referenced.
    /// Nil, and nothing removed, when the shape is locked.
    static func deleteShape(
        at location: (rowIndex: Int, shapeIndex: Int),
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState
    ) -> [String?]? {
        guard !rows[location.rowIndex].shapes[location.shapeIndex].resolvedIsLocked else { return nil }
        let removed = rows[location.rowIndex].shapes.remove(at: location.shapeIndex)
        let imageCandidates = imageFileNames(for: [removed], localeState: localeState)
        LocaleService.removeShapeOverrides(&localeState, shapeId: removed.id)
        cleanupOrphanedTranslationOverrides(rows: rows, localeState: &localeState)
        return imageCandidates
    }

    /// Moves a shape to the top or bottom of its row's stacking order.
    static func reorderShape(at location: (rowIndex: Int, shapeIndex: Int), toFront: Bool, rows: inout [ScreenshotRow]) {
        let shape = rows[location.rowIndex].shapes.remove(at: location.shapeIndex)
        if toFront {
            rows[location.rowIndex].shapes.append(shape)
        } else {
            rows[location.rowIndex].shapes.insert(shape, at: 0)
        }
    }

    /// Lines up (or evenly spaces) the shapes at `indices` within one row.
    static func align(_ alignment: ShapeAlignment, shapesAt indices: [Int], in row: inout ScreenshotRow) {
        let shapes = indices.map { row.shapes[$0] }
        switch alignment {
        case .left:
            guard let target = shapes.map(\.x).min() else { return }
            for i in indices { row.shapes[i].x = target }
        case .centerH:
            let target = shapes.map { $0.x + $0.width / 2 }.reduce(0, +) / CGFloat(max(shapes.count, 1))
            for i in indices { row.shapes[i].x = target - row.shapes[i].width / 2 }
        case .right:
            guard let target = shapes.map({ $0.x + $0.width }).max() else { return }
            for i in indices { row.shapes[i].x = target - row.shapes[i].width }
        case .top:
            guard let target = shapes.map(\.y).min() else { return }
            for i in indices { row.shapes[i].y = target }
        case .centerV:
            let target = shapes.map { $0.y + $0.height / 2 }.reduce(0, +) / CGFloat(max(shapes.count, 1))
            for i in indices { row.shapes[i].y = target - row.shapes[i].height / 2 }
        case .bottom:
            guard let target = shapes.map({ $0.y + $0.height }).max() else { return }
            for i in indices { row.shapes[i].y = target - row.shapes[i].height }
        case .distributeH:
            distribute(indices, in: &row, position: \.x, size: \.width)
        case .distributeV:
            distribute(indices, in: &row, position: \.y, size: \.height)
        }
    }

    private static func distribute(
        _ indices: [Int],
        in row: inout ScreenshotRow,
        position: WritableKeyPath<CanvasShapeModel, CGFloat>,
        size: KeyPath<CanvasShapeModel, CGFloat>
    ) {
        let sorted = indices.sorted { row.shapes[$0][keyPath: position] < row.shapes[$1][keyPath: position] }
        guard let firstIdx = sorted.first, let lastIdx = sorted.last, sorted.count > 1 else { return }
        let first = row.shapes[firstIdx]
        let last = row.shapes[lastIdx]
        let totalSpan = (last[keyPath: position] + last[keyPath: size]) - first[keyPath: position]
        let totalSize = sorted.map { row.shapes[$0][keyPath: size] }.reduce(0, +)
        let gap = (totalSpan - totalSize) / CGFloat(sorted.count - 1)
        var current = first[keyPath: position]
        for idx in sorted {
            row.shapes[idx][keyPath: position] = current
            current += row.shapes[idx][keyPath: size] + gap
        }
    }

    /// Centers a shape in the screenshot column it belongs to.
    static func center(shapeAt index: Int, in row: inout ScreenshotRow, axis: CenterAxis) {
        let shape = row.shapes[index]
        if axis != .vertically {
            let templateLeft = CGFloat(row.owningTemplateIndex(for: shape)) * row.templateWidth
            row.shapes[index].x = templateLeft + (row.templateWidth - shape.width) / 2
        }
        if axis != .horizontally {
            row.shapes[index].y = (row.templateHeight - shape.height) / 2
        }
    }

    /// Applies `mutate` to every unlocked device in the row; false when there is none.
    @discardableResult
    static func changeAllDevices(in row: inout ScreenshotRow, _ mutate: (inout CanvasShapeModel) -> Void) -> Bool {
        let indices = row.shapes.indices.filter { row.shapes[$0].type == .device && !row.shapes[$0].resolvedIsLocked }
        for i in indices { mutate(&row.shapes[i]) }
        return !indices.isEmpty
    }

    // MARK: - Backgrounds

    /// A language's first image also seeds the base, as a shape's first localized screenshot does.
    /// Returns the file it replaced.
    static func setBackgroundImage(_ source: BackgroundImageSource, on config: inout BackgroundImageConfig, localeCode: String?) -> String? {
        if let localeCode, source.hasImage {
            if !config.hasImage { config.source = source }
            return config.localeImages.updateValue(source, forKey: localeCode)?.fileName
        }
        let freed = config.fileName
        config.source = source
        return freed
    }

    /// Every image file `shapes` reference, base and per-locale.
    static func imageFileNames(for shapes: [CanvasShapeModel], localeState: LocaleState) -> [String] {
        shapes.flatMap(\.allImageFileNames) + shapes.flatMap { shape in
            localeState.overrides.values.compactMap { $0[shape.id.uuidString]?.overrideImageFileName }
        }
    }

    /// Set `text` as the base text of every text shape sharing `key` — the members of a reused string.
    static func setSharedBaseText(key: String, text: String, rows: inout [ScreenshotRow]) {
        for r in rows.indices {
            for s in rows[r].shapes.indices where rows[r].shapes[s].type == .text && rows[r].shapes[s].textTranslationKey == key {
                rows[r].shapes[s].text = text
            }
        }
    }

    /// Drop any override entry whose key is no longer a live shape id or a live text shape's
    /// translation key — e.g. after deleting every member of a reused string.
    static func cleanupOrphanedTranslationOverrides(rows: [ScreenshotRow], localeState: inout LocaleState) {
        var live = Set<String>()
        for row in rows {
            for shape in row.shapes {
                live.insert(shape.id.uuidString)
                if shape.type == .text { live.insert(shape.textTranslationKey) }
            }
        }
        for code in Array(localeState.overrides.keys) {
            guard let keys = localeState.overrides[code]?.keys else { continue }
            for key in Array(keys) where !live.contains(key) {
                localeState.overrides[code]?.removeValue(forKey: key)
            }
            if localeState.overrides[code]?.isEmpty == true {
                localeState.overrides.removeValue(forKey: code)
            }
        }
    }

    // MARK: - Locales

    /// Removes the locale, its overrides and the rows' background images for it. Returns the image files it freed.
    static func removeLocale(_ code: String, rows: inout [ScreenshotRow], localeState: inout LocaleState) -> [String] {
        let overrideImages = localeState.overrides[code]?.values.compactMap(\.overrideImageFileName) ?? []
        LocaleService.removeLocale(&localeState, code: code)
        return overrideImages + removeBackgroundImageOverrides(forLocale: code, in: &rows)
    }

    static func removeBackgroundImageOverrides(forLocale code: String, in rows: inout [ScreenshotRow]) -> [String] {
        var freed: [String] = []
        for index in rows.indices where rows[index].hasBackgroundImageEntry(forLocale: code) {
            freed += rows[index].removeBackgroundImageOverrides(forLocale: code)
        }
        return freed
    }

    // MARK: - Translations

    /// Writes a translation through the text-only path, so the geometry override and its auto-fit
    /// record survive, then (with `autoFits`) refits every box showing it.
    static func setTranslation(
        textKey: String, localeCode: String, text: String, richText: String?, autoFits: Bool,
        rows: [ScreenshotRow], localeState: inout LocaleState, availableFontFamilies: Set<String>
    ) -> [UUID: TextAutoFitResult] {
        let value = text.isEmpty ? nil : text
        LocaleService.setTextFieldsOverride(
            &localeState, localeCode: localeCode, key: textKey,
            text: value, richText: value == nil ? nil : richText, clearsRichText: nil
        )
        takeBackAutoFit(textKey: textKey, localeCode: localeCode, rows: rows, localeState: &localeState)
        guard autoFits else { return [:] }
        return fitTranslatedText(
            textKey: textKey, localeCode: localeCode, rows: rows,
            localeState: &localeState, availableFontFamilies: availableFontFamilies
        )
    }

    /// Every write to a translation's text calls this, so an earlier fit never outlives the text it was made for.
    static func takeBackAutoFit(textKey: String, localeCode: String, rows: [ScreenshotRow], localeState: inout LocaleState) {
        for shape in rows.flatMap(\.shapes) where shape.textTranslationKey == textKey {
            guard let override = localeState.override(forCode: localeCode, shapeId: shape.id), override.autoFit != nil else { continue }
            writeShapeOverride(override.removingAutoFit(), shapeId: shape.id, localeCode: localeCode, localeState: &localeState)
        }
    }

    private static func fitTranslatedText(
        textKey: String, localeCode: String, rows: [ScreenshotRow],
        localeState: inout LocaleState, availableFontFamilies: Set<String>
    ) -> [UUID: TextAutoFitResult] {
        // A cleared translation shows the base text, which is the base layout's business.
        guard localeState.overrides[localeCode]?[textKey]?.hasTranslatedTextField == true else { return [:] }
        var results: [UUID: TextAutoFitResult] = [:]
        for row in rows {
            for shape in row.shapes where shape.type == .text && shape.textTranslationKey == textKey {
                let result = TextAutoFitService.fit(
                    shape: shape, localeCode: localeCode, row: row,
                    localeState: localeState, availableFontFamilies: availableFontFamilies
                )
                results[shape.id] = result
                let override = localeState.override(forCode: localeCode, shapeId: shape.id) ?? ShapeLocaleOverride()
                writeShapeOverride(override.addingAutoFit(result.contribution), shapeId: shape.id, localeCode: localeCode, localeState: &localeState)
            }
        }
        return results
    }

    private static func writeShapeOverride(_ override: ShapeLocaleOverride, shapeId: UUID, localeCode: String, localeState: inout LocaleState) {
        LocaleService.setShapeOverride(
            &localeState, localeCode: localeCode, shapeId: shapeId, override: override.isEmpty ? nil : override
        )
    }

    // MARK: - Images

    /// Repoints one shape (or one locale's override) at `fileName`, returning the file it replaced.
    /// `localeCode` is the locale to write, `nil` for the base image.
    static func pointShape(
        _ shape: inout CanvasShapeModel,
        at fileName: String,
        imageSize: CGSize,
        localeCode: String?,
        localeState: inout LocaleState
    ) -> String? {
        guard let localeCode else {
            let previous = setBaseImage(&shape, fileName: fileName, imageSize: imageSize)
            return previous == fileName ? nil : previous
        }

        // A shape with no base image renders an empty frame in every locale that has no override
        // of its own — and in the export — so the first image to arrive becomes the fallback too.
        // Otherwise a locale-targeted import into a fresh row reports success and ships blanks.
        if shape.displayImageFileName == nil {
            _ = setBaseImage(&shape, fileName: fileName, imageSize: imageSize)
        }
        var override = localeState.override(forCode: localeCode, shapeId: shape.id) ?? ShapeLocaleOverride()
        let previous = override.overrideImageFileName
        override.overrideImageFileName = fileName
        if shape.flexesToImageAspect {
            // An abstract frame takes its aspect from the image, and this locale's image need not
            // match the base one — so the resize has to be an override, not a base edit.
            var flexed = shape
            flexed.adaptToImageAspectRatio(imageSize)
            override.offsetX = flexed.x == shape.x ? nil : flexed.x - shape.x
            override.offsetWidth = flexed.width == shape.width ? nil : flexed.width - shape.width
        }
        LocaleService.setShapeOverride(&localeState, localeCode: localeCode, shapeId: shape.id, override: override)
        return previous == fileName ? nil : previous
    }

    private static func setBaseImage(_ shape: inout CanvasShapeModel, fileName: String, imageSize: CGSize) -> String? {
        let previous = shape.displayImageFileName
        shape.displayImageFileName = fileName
        if shape.flexesToImageAspect {
            shape.adaptToImageAspectRatio(imageSize)
        }
        return previous
    }

    static func screenshotImageFileName(for shapeId: UUID, localeCode: String?) -> String {
        let localePart = localeCode.map { "-\($0)" } ?? ""
        return "\(shapeId.uuidString)\(localePart)-\(UUID().uuidString).png"
    }

    /// Creates an image or device shape sized for the given row, without side effects.
    static func makeImageShape(image: NSImage, row: ScreenshotRow, centerX: CGFloat, centerY: CGFloat) -> CanvasShapeModel {
        if let rawCategory = ScreenshotDeviceDetector.detectScreenshotDevice(image) {
            // Phone/tablet pixel sizes overlap between Apple and Android, so when the row's
            // default is an Android category we honor it instead of the Apple-leaning fallback.
            let detectedCategory: DeviceCategory
            switch (row.defaultDeviceCategory, rawCategory) {
            case (.androidPhone, .iphone):
                detectedCategory = .androidPhone
            case (.androidTablet, .ipadPro11), (.androidTablet, .ipadPro13):
                detectedCategory = .androidTablet
            default:
                detectedCategory = rawCategory
            }
            var shape = CanvasShapeModel.defaultDeviceFromRow(
                row,
                centerX: centerX,
                centerY: centerY,
                detectedCategory: detectedCategory
            )
            if let preferredFrame = ScreenshotDeviceDetector.preferredImportFrame(for: image, in: row, detectedCategory: detectedCategory) {
                shape.selectRealFrame(preferredFrame)
                shape.adjustToDeviceAspectRatio(centerX: centerX)
                // A landscape flip preserves the long side, which overflows a portrait template.
                shape.scaleToFitWidth(row.templateWidth * 0.9)
            }
            return shape
        }
        let imgW = image.size.width
        let imgH = image.size.height
        let maxW = row.templateWidth * 0.8
        let maxH = row.templateHeight * 0.8
        let scale = min(maxW / imgW, maxH / imgH, 1.0)
        let w = imgW * scale
        let h = imgH * scale
        return CanvasShapeModel(
            type: .image,
            x: centerX - w / 2,
            y: centerY - h / 2,
            width: w,
            height: h,
            color: .clear
        )
    }

    /// Fills the row's device columns in order (or one column per image when it has no devices),
    /// appending columns for the overflow. `maxTemplatesPerRow` caps the resulting column count.
    /// Returns the files still owed to disk and the ones the import replaced.
    static func stageImport(
        _ sources: [ImageImportSource],
        into row: inout ScreenshotRow,
        localeCode: String?,
        maxTemplatesPerRow: Int?,
        localeState: inout LocaleState
    ) -> StagedImport {
        let templatesWithDevices = templatesContainingDevices(in: row)
        // Templates an image can fill without creating a new one.
        let reusableCount = templatesWithDevices.isEmpty ? row.templates.count : templatesWithDevices.count
        var sources = sources
        if let cap = maxTemplatesPerRow {
            let maxImages = reusableCount + max(0, cap - row.templates.count)
            if sources.count > maxImages {
                sources = Array(sources.prefix(maxImages))
            }
        }
        guard !sources.isEmpty else { return StagedImport() }

        var targetTemplateIndices: [Int]
        if templatesWithDevices.isEmpty {
            while row.templates.count < sources.count {
                insertTemplate(in: &row, at: row.templates.count)
            }
            targetTemplateIndices = Array(0..<sources.count)
        } else {
            targetTemplateIndices = Array(templatesWithDevices.prefix(sources.count))
            while targetTemplateIndices.count < sources.count {
                insertTemplate(in: &row, at: row.templates.count)
                targetTemplateIndices.append(row.templates.count - 1)
            }
        }

        var batch = StagedImport(imported: sources.count)
        for (source, templateIndex) in zip(sources, targetTemplateIndices) {
            let shapeIndex: Int
            if let existing = existingDeviceShapeIndex(in: row, templateIndex: templateIndex) {
                shapeIndex = existing
            } else {
                let shape = makeImageShape(
                    image: source.image, row: row,
                    centerX: row.templateCenterX(at: templateIndex), centerY: row.templateHeight / 2
                )
                shapeIndex = row.shapes.count
                row.shapes.append(shape)
            }
            let fileName = screenshotImageFileName(for: row.shapes[shapeIndex].id, localeCode: localeCode)
            let replaced = pointShape(
                &row.shapes[shapeIndex], at: fileName, imageSize: source.image.size,
                localeCode: localeCode, localeState: &localeState
            )
            batch.staged.append(StagedImageWrite(
                fileName: fileName,
                source: source.sourceURL.map { .file($0) } ?? .image(source.image)
            ))
            batch.replaced.append(replaced)
        }
        return batch
    }

    static func templatesContainingDevices(in row: ScreenshotRow) -> [Int] {
        (0..<row.templates.count).filter { existingDeviceShapeIndex(in: row, templateIndex: $0) != nil }
    }

    /// The device a screenshot dropped on `templateIndex` belongs in: real frames first, then the
    /// one nearest the column's center.
    static func existingDeviceShapeIndex(in row: ScreenshotRow, templateIndex: Int) -> Int? {
        let templateCenterX = row.templateCenterX(at: templateIndex)
        let templateCenterY = row.templateHeight / 2

        var best: (index: Int, hasRealFrame: Bool, distance: CGFloat)?

        for (index, shape) in row.shapes.enumerated() {
            guard shape.type == .device,
                  row.owningTemplateIndex(for: shape) == templateIndex else { continue }

            let hasRealFrame = shape.deviceFrameId != nil
            let shapeCenterX = shape.x + shape.width / 2
            let shapeCenterY = shape.y + shape.height / 2
            let distance = abs(shapeCenterX - templateCenterX) + abs(shapeCenterY - templateCenterY)

            guard let current = best else {
                best = (index, hasRealFrame, distance)
                continue
            }

            if hasRealFrame != current.hasRealFrame {
                if hasRealFrame { best = (index, hasRealFrame, distance) }
            } else if distance < current.distance {
                best = (index, hasRealFrame, distance)
            } else if distance == current.distance && index < current.index {
                best = (index, hasRealFrame, distance)
            }
        }

        return best?.index
    }

    /// Writes staged resources off the main actor, publishing each thumbnail; returns a message per failed write.
    static func flush(
        _ staged: [StagedImageWrite],
        to resourcesDir: URL,
        publish: (String, NSImage) -> Void
    ) async -> [String] {
        var failures: [String] = []
        for write in staged {
            let destination = resourcesDir.appendingPathComponent(write.fileName)
            do {
                switch write.source {
                case .file(let url):
                    try await StagedImageWriter.persist(copying: url, to: destination)
                case .image(let image):
                    // Pulled here, one at a time: `NSImage` can't cross actors, and decoding all of
                    // them up front would hold every full-resolution bitmap for the whole flush.
                    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        throw StagedImageWriteError.noImageData
                    }
                    try await StagedImageWriter.persist(encoding: cgImage, to: destination)
                }
            } catch StagedImageWriteError.writeFailed(let reason) {
                failures.append(AppState.ImageResourceSaveAction.saveScreenshot.writeFailedMessage(reason))
                continue
            } catch {
                failures.append(AppState.ImageResourceSaveAction.saveScreenshot.encodeFailedMessage)
                continue
            }

            if let thumbnail = await ImageDownsampler.downsampledCGImageOffMain(
                at: destination,
                maxDimension: ImageDownsampler.editorImageMaxDimension
            ) {
                publish(write.fileName, NSImage(
                    cgImage: thumbnail,
                    size: NSSize(width: thumbnail.width, height: thumbnail.height)
                ))
            }
        }
        return failures
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
