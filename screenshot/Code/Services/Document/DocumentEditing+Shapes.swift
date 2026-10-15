import Foundation

extension DocumentEditing {

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

    /// Writes `updated` over the shape at `location` as seen in `localeCode` — into the base model or
    /// that language's override — and carries a base-language text edit to every member of its reused string.
    static func commitShapeEdit(
        _ updated: CanvasShapeModel,
        at location: (rowIndex: Int, shapeIndex: Int),
        forLocaleCode localeCode: String,
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState
    ) {
        let base = rows[location.rowIndex].shapes[location.shapeIndex]
        rows[location.rowIndex].shapes[location.shapeIndex] = LocaleService.splitUpdate(
            base: base, updated: updated, localeState: &localeState, forLocaleCode: localeCode
        )
        if base.translationKey != nil, localeCode == localeState.baseLocaleCode, let text = updated.text, text != base.text {
            setSharedBaseText(key: base.textTranslationKey, text: text, rows: &rows)
        }
    }

    /// Removes every `type` shape in the row, locked ones included, with their overrides.
    /// Returns their ids and the image files they referenced.
    static func deleteShapes(
        ofType type: ShapeType,
        inRowAt rowIndex: Int,
        rows: inout [ScreenshotRow],
        localeState: inout LocaleState
    ) -> (removedIds: Set<UUID>, imageCandidates: [String]) {
        let matching = rows[rowIndex].shapes.filter { $0.type == type }
        let imageCandidates = imageFileNames(for: matching, localeState: localeState)
        for shape in matching {
            LocaleService.removeShapeOverrides(&localeState, shapeId: shape.id)
        }
        let removedIds = Set(matching.map(\.id))
        rows[rowIndex].shapes.removeAll { removedIds.contains($0.id) }
        cleanupOrphanedTranslationOverrides(rows: rows, localeState: &localeState)
        return (removedIds, imageCandidates)
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
}
