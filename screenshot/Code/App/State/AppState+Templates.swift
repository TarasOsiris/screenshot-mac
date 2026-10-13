import SwiftUI

/// Remembers the last template move so a rapid follow-up click on the displaced
/// neighbor's button continues moving the same template instead of swapping back.
struct TemplateMoveContinuation {
    static let window: TimeInterval = 0.5
    let rowId: UUID
    let movedTemplateId: UUID
    let displacedTemplateId: UUID
    let toRight: Bool
    let at: Date
}

extension AppState {

    // MARK: - Templates

    func addTemplate(to rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }) else { return }
        withUndo("Add Template") { appendTemplate(to: idx) }
    }

    func insertTemplateBefore(_ templateId: UUID, in rowId: UUID) {
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIdx].templates.firstIndex(where: { $0.id == templateId }) else { return }
        withUndo("Insert Screenshot Before") { insertTemplate(inRowAt: rowIdx, at: templateIndex) }
    }

    func insertTemplateAfter(_ templateId: UUID, in rowId: UUID) {
        guard let rowIdx = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIdx].templates.firstIndex(where: { $0.id == templateId }) else { return }
        withUndo("Insert Screenshot After") { insertTemplate(inRowAt: rowIdx, at: templateIndex + 1) }
    }

    /// Appends a new template (and its default device shape) to the row at the given index.
    /// Does not register undo or schedule save — callers handle that.
    func appendTemplate(to rowIndex: Int) {
        insertTemplate(inRowAt: rowIndex, at: rows[rowIndex].templates.count)
    }

    /// Inserts a new template at the given position, shifting existing shapes right.
    private func insertTemplate(inRowAt rowIndex: Int, at insertIndex: Int) {
        DocumentEditing.insertTemplate(in: &rows[rowIndex], at: insertIndex)
    }

    func removeTemplate(_ templateId: UUID, from rowId: UUID) {
        guard let idx = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[idx].templates.firstIndex(where: { $0.id == templateId }) else { return }
        withUndo("Remove Template") {
            let removed = DocumentEditing.removeTemplate(at: templateIndex, fromRowAt: idx, rows: &rows, localeState: &localeState)
            selectedShapeIds.subtract(removed.removedShapeIds)
            cleanupUnreferencedImages(removed.imageCandidates)
        }
    }

    func duplicateTemplate(_ templateId: UUID, in rowId: UUID) {
        duplicateTemplate(templateId, in: rowId, toEnd: false)
    }

    func duplicateTemplateToEnd(_ templateId: UUID, in rowId: UUID) {
        duplicateTemplate(templateId, in: rowId, toEnd: true)
    }

    private func duplicateTemplate(_ templateId: UUID, in rowId: UUID, toEnd: Bool) {
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == templateId }) else { return }
        withUndo("Duplicate Screenshot") {
            let insertIndex = toEnd ? rows[rowIndex].templates.count : templateIndex + 1
            DocumentEditing.duplicateTemplate(
                at: templateIndex, to: insertIndex, in: &rows[rowIndex],
                localeState: &localeState, resources: self
            )
        }
    }

    func moveTemplateLeft(_ templateId: UUID, in rowId: UUID) {
        let targetId = continuationTargetId(clicked: templateId, in: rowId, toRight: false)
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == targetId }),
              templateIndex > 0 else { return }
        moveTemplate(inRowAt: rowIndex, from: templateIndex, to: templateIndex - 1, undoName: "Move Screenshot Left")
    }

    func moveTemplateRight(_ templateId: UUID, in rowId: UUID) {
        let targetId = continuationTargetId(clicked: templateId, in: rowId, toRight: true)
        guard let rowIndex = rows.firstIndex(where: { $0.id == rowId }),
              let templateIndex = rows[rowIndex].templates.firstIndex(where: { $0.id == targetId }),
              templateIndex < rows[rowIndex].templates.count - 1 else { return }
        moveTemplate(inRowAt: rowIndex, from: templateIndex, to: templateIndex + 1, undoName: "Move Screenshot Right")
    }

    /// A move swaps the clicked template with its neighbor, putting the neighbor's move button
    /// under the still-stationary cursor. A rapid same-direction click on that neighbor means
    /// "keep moving the same screenshot", not "move the neighbor back" — redirect it.
    private func continuationTargetId(clicked templateId: UUID, in rowId: UUID, toRight: Bool) -> UUID {
        guard let c = templateMoveContinuation,
              c.rowId == rowId,
              c.toRight == toRight,
              c.displacedTemplateId == templateId,
              Date().timeIntervalSince(c.at) < TemplateMoveContinuation.window else { return templateId }
        return c.movedTemplateId
    }

    private func moveTemplate(inRowAt rowIndex: Int, from sourceIndex: Int, to destinationIndex: Int, undoName: String) {
        guard sourceIndex != destinationIndex else { return }

        var row = rows[rowIndex]
        guard row.templates.indices.contains(sourceIndex),
              row.templates.indices.contains(destinationIndex) else { return }

        withUndo(undoName) {
            DocumentEditing.moveTemplate(in: &rows[rowIndex], from: sourceIndex, to: destinationIndex)
        }

        templateMoveContinuation = TemplateMoveContinuation(
            rowId: rows[rowIndex].id,
            movedTemplateId: rows[rowIndex].templates[destinationIndex].id,
            displacedTemplateId: rows[rowIndex].templates[sourceIndex].id,
            toRight: destinationIndex > sourceIndex,
            at: Date()
        )
    }
}
