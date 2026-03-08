import AppKit

enum CursorHelper {
    private static let positions: [NSCursor.FrameResizePosition] = [
        .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left, .topLeft
    ]

    /// Returns a resize cursor for the given edge, adjusted for the shape's rotation.
    static func resizeCursor(for edge: ResizeEdge, rotation: Double) -> NSCursor {
        let baseIndex: Int = switch edge {
        case .top: 0
        case .topRight: 1
        case .right: 2
        case .bottomRight: 3
        case .bottom: 4
        case .bottomLeft: 5
        case .left: 6
        case .topLeft: 7
        }

        let steps = Int((rotation / 45).rounded())
        let effectiveIndex = ((baseIndex + steps) % 8 + 8) % 8

        return NSCursor.frameResize(position: positions[effectiveIndex], directions: .all)
    }

    /// A circular-arrow cursor for rotation.
    static let rotateCursor: NSCursor = {
        let size: CGFloat = 20
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let center = CGPoint(x: size / 2, y: size / 2)
            let radius: CGFloat = 6.5
            // Arc spanning 270 degrees (leave a gap for the arrowhead)
            let startAngle: CGFloat = .pi / 4          // 45 degrees
            let endAngle: CGFloat = startAngle - 1.5 * .pi  // -270 degrees sweep

            // White outline for contrast
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(3.5)
            ctx.setLineCap(.round)
            ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            ctx.strokePath()

            // Black arc
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            ctx.strokePath()

            // Arrowhead at the end of the arc
            let tipX = center.x + radius * cos(endAngle)
            let tipY = center.y + radius * sin(endAngle)
            // Tangent direction (perpendicular to radius, in direction of arc motion)
            let tangent = endAngle + .pi / 2
            let arrowLen: CGFloat = 5
            let spread: CGFloat = 0.5

            let p1 = CGPoint(x: tipX - arrowLen * cos(tangent - spread),
                             y: tipY - arrowLen * sin(tangent - spread))
            let p2 = CGPoint(x: tipX - arrowLen * cos(tangent + spread),
                             y: tipY - arrowLen * sin(tangent + spread))

            // White outline
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(3.5)
            ctx.move(to: p1); ctx.addLine(to: CGPoint(x: tipX, y: tipY))
            ctx.addLine(to: p2)
            ctx.strokePath()

            // Black arrowhead
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: p1); ctx.addLine(to: CGPoint(x: tipX, y: tipY))
            ctx.addLine(to: p2)
            ctx.strokePath()

            return true
        }

        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()
}
