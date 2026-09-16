import CoreGraphics
import Foundation

/// The frame a canvas gesture is composing for one shape, before it reaches `rows`.
///
/// `LiveShapeEditSession` carries a properties-bar burst *to* the canvas; this carries a canvas
/// drag/resize/rotate *to* the properties bar and the selection inspector, so their X/Y/W/H and
/// rotation readouts follow the pointer instead of freezing until mouse-up. The document is still
/// written once, on gesture end.
///
/// The channel is one-directional by design: the canvas renders from `CanvasDragSession` and
/// already applies this transform itself, so a canvas layer reading here would apply it twice.
///
/// `frame` is private behind the same gate as `LiveShapeEditSession.shape`: the accessors check
/// `shapeId` first, so a shape that isn't under the pointer never subscribes to the per-tick value
/// — it sees only the two `shapeId` transitions that bracket the gesture.
@Observable @MainActor
final class LiveShapeGeometrySession {
    struct Frame: Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var height: CGFloat
        var rotation: Double

        /// Rounded to what the readouts actually render — whole model units and 0.1° — so a
        /// sub-unit tick of an unthrottled gesture costs no repaint.
        init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, rotation: Double) {
            self.x = x.rounded()
            self.y = y.rounded()
            self.width = width.rounded()
            self.height = height.rounded()
            self.rotation = CanvasShapeModel.normalizedRotation((rotation * 10).rounded() / 10)
        }

        /// A moved or rotated shape. `ResizeState` lives in the canvas layer, so a resize builds
        /// the frame from its own absolute values instead.
        init(_ shape: CanvasShapeModel, offsetBy offset: CGSize = .zero, rotation: Double? = nil) {
            self.init(
                x: shape.x + offset.width,
                y: shape.y + offset.height,
                width: shape.width,
                height: shape.height,
                rotation: rotation ?? shape.rotation
            )
        }
    }

    private(set) var shapeId: UUID?
    private var frame: Frame?

    func update(_ frame: Frame, for id: UUID) {
        // Assigned only on a real change: `shapeId` is what every other reader observes, so an
        // unconditional write would invalidate them all on every tick.
        if shapeId != id { shapeId = id }
        // Same-value writes still notify observers, and a 120 Hz drag rounds to the same frame
        // often enough for the guard to earn its keep.
        if self.frame != frame { self.frame = frame }
    }

    /// Clears only when `id` is what's published, so tearing down one row can't blank the
    /// gesture running in another.
    func end(for id: UUID) {
        guard shapeId == id else { return }
        end()
    }

    func end() {
        guard shapeId != nil else { return }
        shapeId = nil
        frame = nil
    }

    /// The in-flight frame for `id`, or nil when some other shape (or nothing) is being dragged.
    func frame(for id: UUID) -> Frame? {
        guard shapeId == id else { return nil }
        return frame
    }

    /// `shape` with the in-flight geometry applied, or nil when it isn't the shape being dragged.
    func applied(to shape: CanvasShapeModel) -> CanvasShapeModel? {
        guard let frame = frame(for: shape.id) else { return nil }
        var updated = shape
        updated.x = frame.x
        updated.y = frame.y
        updated.width = frame.width
        updated.height = frame.height
        updated.rotation = frame.rotation
        return updated
    }
}
