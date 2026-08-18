import SwiftUI

// SwiftUI rendering for GradientConfig. Kept out of Models/ so the model layer stays
// free of view construction; both the editor canvas and the export renderer draw from here.
extension GradientConfig {
    private var radians: Double {
        (angle - 90) * .pi / 180
    }

    var startPoint: UnitPoint {
        UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    var endPoint: UnitPoint {
        UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    var swiftUIStops: [Gradient.Stop] {
        stops.map { Gradient.Stop(color: $0.color, location: $0.location) }
    }

    var linearGradient: LinearGradient {
        LinearGradient(
            stops: swiftUIStops,
            startPoint: startPoint,
            endPoint: endPoint
        )
    }

    @ViewBuilder
    var gradientFill: some View {
        switch gradientType {
        case .linear:
            Rectangle().fill(linearGradient)
        case .radial:
            // Canvas exposes the actual rendered draw size synchronously (display-space in
            // editor, model-space in export) so endRadius is correct for the view's coordinates.
            // GeometryReader was unreliable here: its size-dependent child isn't always resolved
            // before an offscreen snapshot (NSHostingView/ImageRenderer) captures, which left the
            // background blank intermittently in export/showcase previews.
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let cx = w * centerX
                let cy = h * centerY
                let dx = max(cx, w - cx)
                let dy = max(cy, h - cy)
                let endRadius = sqrt(dx * dx + dy * dy)
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .radialGradient(
                        Gradient(stops: swiftUIStops),
                        center: CGPoint(x: cx, y: cy),
                        startRadius: 0,
                        endRadius: endRadius
                    )
                )
            }
        case .angular:
            Rectangle().fill(AngularGradient(
                stops: swiftUIStops,
                center: UnitPoint(x: centerX, y: centerY),
                angle: .degrees(angle - 90)
            ))
        }
    }
}
