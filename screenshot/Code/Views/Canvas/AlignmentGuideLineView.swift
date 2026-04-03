import SwiftUI

struct AlignmentGuideLineView: View {
    let guide: AlignmentGuide
    let displayScale: CGFloat

    var body: some View {
        Path { path in
            switch guide.axis {
            case .vertical:
                let x = guide.position * displayScale
                path.move(to: CGPoint(x: x, y: guide.start * displayScale))
                path.addLine(to: CGPoint(x: x, y: guide.end * displayScale))
            case .horizontal:
                let y = guide.position * displayScale
                path.move(to: CGPoint(x: guide.start * displayScale, y: y))
                path.addLine(to: CGPoint(x: guide.end * displayScale, y: y))
            }
        }
        .stroke(Color.red, lineWidth: 0.5)
        .allowsHitTesting(false)
    }
}
