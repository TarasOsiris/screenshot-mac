import SwiftUI

struct Device3DAppearancePopover: View {
    @Binding var pitch: Double
    @Binding var yaw: Double
    @Binding var material: DeviceBodyMaterial
    @Binding var lighting: DeviceLighting
    let canResetRotation: Bool
    let onResetRotation: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            rotationSection
            Divider()
            materialSection
            Divider()
            lightingSection
        }
        .padding(14)
        .frame(width: 320)
        .font(.system(size: UIMetrics.FontSize.body))
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 8) {
            Text("3D Device")
                .font(.system(size: UIMetrics.FontSize.body, weight: .semibold))

            Text("Beta")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15), in: .capsule)
                .help("3D device rendering is an experimental feature")

            Spacer()

            Button(action: resetAll) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Reset all")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .disabled(!hasAnyOverride)
            .help("Reset rotation, material, and lighting to defaults")
        }
    }

    @ViewBuilder
    private var rotationSection: some View {
        sectionHeader("Rotation")

        sliderRow(
            label: "Pitch",
            binding: $pitch,
            range: -90...90,
            displayValue: "\(Int(pitch.rounded()))°"
        )
        sliderRow(
            label: "Yaw",
            binding: $yaw,
            range: -90...90,
            displayValue: "\(Int(yaw.rounded()))°"
        )
    }

    @ViewBuilder
    private var materialSection: some View {
        sectionHeader("Material")

        HStack {
            Text("Finish")
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Picker("", selection: finishBinding) {
                ForEach(DeviceBodyFinish.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private var lightingSection: some View {
        sectionHeader("Lighting")

        sliderRow(
            label: "Ambient",
            binding: ambientBinding,
            range: DeviceLighting.ambientIntensityRange,
            displayValue: intLabel(lighting.resolvedAmbientIntensity)
        )
        sliderRow(
            label: "Key",
            binding: keyBinding,
            range: DeviceLighting.keyIntensityRange,
            displayValue: intLabel(lighting.resolvedKeyIntensity)
        )
        sliderRow(
            label: "Rim",
            binding: rimBinding,
            range: DeviceLighting.rimIntensityRange,
            displayValue: intLabel(lighting.resolvedRimIntensity)
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

    private func intLabel(_ value: Double) -> String { "\(Int(value.rounded()))" }

    private var hasAnyOverride: Bool {
        canResetRotation || !material.isEmpty || !lighting.isEmpty
    }

    private func resetAll() {
        material = DeviceBodyMaterial()
        lighting = DeviceLighting()
        if canResetRotation { onResetRotation() }
    }

    private var finishBinding: Binding<DeviceBodyFinish> {
        Binding(get: { material.resolvedFinish }, set: { material.finish = $0 })
    }
    private var ambientBinding: Binding<Double> {
        Binding(get: { lighting.resolvedAmbientIntensity }, set: { lighting.ambientIntensity = $0 })
    }
    private var keyBinding: Binding<Double> {
        Binding(get: { lighting.resolvedKeyIntensity }, set: { lighting.keyIntensity = $0 })
    }
    private var rimBinding: Binding<Double> {
        Binding(get: { lighting.resolvedRimIntensity }, set: { lighting.rimIntensity = $0 })
    }
}
