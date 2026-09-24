import Foundation
import Observation

/// Which rows are showing a static preview, and (on iPad) whether the whole editor is in
/// pan-and-zoom-only view mode. Both are session-only — never persisted, never snapshotted for
/// undo — but entering either has to tear down editing chrome, so this needs the inline text
/// session and a way to clear the selection.
///
/// `textEdit` is a real dependency and arrives at init. `deselectAll` can't — it calls back into
/// `AppState`, which can't reference itself while its own stored properties are still being
/// initialized — so it stays a closure, assigned immediately after construction.
@Observable
@MainActor
final class EditorViewModeController {
    /// Read by every visible row's body, so it stays plainly observed.
    private(set) var previewingRows: Set<UUID> = []

    /// iOS-only editor view mode: shapes are inert, only panning + pinch-zoom work.
    /// Always false on macOS.
    private(set) var isViewMode = false

    @ObservationIgnored private let textEdit: InlineTextEditSession
    /// Clears the shape selection. No-op until wired.
    @ObservationIgnored var deselectAll: () -> Void = {}

    init(textEdit: InlineTextEditSession) {
        self.textEdit = textEdit
    }

    /// Flip the row's preview-mode state. Also drops the active text edit when entering preview
    /// so a stale editor focus doesn't survive into the non-interactive preview.
    func togglePreview(for rowId: UUID) {
        if previewingRows.contains(rowId) {
            previewingRows.remove(rowId)
        } else {
            previewingRows.insert(rowId)
            textEdit.isActive = false
        }
    }

    /// Exit preview mode for a row. Idempotent.
    func exitPreview(for rowId: UUID) {
        previewingRows.remove(rowId)
    }

    /// Drop any preview-mode entries that don't refer to a row in `validIds`.
    /// Called when rows are replaced wholesale (project switch, iCloud reload).
    func reconcilePreviewingRows(against validIds: Set<UUID>) {
        previewingRows = previewingRows.intersection(validIds)
    }

    /// Toggle the editor view mode. Entering it clears any active text edit and selection so no
    /// editing chrome lingers over the non-interactive canvas.
    func setViewMode(_ on: Bool) {
        guard isViewMode != on else { return }
        isViewMode = on
        if on {
            textEdit.isActive = false
            deselectAll()
        }
    }
}
