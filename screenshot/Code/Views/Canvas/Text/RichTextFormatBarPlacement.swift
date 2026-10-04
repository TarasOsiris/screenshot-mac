import CoreGraphics

enum RichTextFormatBarPlacement {
    /// When the container is smaller than the bar, the far edge wins.
    static func clampedCenter(
        anchor: CGPoint,
        containerOrigin: CGPoint,
        containerSize: CGSize,
        barSize: CGSize,
        inset: CGFloat
    ) -> CGPoint {
        let barHalfW = barSize.width / 2
        let barHalfH = barSize.height / 2
        let rawX = anchor.x - containerOrigin.x
        let rawY = anchor.y - containerOrigin.y - barHalfH
        let clampedX = min(max(barHalfW + inset, rawX), containerSize.width - barHalfW - inset)
        let clampedY = min(max(barHalfH + inset, rawY), containerSize.height - barHalfH - inset)
        return CGPoint(x: clampedX, y: clampedY)
    }
}
