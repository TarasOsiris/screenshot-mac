import CoreGraphics

/// How an image shape's picture sits inside its frame: zoomed by `scale` over the aspect-fill fit
/// and panned by an offset stored as a fraction of the frame, so the same crop holds at any
/// display scale.
nonisolated struct ImageCrop: Codable, Equatable {
    var scale: Double = 1
    var offsetX: Double = 0
    var offsetY: Double = 0

    static let scaleRange: ClosedRange<Double> = 1...5

    enum CodingKeys: String, CodingKey {
        case scale = "s", offsetX = "x", offsetY = "y"
    }

    var isIdentity: Bool { scale == 1 && offsetX == 0 && offsetY == 0 }

    /// Scale clamped to its range and offsets clamped so the zoomed image still covers the frame.
    /// `imageAspect` is width / height of the picture being cropped.
    func clamped(imageAspect: CGFloat, frameSize: CGSize) -> ImageCrop {
        let scale = min(max(scale, Self.scaleRange.lowerBound), Self.scaleRange.upperBound)
        guard frameSize.width > 0, frameSize.height > 0, imageAspect > 0 else {
            return ImageCrop(scale: scale)
        }
        let fill = Self.aspectFillSize(imageAspect: imageAspect, frameSize: frameSize)
        let maxX = max(0, (fill.width * scale - frameSize.width) / 2 / frameSize.width)
        let maxY = max(0, (fill.height * scale - frameSize.height) / 2 / frameSize.height)
        return ImageCrop(
            scale: scale,
            offsetX: min(max(offsetX, -maxX), maxX),
            offsetY: min(max(offsetY, -maxY), maxY)
        )
    }

    /// `clamped(imageAspect:frameSize:)` for a picture of `imageSize`; a degenerate size clamps
    /// the scale alone.
    func clamped(imageSize: CGSize, frameSize: CGSize) -> ImageCrop {
        clamped(imageAspect: imageSize.height > 0 ? imageSize.width / imageSize.height : 0, frameSize: frameSize)
    }

    static func aspectFillSize(imageAspect: CGFloat, frameSize: CGSize) -> CGSize {
        let frameAspect = frameSize.width / frameSize.height
        return imageAspect > frameAspect
            ? CGSize(width: frameSize.height * imageAspect, height: frameSize.height)
            : CGSize(width: frameSize.width, height: frameSize.width / imageAspect)
    }
}
