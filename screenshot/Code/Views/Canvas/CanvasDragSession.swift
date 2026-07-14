import SwiftUI

/// Transient drag/resize/rotate state for one row's canvas. Lives outside
/// `EditorRowView`'s `@State` so per-tick gesture updates invalidate only the
/// views that actually read these properties (the dragged shape, its
/// followers, and the selection overlay) — never the whole row body.
@Observable @MainActor
final class CanvasDragSession {
    var activeDragOffset: CGSize = .zero
    var draggingShapeId: UUID?
    var pendingResize: [UUID: ResizeState] = [:]
    var pendingRotation: [UUID: Double] = [:]
    var activeGuides: [AlignmentGuide] = []
    /// Snap targets cached across one drag; not observable view input.
    @ObservationIgnored var cachedSnapTargets: [AlignmentService.OtherShapeBounds]?

    func reset() {
        endDrag()
        pendingResize = [:]
        pendingRotation = [:]
    }

    func endDrag() {
        activeDragOffset = .zero
        draggingShapeId = nil
        activeGuides = []
        cachedSnapTargets = nil
    }
}

/// Isolates the alignment-guide reads so guide changes during a drag
/// re-render only this layer, not the canvas that contains it.
struct ActiveGuidesLayer: View {
    let dragSession: CanvasDragSession
    let displayScale: CGFloat

    var body: some View {
        ForEach(dragSession.activeGuides) { guide in
            AlignmentGuideLineView(guide: guide, displayScale: displayScale)
        }
    }
}
