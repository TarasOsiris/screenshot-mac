import SwiftUI

extension ShapePropertiesSingleSelectionBar {
    // MARK: - Text Background Popover

    struct TextBackgroundPreset: Identifiable {
        let id = UUID()
        let name: String
        let color: Color
        let padding: CGFloat
        let cornerRadius: CGFloat
        let outlineColor: Color?
        let outlineWidth: CGFloat?
    }

    // String(localized:) literals so the catalog extractor picks the names up (it can't see
    // LocalizedStringKey buried in a struct initializer). Button(_ String) renders them verbatim.
    static var textBackgroundPresets: [TextBackgroundPreset] {
        [
            .init(name: String(localized: "Solid"), color: .black, padding: 16, cornerRadius: 8, outlineColor: nil, outlineWidth: nil),
            .init(name: String(localized: "Pill"), color: .black, padding: 20, cornerRadius: 100, outlineColor: nil, outlineWidth: nil),
            .init(name: String(localized: "Outline"), color: .white, padding: 16, cornerRadius: 8, outlineColor: .black, outlineWidth: 4),
            .init(name: String(localized: "Highlight"), color: .yellow.opacity(0.4), padding: 6, cornerRadius: 4, outlineColor: nil, outlineWidth: nil),
        ]
    }

    func applyTextBackgroundPreset(_ preset: TextBackgroundPreset, shapeId: UUID) {
        guard let i = idx(for: shapeId) else { return }
        var updated = resolvedShape(at: i.row, shapeIdx: i.shape)
        updated.textBackgroundColor = preset.color
        updated.textBackgroundPadding = preset.padding
        updated.textBackgroundCornerRadius = preset.cornerRadius
        updated.textBackgroundOutlineColor = preset.outlineColor
        updated.textBackgroundOutlineWidth = preset.outlineWidth
        updated.textBackgroundOpacity = nil
        state.updateShape(updated)
    }

    @ViewBuilder
    func textBackgroundButton(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        Button {
            isTextBackgroundPopoverPresented.toggle()
        } label: {
            textBackgroundSwatch(shape: shape)
        }
        .buttonStyle(.plain)
        .help("Background")
        .barPopover(isPresented: $isTextBackgroundPopoverPresented, title: "Background") {
            textBackgroundPopoverContent(shape: shape, shapeId: shapeId)
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

    @ViewBuilder
    func textBackgroundPopoverContent(shape: CanvasShapeModel, shapeId: UUID) -> some View {
        // Enable/disable toggles both fields together against the live selection — same shape as the
        // outline toggle. Background is a base-shape (non-localized) style, so writes land on base.
        let isOn = Binding<Bool>(
            get: { shape.textBackgroundColorData != nil },
            set: { enabled in
                guard let i = idx(for: shapeId) else { return }
                var updated = resolvedShape(at: i.row, shapeIdx: i.shape)
                updated.textBackgroundColor = enabled ? CanvasShapeModel.defaultTextBackgroundColor : nil
                updated.textBackgroundCornerRadius = enabled ? 0 : nil
                updated.textBackgroundPadding = enabled ? 0 : nil
                updated.textBackgroundOutlineColor = nil
                updated.textBackgroundOutlineWidth = nil
                updated.textBackgroundOpacity = nil
                state.updateShape(updated)
            }
        )
        let opacity = shapeBinding(shapeId, \.textBackgroundOpacity, default: 1.0, continuous: true)
        let opacityPercent = Binding<CGFloat>(
            get: { CGFloat(opacity.wrappedValue * 100) },
            set: { opacity.wrappedValue = Double($0) / 100 }
        )
        let hasOutline = Binding<Bool>(
            get: { (shape.textBackgroundOutlineWidth ?? 0) > 0 },
            set: { enabled in
                guard let i = idx(for: shapeId) else { return }
                var updated = resolvedShape(at: i.row, shapeIdx: i.shape)
                updated.textBackgroundOutlineColor = enabled ? CanvasShapeModel.defaultTextBackgroundOutlineColor : nil
                updated.textBackgroundOutlineWidth = enabled ? CanvasShapeModel.defaultTextBackgroundOutlineWidth : nil
                state.updateShape(updated)
            }
        )

        VStack(alignment: .leading, spacing: 10) {
            // One-tap presets — applying a preset also turns the background on.
            HStack(spacing: 6) {
                ForEach(Self.textBackgroundPresets) { preset in
                    Button(preset.name) {
                        applyTextBackgroundPreset(preset, shapeId: shapeId)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            Toggle("Background", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)

            if isOn.wrappedValue {
                LabeledContent("Color") {
                    ColorPicker(
                        "",
                        selection: shapeBinding(shapeId, \.textBackgroundColor, default: CanvasShapeModel.defaultTextBackgroundColor),
                        supportsOpacity: true
                    )
                    .labelsHidden()
                    .frame(width: UIMetrics.ColorSwatch.inline)
                }

                PopoverSliderField(
                    label: "Padding",
                    value: shapeBinding(shapeId, \.textBackgroundPadding, default: 0, continuous: true),
                    range: 0...100
                )

                PopoverSliderField(
                    label: "Radius",
                    value: shapeBinding(shapeId, \.textBackgroundCornerRadius, default: 0, continuous: true),
                    range: 0...100
                )

                PopoverSliderField(
                    label: "Opacity",
                    value: opacityPercent,
                    range: 0...100,
                    resetValue: 100
                )

                Divider()

                Toggle("Outline", isOn: hasOutline)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(hasOutline.wrappedValue ? String(localized: "Disable outline") : String(localized: "Enable outline"))

                if hasOutline.wrappedValue {
                    LabeledContent("Outline") {
                        ColorPicker(
                            "",
                            selection: shapeBinding(
                                shapeId,
                                \.textBackgroundOutlineColor,
                                default: CanvasShapeModel.defaultTextBackgroundOutlineColor
                            ),
                            supportsOpacity: true
                        )
                        .labelsHidden()
                        .frame(width: UIMetrics.ColorSwatch.inline)
                    }

                    PopoverSliderField(
                        label: "Width",
                        value: shapeBinding(
                            shapeId,
                            \.textBackgroundOutlineWidth,
                            default: CanvasShapeModel.defaultTextBackgroundOutlineWidth,
                            continuous: true
                        ),
                        range: 1...50,
                        resetValue: CanvasShapeModel.defaultTextBackgroundOutlineWidth
                    )
                }
            }
        }
        .font(.system(size: UIMetrics.FontSize.body))
        .controlSize(.small)
    }
}
