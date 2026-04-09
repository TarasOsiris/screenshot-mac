import SwiftUI

extension AppState {

    // MARK: - Selection

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
            visibleCanvasModelCenter = nil
        }
    }

    func selectShape(_ shapeId: UUID, in rowId: UUID) {
        finishContinuousEditIfNeeded()
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              rows[rowIdx].shapes.contains(where: { $0.id == shapeId }) else { return }
        selectedRowId = rowId
        selectedShapeIds = [shapeId]
    }

    func toggleShapeSelection(_ shapeId: UUID, in rowId: UUID) {
        finishContinuousEditIfNeeded()
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              rows[rowIdx].shapes.contains(where: { $0.id == shapeId }) else { return }
        // Different row → switch row and select just this shape
        if selectedRowId != rowId {
            selectedRowId = rowId
            selectedShapeIds = [shapeId]
            visibleCanvasModelCenter = nil
            return
        }
        if isEditingText {
            isEditingText = false
        }
        if selectedShapeIds.contains(shapeId) {
            selectedShapeIds.remove(shapeId)
        } else {
            selectedShapeIds.insert(shapeId)
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
        isEditingText = false
    }

    /// Scroll to center the selected shape(s) on screen.
    func focusOnSelection() {
        guard let rowId = selectedRowId,
              !selectedShapeIds.isEmpty else { return }
        guard rows.contains(where: { $0.id == rowId }) else { return }
        canvasFocusAnimated = false
        canvasFocusRowId = rowId
        canvasFocusRequestNonce += 1
        focusShapeId = selectedShapeIds.first
        focusRequestNonce += 1
    }

    // MARK: - Selection Helpers

    func normalizeSelection() {
        if let selectedRowId, !rows.contains(where: { $0.id == selectedRowId }) {
            self.selectedRowId = rows.first?.id
        }

        if !selectedShapeIds.isEmpty {
            guard let rowIdx = selectedRowIndex else {
                selectedShapeIds = []
                isEditingText = false
                return
            }
            let existingIds = Set(rows[rowIdx].shapes.map(\.id))
            selectedShapeIds = selectedShapeIds.intersection(existingIds)
            if selectedShapeIds.isEmpty {
                isEditingText = false
            }
        }
    }
}
