import CoreGraphics
import Foundation

/// Where the editor last saw the pointer and the viewport, so added and pasted shapes land in
/// view. The canvas writes these as the user moves; nothing observes them, so a mouse move never
/// invalidates a view.
final class CanvasPlacementHints {
    /// The pointer over the canvas in model space; nil once it leaves.
    var mouseModelPosition: CGPoint?
    /// Model-space x of the centre of the selected row's horizontal viewport. A scalar rather than
    /// a point: the y was always derived from the row, and only the x is ever read.
    var visibleModelCenterX: CGFloat?
    /// The shape an add just inserted, so its view can play the appear animation once.
    var justAddedShapeId: UUID?
}
