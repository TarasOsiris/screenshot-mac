import CoreGraphics
import Foundation
@testable import Screenshot_Bro
import Testing

/// Pure-value suite — no `makeTestState`, so no shared data directory and no `.serialized`.
@MainActor
struct LiveShapeGeometrySessionTests {

    @Test func frameIsScopedToTheDraggedShape() {
        let session = LiveShapeGeometrySession()
        let shape = CanvasShapeModel(type: .rectangle, x: 10, y: 20, width: 30, height: 40)
        let other = CanvasShapeModel(type: .circle, x: 0, y: 0, width: 10, height: 10)

        #expect(session.frame(for: shape.id) == nil, "Nothing is being dragged")

        session.update(.init(shape, offsetBy: CGSize(width: 5, height: -5)), for: shape.id)
        #expect(session.frame(for: shape.id) == .init(x: 15, y: 15, width: 30, height: 40, rotation: 0))
        #expect(session.frame(for: other.id) == nil, "Another shape must not see the gesture")
        #expect(session.applied(to: other) == nil)

        session.end()
        #expect(session.frame(for: shape.id) == nil)
        #expect(session.shapeId == nil)
    }

    /// The gate every reader of `editingShape` observes. `@Observable` notifies on same-value
    /// writes, so a tick must not touch it at all — otherwise the per-tick frame invalidates the
    /// controls of shapes that aren't being dragged.
    @Test func ticksWithinOneGestureDoNotTouchTheGate() {
        let session = LiveShapeGeometrySession()
        let shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 10, height: 10)
        session.update(.init(shape), for: shape.id)

        let notified = observationDidNotify({ session.shapeId }) {
            session.update(.init(shape, offsetBy: CGSize(width: 1, height: 0)), for: shape.id)
            session.update(.init(shape, offsetBy: CGSize(width: 2, height: 0)), for: shape.id)
        }

        #expect(!notified, "Ticks within one gesture keep the same target")
        #expect(session.frame(for: shape.id)?.x == 2)
    }

    /// A resize publishes absolute values and must leave everything that isn't geometry alone —
    /// the shape it is applied to may itself be mid-slider-burst.
    @Test func appliedOverwritesGeometryOnly() {
        let session = LiveShapeGeometrySession()
        var shape = CanvasShapeModel(type: .text, x: 10, y: 10, width: 100, height: 50)
        shape.opacity = 0.5
        shape.text = "Hello"

        session.update(.init(x: 0, y: 5, width: 200, height: 80, rotation: 45), for: shape.id)
        let applied = session.applied(to: shape)

        #expect(applied?.x == 0)
        #expect(applied?.y == 5)
        #expect(applied?.width == 200)
        #expect(applied?.height == 80)
        #expect(applied?.rotation == 45)
        #expect(applied?.opacity == 0.5)
        #expect(applied?.text == "Hello")
    }

    /// A rotate handle composes its angle from a delta; the readout must show it in the same
    /// 0..<360 form the commit stores, or the number jumps on release.
    @Test func rotationIsPublishedNormalized() {
        #expect(CanvasShapeModel.normalizedRotation(-15) == 345)
        #expect(CanvasShapeModel.normalizedRotation(370) == 10)
        #expect(CanvasShapeModel.normalizedRotation(0) == 0)

        let session = LiveShapeGeometrySession()
        let shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 10, height: 10)
        session.update(LiveShapeGeometrySession.Frame(shape).rotated(by: -30), for: shape.id)
        #expect(session.frame(for: shape.id)?.rotation == 330)
    }

    /// A gesture is published at the precision the fields render, so a sub-unit tick of an
    /// unthrottled drag must not repaint them — same-value writes notify too.
    @Test func subUnitTicksRoundToTheSameFrame() {
        let session = LiveShapeGeometrySession()
        let shape = CanvasShapeModel(type: .rectangle, x: 10, y: 10, width: 10, height: 10)
        session.update(.init(shape, offsetBy: CGSize(width: 0.2, height: 0.1)), for: shape.id)

        let notified = observationDidNotify({ session.frame(for: shape.id) }) {
            session.update(.init(shape, offsetBy: CGSize(width: 0.3, height: 0.2)), for: shape.id)
        }

        #expect(!notified)
        #expect(session.frame(for: shape.id)?.x == 10)
    }

    /// One row tearing down must not blank a gesture running in another.
    @Test func endForAnotherShapeLeavesTheGestureAlone() {
        let session = LiveShapeGeometrySession()
        let shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 10, height: 10)

        session.update(.init(shape, offsetBy: CGSize(width: 7, height: 0)), for: shape.id)
        session.end(for: UUID())
        #expect(session.frame(for: shape.id)?.x == 7)

        session.end(for: shape.id)
        #expect(session.shapeId == nil)
        session.end()
        #expect(session.shapeId == nil, "end() is idempotent")
    }
}
