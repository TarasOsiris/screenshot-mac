import SwiftUI

struct ShapeDeviceModelRotationControls: View {
    let pitch: Binding<Double>
    let yaw: Binding<Double>
    let canReset: Bool
    let onReset: () -> Void
    let bodyMaterial: Binding<DeviceBodyMaterial>
    let lighting: Binding<DeviceLighting>

    @State private var isPopoverPresented = false

    var body: some View {
        ShapePropertiesSection {
            PropertiesBarPopoverTrigger(
                systemImage: "cube.transparent",
                isPresented: $isPopoverPresented,
                showsOverrideDot: hasAnyOverride,
                help: "Rotation, material, and lighting",
                popoverTitle: "Appearance"
            ) {
                Text("3D")
            } content: {
                Device3DAppearancePopover(
                    pitch: pitch,
                    yaw: yaw,
                    material: bodyMaterial,
                    lighting: lighting,
                    canResetRotation: canReset,
                    onResetRotation: onReset
                )
            }
        }
    }

    private var hasAnyOverride: Bool {
        canReset || !bodyMaterial.wrappedValue.isEmpty || !lighting.wrappedValue.isEmpty
    }
}
