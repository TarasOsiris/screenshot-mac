import SwiftUI

/// Every value comes from a binding, never a captured `CanvasShapeModel`: the width slider is a
/// continuous edit, so a shape captured in the properties bar's body would freeze the readout for
/// the whole drag. See `ShapePropertiesSingleSelectionBar.documentShape`.
struct ShapeOutlineControls: View {
    let hasOutline: Binding<Bool>
    let outlineColor: Binding<Color>
    let outlineWidth: Binding<CGFloat>

    var body: some View {
        Toggle("Outline", isOn: hasOutline)
            .toggleStyle(.switch)
            .compactControlSize()
            .help(hasOutline.wrappedValue ? String(localized: "Disable outline") : String(localized: "Enable outline"))

        if hasOutline.wrappedValue {
            ColorPicker("", selection: outlineColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: UIMetrics.ColorSwatch.inline)
                .padding(.horizontal, 4)
                .help("Outline")

            ShapePropertiesSeparator()

            ShapePropertiesControlGroup("Width") {
                Slider(value: outlineWidth, in: 1...50)
                    .frame(width: UIMetrics.SliderWidth.standard)

                Text(verbatim: "\(Int(outlineWidth.wrappedValue.rounded()))")
                    .frame(width: propertiesSliderValueWidth, alignment: .trailing)
            }
        }
    }
}
