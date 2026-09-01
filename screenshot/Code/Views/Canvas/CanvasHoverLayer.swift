import SwiftUI

/// The hover outline for the shape under the pointer.
///
/// Mounted once per row, like `CanvasSelectionLayer`, and the only view that reads
/// `dragSession.hoveredShapeId` — so moving the pointer re-renders this overlay rather than every
/// shape in the row. It replaces an `.onContinuousHover` on each `CanvasShapeView`, which gave
/// every shape a responder node for `NSHostingView.didRequestHoverUpdate()` to re-walk on every
/// display cycle: 14% of a scrollbar-drag trace.
struct CanvasHoverLayer: View {
    @Environment(\.displayScale) private var screenScale

    let resolvedShapes: [CanvasShapeModel]
    let selectedShapeIds: Set<UUID>
    /// Model points × (base displayScale × zoom), matching `CanvasSelectionLayer`.
    let visualScale: CGFloat
    /// Read inside `body` on purpose — see `hoveredShapeId`.
    let dragSession: CanvasDragSession
    let liveShapeEdit: LiveShapeEditSession

    var body: some View {
        // Selection chrome wins: a selected shape already has an outline, and a drag replaces the
        // hover affordance with the closed-hand cursor.
        if let hoveredId = dragSession.hoveredShapeId,
           dragSession.draggingShapeId == nil,
           !selectedShapeIds.contains(hoveredId),
           let base = resolvedShapes.first(where: { $0.id == hoveredId }) {
            let shape = liveShapeEdit.liveShape(for: base.id) ?? base
            let displayRect = CanvasShapeDisplayGeometry.snappedRect(
                x: shape.x,
                y: shape.y,
                width: shape.width,
                height: shape.height,
                displayScale: visualScale,
                screenScale: screenScale
            )
            Rectangle()
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                .modifier(ShapeChromeFrame(displayRect: displayRect, rotation: shape.rotation))
        }
    }
}
