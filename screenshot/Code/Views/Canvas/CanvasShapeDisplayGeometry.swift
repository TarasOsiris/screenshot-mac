import CoreGraphics

enum CanvasShapeDisplayGeometry {
    static func snappedRect(
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        displayScale: CGFloat,
        screenScale: CGFloat
    ) -> CGRect {
        let pixelStep = 1 / max(screenScale, 1)

        func snap(_ value: CGFloat) -> CGFloat {
            (value / pixelStep).rounded() * pixelStep
        }

        let rawMinX = x * displayScale
        let rawMinY = y * displayScale
        let rawMaxX = (x + width) * displayScale
        let rawMaxY = (y + height) * displayScale

        let minX = snap(rawMinX)
        let minY = snap(rawMinY)
        let maxX = snap(rawMaxX)
        let maxY = snap(rawMaxY)

        return CGRect(
            x: minX,
            y: minY,
            width: max(pixelStep, maxX - minX),
            height: max(pixelStep, maxY - minY)
        )
    }
}
