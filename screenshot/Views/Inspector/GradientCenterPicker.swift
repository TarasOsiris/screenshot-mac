import SwiftUI

struct GradientCenterPicker: View {
    @Binding var centerX: Double
    @Binding var centerY: Double
    private let edgeInset: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let area = size - edgeInset * 2

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1.5)

                Path { path in
                    let cx = edgeInset + area * centerX
                    let cy = edgeInset + area * centerY
                    path.move(to: CGPoint(x: cx, y: edgeInset))
                    path.addLine(to: CGPoint(x: cx, y: size - edgeInset))
                    path.move(to: CGPoint(x: edgeInset, y: cy))
                    path.addLine(to: CGPoint(x: size - edgeInset, y: cy))
                }
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 8, height: 8)
                    .offset(
                        x: area * (centerX - 0.5),
                        y: area * (centerY - 0.5)
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = (value.location.x - edgeInset) / area
                        let y = (value.location.y - edgeInset) / area
                        centerX = min(max(x, 0), 1)
                        centerY = min(max(y, 0), 1)
                    }
            )
        }
        .frame(width: 48, height: 48)
    }
}
