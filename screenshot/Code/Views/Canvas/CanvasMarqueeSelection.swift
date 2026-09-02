import SwiftUI

/// Draws the rubber band itself. The outlines of what it has swept up belong to
/// `CanvasSelectionLayer`, the single owner of selection chrome — so this reads only
/// `marqueeRect` and a per-tick band move re-renders one rectangle, nothing else.
struct CanvasMarqueeLayer: View {
    let dragSession: CanvasDragSession
    /// Model points × (base displayScale × zoom) — same value the shape layer draws at.
    let displayScale: CGFloat

    var body: some View {
        if let rect = dragSession.marqueeRect {
            Rectangle()
                .fill(Color.accentColor.opacity(UIMetrics.Opacity.accentBadge))
                .overlay {
                    Rectangle()
                        .strokeBorder(
                            Color.accentColor.opacity(UIMetrics.Opacity.accentEmphasis),
                            lineWidth: UIMetrics.BorderWidth.standard
                        )
                }
                .frame(
                    width: max(rect.width * displayScale, UIMetrics.BorderWidth.standard),
                    height: max(rect.height * displayScale, UIMetrics.BorderWidth.standard)
                )
                .position(x: rect.midX * displayScale, y: rect.midY * displayScale)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Owns both empty-canvas interactions on the canvas container: Sketch-style drag-to-select,
    /// and the plain click that selects the row. On macOS they share one `DragGesture` rather than
    /// sitting in separate modifiers because two gestures on the same view are resolved by
    /// SwiftUI's arbitration, and the tap won — the marquee never started. One gesture that
    /// classifies its own tap-vs-drag is deterministic. Plain `.gesture` (not
    /// `.highPriorityGesture`) keeps child priority intact, so a drag starting on a shape still
    /// moves that shape.
    ///
    /// iPad gets the click only: there a one-finger canvas drag pans the row.
    ///
    /// `onSelect` receives the pre-drag selection when the band starts (empty unless shift is
    /// held) and the swept set on release — the sweep's only two writes.
    func canvasBackgroundGesture(
        row: ScreenshotRow,
        shapes: [CanvasShapeModel],
        displayScale: CGFloat,
        dragSession: CanvasDragSession,
        liveShapeEdit: LiveShapeEditSession,
        existingSelection: Set<UUID>,
        isEnabled: Bool,
        onSelect: @escaping (Set<UUID>) -> Void,
        onTapEmptyCanvas: @escaping () -> Void
    ) -> some View {
        #if os(macOS)
        modifier(
            CanvasMarqueeSelectionModifier(
                row: row,
                shapes: shapes,
                displayScale: displayScale,
                dragSession: dragSession,
                liveShapeEdit: liveShapeEdit,
                existingSelection: existingSelection,
                isEnabled: isEnabled,
                onSelect: onSelect,
                onTapEmptyCanvas: onTapEmptyCanvas
            )
        )
        #else
        onTapGesture {
            guard isEnabled else { return }
            onTapEmptyCanvas()
        }
        #endif
    }
}

#if os(macOS)
private struct CanvasMarqueeSelectionModifier: ViewModifier {
    let row: ScreenshotRow
    let shapes: [CanvasShapeModel]
    let displayScale: CGFloat
    let dragSession: CanvasDragSession
    /// Only ever read from the gesture handlers, never from `body`: a properties-bar drag writes
    /// here ~30 times a second, and keeping the row out of that is the whole point of the session.
    let liveShapeEdit: LiveShapeEditSession
    /// Row-scoped selection as of the last body evaluation. Only read when the sweep begins, so
    /// it is the pre-drag selection that a shift-drag adds to.
    let existingSelection: Set<UUID>
    let isEnabled: Bool
    let onSelect: (Set<UUID>) -> Void
    let onTapEmptyCanvas: () -> Void

    /// Slop before a press counts as a sweep rather than a click. Applied by hand instead of via
    /// `DragGesture(minimumDistance:)` so this one gesture can also report the click.
    private static let dragSlop: CGFloat = 3

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(handleChanged)
                .onEnded(handleEnded)
        )
    }

    private static func exceededSlop(_ translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= dragSlop
    }

    private func handleEnded(_ value: DragGesture.Value) {
        let base = dragSession.marqueeBase
        defer { dragSession.endMarquee() }

        if dragSession.marqueeRect != nil {
            // The sweep's commit. Ordered before `endMarquee` so the outlines the band was
            // drawing are never cleared before the real selection replaces them.
            onSelect(dragSession.marqueeSelection)
            return
        }
        // A press that landed on a shape belongs to that shape; reporting it as an empty-canvas
        // click would deselect the very shape the user just clicked.
        let startedOnShape = base?.startedOnShape
            ?? containsShape(at: modelPoint(value.startLocation))
        guard isEnabled, !startedOnShape, !Self.exceededSlop(value.translation) else { return }
        onTapEmptyCanvas()
    }

    private func handleChanged(_ value: DragGesture.Value) {
        guard isEnabled else { return }
        // Captured on the very first tick — before the slop test — so the shift state and the
        // start point are the ones in effect at mouse-down, as the Help text promises.
        let base = dragSession.marqueeBase ?? captureBase(startLocation: value.startLocation)
        guard !base.startedOnShape else { return }

        let alreadySweeping = dragSession.marqueeRect != nil
        guard alreadySweeping || Self.exceededSlop(value.translation) else { return }
        if !alreadySweeping {
            // Drop the previous selection the moment the band starts, the way Sketch does. A
            // no-op for a shift-drag, whose base *is* the current selection.
            onSelect(base.baseSelection)
        }

        let current = modelPoint(value.location)
        let rect = CGRect(
            x: min(base.origin.x, current.x),
            y: min(base.origin.y, current.y),
            width: abs(current.x - base.origin.x),
            height: abs(current.y - base.origin.y)
        )
        // Same-value writes still notify observers, and `modelPoint` clamps to the canvas — so
        // dragging on past an edge would otherwise re-render on every tick for an identical band.
        if dragSession.marqueeRect != rect {
            dragSession.marqueeRect = rect
        }
        let swept = row.shapeIds(intersecting: rect, among: shapes).union(base.baseSelection)
        if dragSession.marqueeSelection != swept {
            dragSession.marqueeSelection = swept
        }
    }

    private func captureBase(startLocation: CGPoint) -> CanvasDragSession.MarqueeBase {
        let origin = modelPoint(startLocation)
        let base = CanvasDragSession.MarqueeBase(
            origin: origin,
            // The same live-flags query `handleTap` uses for shift-click. Read once, so a shift
            // pressed mid-drag can't flip an in-progress sweep from replacing to adding.
            baseSelection: PlatformModifiers.shiftDown ? existingSelection : [],
            startedOnShape: containsShape(at: origin)
        )
        dragSession.marqueeBase = base
        return base
    }

    /// The refuse-on-shape test, against the geometry the canvas is *showing*: a properties-bar
    /// drag holds the shape's new size and rotation in the live session until the burst settles, so
    /// testing the document's copy would let a press inside the visible shape rubber-band over it.
    private func containsShape(at point: CGPoint) -> Bool {
        let transientShape = liveShapeEdit.shapeId.flatMap { liveShapeEdit.liveShape(for: $0) }
        return row.containsShape(at: point, among: shapes, replacingWith: transientShape)
    }

    /// Display point → model point, clamped to the canvas so a drag past its edge still
    /// produces a band that lines up with what the user sees.
    private func modelPoint(_ point: CGPoint) -> CGPoint {
        let scale = max(displayScale, 0.0001)
        return CGPoint(
            x: min(max(point.x / scale, 0), row.templateWidth * CGFloat(row.templates.count)),
            y: min(max(point.y / scale, 0), row.templateHeight)
        )
    }
}
#endif
