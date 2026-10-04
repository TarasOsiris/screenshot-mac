import CoreGraphics
import Foundation

extension CanvasShapeModel {
    /// The unrotated frame; `rotation` turns it about its center.
    nonisolated var frameRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    /// Axis-aligned bounding box accounting for rotation.
    nonisolated var aabb: (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        let cx = x + width / 2
        let cy = y + height / 2
        let hw = width / 2
        let hh = height / 2

        guard rotation != 0 else {
            return (x, y, x + width, y + height)
        }

        let rad = rotation * .pi / 180
        let cosA = abs(cos(rad))
        let sinA = abs(sin(rad))
        let newHW = hw * cosA + hh * sinA
        let newHH = hw * sinA + hh * cosA
        return (cx - newHW, cy - newHH, cx + newHW, cy + newHH)
    }

    var visualAABB: (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        let bounds = aabb
        guard let shadow, shadow.isActive else {
            return bounds
        }

        let offsetLength = hypot(shadow.resolvedOffsetX, shadow.resolvedOffsetY)
        let expansion = shadow.resolvedRadius + offsetLength
        return (
            minX: bounds.minX - expansion,
            minY: bounds.minY - expansion,
            maxX: bounds.maxX + expansion,
            maxY: bounds.maxY + expansion
        )
    }

    /// Shrinks the frame about its center so artwork of `naturalSize` fits it without stretching.
    mutating func fitFrame(toAspectOf naturalSize: CGSize) {
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }
        let scale = min(width / naturalSize.width, height / naturalSize.height)
        let fittedWidth = naturalSize.width * scale
        let fittedHeight = naturalSize.height * scale
        // A sub-half-point difference is float drift from a matching ratio, not a real change.
        guard abs(fittedWidth - width) >= 0.5 || abs(fittedHeight - height) >= 0.5 else { return }
        x += (width - fittedWidth) / 2
        y += (height - fittedHeight) / 2
        width = fittedWidth
        height = fittedHeight
    }

    /// Device frames must scale uniformly or the bezel distorts.
    var locksAspectRatioOnResize: Bool {
        type == .device && (deviceFrameId != nil || deviceCategory != .invisible)
    }

    var minResizeSize: CGFloat { type == .device ? Self.deviceMinSize : Self.shapeMinSize }

    /// Degrees folded into 0..<360, the form `rotation` is stored in. Every surface that composes
    /// an angle from a delta normalizes through here, so a live readout matches what its gesture
    /// finally commits.
    nonisolated static func normalizedRotation(_ degrees: Double) -> Double {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    /// Uniform scale that reaches `target` on the driving axis without letting either dimension
    /// fall under `minResizeSize` — the floor moves both sides together so the ratio survives it.
    /// Both resize paths run through here: the handle drag and the properties bar's typed size.
    func aspectLockedSize(target: CGFloat, drivenBy driving: CGFloat) -> CGSize {
        let minScale = max(minResizeSize / max(width, 1), minResizeSize / max(height, 1))
        let scale = max(minScale, target / max(driving, 1))
        return CGSize(width: max(width, 1) * scale, height: max(height, 1) * scale)
    }

    /// Unlike a handle drag these pin the top-left, because `x`/`y` are their own fields in the
    /// properties bar.
    mutating func applyManualWidth(_ newWidth: CGFloat) {
        guard locksAspectRatioOnResize else {
            width = max(minResizeSize, newWidth)
            return
        }
        applyAspectLocked(target: newWidth, drivenBy: width)
    }

    mutating func applyManualHeight(_ newHeight: CGFloat) {
        guard locksAspectRatioOnResize else {
            height = max(minResizeSize, newHeight)
            return
        }
        applyAspectLocked(target: newHeight, drivenBy: height)
    }

    private mutating func applyAspectLocked(target: CGFloat, drivenBy driving: CGFloat) {
        let size = aspectLockedSize(target: target, drivenBy: driving)
        width = size.width
        height = size.height
    }

    /// Shrinks the shape to `maxWidth` when it overflows, preserving aspect ratio and current center.
    mutating func scaleToFitWidth(_ maxWidth: CGFloat) {
        guard maxWidth > 0, width > maxWidth else { return }
        let centerX = x + width / 2
        let centerY = y + height / 2
        let scale = maxWidth / width
        width *= scale
        height *= scale
        x = centerX - width / 2
        y = centerY - height / 2
    }
}
