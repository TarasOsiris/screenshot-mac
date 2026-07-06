import SwiftUI

/// Properties-bar section for a shape's configurable drop shadow.
/// A button opens a popover with presets and fine-tune sliders, mirroring
/// `ShapeDeviceModelRotationControls`.
struct ShapeShadowControls: View {
    let shadow: Binding<ShadowConfig>

    @State private var isPopoverPresented = false

    var body: some View {
        ShapePropertiesSection {
            PropertiesBarPopoverTrigger(
                systemImage: "square.bottomhalf.filled",
                isPresented: $isPopoverPresented,
                showsOverrideDot: shadow.wrappedValue.isActive,
                help: "Drop shadow",
                popoverTitle: "Shadow"
            ) {
                Text("Shadow")
            } content: {
                ShadowPopover(shadow: shadow)
            }
        }
    }
}
