import SwiftUI

struct GradientAngleWheel: View {
    @Binding var angle: Double
    let size: CGFloat = 48
    private let edgeInset: Double = 4

    private func rad(_ deg: Double) -> Double {
        (deg - 90) * .pi / 180
    }

    var body: some View {
        let radians = rad(angle)
        let radius = Double(size) / 2 - edgeInset

        ZStack {
            Circle()
                .strokeBorder(Color.secondary.opacity(UIMetrics.Opacity.accentSelection), lineWidth: UIMetrics.BorderWidth.emphasis)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.primary.opacity(UIMetrics.Opacity.hairlineOverlay), .clear],
                        startPoint: unitPoint(for: angle),
                        endPoint: unitPoint(for: angle + 180)
                    )
                )
                .padding(UIMetrics.BorderWidth.emphasis)

            Path { path in
                let center = CGPoint(x: size / 2, y: size / 2)
                let end = CGPoint(
                    x: center.x + cos(radians) * radius,
                    y: center.y + sin(radians) * radius
                )
                path.move(to: center)
                path.addLine(to: end)
            }
            .stroke(Color.accentColor, lineWidth: 2)

            Circle()
                .fill(Color.accentColor)
                .frame(width: 6, height: 6)
                .offset(
                    x: cos(radians) * radius,
                    y: sin(radians) * radius
                )
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let center = CGPoint(x: size / 2, y: size / 2)
                    let dx = Double(value.location.x - center.x)
                    let dy = Double(value.location.y - center.y)
                    var degrees = atan2(dy, dx) * 180 / .pi + 90
                    if degrees < 0 { degrees += 360 }
                    let snapped = (degrees / 15).rounded() * 15
                    if abs(degrees - snapped) < 3 {
                        degrees = snapped
                    }
                    angle = degrees.truncatingRemainder(dividingBy: 360)
                }
        )
    }

    private func unitPoint(for deg: Double) -> UnitPoint {
        let radians = rad(deg)
        return UnitPoint(
            x: 0.5 + cos(radians) * 0.5,
            y: 0.5 + sin(radians) * 0.5
        )
    }
}
