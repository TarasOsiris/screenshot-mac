import SwiftUI

/// Popover for editing a shape's drop shadow: enable toggle, presets, and
/// fine-tune sliders for color, blur, offset, and opacity. Layout mirrors
/// `Device3DAppearancePopover`. On iPad it's presented as a sheet, so the
/// content is a standard `Form` instead of the dense desktop column.
struct ShadowPopover: View {
    @Binding var shadow: ShadowConfig

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            Toggle("Enable shadow", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.small)

            if shadow.isActive {
                Divider()
                presetSection
                Divider()
                detailSection
            }
        }
        .popoverColumn()
        #else
        Form {
            Section {
                Toggle("Enable shadow", isOn: enabledBinding)
            }
            if shadow.isActive {
                Section("Preset") {
                    HStack(spacing: 8) {
                        ForEach(ShadowConfig.Preset.allCases) { preset in
                            presetButton(preset)
                        }
                    }
                }
                Section("Adjust") {
                    ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
                    detailSliders
                }
            }
        }
        #endif
    }

    private var header: some View {
        PopoverHeader(
            title: "Shadow",
            resetLabel: "Reset",
            resetHelp: "Remove the shadow",
            isResetDisabled: { shadow.isEmpty },
            onReset: reset
        )
    }

    @ViewBuilder
    private var presetSection: some View {
        PopoverSectionHeader("Preset")
        HStack(spacing: 6) {
            ForEach(ShadowConfig.Preset.allCases) { preset in
                presetButton(preset)
            }
        }
    }

    @ViewBuilder
    private func presetButton(_ preset: ShadowConfig.Preset) -> some View {
        let isSelected = shadow.matchingPreset == preset
        Button {
            shadow = ShadowConfig.preset(preset, color: shadow.resolvedColor)
        } label: {
            Text(preset.label)
                .font(presetFont(isSelected: isSelected))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.presetVerticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    #if os(macOS)
    private static let presetVerticalPadding: CGFloat = 4
    private func presetFont(isSelected: Bool) -> Font {
        .system(size: 11, weight: isSelected ? .semibold : .regular)
    }
    #else
    private static let presetVerticalPadding: CGFloat = 10
    private func presetFont(isSelected: Bool) -> Font {
        .subheadline.weight(isSelected ? .semibold : .regular)
    }
    #endif

    @ViewBuilder
    private var detailSection: some View {
        PopoverSectionHeader("Adjust")

        HStack {
            Text("Color")
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
            Spacer()
        }

        detailSliders
    }

    /// The four tuning sliders, shared by the macOS column and the iPad Form.
    @ViewBuilder
    private var detailSliders: some View {
        PopoverSliderRow(label: "Blur", value: radiusBinding, range: ShadowConfig.radiusRange)
        PopoverSliderRow(label: "Offset X", value: offsetXBinding, range: ShadowConfig.offsetRange)
        PopoverSliderRow(label: "Offset Y", value: offsetYBinding, range: ShadowConfig.offsetRange)
        PopoverSliderRow(
            label: "Opacity",
            value: opacityBinding,
            range: ShadowConfig.opacityRange,
            format: { "\(Int(($0 * 100).rounded()))%" }
        )
    }

    private func reset() {
        shadow = ShadowConfig()
    }

    // MARK: - Bindings

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { shadow.isActive },
            set: { shadow.enabled = $0 }
        )
    }
    private var colorBinding: Binding<Color> {
        Binding(get: { shadow.resolvedColor }, set: { shadow.color = $0 })
    }
    private var radiusBinding: Binding<Double> {
        Binding(get: { Double(shadow.resolvedRadius) }, set: { shadow.radius = CGFloat($0) })
    }
    private var offsetXBinding: Binding<Double> {
        Binding(get: { Double(shadow.resolvedOffsetX) }, set: { shadow.offsetX = CGFloat($0) })
    }
    private var offsetYBinding: Binding<Double> {
        Binding(get: { Double(shadow.resolvedOffsetY) }, set: { shadow.offsetY = CGFloat($0) })
    }
    private var opacityBinding: Binding<Double> {
        Binding(get: { shadow.resolvedOpacity }, set: { shadow.opacity = $0 })
    }
}
