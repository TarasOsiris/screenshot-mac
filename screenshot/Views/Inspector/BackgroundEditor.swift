import SwiftUI

struct BackgroundEditor: View {
    @Binding var backgroundStyle: BackgroundStyle
    @Binding var bgColor: Color
    @Binding var gradientConfig: GradientConfig
    var compact: Bool = false
    var onChanged: () -> Void

    var body: some View {
        Picker("Style", selection: $backgroundStyle.onSet { onChanged() }) {
            Text("Color").tag(BackgroundStyle.color)
            Text("Gradient").tag(BackgroundStyle.gradient)
        }
        .pickerStyle(.segmented)
        .controlSize(compact ? .mini : .small)

        if backgroundStyle == .color {
            ColorPicker(
                "Color",
                selection: $bgColor.onSet { onChanged() },
                supportsOpacity: false
            )
            .font(.system(size: compact ? 10 : 12))
        } else {
            GradientStopEditor(
                config: $gradientConfig,
                onChanged: onChanged
            )

            let gridSpacing: CGFloat = compact ? 2 : 4
            let swatchHeight: CGFloat = compact ? 20 : 28
            let cornerRadius: CGFloat = compact ? 3 : 4

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 4), spacing: gridSpacing) {
                ForEach(gradientPresets) { preset in
                    Button {
                        gradientConfig = preset.config
                        onChanged()
                    } label: {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(preset.config.linearGradient)
                            .frame(height: swatchHeight)
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help(preset.label)
                }
            }

            let angleFontSize: CGFloat = compact ? 14 : 18
            let buttonSize: CGFloat = compact ? 14 : 18
            let arrowSize: CGFloat = compact ? 7 : 8

            VStack(spacing: 6) {
                HStack(spacing: compact ? 8 : 12) {
                    GradientAngleWheel(
                        angle: $gradientConfig.angle.onSet { onChanged() }
                    )
                    .frame(width: compact ? 36 : nil, height: compact ? 36 : nil)

                    VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                        Text("\(Int(gradientConfig.angle))°")
                            .font(.system(size: angleFontSize, weight: .medium).monospacedDigit())
                            .foregroundStyle(.primary)

                        HStack(spacing: compact ? 1 : 2) {
                            ForEach([0, 45, 90, 135, 180, 225, 270, 315], id: \.self) { a in
                                Button {
                                    gradientConfig.angle = Double(a)
                                    onChanged()
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: arrowSize))
                                        .rotationEffect(.degrees(Double(a)))
                                        .frame(width: buttonSize, height: buttonSize)
                                        .background(
                                            RoundedRectangle(cornerRadius: compact ? 2 : 3)
                                                .fill(Int(gradientConfig.angle) == a ? Color.accentColor.opacity(0.3) : Color.clear)
                                        )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .help("\(a)°")
                            }
                        }
                    }
                }
            }
        }
    }
}
