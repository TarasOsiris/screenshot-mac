import CoreGraphics

/// Converts between canvas axes and a shape's own axes, turned clockwise by `degrees` about the
/// frame's center. The one copy of the sign convention the resize and crop math share.
nonisolated enum ShapeRotation {
    static func toLocal(_ vector: CGSize, degrees: Double) -> CGSize {
        let radians = degrees * .pi / 180
        return CGSize(
            width: vector.width * cos(radians) + vector.height * sin(radians),
            height: -vector.width * sin(radians) + vector.height * cos(radians)
        )
    }

    static func toCanvas(_ vector: CGSize, degrees: Double) -> CGSize {
        toLocal(vector, degrees: -degrees)
    }

    /// `local` is in `frame`'s own axes with the origin at its center; the result is the unrotated
    /// model rect (the shape's x/y/width/height) of a frame that covers it at the same rotation.
    static func canvasFrame(ofLocal local: CGRect, in frame: CGRect, degrees: Double) -> CGRect {
        let center = toCanvas(CGSize(width: local.midX, height: local.midY), degrees: degrees)
        return CGRect(
            x: frame.midX + center.width - local.width / 2,
            y: frame.midY + center.height - local.height / 2,
            width: local.width,
            height: local.height
        )
    }
}
