import CoreGraphics

struct ResizeState {
    var newX: CGFloat
    var newY: CGFloat
    var newW: CGFloat
    var newH: CGFloat

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
}

/// A model-space pointer translation becomes the shape's new frame, with the handle's opposite
/// corner or edge pinned. Every branch taken per tick must agree with its neighbour at the
/// boundary where it flips, or the shape visibly steps mid-drag.
enum ResizeGeometry {
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
