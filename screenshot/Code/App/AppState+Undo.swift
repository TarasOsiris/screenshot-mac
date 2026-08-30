import SwiftUI

// The undo/persistence contract: withUndo snapshots rows + localeState as one document,
// registers a step only if they actually changed, and schedules the save. Nested calls join
// the outer transaction via edits.isInUndoTransaction, so a wrapped helper never makes a second step.
extension AppState {
    // MARK: - Undo

    /// Wraps a document mutation so undo is captured automatically: snapshots the whole
    /// document before `body`, restores it on undo (re-registering redo), and schedules the
    /// save. A `body` that changes nothing registers no undo step. Nested `withUndo` calls
    /// join the outer transaction so a wrapped helper doesn't create a second step.
    @discardableResult
    func withUndo<T>(_ actionName: String, _ body: () -> T) -> T {
        commitAllPendingEdits()
        if edits.isInUndoTransaction { return body() }
        edits.isInUndoTransaction = true
        defer { edits.isInUndoTransaction = false }

        let baseRows = rows
        let baseLocaleState = localeState
        let result = body()
        guard rows != baseRows || localeState != baseLocaleState else { return result }
        CrashReportingService.breadcrumb(.edit, actionName, data: ["rows": rows.count])
        registerSnapshot(actionName, baseRows: baseRows, baseLocaleState: baseLocaleState)
        scheduleSave()
        return result
    }

    /// Row-scoped `withUndo` for mutations confined to one row (plus `localeState` and
    /// selection): the no-op check compares a single row instead of the whole document,
    /// and the undo step retains one row. Shares `edits.isInUndoTransaction`, so nesting with
    /// `withUndo` (either direction) joins the outer transaction. The row must exist
    /// before and after `body` — ops that add/remove/reorder rows, or that touch other
    /// rows (e.g. shared-base-text fan-out), stay on `withUndo`.
    func withRowUndo(_ actionName: String, rowId: UUID, _ body: () -> Void) {
        commitAllPendingEdits()
        if edits.isInUndoTransaction { body(); return }
        edits.isInUndoTransaction = true
        defer { edits.isInUndoTransaction = false }

        guard let idx = rowIndex(for: rowId) else { return }
        let baseRow = rows[idx]
        let baseLocaleState = localeState
        let baseRowCount = rows.count
        #if DEBUG
        let allRowsBase = rows
        #endif
        body()
        #if DEBUG
        assert(
            rows.count == allRowsBase.count
                && zip(rows, allRowsBase).allSatisfy { $0.id == $1.id && ($0.id == rowId || $0 == $1) },
            "withRowUndo(\"\(actionName)\") body mutated rows other than the target row — use withUndo"
        )
        #endif
        // The deep DEBUG assert needs a whole-document copy, which is exactly what this path
        // avoids; the row count is O(1) and still catches the corrupting misuse in release.
        if rows.count != baseRowCount {
            CrashReportingService.report(
                .undoScopeViolation,
                extra: ["action": actionName, "base_rows": baseRowCount, "rows": rows.count]
            )
        }
        guard let newIdx = rowIndex(for: rowId) else { return }
        guard rows[newIdx] != baseRow || localeState != baseLocaleState else { return }
        CrashReportingService.breadcrumb(.edit, actionName, data: ["shapes": rows[newIdx].shapes.count])
        registerRowSnapshot(actionName, rowId: rowId, baseRow: baseRow, baseLocaleState: baseLocaleState)
        scheduleSave()
    }

    /// Registers a whole-document restore on the undo stack, re-registering its own inverse
    /// so redo cycles back to the post-edit state. Shared by `withUndo` and the continuous-edit
    /// commit path.
    private func registerSnapshot(_ actionName: String, baseRows: [ScreenshotRow], baseLocaleState: LocaleState) {
        guard let undoManager else { return }
        registeringUndoStep(on: undoManager) {
            undoManager.registerUndo(withTarget: self) { target in
                let redoRows = target.rows
                let redoLocaleState = target.localeState
                target.rows = baseRows
                target.localeState = baseLocaleState
                target.templateMoveContinuation = nil
                target.normalizeSelection()
                target.scheduleSave()
                target.registerSnapshot(actionName, baseRows: redoRows, baseLocaleState: redoLocaleState)
                target.undoManager?.setActionName(actionName)
            }
            undoManager.setActionName(actionName)
        }
    }

    /// `groupsByEvent` is off on the document's manager, so nothing opens the group
    /// `registerUndo` requires. No-op when one is already open — `undo()`/`redo()` open one
    /// while replaying, which is how a re-registered inverse joins the right stack.
    private func registeringUndoStep(on undoManager: UndoManager, _ body: () -> Void) {
        let needsGroup = undoManager.groupingLevel == 0
        if needsGroup { undoManager.beginUndoGrouping() }
        body()
        if needsGroup { undoManager.endUndoGrouping() }
        // Every push consumes a slot in the bounded stack; the orphaned-image sweep measures
        // reachability in these units.
        undoStepGeneration += 1
    }

    /// Full-snapshot undo with a pre-captured base — used by the debounced translation-edit
    /// path, which captures its base before the keystroke burst. Discrete mutations go through
    /// `withUndo` instead.
    func registerUndoWithBase(_ actionName: String, base: [ScreenshotRow], baseLocaleState: LocaleState? = nil) {
        CrashReportingService.breadcrumb(.edit, actionName, data: ["rows": rows.count])
        registerSnapshot(actionName, baseRows: base, baseLocaleState: baseLocaleState ?? localeState)
    }

    /// Row-scoped undo with a pre-captured base row. Looks up the row by ID on undo/redo,
    /// so it's safe even if row indices shift (though callers should only use this when row count is stable).
    func registerUndoForRowWithBase(_ actionName: String, baseRow: ScreenshotRow, baseLocaleState: LocaleState? = nil) {
        CrashReportingService.breadcrumb(.edit, actionName, data: ["shapes": baseRow.shapes.count])
        registerRowSnapshot(actionName, rowId: baseRow.id, baseRow: baseRow, baseLocaleState: baseLocaleState ?? localeState)
    }

    /// Row-scoped counterpart to `registerSnapshot`: restores a single row by ID and
    /// re-registers its own inverse, so undo↔redo cycles indefinitely (the earlier
    /// two-closure form dropped the step after the first redo). If the row no longer
    /// exists the step is skipped — callers only use this when the row count is stable.
    private func registerRowSnapshot(_ actionName: String, rowId: UUID, baseRow: ScreenshotRow, baseLocaleState: LocaleState) {
        guard let undoManager else { return }
        registeringUndoStep(on: undoManager) {
            undoManager.registerUndo(withTarget: self) { target in
                guard let idx = target.rows.firstIndex(where: { $0.id == rowId }) else { return }
                let redoRow = target.rows[idx]
                let redoLocaleState = target.localeState
                target.rows[idx] = baseRow
                target.localeState = baseLocaleState
                target.templateMoveContinuation = nil
                target.normalizeSelection()
                target.scheduleSave()
                target.registerRowSnapshot(actionName, rowId: rowId, baseRow: redoRow, baseLocaleState: redoLocaleState)
                target.undoManager?.setActionName(actionName)
            }
            undoManager.setActionName(actionName)
        }
    }

    var canUndoDocumentAction: Bool {
        edits.hasPendingEdit || (undoManager?.canUndo ?? false)
    }

    // A pending edit (continuous burst or debounced nudge/text) is the user's most recent
    // change: committing it (the flush inside redo/undoDocumentAction) registers a fresh undo
    // step, which clears the redo stack. So redo is unavailable while one is pending — the
    // inverse of canUndoDocumentAction.
    var canRedoDocumentAction: Bool {
        !edits.hasPendingEdit && (undoManager?.canRedo ?? false)
    }

    func undoDocumentAction() {
        commitAllPendingEdits()
        CrashReportingService.breadcrumb(.edit, "Undo", data: ["action": undoManager?.undoActionName ?? ""])
        undoManager?.undo()
    }

    func redoDocumentAction() {
        commitAllPendingEdits()
        guard undoManager?.canRedo == true else { return }
        CrashReportingService.breadcrumb(.edit, "Redo", data: ["action": undoManager?.redoActionName ?? ""])
        undoManager?.redo()
    }

    /// Commits every pending continuous/debounced edit, registering each as its own undo
    /// step. Called at undo-stack boundaries (discrete `withUndo` actions, undo, redo) and
    /// when a different debounced interaction begins, so steps register in chronological
    /// order. Each coalescer's `finish()` is a no-op when its own path has nothing captured.
    func commitAllPendingEdits() {
        // Inline text first: the still-mounted editor must leave local edit mode before the
        // coalesced edits commit, or it can recommit its draft after a locale switch.
        textEdit.flushActiveEditor()
        edits.commitAll()
    }

    // MARK: - Helpers

    func shapeLocation(for shapeId: UUID) -> (rowIndex: Int, shapeIndex: Int)? {
        for rowIndex in rows.indices {
            if let shapeIndex = rows[rowIndex].shapes.firstIndex(where: { $0.id == shapeId }) {
                return (rowIndex, shapeIndex)
            }
        }
        return nil
    }

    func allTextShapes() -> [CanvasShapeModel] {
        rows.flatMap { row in
            row.shapes.filter { $0.type == .text }
        }
    }

    /// Drops every debounced edit without registering an undo step (project switch / reset).
    func cancelPendingDebounceTasks() {
        textEdit.clearInlineTextCommit()
        edits.cancelAll()
        // The zoom throttle used to live in `edits` and be reset by cancelAll(). Drop, don't
        // flush: the pending value belongs to a document that is going away.
        zoom.cancelContinuous()
    }
}
