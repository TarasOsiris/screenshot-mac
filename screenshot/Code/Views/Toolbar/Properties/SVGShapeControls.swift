import SwiftUI

struct SVGShapeControls: View {
    @Binding var usesCustomColor: Bool
    @Binding var color: Color
    let onReplace: () -> Void

    var body: some View {
        ShapePropertiesSection {
            HStack(spacing: 4) {
                Toggle("Custom color", isOn: $usesCustomColor)
                    .toggleStyle(.switch)
                    .compactControlSize()
                    .help("Use custom color for SVG")

                if usesCustomColor {
                    ColorPicker("SVG custom color", selection: $color, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: UIMetrics.ColorSwatch.inline)
                        .help("SVG custom color")
                }
            }

            ShapePropertiesSeparator()

            Button(action: onReplace) {
                Label("Replace SVG", systemImage: "arrow.triangle.2.circlepath")
            }
            .propertiesBarSecondaryButton()
        }
    }
}
