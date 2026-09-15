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
            Device3DAppearanceControls(pitch: $pitch, yaw: $yaw, material: $material, lighting: $lighting)
        }
        .popoverColumn()
        #else
        Form {
            Device3DAppearanceControls(pitch: $pitch, yaw: $yaw, material: $material, lighting: $lighting)
            Section {
                PopoverResetButton(label: "Reset all", isDisabled: { !hasAnyOverride }, action: resetAll)
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
            isResetDisabled: { !hasAnyOverride },
            onReset: resetAll
        )
    }

    private var hasAnyOverride: Bool {
        canResetRotation || !material.isEmpty || !lighting.isEmpty
    }

    private func resetAll() {
        material = DeviceBodyMaterial()
        lighting = DeviceLighting()
        if canResetRotation { onResetRotation() }
    }
}

/// Rotation, material and lighting for a model-backed device, without a title or reset — the
/// popover and the inspector section each supply their own.
struct Device3DAppearanceControls: View {
    @Binding var pitch: Double
    @Binding var yaw: Double
    @Binding var material: DeviceBodyMaterial
    @Binding var lighting: DeviceLighting

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 12) {
            rotationSection
            Divider()
            materialSection
            Divider()
            lightingSection
        }
        #else
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
        #endif
    }

    @ViewBuilder
    private var rotationSection: some View {
        PopoverSectionHeader("Rotation")
        rotationSliders
    }

    /// Nothing here reads `pitch`, `yaw`, `material` or `lighting`. Each row formats its own
    /// readout from its binding, so a 30 Hz drag re-evaluates that one row instead of this body —
    /// which would otherwise drag the segmented `Picker` below through a full `updateNSView` and
    /// AppKit layout on every tick.
    @ViewBuilder
    private var rotationSliders: some View {
        PopoverSliderRow(label: "Pitch", value: $pitch, range: -90...90, format: Self.degrees)
        PopoverSliderRow(label: "Yaw", value: $yaw, range: -90...90, format: Self.degrees)
    }

    private static let degrees: (Double) -> String = { "\(Int($0.rounded()))°" }

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
            .accessibilityLabel("Finish")
        }
    }

    @ViewBuilder
    private var lightingSection: some View {
        PopoverSectionHeader("Lighting")
        lightingSliders
    }

    @ViewBuilder
    private var lightingSliders: some View {
        PopoverSliderRow(label: "Ambient", value: ambientBinding, range: DeviceLighting.ambientIntensityRange)
        PopoverSliderRow(label: "Key", value: keyBinding, range: DeviceLighting.keyIntensityRange)
        PopoverSliderRow(label: "Rim", value: rimBinding, range: DeviceLighting.rimIntensityRange)
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
