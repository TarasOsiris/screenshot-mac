import SwiftUI

/// Properties-bar section for a device's configurable drop shadow.
/// A button opens a popover with presets and fine-tune sliders, mirroring
/// `ShapeDeviceModelRotationControls`.
struct ShapeDeviceShadowControls: View {
    let shadow: Binding<ShadowConfig>

    @State private var isPopoverPresented = false

    var body: some View {
        ShapePropertiesSection {
            Button {
                isPopoverPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.bottomhalf.filled")
                        .font(.system(size: 11))
                    Text("Shadow")
                        .font(.system(size: UIMetrics.FontSize.body))
                    if shadow.wrappedValue.isActive {
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
            .help("Drop shadow")
            .barPopover(isPresented: $isPopoverPresented, title: "Shadow", detents: [.medium, .large]) {
                DeviceShadowPopover(shadow: shadow)
            }
        }
    }
}
