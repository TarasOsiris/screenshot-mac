import Foundation

/// Nonce-driven "scroll into view" requests for the canvas, split out of `AppState`. A caller bumps
/// a request nonce; the observing view (`ContentView`'s row `ScrollViewReader`, `EditorRowView`'s
/// per-shape reader) scrolls and clears the target. Kept as plain observable signals — no document
/// state — so they don't belong on `AppState`.
@Observable
final class CanvasFocusController {
    /// Row the canvas ScrollView should center; cleared by the observer once scrolled.
    var rowId: UUID?
    var rowRequestNonce = 0
    var animated = true

    /// Shape the per-row canvas should center; cleared by the observer once scrolled.
    var shapeId: UUID?
    var shapeRequestNonce = 0

    /// Request the canvas to scroll a row to center.
    func requestRow(_ rowId: UUID, animated: Bool) {
        self.animated = animated
        self.rowId = rowId
        rowRequestNonce += 1
    }

    /// Request the canvas to scroll a shape to center.
    func requestShape(_ shapeId: UUID?) {
        self.shapeId = shapeId
        shapeRequestNonce += 1
    }
}
