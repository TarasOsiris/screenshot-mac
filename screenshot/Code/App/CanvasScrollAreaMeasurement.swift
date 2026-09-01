import Foundation

/// Which rows have already had their horizontal scroll area re-keyed once (see `EditorRowView`).
///
/// The re-key exists because a `LazyVStack`'s first lazy layout pass can hand a row an unbounded
/// width, leaving the inner horizontal `ScrollView` sized to its content and unscrollable. Holding
/// that "already measured" flag in the row's own `@State` meant it reset every time the LazyVStack
/// recycled the row off-screen, so every scroll-in rebuilt the whole canvas subtree twice. This
/// registry outlives the row views, so the relayout happens once per row per session.
///
/// Deliberately **not** `@Observable`: rows read it during `body`, and an observed read would put
/// every row back in one invalidation scope — the opposite of what this is for. Same shape as
/// `ClipPathMemo` in `CanvasShapeView`.
@MainActor
final class CanvasScrollAreaMeasurement {
    private var measuredRowIds: Set<UUID> = []
    private var projectId: UUID?

    func isMeasured(_ rowId: UUID) -> Bool {
        measuredRowIds.contains(rowId)
    }

    func markMeasured(_ rowId: UUID) {
        measuredRowIds.insert(rowId)
    }

    /// Clears the set when a *different* project is applied. Gated on the id because the same
    /// project is re-applied on every iCloud reload, where the row views are still alive and their
    /// widths already settled — forgetting them there would buy back the double build for free.
    /// Returns whether it actually reset, so callers can drop their own per-project caches in step.
    @discardableResult
    func reset(for projectId: UUID) -> Bool {
        guard self.projectId != projectId else { return false }
        self.projectId = projectId
        measuredRowIds.removeAll()
        return true
    }
}
