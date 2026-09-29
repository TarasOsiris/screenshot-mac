import SwiftUI

/// A crop-mode handle: an L-bracket hugging a corner, or a bar along an edge — the photo-editor
/// shape that says "this trims" rather than "this scales".
struct CropHandleGlyph: View {
    let edge: ResizeEdge
    let zoom: CGFloat

    var body: some View {
        let arm = UIMetrics.CanvasHandle.cropBracketArm / zoom
        let thickness = UIMetrics.CanvasHandle.cropBracketThickness / zoom
        let path = glyphPath(arm: arm)
        ZStack {
            path.stroke(Color.accentColor, style: StrokeStyle(lineWidth: thickness + 2 / zoom, lineCap: .square, lineJoin: .miter))
            path.stroke(Color.white, style: StrokeStyle(lineWidth: thickness, lineCap: .square, lineJoin: .miter))
        }
        .frame(width: arm * 2, height: arm * 2)
    }

    /// Drawn in a 2·arm square centered on the handle point, pointing into the frame.
    private func glyphPath(arm: CGFloat) -> Path {
        let sides = edge.movingSides
        let inwardX: CGFloat = sides.x == .min ? 1 : -1
        let inwardY: CGFloat = sides.y == .min ? 1 : -1
        let center = CGPoint(x: arm, y: arm)
        var path = Path()
        switch (sides.x, sides.y) {
        case (.some, .some):
            path.move(to: CGPoint(x: center.x, y: center.y + arm * inwardY))
            path.addLine(to: center)
            path.addLine(to: CGPoint(x: center.x + arm * inwardX, y: center.y))
        case (.some, nil):
            path.move(to: CGPoint(x: center.x, y: center.y - arm * 0.6))
            path.addLine(to: CGPoint(x: center.x, y: center.y + arm * 0.6))
        default:
            path.move(to: CGPoint(x: center.x - arm * 0.6, y: center.y))
            path.addLine(to: CGPoint(x: center.x + arm * 0.6, y: center.y))
        }
        return path
    }
}

/// Floating reminder of what crop mode does and how to leave it, above the frame (below it when
/// the frame is at the top of the canvas).
struct CropModeHint: View {
    let displayRect: CGRect
    let rotation: Double

    var body: some View {
        let radians = rotation * .pi / 180
        let boundsHeight = abs(displayRect.width * sin(radians)) + abs(displayRect.height * cos(radians))
        let gap = UIMetrics.CanvasHandle.cropHintGap
        let above = displayRect.midY - boundsHeight / 2 - gap
        let y = above > gap ? above : displayRect.midY + boundsHeight / 2 + gap

        hintText
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .overlay { Capsule().strokeBorder(Color.primary.opacity(UIMetrics.Opacity.hairlineOverlay)) }
            .fixedSize()
            .allowsHitTesting(false)
            .position(x: displayRect.midX, y: y)
    }

    private var hintText: Text {
        #if os(macOS)
        Text("Drag to reposition · Return to finish")
        #else
        Text("Drag to reposition")
        #endif
    }
}

/// Rule-of-thirds guides over the crop window while it's being adjusted.
struct CropThirdsGrid: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for fraction in [1.0 / 3, 2.0 / 3] {
                path.move(to: CGPoint(x: size.width * fraction, y: 0))
                path.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
                path.move(to: CGPoint(x: 0, y: size.height * fraction))
                path.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
            }
            context.stroke(path, with: .color(.white.opacity(UIMetrics.Opacity.cropGrid)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}
