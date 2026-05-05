import SwiftUI

struct ShapeDeviceModelRotationControls: View {
    let shape: CanvasShapeModel
    let pitch: Binding<Double>
    let yaw: Binding<Double>
    let canReset: Bool
    let onReset: () -> Void
    let bodyMaterial: Binding<DeviceBodyMaterial>
    let lighting: Binding<DeviceLighting>

    @State private var isAppearancePopoverPresented = false

    var body: some View {
        ShapePropertiesSection {
            ShapePropertiesControlGroup("Pitch") {
                Slider(value: pitch, in: -35...35)
                    .frame(width: 80)

                Text(verbatim: "\(Int(shape.resolvedDevicePitch.rounded()))°")
                    .frame(width: 28, alignment: .trailing)
            }

            ShapePropertiesSeparator()

            ShapePropertiesControlGroup("Yaw") {
                Slider(value: yaw, in: -45...45)
                    .frame(width: 80)

                Text(verbatim: "\(Int(shape.resolvedDeviceYaw.rounded()))°")
                    .frame(width: 28, alignment: .trailing)
            }

            ShapePropertiesSeparator()

            ActionButton(
                icon: "arrow.counterclockwise",
                tooltip: "Reset 3D device rotation",
                frameSize: 24,
                disabled: !canReset,
                action: onReset
            )

            ShapePropertiesSeparator()

            ActionButton(
                icon: "cube.transparent",
                tooltip: "Material & lighting…",
                frameSize: 24
            ) {
                isAppearancePopoverPresented.toggle()
            }
            .popover(isPresented: $isAppearancePopoverPresented, arrowEdge: .top) {
                Device3DAppearancePopover(material: bodyMaterial, lighting: lighting)
            }

            ShapePropertiesSeparator()

            Text("Beta")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.orange.opacity(0.15), in: .capsule)
                .help("3D device rotation is an experimental feature")
        }
    }
}
