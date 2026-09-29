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

    /// Moves the picture by `translation` (model points, in the frame's own axes), starting from
    /// the clamped crop so an offset left over from a higher zoom can't swallow the first part of
    /// a pan. The result is unclamped, so a drag can overshoot while it's live.
    func panned(by translation: CGSize, frameSize: CGSize, imageSize: CGSize?) -> ImageCrop {
        var crop = imageSize.map { clamped(imageSize: $0, frameSize: frameSize) } ?? self
        crop.offsetX += translation.width / max(frameSize.width, 1)
        crop.offsetY += translation.height / max(frameSize.height, 1)
        return crop
    }

    /// Where the whole picture sits, in the frame's own axes with the origin at the frame's center.
    func pictureRect(imageSize: CGSize, frameSize: CGSize) -> CGRect {
        let crop = clamped(imageSize: imageSize, frameSize: frameSize)
        guard imageSize.width > 0, imageSize.height > 0, frameSize.width > 0, frameSize.height > 0 else {
            return CGRect(x: -frameSize.width / 2, y: -frameSize.height / 2, width: frameSize.width, height: frameSize.height)
        }
        let fill = Self.aspectFillSize(imageAspect: imageSize.width / imageSize.height, frameSize: frameSize)
        let width = fill.width * crop.scale
        let height = fill.height * crop.scale
        return CGRect(
            x: crop.offsetX * frameSize.width - width / 2,
            y: crop.offsetY * frameSize.height - height / 2,
            width: width,
            height: height
        )
    }

    /// The crop that keeps the picture where it is on the canvas when the frame moves from
    /// `oldFrame` to `newFrame` — both unrotated model rects of a shape turned by `rotation`.
    func refitted(from oldFrame: CGRect, to newFrame: CGRect, rotation: Double, imageSize: CGSize) -> ImageCrop {
        guard newFrame.width > 0, newFrame.height > 0, imageSize.width > 0, imageSize.height > 0 else { return self }
        let picture = pictureRect(imageSize: imageSize, frameSize: oldFrame.size)
        let local = Self.localOffset(from: oldFrame, to: newFrame, rotation: rotation)
        let fill = Self.aspectFillSize(imageAspect: imageSize.width / imageSize.height, frameSize: newFrame.size)
        let crop = ImageCrop(
            scale: picture.width / fill.width,
            offsetX: (picture.midX - local.width) / newFrame.width,
            offsetY: (picture.midY - local.height) / newFrame.height
        ).clamped(imageSize: imageSize, frameSize: newFrame.size)
        // Round-off from the round trip must not leave a phantom crop on an untouched picture.
        let epsilon = 1e-9
        return ImageCrop(
            scale: abs(crop.scale - 1) < epsilon ? 1 : crop.scale,
            offsetX: abs(crop.offsetX) < epsilon ? 0 : crop.offsetX,
            offsetY: abs(crop.offsetY) < epsilon ? 0 : crop.offsetY
        )
    }

    /// `newFrame`'s center relative to `oldFrame`'s, along the shape's own rotated axes.
    static func localOffset(from oldFrame: CGRect, to newFrame: CGRect, rotation: Double) -> CGSize {
        let dx = newFrame.midX - oldFrame.midX
        let dy = newFrame.midY - oldFrame.midY
        let radians = rotation * .pi / 180
        return CGSize(
            width: dx * cos(radians) + dy * sin(radians),
            height: -dx * sin(radians) + dy * cos(radians)
        )
    }

    /// The value a shape stores: nil for the identity crop.
    var storedValue: ImageCrop? { isIdentity ? nil : self }

    static func aspectFillSize(imageAspect: CGFloat, frameSize: CGSize) -> CGSize {
        let frameAspect = frameSize.width / frameSize.height
        return imageAspect > frameAspect
            ? CGSize(width: frameSize.height * imageAspect, height: frameSize.height)
            : CGSize(width: frameSize.width, height: frameSize.width / imageAspect)
    }
}
