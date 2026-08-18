import SwiftUI

// Multi-shape geometry: aligning, distributing and matching size across a selection. Split out
// of AppState+Shapes.swift, which had grown past 690 lines.
extension AppState {
    // MARK: - Align Selected Shapes

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
