import Foundation

/// The shape being composed by an in-flight continuous edit (a properties-bar slider drag),
/// before it is written back to `AppState.rows`.
///
/// A slider ticks ~30 times a second and `rows` is a single observed property, so writing every
/// tick straight into the document re-ran `ContentView`'s row builder, the whole edited row —
/// every shape across every template — the properties bar and any open popover. A profile of a
/// pitch/yaw drag spent 79% of the main thread inside SwiftUI layout and the accessibility graph,
/// which starved the drag down to ~10 of 30 ticks. Same reasoning, and the same shape of fix, as
/// `CanvasDragSession` for canvas drags: the burst lives here and lands in `rows` once, at the end.
///
/// Read it only through `liveShape(for:)`. That checks `shapeId` before touching `shape`, so under
/// Observation a shape that isn't the one being edited never subscribes to the per-tick value —
/// it sees only the two `shapeId` transitions that bracket the burst.
@Observable @MainActor
final class LiveShapeEditSession {
    private(set) var shapeId: UUID?
    private(set) var shape: CanvasShapeModel?

    func update(_ shape: CanvasShapeModel) {
        // Assigned only on a real change: `shapeId` is what every other shape observes, so an
        // unconditional write would invalidate the whole canvas on every tick.
        if shapeId != shape.id { shapeId = shape.id }
        self.shape = shape
    }

    func end() {
        guard shapeId != nil || shape != nil else { return }
        shapeId = nil
        shape = nil
    }

    /// The in-flight value for `id`, or nil when some other shape (or nothing) is being edited.
    func liveShape(for id: UUID) -> CanvasShapeModel? {
        guard shapeId == id else { return nil }
        return shape
    }
}
