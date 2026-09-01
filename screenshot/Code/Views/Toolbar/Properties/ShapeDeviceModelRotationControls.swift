import SwiftUI

struct ShapeDeviceModelRotationControls: View {
    let pitch: Binding<Double>
    let yaw: Binding<Double>
    let canReset: Bool
    let onReset: () -> Void
    let bodyMaterial: Binding<DeviceBodyMaterial>
    let lighting: Binding<DeviceLighting>
    /// A plain `Bool` derived from the document, not from the bindings above. Reading
    /// `bodyMaterial.wrappedValue` here would subscribe this view — and therefore the popover it
    /// presents, `Picker` and all — to the ~30 Hz value of a pitch drag. The dot only changes at
    /// the two edges of a burst, so the document's answer is the right one.
    let showsOverrideDot: Bool

    @State private var isPopoverPresented = false

    var body: some View {
        ShapePropertiesSection {
            PropertiesBarPopoverTrigger(
                systemImage: "cube.transparent",
                isPresented: $isPopoverPresented,
                showsOverrideDot: showsOverrideDot,
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
}
