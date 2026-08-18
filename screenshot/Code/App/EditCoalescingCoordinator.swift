import Foundation

/// Owns every debounced/throttled editing burst in the document.
///
/// These eleven properties were stored on `AppState` because Swift can't put stored properties in
/// an extension, not because they were document state — nothing outside the undo path reads them,
/// and none of them is observed. Gathering them here gives the invariant a place to live: **at most
/// one coalescer is ever active**, because beginning any burst first commits all the others, which
/// is what keeps undo steps registering in chronological order.
///
/// `DebouncedUndoCoalescer` owns one burst; `ContinuousApplyThrottle` owns how often the model is
/// written mid-burst. This is the registry that holds them.
@MainActor
final class EditCoalescingCoordinator {
    let shapeEdit = DebouncedUndoCoalescer(debounceDelay: AppState.continuousUndoDebounceDelay)
    let rowEdit = DebouncedUndoCoalescer(debounceDelay: AppState.continuousUndoDebounceDelay)
    let nudge = DebouncedUndoCoalescer(debounceDelay: AppState.nudgeUndoDebounceDelay)
    let baseText = DebouncedUndoCoalescer(debounceDelay: AppState.textEditUndoDebounceDelay)
    let translation = DebouncedUndoCoalescer(debounceDelay: AppState.textEditUndoDebounceDelay)

    var all: [DebouncedUndoCoalescer] { [shapeEdit, rowEdit, nudge, baseText, translation] }

    // ~30fps apply throttles for the continuous (slider/drag/pinch) paths: the coalescers above own
    // the single debounced undo step; these own how often the model is actually written mid-burst.
    let shapeEditThrottle = ContinuousApplyThrottle(interval: AppState.continuousEditInterval)
    let rowEditThrottle = ContinuousApplyThrottle(interval: AppState.continuousEditInterval)

    /// Undo action names for the in-flight burst, set when it begins.
    var nudgeActionName: String = "Move Shape"
    var continuousRowEditActionName: String = "Edit Background"
    /// The row being composed by an in-flight continuous row edit — read by the inspector and
    /// template control bar so the UI reflects the drag before the throttled write reaches `rows`.
    var continuousRowEditWorkingRow: ScreenshotRow?

    /// Set while a `withUndo`/`withRowUndo` body is running, so a nested call joins the outer
    /// transaction instead of registering a second step.
    var isInUndoTransaction = false

    /// True while any burst is captured but not yet registered as an undo step.
    var hasPendingEdit: Bool { all.contains { $0.isActive } }

    /// Registers every pending burst as its own undo step. A coalescer with nothing captured
    /// no-ops, so this is safe to call at any undo-stack boundary.
    func commitAll() {
        for coalescer in all { coalescer.finish() }
    }

    /// Drops every pending burst without registering an undo step (project switch / reset).
    func cancelAll() {
        for coalescer in all { coalescer.cancel() }
        shapeEditThrottle.reset()
        rowEditThrottle.reset()
        continuousRowEditWorkingRow = nil
    }
}
