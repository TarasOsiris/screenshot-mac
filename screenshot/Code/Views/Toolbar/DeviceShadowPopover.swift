import SwiftUI

/// Popover for editing a device's drop shadow: enable toggle, presets, and
/// fine-tune sliders for color, blur, offset, and opacity. Layout mirrors
/// `Device3DAppearancePopover`.
struct DeviceShadowPopover: View {
    @Binding var shadow: ShadowConfig

    var body: some View {
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
        .padding(14)
        .frame(width: 320)
        .font(.system(size: UIMetrics.FontSize.body))
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Text("Shadow")
                .font(.system(size: UIMetrics.FontSize.body, weight: .semibold))

            Spacer()

            Button(action: reset) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(shadow.isEmpty)
            .help("Remove the shadow")
        }
    }

    @ViewBuilder
    private var presetSection: some View {
        sectionHeader("Preset")
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
            shadow = ShadowConfig.preset(preset)
        } label: {
            Text(preset.label)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detailSection: some View {
        sectionHeader("Adjust")

        HStack {
            Text("Color")
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            ColorPicker("", selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
            Spacer()
        }

        sliderRow(
            label: "Blur",
            binding: radiusBinding,
            range: ShadowConfig.radiusRange,
            displayValue: intLabel(shadow.resolvedRadius)
        )
        sliderRow(
            label: "Offset X",
            binding: offsetXBinding,
            range: ShadowConfig.offsetRange,
            displayValue: intLabel(shadow.resolvedOffsetX)
        )
        sliderRow(
            label: "Offset Y",
            binding: offsetYBinding,
            range: ShadowConfig.offsetRange,
            displayValue: intLabel(shadow.resolvedOffsetY)
        )
        sliderRow(
            label: "Opacity",
            binding: opacityBinding,
            range: ShadowConfig.opacityRange,
            displayValue: "\(Int((shadow.resolvedOpacity * 100).rounded()))%"
        )
    }

    @ViewBuilder
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    @ViewBuilder
    private func sliderRow(
        label: LocalizedStringKey,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        displayValue: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Slider(value: binding, in: range)
                .controlSize(.regular)
            Text(displayValue)
                .frame(width: 44, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func intLabel(_ value: CGFloat) -> String { "\(Int(value.rounded()))" }

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
