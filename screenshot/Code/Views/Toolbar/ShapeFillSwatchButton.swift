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

    // iPad needs extra width so the enlarged gradient angle wheel + preset row fit on one line.
    #if os(macOS)
    private static let popoverWidth: CGFloat = 260
    #else
    private static let popoverWidth: CGFloat = 300
    #endif

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
        .barPopover(isPresented: $isPresented, title: "Fill") {
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
            .frame(width: Self.popoverWidth)
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
                            .font(.system(size: UIMetrics.FontSize.inlineLabel))
                            .foregroundStyle(.secondary)
                    }
            }
        }
    }
}
