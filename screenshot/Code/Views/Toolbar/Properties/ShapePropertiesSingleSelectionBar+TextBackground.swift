import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    // MARK: - Text Background Popover

    @ViewBuilder
    func textBackgroundButton(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        Button {
            isTextBackgroundPopoverPresented.toggle()
        } label: {
            textBackgroundSwatch(shape: shape)
        }
        .buttonStyle(.plain)
        .help("Background")
        .barPopover(isPresented: $isTextBackgroundPopoverPresented, title: "Background", scrollableContent: true) {
            TextBackgroundControls(state: state, shapeId: shapeId)
                .padding(12)
                .barPopoverContentWidth(280)
        }
    }

    @ViewBuilder
    private func textBackgroundSwatch(shape: CanvasShapeModel) -> some View {
        if let bg = shape.textBackgroundColor {
            let chip = RoundedRectangle(cornerRadius: UIMetrics.CornerRadius.chip)
            chip
                .fill(bg)
                .frame(width: UIMetrics.ColorSwatch.preview, height: UIMetrics.ColorSwatch.preview)
                .overlay {
                    if let outline = shape.textBackgroundOutlineColor, (shape.textBackgroundOutlineWidth ?? 0) > 0 {
                        chip.strokeBorder(outline, lineWidth: UIMetrics.BorderWidth.standard)
                    } else {
                        chip.strokeBorder(.separator, lineWidth: UIMetrics.BorderWidth.hairline)
                    }
                }
        } else {
            Image(systemName: "character.textbox")
                .foregroundStyle(.secondary)
                .frame(width: UIMetrics.ColorSwatch.preview, height: UIMetrics.ColorSwatch.preview)
        }
    }
}
