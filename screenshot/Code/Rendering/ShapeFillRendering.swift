import SwiftUI

// SwiftUI fill rendering for CanvasShapeModel. Lives here rather than Models/ because it
// builds views (and reaches BackgroundImageView) — the model layer must not depend on them.
extension CanvasShapeModel {
    @ViewBuilder
    func fillView(image: NSImage? = nil, modelSize: CGSize? = nil) -> some View {
        switch resolvedFillStyle {
        case .color:
            Rectangle().fill(color)
        case .gradient:
            (fillGradientConfig ?? GradientConfig()).gradientFill
        case .image:
            if let image, let config = fillImageConfig {
                ZStack {
                    Rectangle().fill(color)
                    BackgroundImageView(image: image, config: config, modelSize: modelSize)
                }
            } else {
                Rectangle().fill(color)
            }
        }
    }
}
