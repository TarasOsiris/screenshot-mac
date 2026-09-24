#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Observation

/// The canvas's in-progress inline text edit: whether one is active, the rich-text formatting
/// state that goes with it, and the registered handlers that commit or end it.
///
/// Pure view state — nothing here is persisted or snapshotted for undo — but it is coupled to the
/// undo machinery through `flushActiveEditor()`, which `AppState.commitAllPendingEdits()` must
/// call before committing coalesced edits.
@Observable
@MainActor
final class InlineTextEditSession {
    var isActive = false {
        didSet {
            if !isActive {
                richTextSelectionState = nil
                richTextFormatBarAnchor = nil
                richTextFormatController = nil
                // The inline commit registration is cleared by the editing view's keyed
                // teardown (onInlineTextEditChanged(nil)); clearing it unkeyed here would
                // wipe a newer editor's registration during an editor-to-editor handoff.
            }
        }
    }

    var richTextSelectionState: RichTextSelectionState?
    var richTextFormatBarAnchor: CGPoint?
    @ObservationIgnored var richTextFormatController: RichTextFormatController?

    /// Commits the editing `CanvasShapeView`'s in-progress inline text under the *current*
    /// locale; registered while editing, flushed before locale switches.
    @ObservationIgnored private(set) var commitActiveInlineTextEdit: (() -> Void)?
    @ObservationIgnored private(set) var endActiveInlineTextEdit: (() -> Void)?
    @ObservationIgnored private var inlineTextEditShapeId: UUID?

    /// Register the active inline text editor's commit closure, keyed by shape so a stale
    /// teardown from a previously-editing shape can't clear a newer editor's registration.
    func registerInlineTextCommit(for shapeId: UUID, endEditing: (() -> Void)? = nil, _ commit: @escaping () -> Void) {
        inlineTextEditShapeId = shapeId
        commitActiveInlineTextEdit = commit
        endActiveInlineTextEdit = endEditing
    }

    /// Clear the registered inline commit. With a `shapeId`, only clears if it still owns the
    /// registration (ignores a late clear from a shape that's already been superseded).
    func clearInlineTextCommit(for shapeId: UUID? = nil) {
        if let shapeId, inlineTextEditShapeId != shapeId { return }
        inlineTextEditShapeId = nil
        commitActiveInlineTextEdit = nil
        endActiveInlineTextEdit = nil
    }

    /// Flush the canvas's in-progress inline text edit, then tell the still-mounted editor to
    /// leave local edit mode so it can't recommit that draft after a locale switch.
    ///
    /// The clear happens *before* the handlers are invoked, and that ordering is the whole point:
    /// `commitInlineText` runs its own `withUndo`, which re-enters `commitAllPendingEdits`, which
    /// would otherwise invoke these handlers a second time. Encoding it here means the call site
    /// can no longer get it wrong.
    func flushActiveEditor() {
        let commit = commitActiveInlineTextEdit
        let end = endActiveInlineTextEdit
        clearInlineTextCommit()
        commit?()
        end?()
    }
}
