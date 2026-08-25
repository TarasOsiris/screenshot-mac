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
    /// In-progress marquee band in model space. Read only by `CanvasMarqueeLayer`.
    var marqueeRect: CGRect?
    /// What the in-flight band has swept up, already unioned with the pre-drag selection. Lives
    /// here rather than on `AppState` so a sweep doesn't re-run the row body, the properties bar
    /// and the whole macOS main menu on every shape it crosses; committed once on release.
    var marqueeSelection: Set<UUID> = []
    /// Snap targets cached across one drag; not observable view input.
    @ObservationIgnored var cachedSnapTargets: [AlignmentService.OtherShapeBounds]?
    /// Captured on the marquee's first tick; not observable view input.
    @ObservationIgnored var marqueeBase: MarqueeBase?

    /// The parts of a marquee drag that are fixed at mouse-down: where it started, what the
    /// selection was (so a shift-drag can union against it on every tick), and whether the press
    /// landed on a shape — in which case the gesture belongs to that shape and never sweeps.
    struct MarqueeBase {
        let origin: CGPoint
        let baseSelection: Set<UUID>
        let startedOnShape: Bool
    }

    func reset() {
        endDrag()
        endMarquee()
        pendingResize = [:]
        pendingRotation = [:]
    }

    func endMarquee() {
        if marqueeRect != nil { marqueeRect = nil }
        if !marqueeSelection.isEmpty { marqueeSelection = [] }
        marqueeBase = nil
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
