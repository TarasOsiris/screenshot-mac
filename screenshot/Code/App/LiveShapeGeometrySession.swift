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
/// `frame` is private behind the same gate as `LiveShapeEditSession.shape`, so a shape that isn't
/// under the pointer subscribes to the two `shapeId` transitions and not to the ticks between.
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

        /// A shape's own frame, optionally moved. `ResizeState` lives in the canvas layer, so a
        /// resize builds the frame from its own absolute values instead.
        init(_ shape: CanvasShapeModel, offsetBy offset: CGSize = .zero) {
            self.init(
                x: shape.x + offset.width,
                y: shape.y + offset.height,
                width: shape.width,
                height: shape.height,
                rotation: shape.rotation
            )
        }

        /// A rotate handle composes its angle from a delta against the pre-gesture rotation.
        func rotated(by delta: Double) -> Frame {
            Frame(x: x, y: y, width: width, height: height, rotation: rotation + delta)
        }
    }

    private(set) var shapeId: UUID?
    private var frame: Frame?

    // `@Observable` notifies on same-value writes, so both assign only on change — `shapeId` is
    // what every other shape's readouts observe, and a 120 Hz drag rounds to a repeated frame often.
    func update(_ frame: Frame, for id: UUID) {
        if shapeId != id { shapeId = id }
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

    func frame(for id: UUID) -> Frame? {
        guard shapeId == id else { return nil }
        return frame
    }

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
