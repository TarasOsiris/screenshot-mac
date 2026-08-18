import SwiftUI

struct Device3DAppearancePopover: View {
    @Binding var pitch: Double
    @Binding var yaw: Double
    @Binding var material: DeviceBodyMaterial
    @Binding var lighting: DeviceLighting
    let canResetRotation: Bool
    let onResetRotation: () -> Void

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            rotationSection
            Divider()
            materialSection
            Divider()
            lightingSection
        }
        .popoverColumn()
        #else
        Form {
            Section("Rotation") {
                rotationSliders
            }
            Section("Material") {
                Picker("Finish", selection: finishBinding) {
                    ForEach(DeviceBodyFinish.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section("Lighting") {
                lightingSliders
            }
            Section {
                Button("Reset all", role: .destructive, action: resetAll)
                    .disabled(!hasAnyOverride)
            } footer: {
                Text("3D device rendering is an experimental feature")
            }
        }
        #endif
    }

    private var header: some View {
        PopoverHeader(
            title: "3D Device",
            badge: "Beta",
            badgeHelp: "3D device rendering is an experimental feature",
            resetLabel: "Reset all",
            resetHelp: "Reset rotation, material, and lighting to defaults",
            isResetDisabled: !hasAnyOverride,
            onReset: resetAll
        )
    }

    @ViewBuilder
    private var rotationSection: some View {
        PopoverSectionHeader("Rotation")
        rotationSliders
    }

    @ViewBuilder
    private var rotationSliders: some View {
        PopoverSliderRow(
            label: "Pitch",
            value: $pitch,
            range: -90...90,
            displayValue: "\(Int(pitch.rounded()))°"
        )
        PopoverSliderRow(
            label: "Yaw",
            value: $yaw,
            range: -90...90,
            displayValue: "\(Int(yaw.rounded()))°"
        )
    }

    @ViewBuilder
    private var materialSection: some View {
        PopoverSectionHeader("Material")

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
        PopoverSectionHeader("Lighting")
        lightingSliders
    }

    @ViewBuilder
    private var lightingSliders: some View {
        PopoverSliderRow(
            label: "Ambient",
            value: ambientBinding,
            range: DeviceLighting.ambientIntensityRange,
            displayValue: intLabel(lighting.resolvedAmbientIntensity)
        )
        PopoverSliderRow(
            label: "Key",
            value: keyBinding,
            range: DeviceLighting.keyIntensityRange,
            displayValue: intLabel(lighting.resolvedKeyIntensity)
        )
        PopoverSliderRow(
            label: "Rim",
            value: rimBinding,
            range: DeviceLighting.rimIntensityRange,
            displayValue: intLabel(lighting.resolvedRimIntensity)
        )
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
