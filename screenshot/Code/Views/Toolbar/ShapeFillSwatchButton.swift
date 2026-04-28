import SwiftUI

struct ShapeFillSwatchButton: View {
    let shape: CanvasShapeModel
    @Binding var isPresented: Bool
    let backgroundStyle: Binding<BackgroundStyle>
    let bgColor: Binding<Color>
    let gradientConfig: Binding<GradientConfig>
    let backgroundImageConfig: Binding<BackgroundImageConfig>
    var backgroundImage: NSImage?
    let onChanged: () -> Void
    let onPickImage: () -> Void
    let onRemoveImage: () -> Void
    let onDropImage: (NSImage) -> Void

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            preview
                .frame(width: UIMetrics.ColorSwatch.preview, height: UIMetrics.ColorSwatch.preview)
                .clipShape(RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip))
                .overlay(
                    RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
                        .strokeBorder(.separator, lineWidth: UIMetrics.BorderWidth.hairline)
                )
        }
        .buttonStyle(.plain)
        .help("Fill")
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(spacing: 8) {
                BackgroundEditor(
                    backgroundStyle: backgroundStyle,
                    bgColor: bgColor,
                    gradientConfig: gradientConfig,
                    backgroundImageConfig: backgroundImageConfig,
                    backgroundImage: backgroundImage,
                    onChanged: onChanged,
                    onPickImage: onPickImage,
                    onRemoveImage: onRemoveImage,
                    onDropImage: onDropImage
                )
            }
            .padding(12)
            .frame(width: 260)
        }
    }

    @ViewBuilder
    private var preview: some View {
        switch shape.resolvedFillStyle {
        case .color:
            Rectangle().fill(shape.color)
        case .gradient:
            (shape.fillGradientConfig ?? GradientConfig()).gradientFill
        case .image:
            if let backgroundImage {
                Image(nsImage: backgroundImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(shape.color)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}
