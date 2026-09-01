import CoreGraphics

/// Point-in-shape geometry for the canvas, in model space.
///
/// Split out as pure arithmetic so the editor can resolve *which* shape is under the cursor once
/// per row instead of installing a hit-testing responder on every shape. Kept free of any shape or
/// row type so it stays directly testable.
nonisolated enum CanvasHitTesting {
    /// True when `point` lies inside `rect` rotated `rotationDegrees` about its centre, and — when
    /// the shape clips to its column — inside `clip` as well.
    ///
    /// Deliberately unrotates the point rather than testing the axis-aligned bounding box: the AABB
    /// of a tilted shape reports hits in its empty corners.
    static func contains(
        point: CGPoint,
        rect: CGRect,
        rotationDegrees: Double,
        clip: CGRect?
    ) -> Bool {
        // Inclusive on all four edges, like the body test below and like the bounding-box test this
        // replaced. `CGRect.contains` is exclusive on maxX/maxY, which would drop a press exactly on
        // a clipped shape's column edge.
        if let clip,
           point.x < clip.minX || point.x > clip.maxX || point.y < clip.minY || point.y > clip.maxY {
            return false
        }

        // `rect.width`/`.height` are standardized, so these are never negative.
        let halfWidth = rect.width / 2
        let halfHeight = rect.height / 2

        let dx = point.x - rect.midX
        let dy = point.y - rect.midY

        guard rotationDegrees != 0 else {
            return abs(dx) <= halfWidth && abs(dy) <= halfHeight
        }

        let radians = -rotationDegrees * .pi / 180
        let localX = dx * cos(radians) - dy * sin(radians)
        let localY = dx * sin(radians) + dy * cos(radians)
        return abs(localX) <= halfWidth && abs(localY) <= halfHeight
    }
}
