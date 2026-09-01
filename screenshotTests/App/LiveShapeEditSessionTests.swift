import CoreGraphics
import Observation
@testable import Screenshot_Bro
import Testing

@Suite(.serialized)
@MainActor
struct LiveShapeEditSessionTests {

    @Test func liveShapeIsScopedToTheEditedShape() {
        let session = LiveShapeEditSession()
        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 10, height: 10)
        let other = CanvasShapeModel(type: .circle, x: 0, y: 0, width: 10, height: 10)

        #expect(session.liveShape(for: shape.id) == nil, "Nothing is being edited")

        shape.rotation = 45
        session.update(shape)
        #expect(session.liveShape(for: shape.id)?.rotation == 45)
        #expect(session.liveShape(for: other.id) == nil, "Another shape must not see the burst")

        session.end()
        #expect(session.liveShape(for: shape.id) == nil)
        #expect(session.shapeId == nil)
    }

    /// The gate every other shape's canvas view reads. It must move only at the edges of a burst,
    /// or the per-tick value invalidates shapes that aren't being edited.
    @Test func shapeIdChangesOnlyWhenTheTargetChanges() {
        let session = LiveShapeEditSession()
        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 10, height: 10)

        session.update(shape)
        let afterFirstTick = session.shapeId
        shape.rotation = 10
        session.update(shape)
        shape.rotation = 20
        session.update(shape)

        #expect(session.shapeId == afterFirstTick, "Ticks within one burst keep the same target")
        #expect(session.liveShape(for: shape.id)?.rotation == 20)
    }

    @Test func endIsIdempotent() {
        let session = LiveShapeEditSession()
        session.end()
        session.end()
        #expect(session.shapeId == nil)
        #expect(session.shape == nil)
    }
}

@Suite(.serialized)
@MainActor
struct ContinuousShapeEditCommitTests {

    /// The contract the editor's frame rate depends on: a burst must not touch `rows`, because a
    /// write there re-runs the row builder, the whole edited row and the properties bar.
    @Test func burstComposesOffDocumentAndCommitsOnce() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        shape.rotation = 0
        state.addShape(shape)
        let baseRotation = state.rows.first!.shapes.first { $0.id == shape.id }!.rotation

        shape.rotation = 15
        state.updateShapeContinuous(shape)
        shape.rotation = 30
        state.updateShapeContinuous(shape)

        #expect(
            state.rows.first!.shapes.first { $0.id == shape.id }!.rotation == baseRotation,
            "An in-flight burst must leave the document alone"
        )
        // The ~30fps throttle applies the first tick straight away and defers the second, so the
        // session holds 15 here; `finish` flushes the pending one before it commits.
        #expect(state.liveShapeEdit.liveShape(for: shape.id)?.rotation == 15)
        #expect(state.edits.shapeEditThrottle.hasPending)

        state.finishContinuousEditIfNeeded()
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.rotation == 30)
        #expect(state.liveShapeEdit.liveShape(for: shape.id) == nil, "The session clears on commit")
    }

    /// One visit to the 3D popover moves pitch and then yaw inside a single burst. Each tick is
    /// built from the previous one, so the first field must survive the second.
    @Test func laterTicksBuildOnEarlierOnesInTheSameBurst() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel(type: .device, x: 0, y: 0, width: 100, height: 200)
        state.addShape(shape)

        shape.devicePitch = -22
        state.updateShapeContinuous(shape)

        var next = state.liveShapeEdit.liveShape(for: shape.id)!
        next.deviceYaw = -14
        state.updateShapeContinuous(next)

        state.finishContinuousEditIfNeeded()
        let committed = state.rows.first!.shapes.first { $0.id == shape.id }!
        #expect(committed.devicePitch == -22)
        #expect(committed.deviceYaw == -14)
    }

    @Test func switchingShapesMidBurstCommitsTheFirst() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        state.selectRow(state.rows.first!.id)

        var first = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        var second = CanvasShapeModel(type: .circle, x: 100, y: 0, width: 50, height: 50)
        state.addShape(first)
        state.addShape(second)

        first.rotation = 40
        state.updateShapeContinuous(first)
        second.rotation = 70
        state.updateShapeContinuous(second)

        #expect(
            state.rows.first!.shapes.first { $0.id == first.id }!.rotation == 40,
            "Starting a second burst commits the first"
        )
        #expect(state.liveShapeEdit.liveShape(for: first.id) == nil)
        #expect(state.liveShapeEdit.liveShape(for: second.id)?.rotation == 70)
    }

    /// The invariant the whole change rests on. `rows` is one observed property, so a write to it
    /// invalidates `ContentView`'s row builder, the edited row's entire subtree and the properties
    /// bar. A drag tick must not notify anything tracking it; the settle must.
    @Test func aBurstTickDoesNotNotifyRowObservers() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        state.addShape(shape)

        let notified = RowObservationFlag()
        withObservationTracking { _ = state.rows } onChange: { notified.fire() }

        shape.rotation = 25
        state.updateShapeContinuous(shape)
        #expect(!notified.didFire, "A slider tick must not invalidate every reader of `rows`")

        let onCommit = RowObservationFlag()
        withObservationTracking { _ = state.rows } onChange: { onCommit.fire() }
        state.finishContinuousEditIfNeeded()
        #expect(onCommit.didFire, "The settled burst does reach the document")
    }

    /// Project switch and reset drop the burst rather than committing it — the document it belongs
    /// to is going away.
    @Test func cancellingPendingEditsDropsTheSession() {
        let (state, tempDir) = makeTestState()
        defer { cleanupTestState(tempDir) }
        state.selectRow(state.rows.first!.id)

        var shape = CanvasShapeModel(type: .rectangle, x: 0, y: 0, width: 50, height: 50)
        state.addShape(shape)
        let baseRotation = state.rows.first!.shapes.first { $0.id == shape.id }!.rotation

        shape.rotation = 55
        state.updateShapeContinuous(shape)
        state.cancelPendingDebounceTasks()

        #expect(state.liveShapeEdit.liveShape(for: shape.id) == nil)
        #expect(state.rows.first!.shapes.first { $0.id == shape.id }!.rotation == baseRotation)
    }
}

/// `withObservationTracking`'s `onChange` is `@Sendable`, so the flag it sets can't be a captured
/// `var`. Observation fires it on the mutating thread — the main actor here — so a plain box is
/// enough; the `nonisolated(unsafe)` is what lets the `@Sendable` closure reach it.
private final class RowObservationFlag: @unchecked Sendable {
    nonisolated(unsafe) private(set) var didFire = false
    nonisolated func fire() { didFire = true }
}
