import SwiftUI

struct ShapeOutlineControls: View {
    let shape: CanvasShapeModel
    let hasOutline: Binding<Bool>
    let outlineColor: Binding<Color>
    let outlineWidth: Binding<CGFloat>

    var body: some View {
        Toggle("Outline", isOn: hasOutline)
            .toggleStyle(.switch)
            .controlSize(.small)
            .help(hasOutline.wrappedValue ? String(localized: "Disable outline") : String(localized: "Enable outline"))

        if hasOutline.wrappedValue {
            ColorPicker("", selection: outlineColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 30)
                .padding(.horizontal, 4)
                .help("Outline")

            ShapePropertiesSeparator()

            ShapePropertiesControlGroup("Width") {
                Slider(value: outlineWidth, in: 1...50)
                    .frame(width: 80)

                Text(verbatim: "\(Int((shape.outlineWidth ?? CanvasShapeModel.defaultOutlineWidth).rounded()))")
                    .frame(width: 28, alignment: .trailing)
            }
        }
    }
}
