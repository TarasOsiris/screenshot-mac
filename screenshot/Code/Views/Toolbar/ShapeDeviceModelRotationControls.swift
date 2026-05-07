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
            Button {
                isPopoverPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 11))
                    Text("3D")
                        .font(.system(size: UIMetrics.FontSize.body))
                    if hasAnyOverride {
                        OverrideDot()
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Rotation, material, and lighting")
            .popover(isPresented: $isPopoverPresented, arrowEdge: .top) {
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
