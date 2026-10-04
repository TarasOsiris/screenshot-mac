import SwiftUI

extension EditorRowView {
    /// Resolves the shape under the pointer for the whole row, replacing an `.onContinuousHover`
    /// per shape.
    func updateHover(at modelPoint: CGPoint, in resolvedShapes: [CanvasShapeModel]) {
        // View mode shows no editor helpers, which is what gated the outline when it lived on the
        // shape.
        let hit: UUID?
        if state.viewMode.isViewMode {
            hit = nil
        } else {
            // `CanvasHoverLayer` draws the outline at the live geometry, and a properties-bar drag
            // keeps its value in the session until the burst settles — so hit-testing the document's
            // copy would leave hover pointing at where the shape used to be for the whole drag.
            let transientShape = state.liveShapeEdit.shapeId.flatMap {
                state.liveShapeEdit.liveShape(for: $0)
            }
            hit = row.hitShape(
                at: modelPoint,
                among: resolvedShapes,
                replacingWith: transientShape
            )?.id
        }
        let previous = dragSession.hoveredShapeId
        // Same-value writes still notify `@Observable` observers, and this runs on every mouse move.
        guard previous != hit else { return }
        dragSession.hoveredShapeId = hit
        applyHoverCursor(from: previous, to: hit, in: resolvedShapes)
    }

    func clearHover() {
        guard let previous = dragSession.hoveredShapeId else { return }
        dragSession.hoveredShapeId = nil
        applyHoverCursor(from: previous, to: nil, in: [])
    }

    /// Only ever called on a hover *transition*, and only acts on one into or out of a **selected**
    /// shape — the scope the per-shape hover had. The open hand advertises the drag you can start
    /// on a shape that is already selected, not the selection you could make. It writes the
    /// `.canvas` hover slot, which a handle painted on top of the shape outranks and any in-flight
    /// gesture's hold outranks — so it needs no guards of its own against either.
    private func applyHoverCursor(from previous: UUID?, to hoveredId: UUID?, in resolvedShapes: [CanvasShapeModel]) {
        // Clear rather than return: `updateHover` forces the hit to nil in view mode, so the
        // exit transition that would drop the hand is the very call this guard swallows — and
        // once the hover is nil, the `previous != hit` gate short-circuits every later move.
        guard !state.viewMode.isViewMode else {
            PlatformCursor.clear(.canvas)
            return
        }
        let leavingSelected = previous.map(selectedShapeIds.contains) ?? false
        let enteringSelected = hoveredId.map(selectedShapeIds.contains) ?? false
        guard leavingSelected || enteringSelected else { return }
        guard let hoveredId, enteringSelected else {
            PlatformCursor.hover(nil, for: .canvas)
            return
        }
        let locked = resolvedShapes.first { $0.id == hoveredId }?.resolvedIsLocked ?? false
        PlatformCursor.hover(locked ? nil : .openHand, for: .canvas)
    }
}
