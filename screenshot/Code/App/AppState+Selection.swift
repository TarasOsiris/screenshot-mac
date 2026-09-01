import SwiftUI

extension AppState {

    // MARK: - Selection

    var selectedTranslatableTextShapeIds: Set<UUID> {
        guard let rowIndex = selectedRowIndex else { return [] }
        let selected = selectedShapeIds
        return Set(
            rows[rowIndex].shapes
                .filter { selected.contains($0.id) && $0.hasTranslatableText }
                .map(\.id)
        )
    }

    func selectRow(_ id: UUID?) {
        finishContinuousEditIfNeeded()
        guard let id else {
            deselectAll()
            return
        }
        guard rows.contains(where: { $0.id == id }) else { return }
        let rowChanged = selectedRowId != id
        selectedRowId = id
        selectedShapeIds = []
        if rowChanged {
            visibleCanvasModelCenterX = nil
        }
    }

    func selectShape(_ shapeId: UUID, in rowId: UUID) {
        finishContinuousEditIfNeeded()
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              rows[rowIdx].shapes.contains(where: { $0.id == shapeId }) else { return }
        // Guarded like the three siblings below: a same-value write still notifies every
        // `@Observable` reader, and `selectedRowId` is read by the inspector, the properties bar
        // and the command menus — so an unguarded write made a click in the already-selected row
        // cost as much as one that actually moved rows.
        if selectedRowId != rowId {
            selectedRowId = rowId
            visibleCanvasModelCenterX = nil
        }
        if selectedShapeIds != [shapeId] {
            selectedShapeIds = [shapeId]
        }
    }

    func toggleShapeSelection(_ shapeId: UUID, in rowId: UUID) {
        finishContinuousEditIfNeeded()
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              rows[rowIdx].shapes.contains(where: { $0.id == shapeId }) else { return }
        // Different row → switch row and select just this shape
        if selectedRowId != rowId {
            selectedRowId = rowId
            selectedShapeIds = [shapeId]
            visibleCanvasModelCenterX = nil
            return
        }
        if textEdit.isActive {
            textEdit.isActive = false
        }
        if selectedShapeIds.contains(shapeId) {
            selectedShapeIds.remove(shapeId)
        } else {
            selectedShapeIds.insert(shapeId)
        }
    }

    /// Bulk selection — the marquee's commit. Narrows `ids` to shapes that actually exist in the
    /// row, so the `selection ⊆ row.shapes` invariant `normalizeSelection` enforces holds by
    /// construction rather than by trusting the caller.
    func selectShapes(_ ids: Set<UUID>, in rowId: UUID) {
        finishContinuousEditIfNeeded()
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        if textEdit.isActive {
            textEdit.isActive = false
        }
        let present = ids.intersection(rows[rowIdx].shapes.lazy.map(\.id))
        if selectedRowId != rowId {
            selectedRowId = rowId
            visibleCanvasModelCenterX = nil
        }
        if selectedShapeIds != present {
            selectedShapeIds = present
        }
    }

    func selectAllShapesInRow() {
        finishContinuousEditIfNeeded()
        guard let rowIdx = selectedRowIndex else { return }
        selectedShapeIds = Set(rows[rowIdx].activeShapes.map(\.id))
    }

    func deselectAll() {
        finishContinuousEditIfNeeded()
        selectedShapeIds = []
        selectedRowId = nil
        textEdit.isActive = false
    }

    /// Request the canvas ScrollView to scroll a row to center (drives the `ScrollViewReader`
    /// in `ContentView` via the nonce).
    func requestCanvasFocus(on rowId: UUID, animated: Bool) {
        canvasFocus.requestRow(rowId, animated: animated)
    }

    /// Scroll to center the selected shape(s) on screen.
    func focusOnSelection() {
        guard let rowId = selectedRowId,
              !selectedShapeIds.isEmpty else { return }
        guard rows.contains(where: { $0.id == rowId }) else { return }
        requestCanvasFocus(on: rowId, animated: false)
        canvasFocus.requestShape(selectedShapeIds.first)
    }

    // MARK: - Selection Helpers

    func normalizeSelection() {
        if let selectedRowId, !rows.contains(where: { $0.id == selectedRowId }) {
            self.selectedRowId = rows.first?.id
        }

        if !selectedShapeIds.isEmpty {
            guard let rowIdx = selectedRowIndex else {
                selectedShapeIds = []
                textEdit.isActive = false
                return
            }
            let existingIds = Set(rows[rowIdx].shapes.map(\.id))
            selectedShapeIds = selectedShapeIds.intersection(existingIds)
            if selectedShapeIds.isEmpty {
                textEdit.isActive = false
            }
        }
    }
}
