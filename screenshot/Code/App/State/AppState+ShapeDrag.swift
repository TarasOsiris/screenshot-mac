import SwiftUI
import UniformTypeIdentifiers

extension AppState {
    // MARK: - Option+Drag Duplicate

    func duplicateShapeForOptionDrag(_ shapeId: UUID) -> UUID? {
        guard let location = shapeLocation(for: shapeId),
              !rows[location.rowIndex].shapes[location.shapeIndex].resolvedIsLocked else { return nil }
        return insertDuplicate(of: shapeId, undoName: "Duplicate Shape")
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
}
