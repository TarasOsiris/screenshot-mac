import SwiftUI

struct CanvasTemplateSeparatorLines: View {
    let templateCount: Int
    let templateDisplayWidth: CGFloat
    let templateDisplayHeight: CGFloat

    var body: some View {
        if templateCount > 1 {
            ForEach(1..<templateCount, id: \.self) { index in
                separator
                    .frame(width: 1, height: templateDisplayHeight)
                    .offset(x: templateDisplayWidth * CGFloat(index))
                    .allowsHitTesting(false)
            }
        }
    }

    private var separator: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: templateDisplayHeight))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(.black)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 0, y: templateDisplayHeight))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 4], dashPhase: 4))
            .foregroundStyle(.white)
        }
    }
}
