import SwiftUI

struct Device3DAppearancePopover: View {
    @Binding var material: DeviceBodyMaterial
    @Binding var lighting: DeviceLighting

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            materialSection
            Divider()
            lightingSection
        }
        .padding(14)
        .frame(width: 300)
        .font(.system(size: UIMetrics.FontSize.body))
        .controlSize(.small)
    }

    @ViewBuilder
    private var materialSection: some View {
        sectionHeader(title: "Body material", canReset: !material.isEmpty) {
            material = DeviceBodyMaterial()
        }

        LabeledContent("Finish") {
            Picker("", selection: finishBinding) {
                ForEach(DeviceBodyFinish.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 160)
        }

        if material.resolvedFinish == .glossy {
            sliderRow(
                label: "Metalness",
                binding: metalnessBinding,
                range: DeviceBodyMaterial.metalnessRange,
                formatter: percentLabel
            )
            sliderRow(
                label: "Roughness",
                binding: roughnessBinding,
                range: DeviceBodyMaterial.roughnessRange,
                formatter: percentLabel
            )
        } else {
            Text("Glossy lets you tune metalness and roughness for richer reflections. Matte stays close to the original look.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var lightingSection: some View {
        sectionHeader(title: "Lighting", canReset: !lighting.isEmpty) {
            lighting = DeviceLighting()
        }

        sliderRow(
            label: "Ambient",
            binding: ambientBinding,
            range: DeviceLighting.ambientIntensityRange,
            formatter: intLabel
        )
        sliderRow(
            label: "Key",
            binding: keyBinding,
            range: DeviceLighting.keyIntensityRange,
            formatter: intLabel
        )
        sliderRow(
            label: "Rim",
            binding: rimBinding,
            range: DeviceLighting.rimIntensityRange,
            formatter: intLabel
        )
    }

    @ViewBuilder
    private func sectionHeader(title: LocalizedStringKey, canReset: Bool, onReset: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(.system(size: UIMetrics.FontSize.body, weight: .semibold))
            Spacer()
            Button(action: onReset) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .disabled(!canReset)
            .help("Reset to default")
        }
    }

    @ViewBuilder
    private func sliderRow(
        label: LocalizedStringKey,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        formatter: @escaping (Double) -> String
    ) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Slider(value: binding, in: range)
                    .frame(width: 140)
                Text(formatter(binding.wrappedValue))
                    .frame(width: 40, alignment: .trailing)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private let intLabel: (Double) -> String = { "\(Int($0.rounded()))" }
    private let percentLabel: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    private var finishBinding: Binding<DeviceBodyFinish> {
        Binding(get: { material.resolvedFinish }, set: { material.finish = $0 })
    }
    private var metalnessBinding: Binding<Double> {
        Binding(get: { material.resolvedMetalness }, set: { material.metalness = $0 })
    }
    private var roughnessBinding: Binding<Double> {
        Binding(get: { material.resolvedRoughness }, set: { material.roughness = $0 })
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
