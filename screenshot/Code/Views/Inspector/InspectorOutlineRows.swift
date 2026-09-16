#if os(macOS)
import SwiftUI

/// Outline toggle, colour and width rows for the selection inspector, one shape or many.
struct InspectorOutlineRows: View {
    let isOn: Binding<Bool>
    let color: Binding<Color>
    let width: Binding<CGFloat>
    /// From the container's document value, so a width drag doesn't re-render it.
    let showsDetails: Bool

    var body: some View {
        Toggle("Enable outline", isOn: isOn)
            .toggleStyle(.switch)

        if showsDetails {
            EditorLabeledContent("Color") {
                ColorPicker("Outline", selection: color, supportsOpacity: false)
                    .labelsHidden()
            }
            PopoverSliderRow(label: "Width", value: width, range: 1...50, layout: .formRow)
        }
    }
}
#endif
