import CoreGraphics

struct ResizeState {
    var newX: CGFloat
    var newY: CGFloat
    var newW: CGFloat
    var newH: CGFloat

    var frame: CGRect { CGRect(x: newX, y: newY, width: newW, height: newH) }

    func movedFrom(_ shape: CanvasShapeModel) -> Bool {
        changed(newX, from: shape.x)
            || changed(newY, from: shape.y)
            || changed(newW, from: shape.width)
            || changed(newH, from: shape.height)
    }

    private func changed(_ value: CGFloat, from original: CGFloat) -> Bool {
        let scale = max(1, max(abs(value), abs(original)))
        return abs(value - original) > CGFloat.ulpOfOne * scale * 32
    }
}

enum ResizeEdge: Equatable, CaseIterable {
    case topLeft, top, topRight
    case left, right
    case bottomLeft, bottom, bottomRight

    /// The point that should stay fixed (opposite corner/edge), in local shape coords (0,0 = top-left)
    func anchorPoint(width w: CGFloat, height h: CGFloat) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: w, y: h)
        case .top:         return CGPoint(x: w / 2, y: h)
        case .topRight:    return CGPoint(x: 0, y: h)
        case .left:        return CGPoint(x: w, y: h / 2)
        case .right:       return CGPoint(x: 0, y: h / 2)
        case .bottomLeft:  return CGPoint(x: w, y: 0)
        case .bottom:      return CGPoint(x: w / 2, y: 0)
        case .bottomRight: return CGPoint(x: 0, y: 0)
        }
    }

    /// The edges this handle drags on an unrotated shape.
    var movingSides: (x: AlignmentService.ResizeSide?, y: AlignmentService.ResizeSide?) {
        switch self {
        case .topLeft:     return (.min, .min)
        case .top:         return (nil, .min)
        case .topRight:    return (.max, .min)
        case .left:        return (.min, nil)
        case .right:       return (.max, nil)
        case .bottomLeft:  return (.min, .max)
        case .bottom:      return (nil, .max)
        case .bottomRight: return (.max, .max)
        }
    }
}

/// A model-space pointer translation becomes the shape's new frame, with the handle's opposite
/// corner or edge pinned. Every branch taken per tick must agree with its neighbour at the
/// boundary where it flips, or the shape visibly steps mid-drag.
enum ResizeGeometry {
    typealias ResizeSnapper = (
        _ frame: CGRect,
        _ movingX: AlignmentService.ResizeSide?,
        _ movingY: AlignmentService.ResizeSide?
    ) -> ResizeSnapResult

    /// `resize`, with the dragged edges pulled onto nearby alignment targets. The snap is fed back
    /// as a translation so the min-size floor, aspect lock and anchor pin still decide the frame.
    static func snappedResize(
        shape: CanvasShapeModel,
        edge: ResizeEdge,
        translation: CGSize,
        lockAspectRatio: Bool,
        snap: ResizeSnapper
    ) -> (state: ResizeState, guides: [AlignmentGuide]) {
        let raw = resize(shape: shape, edge: edge, translation: translation, lockAspectRatio: lockAspectRatio)
        // A rotated shape's handles don't move axis-aligned edges.
        guard abs(shape.rotation.truncatingRemainder(dividingBy: 360)) <= 1e-6 else { return (raw, []) }

        let sides = edge.movingSides
        let result = snap(raw.frame, sides.x, sides.y)
        guard result.delta != .zero else { return (raw, result.guides) }

        let snappedTranslation: CGSize
        if lockAspectRatio {
            snappedTranslation = aspectLockedTranslation(shape: shape, raw: raw, sides: sides, delta: result.delta)
        } else {
            snappedTranslation = CGSize(
                width: translation.width + result.delta.width,
                height: translation.height + result.delta.height
            )
        }
        let snapped = resize(shape: shape, edge: edge, translation: snappedTranslation, lockAspectRatio: lockAspectRatio)
        let landed = result.guides.filter { guide in
            guard let side = guide.axis == .vertical ? sides.x : sides.y else { return false }
            return abs(side.edge(of: snapped.frame, along: guide.axis) - guide.position) < 0.01
        }
        return (snapped, landed)
    }

    /// One scale drives both axes, so only the closer of the two matches can be honoured. The
    /// translation is built along the shape's diagonal so `lockedSize`'s projection returns it exactly.
    private static func aspectLockedTranslation(
        shape: CanvasShapeModel,
        raw: ResizeState,
        sides: (x: AlignmentService.ResizeSide?, y: AlignmentService.ResizeSide?),
        delta: CGSize
    ) -> CGSize {
        let signX = sides.x?.sign ?? 0
        let signY = sides.y?.sign ?? 0
        let usesX = delta.width != 0 && (delta.height == 0 || abs(delta.width) <= abs(delta.height))
        let scale = usesX
            ? (raw.newW + delta.width * signX) / max(shape.width, 1)
            : (raw.newH + delta.height * signY) / max(shape.height, 1)
        return CGSize(
            width: shape.width * (scale - 1) * signX,
            height: shape.height * (scale - 1) * signY
        )
    }

    static func resize(
        shape: CanvasShapeModel,
        edge: ResizeEdge,
        translation: CGSize,
        lockAspectRatio: Bool
    ) -> ResizeState {
        let radians = shape.rotation * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        let localTx = translation.width * cosA + translation.height * sinA
        let localTy = -translation.width * sinA + translation.height * cosA

        let target = targetSize(shape: shape, edge: edge, localTx: localTx, localTy: localTy)
        let size = lockAspectRatio
            ? lockedSize(shape: shape, edge: edge, target: target)
            : CGSize(
                width: max(shape.minResizeSize, target.width),
                height: max(shape.minResizeSize, target.height)
            )

        return framePinningAnchor(of: shape, edge: edge, to: size, cosA: cosA, sinA: sinA)
    }

    /// Unclamped on purpose: flooring each axis first would kink the locked path's uniform scale
    /// the moment one of them hits the floor. `aspectLockedSize` carries that floor as one
    /// `minScale` instead.
    private static func targetSize(
        shape: CanvasShapeModel,
        edge: ResizeEdge,
        localTx: CGFloat,
        localTy: CGFloat
    ) -> CGSize {
        var width = shape.width
        var height = shape.height
        switch edge {
        case .topLeft:     width -= localTx; height -= localTy
        case .top:                           height -= localTy
        case .topRight:    width += localTx; height -= localTy
        case .left:        width -= localTx
        case .right:       width += localTx
        case .bottomLeft:  width -= localTx; height += localTy
        case .bottom:                        height += localTy
        case .bottomRight: width += localTx; height += localTy
        }
        return CGSize(width: width, height: height)
    }

    /// A corner projects onto the shape's own diagonal rather than driving off whichever axis
    /// moved more: that choice flips while one axis grows and the other shrinks, and its two
    /// candidate scales sit either side of 1, so the size steps by the gap between them.
    private static func lockedSize(shape: CanvasShapeModel, edge: ResizeEdge, target: CGSize) -> CGSize {
        switch edge {
        case .left, .right:
            return shape.aspectLockedSize(target: target.width, drivenBy: shape.width)
        case .top, .bottom:
            return shape.aspectLockedSize(target: target.height, drivenBy: shape.height)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            let width = max(shape.width, 1)
            let height = max(shape.height, 1)
            let scale = (target.width * width + target.height * height) / (width * width + height * height)
            return shape.aspectLockedSize(target: width * scale, drivenBy: width)
        }
    }

    /// Places `size` so the handle's opposite corner or edge midpoint stays where it was, in
    /// rotated canvas space.
    private static func framePinningAnchor(
        of shape: CanvasShapeModel,
        edge: ResizeEdge,
        to size: CGSize,
        cosA: CGFloat,
        sinA: CGFloat
    ) -> ResizeState {
        let anchor = edge.anchorPoint(width: shape.width, height: shape.height)
        let anchorX = anchor.x - shape.width / 2
        let anchorY = anchor.y - shape.height / 2
        let anchorCanvasX = shape.x + shape.width / 2 + anchorX * cosA - anchorY * sinA
        let anchorCanvasY = shape.y + shape.height / 2 + anchorX * sinA + anchorY * cosA

        let newAnchor = edge.anchorPoint(width: size.width, height: size.height)
        let newAnchorX = newAnchor.x - size.width / 2
        let newAnchorY = newAnchor.y - size.height / 2
        let newCenterX = anchorCanvasX - (newAnchorX * cosA - newAnchorY * sinA)
        let newCenterY = anchorCanvasY - (newAnchorX * sinA + newAnchorY * cosA)

        return ResizeState(
            newX: newCenterX - size.width / 2,
            newY: newCenterY - size.height / 2,
            newW: size.width,
            newH: size.height
        )
    }
}
