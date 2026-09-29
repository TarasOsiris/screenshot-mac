import SwiftUI

// The text-shape controls shared by the properties bar's Text popover (macOS column, iPad form)
// and the selection inspector. Each is its own view so the live value a control reads stays in
// that leaf rather than in whichever container lays them out.

struct TextFontPickerControl: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    var presentation: FontPicker.Presentation = .menu

    var body: some View {
        FontPicker(
            selection: shapeBinding(shapeId, \.fontName, default: ""),
            fontWeight: fontWeightBinding(shapeId),
            italic: italicBinding(shapeId),
            customFaces: state.customFaces,
            onApplyImportedSelection: { imported in
                applyImportedFontSelection(imported, to: shapeId)
            },
            onImportFont: { url in state.importCustomFont(from: url) },
            presentation: presentation
        )
    }
}

struct TextFontWeightControl: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    let customControlState: CustomFontControlState?

    var body: some View {
        FontWeightPicker(
            selection: fontWeightBinding(shapeId),
            options: customControlState?.availableWeights ?? CustomFontRegistry.presetWeightBuckets
        )
    }
}

struct MultiTextFontPickerControl: View, MultiShapeEditing {
    let state: AppState
    /// The first selected shape's custom-font state; the whole selection follows it.
    let controlState: CustomFontControlState?
    var presentation: FontPicker.Presentation = .menu

    var body: some View {
        FontPicker(
            selection: multiFontNameBinding(),
            fontWeight: multiFontWeightBinding(controlState: controlState),
            italic: multiItalicBinding(controlState: controlState),
            customFaces: state.customFaces,
            onApplyImportedSelection: { applyImportedFontSelectionOnSelection($0) },
            onImportFont: { url in state.importCustomFont(from: url) },
            presentation: presentation
        )
    }
}

struct MultiTextFontWeightControl: View, MultiShapeEditing {
    let state: AppState
    let controlState: CustomFontControlState?

    var body: some View {
        FontWeightPicker(
            selection: multiFontWeightBinding(controlState: controlState),
            options: controlState?.availableWeights ?? CustomFontRegistry.presetWeightBuckets
        )
    }
}

struct TextFontSizeField: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    var layout: InspectorValueLayout = .strip

    @State private var text = ""
    @State private var isActive = false

    var body: some View {
        let draft = ShapeFieldDraft(text: $text, isActive: $isActive)
        HStack(spacing: 0) {
            ShapePropertyField(
                shapeId: shapeId,
                text: $text,
                isActive: $isActive,
                width: propertiesFontFieldWidth,
                layout: layout,
                modelValue: editingShape(shapeId)?.fontSize.map(Double.init),
                current: { currentFontSizeString(for: $0) },
                commit: { commitFontSize(to: $0, draft: draft) },
                liveApply: { applyFontSizeContinuously(fallbackShapeId: shapeId, draft: draft) },
                liveSelection: { state.selectedShapeId },
                overrideField: .fontSize
            )

            PresetChevronMenu {
                ForEach(CanvasShapeModel.fontSizePresets, id: \.self) { size in
                    Button("\(size)") {
                        text = "\(size)"
                        commitFontSize(to: state.selectedShapeId ?? shapeId, draft: draft)
                    }
                }
            }
        }
    }
}

struct TextLineSpacingField: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    var layout: InspectorValueLayout = .strip

    @State private var text = ""
    @State private var isActive = false

    var body: some View {
        let draft = ShapeFieldDraft(text: $text, isActive: $isActive)
        HStack(spacing: 0) {
            ShapePropertyField(
                shapeId: shapeId,
                text: $text,
                isActive: $isActive,
                width: propertiesFontFieldWidth,
                layout: layout,
                modelValue: editingShape(shapeId)?.lineHeightMultiple.map(Double.init),
                current: { currentLineHeightString(for: $0) },
                commit: { commitLineHeight(to: $0, draft: draft) },
                liveApply: { applyLineHeightContinuously(fallbackShapeId: shapeId, draft: draft) },
                liveSelection: { state.selectedShapeId },
                // This control writes `lineHeightMultiple`; `lineSpacing` is the legacy field.
                overrideField: .lineHeight
            )

            PresetChevronMenu {
                ForEach(ShapeTextDefaults.lineHeightPresets, id: \.self) { preset in
                    Button("\(preset)%") {
                        text = "\(preset)"
                        commitLineHeight(to: state.selectedShapeId ?? shapeId, draft: draft)
                    }
                }
            }

            Text("%")
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
        }
    }
}

struct TextAlignPicker: View {
    @Binding var selection: TextAlign

    var body: some View {
        Picker("", selection: $selection) {
            Image(systemName: "text.alignleft").tag(TextAlign.left)
            Image(systemName: "text.aligncenter").tag(TextAlign.center)
            Image(systemName: "text.alignright").tag(TextAlign.right)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Horizontal alignment")
        .accessibilityLabel("Horizontal alignment")
    }
}

struct TextVerticalAlignPicker: View {
    @Binding var selection: TextVerticalAlign

    var body: some View {
        Picker("", selection: $selection) {
            Image(systemName: "arrow.up.to.line").tag(TextVerticalAlign.top)
            Image(systemName: "arrow.up.and.down").tag(TextVerticalAlign.center)
            Image(systemName: "arrow.down.to.line").tag(TextVerticalAlign.bottom)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Vertical alignment")
        .accessibilityLabel("Vertical alignment")
    }
}

struct TextLetterSpacingControl: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    var sliderWidth: CGFloat = UIMetrics.SliderWidth.standard
    /// `.formRow` is the whole labeled inspector row; otherwise just the value, for the bar to label.
    var layout: InspectorValueLayout = .strip

    private static let range: ClosedRange<CGFloat> = -5...30

    var body: some View {
        let trackingBinding = shapeBinding(shapeId, \.letterSpacing, default: 0, continuous: true)
        if layout == .formRow {
            PopoverSliderRow(
                label: "Letter Spacing",
                value: trackingBinding,
                range: Self.range,
                layout: layout,
                format: { Double($0).formatted(.number.precision(.fractionLength(1))) }
            ) {
                resetButton(trackingBinding)
            }
        } else {
            stripControl(trackingBinding)
        }
    }

    private func stripControl(_ trackingBinding: Binding<CGFloat>) -> some View {
        HStack(spacing: 4) {
            Slider(value: trackingBinding, in: Self.range)
                .frame(width: sliderWidth)

            Text(trackingBinding.wrappedValue, format: .number.precision(.fractionLength(1)))
                .frame(width: propertiesTrackingValueWidth, alignment: .trailing)
                .onTapGesture(count: 2) { trackingBinding.wrappedValue = 0 }
                #if os(macOS)
                .help("Double-click to reset")
                #else
                .help("Double-tap to reset")
                #endif

            resetButton(trackingBinding)
        }
    }

    /// Disabled rather than hidden, so dragging off zero doesn't shift the slider.
    private func resetButton(_ trackingBinding: Binding<CGFloat>) -> some View {
        ActionButton(
            icon: "arrow.counterclockwise",
            tooltip: "Reset letter spacing",
            frameSize: UIMetrics.IconButton.frameSize,
            disabled: trackingBinding.wrappedValue == 0
        ) {
            trackingBinding.wrappedValue = 0
        }
    }
}

struct TextClearFormattingButton: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID

    var body: some View {
        Button("Clear Formatting") {
            clearRichTextFormatting(shapeId)
        }
    }
}

/// Presets on, background toggle, then the background's colour, padding, radius, opacity and
/// outline. Reads its toggles' values in its own body, so a slider tick re-renders only this.
struct TextBackgroundControls: View, ShapeEditing {
    let state: AppState
    let shapeId: UUID
    /// `.formRow` lays the controls out as the selection inspector's separated label/value rows.
    var layout: InspectorValueLayout = .popoverColumn

    var body: some View {
        if layout == .formRow {
            formRows
        } else {
            popoverColumn
        }
    }

    @ViewBuilder
    private var formRows: some View {
        let isOn = textBackgroundEnabledBinding(shapeId)
        let matching = matchingPresetName
        Toggle("Background", isOn: isOn)
            .toggleStyle(.switch)
        // Applying a preset also turns the background on, so it stays reachable while off.
        EditorLabeledContent("Preset") {
            Picker("Preset", selection: presetNameBinding(current: matching)) {
                if matching == nil {
                    Text(isOn.wrappedValue ? "Custom" : "None").tag(String?.none)
                }
                ForEach(TextBackgroundPreset.presets) { preset in
                    Text(verbatim: preset.name).tag(Optional(preset.name))
                }
            }
            .inspectorPopUpPicker()
        }
        if isOn.wrappedValue {
            backgroundRows
            outlineRows
        }
    }

    private var popoverColumn: some View {
        let isOn = textBackgroundEnabledBinding(shapeId)
        return VStack(alignment: .leading, spacing: 10) {
            // One-tap presets — applying a preset also turns the background on.
            HStack(spacing: 6) { presetButtons }

            Divider()

            Toggle("Background", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)

            if isOn.wrappedValue {
                backgroundRows
                Divider()
                outlineRows
            }
        }
        .scaledFont(UIMetrics.FontSize.body)
        .controlSize(.small)
    }

    @ViewBuilder
    private var backgroundRows: some View {
        EditorLabeledContent("Color") {
            PaletteColorPicker(
                "",
                selection: shapeBinding(shapeId, \.textBackgroundColor, default: CanvasShapeModel.defaultTextBackgroundColor),
                supportsOpacity: true, wellWidth: UIMetrics.ColorSwatch.inline
            )
            .labelsHidden()
        }

        PopoverSliderField(
            label: "Padding",
            value: shapeBinding(shapeId, \.textBackgroundPadding, default: 0, continuous: true),
            range: 0...100,
            layout: layout
        )

        PopoverSliderField(
            label: "Radius",
            value: shapeBinding(shapeId, \.textBackgroundCornerRadius, default: 0, continuous: true),
            range: 0...100,
            layout: layout
        )

        PopoverSliderField(
            label: "Opacity",
            value: textBackgroundOpacityPercentBinding(shapeId),
            range: 0...100,
            resetValue: 100,
            layout: layout,
            unit: "%"
        )
    }

    @ViewBuilder
    private var outlineRows: some View {
        let hasOutline = textBackgroundOutlineEnabledBinding(shapeId)
        Toggle("Outline", isOn: hasOutline)
            .toggleStyle(.switch)
            .help(hasOutline.wrappedValue ? String(localized: "Disable outline") : String(localized: "Enable outline"))

        if hasOutline.wrappedValue {
            EditorLabeledContent("Outline") {
                PaletteColorPicker(
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
                resetValue: CanvasShapeModel.defaultTextBackgroundOutlineWidth,
                layout: layout
            )
        }
    }

    private var matchingPresetName: String? {
        guard let shape = resolvedDocumentShape(shapeId), shape.textBackgroundColorData != nil else { return nil }
        return TextBackgroundPreset.presets.first { $0.matches(shape) }?.name
    }

    private func presetNameBinding(current: String?) -> Binding<String?> {
        Binding(
            get: { current },
            set: { name in
                guard let preset = TextBackgroundPreset.presets.first(where: { $0.name == name }) else { return }
                applyTextBackgroundPreset(preset, shapeId: shapeId)
            }
        )
    }

    @ViewBuilder
    private var presetButtons: some View {
        ForEach(TextBackgroundPreset.presets) { preset in
            Button(preset.name) {
                applyTextBackgroundPreset(preset, shapeId: shapeId)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

struct PresetChevronMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "chevron.down")
                .scaledFont(UIMetrics.FontSize.hint)
                .foregroundStyle(.secondary)
                .frame(width: UIMetrics.ChevronMenu.width, height: UIMetrics.ChevronMenu.height)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Presets")
    }
}
